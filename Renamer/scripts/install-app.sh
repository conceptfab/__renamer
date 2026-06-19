#!/bin/bash
#
# Copies the built Renamer.app from <repo>/dist/ into /Applications.
#
# Usage:
#   Renamer/scripts/install-app.sh [--build] [--open]
#
#   --build    build dist/Renamer.app first (runs build-app.sh --no-dmg)
#   --open     launch /Applications/Renamer.app after install
#
set -euo pipefail

# --- paths -------------------------------------------------------------------
RENAMER_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPO_ROOT="$(cd "$RENAMER_DIR/.." && pwd)"
SOURCE_APP="$REPO_ROOT/dist/Renamer.app"
TARGET_APP="/Applications/Renamer.app"

# --- flags -------------------------------------------------------------------
BUILD_FIRST=false
OPEN_APP=false
for arg in "$@"; do
    case "$arg" in
        --build) BUILD_FIRST=true ;;
        --open)  OPEN_APP=true ;;
        -h|--help)
            sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'
            exit 0 ;;
        *)
            echo "Unknown option: $arg (try --help)" >&2
            exit 2 ;;
    esac
done

# --- optional: build ---------------------------------------------------------
if $BUILD_FIRST; then
    echo "==> Building app"
    "$RENAMER_DIR/scripts/build-app.sh" --no-dmg
fi

if [[ ! -d "$SOURCE_APP" ]]; then
    echo "Built app not found: $SOURCE_APP" >&2
    echo "Run Renamer/scripts/build-app.sh first, or use --build." >&2
    exit 1
fi

# --- install -----------------------------------------------------------------
echo "==> Installing Renamer to /Applications"
if [[ -d "$TARGET_APP" ]]; then
    echo "    Replacing existing $TARGET_APP"
    rm -rf "$TARGET_APP"
fi

ditto "$SOURCE_APP" "$TARGET_APP"

echo ""
echo "Done."
echo "  Installed: $TARGET_APP"

if $OPEN_APP; then
    echo "==> Opening app"
    open "$TARGET_APP"
fi
