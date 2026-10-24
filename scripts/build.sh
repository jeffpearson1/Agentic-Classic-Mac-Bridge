#!/usr/bin/env bash
# Build every Mac app under apps/ with the Retro68 68k toolchain.
#
#   scripts/build.sh            configure (first time) and build all apps
#   scripts/build.sh Hello      build one target
#
# Output: build/apps/<app>/<Target>.bin (MacBinary), .dsk (disk image), .APPL
#
# RETRO68_TOOLCHAIN points at the Retro68 install prefix; it defaults to
# /opt/retro68 (scripts/setup-toolchain.sh) or the Docker image's location.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [[ -z "${RETRO68_TOOLCHAIN:-}" ]]; then
    for candidate in /opt/retro68 /Retro68-build/toolchain; do
        if [[ -d "$candidate/m68k-apple-macos" ]]; then
            RETRO68_TOOLCHAIN=$candidate
            break
        fi
    done
fi
TOOLCHAIN_FILE="${RETRO68_TOOLCHAIN:-}/m68k-apple-macos/cmake/retro68.toolchain.cmake"
if [[ ! -f "$TOOLCHAIN_FILE" ]]; then
    echo "Retro68 not found. Run scripts/setup-toolchain.sh or set RETRO68_TOOLCHAIN." >&2
    exit 1
fi

BUILD_DIR="$ROOT/build/apps"
if [[ ! -f "$BUILD_DIR/CMakeCache.txt" ]]; then
    cmake -S "$ROOT/apps" -B "$BUILD_DIR" -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN_FILE"
fi

if [[ $# -gt 0 ]]; then
    cmake --build "$BUILD_DIR" --target "$@"
else
    cmake --build "$BUILD_DIR"
fi
