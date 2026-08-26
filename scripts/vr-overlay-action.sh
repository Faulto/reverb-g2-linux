#!/usr/bin/env bash
# Fixed command bridge used by the in-headset SteamVR dashboard overlay.

set -euo pipefail

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
REPO="$(cd "$(dirname "$SCRIPT_PATH")/.." && pwd)"
LAUNCHER="$REPO/scripts/beat-saber-index.sh"

case "${1:-}" in
    start-modded)
        exec "$LAUNCHER" play-modded
        ;;
    set-floor)
        # The overlay owns the visible countdown. Keep the launcher's full pose
        # validation and standing-origin safeguards, but do not count down twice.
        exec "$LAUNCHER" floor 0
        ;;
    *)
        printf 'usage: %s [start-modded|set-floor]\n' "$0" >&2
        exit 2
        ;;
esac
