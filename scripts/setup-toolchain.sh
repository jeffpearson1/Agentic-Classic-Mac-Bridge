#!/usr/bin/env bash
# Install everything needed to build Mac apps and run the emulator:
# Retro68 (68k only) and the Snow emulator, both built from pinned sources.
#
#   scripts/setup-toolchain.sh                    install whatever is missing
#   scripts/setup-toolchain.sh --save-cache       also write tarballs to $CACHE_DIR
#   scripts/setup-toolchain.sh [retro68] [snow]   only these components
#
# A full build takes a long time (Retro68 builds GCC). When $CACHE_DIR holds
# tarballs from an earlier --save-cache run, they are restored instead.
#
# Environment:
#   RETRO68_PREFIX  install prefix for Retro68       (default /opt/retro68)
#   SNOW_PREFIX     install prefix for Snow          (default /opt/snow)
#   SRC_DIR         where sources are cloned/built   (default ~/.cache/macdev-src)
#   CACHE_DIR       tarball cache                    (default /mnt/project-files/cache)

set -euo pipefail

RETRO68_PREFIX="${RETRO68_PREFIX:-/opt/retro68}"
SNOW_PREFIX="${SNOW_PREFIX:-/opt/snow}"
SRC_DIR="${SRC_DIR:-$HOME/.cache/macdev-src}"
CACHE_DIR="${CACHE_DIR:-/mnt/project-files/cache}"

# Pinned upstream versions. Bump deliberately and re-save the cache.
RETRO68_REPO=https://github.com/autc04/Retro68
RETRO68_REF=0cbd3cb918a127a0d30a675b337f8f8e15062786
SNOW_REPO=https://github.com/twvd/snow
SNOW_REF=v1.5.0

RETRO68_TARBALL="$CACHE_DIR/retro68-68k-${RETRO68_REF:0:12}-$(uname -m).tar.zst"
SNOW_TARBALL="$CACHE_DIR/snow-${SNOW_REF}-$(uname -m).tar.zst"

SAVE_CACHE=0
COMPONENTS=()
for arg in "$@"; do
    case "$arg" in
        --save-cache) SAVE_CACHE=1 ;;
        retro68|snow) COMPONENTS+=("$arg") ;;
        *) echo "unknown argument: $arg" >&2; exit 2 ;;
    esac
done
[[ ${#COMPONENTS[@]} -eq 0 ]] && COMPONENTS=(retro68 snow)

log() { echo "[setup-toolchain] $*" >&2; }

SUDO=""
[[ $EUID -ne 0 ]] && SUDO="sudo"

install_packages() {
    log "installing build dependencies"
    $SUDO apt-get update -qq
    DEBIAN_FRONTEND=noninteractive $SUDO apt-get install -y -qq \
        build-essential cmake ninja-build git curl zstd pkg-config \
        libgmp-dev libmpfr-dev libmpc-dev libboost-all-dev \
        bison flex texinfo ruby \
        hfsutils libasound2-dev xvfb xdotool >/dev/null
}

# Clone $1 at ref $2 into $3 (shallow, with submodules).
fetch_source() {
    local repo=$1 ref=$2 dir=$3
    if [[ ! -d "$dir/.git" ]]; then
        git init -q "$dir"
        git -C "$dir" remote add origin "$repo"
    fi
    git -C "$dir" fetch -q --depth 1 origin "$ref"
    git -C "$dir" checkout -q FETCH_HEAD
    git -C "$dir" submodule update -q --init --depth 1
}

restore() {
    local tarball=$1 prefix=$2
    [[ -f "$tarball" ]] || return 1
    log "restoring $(basename "$tarball")"
    $SUDO mkdir -p "$prefix"
    $SUDO tar -C "$prefix" --zstd -xf "$tarball"
}

save() {
    local tarball=$1 prefix=$2
    mkdir -p "$CACHE_DIR"
    log "saving $(basename "$tarball")"
    tar -C "$prefix" --zstd -cf "$tarball.tmp" .
    mv "$tarball.tmp" "$tarball"
}

setup_retro68() {
    if [[ -x "$RETRO68_PREFIX/bin/m68k-apple-macos-gcc" ]]; then
        log "Retro68 already installed in $RETRO68_PREFIX"
    elif ! restore "$RETRO68_TARBALL" "$RETRO68_PREFIX"; then
        log "building Retro68 from source (this takes a while)"
        fetch_source "$RETRO68_REPO" "$RETRO68_REF" "$SRC_DIR/retro68"
        mkdir -p "$SRC_DIR/retro68-build"
        $SUDO mkdir -p "$RETRO68_PREFIX"
        $SUDO chown "$(id -u):$(id -g)" "$RETRO68_PREFIX"
        (cd "$SRC_DIR/retro68-build" &&
            "$SRC_DIR/retro68/build-toolchain.bash" \
                --no-ppc --no-carbon --ninja --prefix="$RETRO68_PREFIX")
    fi
    if [[ $SAVE_CACHE -eq 1 && ! -f "$RETRO68_TARBALL" ]]; then
        save "$RETRO68_TARBALL" "$RETRO68_PREFIX"
    fi
}

setup_snow() {
    if [[ -x "$SNOW_PREFIX/bin/snowemu" ]]; then
        log "Snow already installed in $SNOW_PREFIX"
    elif ! restore "$SNOW_TARBALL" "$SNOW_PREFIX"; then
        log "building Snow $SNOW_REF from source"
        command -v cargo >/dev/null || {
            curl -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal
            # shellcheck disable=SC1091
            source "$HOME/.cargo/env"
        }
        fetch_source "$SNOW_REPO" "$SNOW_REF" "$SRC_DIR/snow"
        (cd "$SRC_DIR/snow" && cargo build -r -p snow_frontend_egui)
        $SUDO mkdir -p "$SNOW_PREFIX/bin"
        $SUDO cp "$SRC_DIR/snow/target/release/snowemu" "$SNOW_PREFIX/bin/"
    fi
    if [[ $SAVE_CACHE -eq 1 && ! -f "$SNOW_TARBALL" ]]; then
        save "$SNOW_TARBALL" "$SNOW_PREFIX"
    fi
}

install_packages
for component in "${COMPONENTS[@]}"; do
    "setup_$component"
done
log "done: ${COMPONENTS[*]}"
