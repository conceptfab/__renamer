#!/bin/bash
#
# Generates AppIcon.icns for the Renamer macOS app bundle from docs/icon.png.
#
set -euo pipefail

RENAMER_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPO_ROOT="$(cd "$RENAMER_DIR/.." && pwd)"
SOURCE="$REPO_ROOT/docs/icon.png"
ICONSET="$RENAMER_DIR/Resources/AppIcon.iconset"
OUTPUT="$RENAMER_DIR/Resources/AppIcon.icns"

if [[ ! -f "$SOURCE" ]]; then
    echo "Source icon not found: $SOURCE" >&2
    exit 1
fi

mkdir -p "$RENAMER_DIR/Resources"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"

declare -a SIZES=(
    "16:icon_16x16.png"
    "32:icon_16x16@2x.png"
    "32:icon_32x32.png"
    "64:icon_32x32@2x.png"
    "128:icon_128x128.png"
    "256:icon_128x128@2x.png"
    "256:icon_256x256.png"
    "512:icon_256x256@2x.png"
    "512:icon_512x512.png"
    "1024:icon_512x512@2x.png"
)

for entry in "${SIZES[@]}"; do
  size="${entry%%:*}"
  name="${entry#*:}"
  sips -z "$size" "$size" "$SOURCE" --out "$ICONSET/$name" >/dev/null
done

iconutil -c icns "$ICONSET" -o "$OUTPUT"
rm -rf "$ICONSET"

echo "Generated $OUTPUT"
