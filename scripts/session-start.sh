#!/usr/bin/env bash
# SessionStart hook for Claude Code cloud sessions.
# Restores Retro68 and Snow from the project cache when they are missing.
# It never runs the long from-source build; that is left to Claude or a human
# running scripts/setup-toolchain.sh explicitly.

set -uo pipefail

[[ "${CLAUDE_CODE_REMOTE:-}" == "true" ]] || exit 0

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CACHE_DIR="${CACHE_DIR:-/mnt/project-files/cache}"

missing=()
[[ -x /opt/retro68/bin/m68k-apple-macos-gcc ]] || missing+=(retro68)
[[ -x /opt/snow/bin/snowemu ]] || missing+=(snow)
[[ ${#missing[@]} -eq 0 ]] && exit 0

if ls "$CACHE_DIR"/retro68-68k-*.tar.zst "$CACHE_DIR"/snow-*.tar.zst >/dev/null 2>&1; then
    # Restores from the cache are quick; the script only builds what has no tarball.
    if "$ROOT/scripts/setup-toolchain.sh" "${missing[@]}" >/tmp/setup-toolchain.log 2>&1; then
        echo "Toolchain restored from cache (${missing[*]})."
    else
        echo "Toolchain restore failed; see /tmp/setup-toolchain.log."
    fi
else
    echo "Toolchain missing (${missing[*]}) and no cache in $CACHE_DIR." \
         "Run scripts/setup-toolchain.sh --save-cache in the background (Retro68 takes about an hour)."
fi
