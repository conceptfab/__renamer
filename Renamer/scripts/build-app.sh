#!/bin/bash
#
# Builds the Renamer macOS app and packages it into <repo>/dist/.
#
# Outputs:
#   dist/Renamer.app            - runnable, ad-hoc signed app bundle
#   dist/Renamer-<version>.dmg  - drag-to-Applications disk image (unless --no-dmg)
#
# Usage:
#   Renamer/scripts/build-app.sh [--test] [--clean] [--no-dmg] [--run]
#
#   --test     run the RenamerCore test suite first; abort on failure
#   --clean    remove dist/ before building
#   --no-dmg   build the .app only, skip the .dmg
#   --run      open the built .app when finished
#
set -euo pipefail

# SwiftUI SDK macros ship with the full Xcode installation. Prefer it when the
# machine's global selection points to Command Line Tools, without changing the
# global developer directory or overriding an explicit caller choice.
if [[ -z "${DEVELOPER_DIR:-}" && "$(xcode-select -p)" == */CommandLineTools ]]; then
    for RENAMER_DEVELOPER_DIR in \
        /Applications/Xcode.app/Contents/Developer \
        /Applications/Xcode-beta.app/Contents/Developer; do
        if [[ -d "$RENAMER_DEVELOPER_DIR" ]]; then
            export DEVELOPER_DIR="$RENAMER_DEVELOPER_DIR"
            break
        fi
    done
fi

# --- paths -------------------------------------------------------------------
RENAMER_DIR="$(cd "$(dirname "$0")/.." && pwd)"   # .../Renamer
REPO_ROOT="$(cd "$RENAMER_DIR/.." && pwd)"        # repo root
CORE_DIR="$REPO_ROOT/RenamerCore"
DIST="$REPO_ROOT/dist"
APP="$DIST/Renamer.app"

# --- flags -------------------------------------------------------------------
RUN_TESTS=false
CLEAN=false
MAKE_DMG=true
OPEN_APP=false
for arg in "$@"; do
    case "$arg" in
        --test)   RUN_TESTS=true ;;
        --clean)  CLEAN=true ;;
        --no-dmg) MAKE_DMG=false ;;
        --run)    OPEN_APP=true ;;
        -h|--help)
            sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'
            exit 0 ;;
        *)
            echo "Unknown option: $arg (try --help)" >&2
            exit 2 ;;
    esac
done

# --- version (from Info.plist) ----------------------------------------------
INFO_PLIST="$RENAMER_DIR/Info.plist"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"
MIN_MACOS="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$INFO_PLIST")"
SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version)"

# --- optional: tests ---------------------------------------------------------
if $RUN_TESTS; then
    echo "==> Running RenamerCore tests"
    ( cd "$CORE_DIR" && swift test )
fi

# --- optional: clean ---------------------------------------------------------
if $CLEAN; then
    echo "==> Cleaning $DIST"
    rm -rf "$DIST"
fi

# --- build (release) ---------------------------------------------------------
echo "==> Building Renamer $VERSION (release)"
# SwiftPM can stamp the deployment target as the SDK version. Pass both values
# explicitly so AppKit adopts the current system appearance while retaining the
# existing minimum macOS requirement.
( cd "$RENAMER_DIR" && swift build -c release \
    -Xlinker -platform_version -Xlinker macos \
    -Xlinker "$MIN_MACOS" -Xlinker "$SDK_VERSION" )
BIN="$(cd "$RENAMER_DIR" && swift build -c release --show-bin-path)/Renamer"

if [[ ! -x "$BIN" ]]; then
    echo "Build did not produce an executable at: $BIN" >&2
    exit 1
fi

# --- app icon ----------------------------------------------------------------
ICON="$RENAMER_DIR/Resources/AppIcon.icns"
ICON_SOURCE="$REPO_ROOT/docs/icon-macos.png"
if [[ ! -f "$ICON" || "$ICON_SOURCE" -nt "$ICON" ]]; then
    echo "==> Generating app icon"
    "$RENAMER_DIR/scripts/generate-icon.sh"
fi

# --- assemble .app bundle ----------------------------------------------------
echo "==> Assembling $APP"
mkdir -p "$DIST"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Renamer"
chmod +x "$APP/Contents/MacOS/Renamer"
cp "$INFO_PLIST" "$APP/Contents/Info.plist"
cp "$ICON" "$APP/Contents/Resources/AppIcon.icns"

# --- ad-hoc code signing (so it launches locally without Gatekeeper noise) ---
echo "==> Code signing (ad-hoc)"
codesign --force --sign - --timestamp=none "$APP"
codesign --verify --deep --strict "$APP"

# --- optional: .dmg ----------------------------------------------------------
DMG=""
if $MAKE_DMG; then
    DMG="$DIST/Renamer-$VERSION.dmg"
    echo "==> Building $DMG"
    STAGING="$(mktemp -d)"
    trap 'rm -rf "$STAGING"' EXIT
    cp -R "$APP" "$STAGING/Renamer.app"
    ln -s /Applications "$STAGING/Applications"
    rm -f "$DMG"
    hdiutil create \
        -volname "Renamer $VERSION" \
        -srcfolder "$STAGING" \
        -fs HFS+ \
        -format UDZO \
        -ov \
        "$DMG" >/dev/null
    rm -rf "$STAGING"
    trap - EXIT
fi

# --- summary -----------------------------------------------------------------
echo ""
echo "Done."
echo "  App: $APP"
[[ -n "$DMG" ]] && echo "  DMG: $DMG"

if $OPEN_APP; then
    echo "==> Opening app"
    open "$APP"
fi
