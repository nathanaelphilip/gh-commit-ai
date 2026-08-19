#!/usr/bin/env bash

set -e

VERSION="1.0.0"

# Colors for output (simplified palette)
RED='\033[38;2;174;32;18m'     # #AE2012 (errors only)
NC='\033[0m' # No Color

# fd 3 = live-progress channel (spinner / streaming arrow). Kept separate from
# stderr (fd 2) so provider error output on fd 2 can be captured and logged
# without hiding the progress indicator. Defaults to the real stderr (terminal).
exec 3>&2

# Paths registered here are removed when the script exits for any reason,
# including Ctrl-C. Without this, an interrupted run left temp files behind and
# could orphan the background spinner subshell.
GH_COMMIT_AI_TEMP_PATHS=()

register_temp_path() {
    [ -n "$1" ] || return 0
    GH_COMMIT_AI_TEMP_PATHS+=("$1")
}

cleanup_temp_paths() {
    local path
    for path in "${GH_COMMIT_AI_TEMP_PATHS[@]+"${GH_COMMIT_AI_TEMP_PATHS[@]}"}"; do
        rm -rf "$path" 2>/dev/null || true
    done
    GH_COMMIT_AI_TEMP_PATHS=()

    # Kill a spinner still running in the background on an interrupted run.
    if [ -n "${STREAM_SPINNER_PID:-}" ]; then
        kill "$STREAM_SPINNER_PID" 2>/dev/null || true
    fi
}

trap cleanup_temp_paths EXIT
trap 'cleanup_temp_paths; exit 130' INT
trap 'cleanup_temp_paths; exit 143' TERM

