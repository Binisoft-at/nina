#!/usr/bin/env bash
# Regenerates every Nina icon PNG from the SVG sources in design/:
#   App AppIcon (iOS light/dark/tinted + macOS 16-512 @1x/@2x), Watch AppIcon, the NinaMark image set,
#   design/icon-1024.png, design/icon-mac-1024.png and design/contact-sheet.png.
# Usage (from the repo root):  bash design/export.sh
# Needs node with Playwright (headless Chromium) and ImageMagick (magick or convert).
set -euo pipefail

DESIGN="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$DESIGN")"
APPICON="$ROOT/App/Resources/Assets.xcassets/AppIcon.appiconset"
WATCHICON="$ROOT/Watch/Resources/Assets.xcassets/AppIcon.appiconset"
MARK="$ROOT/App/Resources/Assets.xcassets/NinaMark.imageset"
IM="$(command -v magick || command -v convert || true)"
[ -n "$IM" ] || { echo "ImageMagick (magick or convert) is required" >&2; exit 1; }
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Opaque RGB PNG (iOS and watchOS icons must not have an alpha channel).
opaque() { "$IM" "$1" -background black -alpha remove -alpha off -strip "PNG24:$2"; }
# Smaller sizes are downscaled from the 1024 render: crisper than rasterising the vectors at 16-64 px.
shrink() { "$IM" "$1" -filter Lanczos -resize "$2x$2" -strip "PNG32:$3"; }

# 1. Vectors -> PNG with headless Chromium.
node "$DESIGN/render.js" \
  "$DESIGN/icon.svg"        "$TMP/light.png"    1024 \
  "$DESIGN/icon-dark.svg"   "$TMP/dark.png"     1024 \
  "$DESIGN/icon-tinted.svg" "$TMP/tinted.png"   1024 \
  "$DESIGN/icon-mac.svg"    "$TMP/mac.png"      1024 \
  "$DESIGN/mark.svg"        "$TMP/mark-120.png" 120 \
  "$DESIGN/mark.svg"        "$TMP/mark-240.png" 240 \
  "$DESIGN/mark.svg"        "$TMP/mark-360.png" 360

# 2. iOS / iPadOS: one 1024 icon per appearance (the system masks and scales it).
opaque "$TMP/light.png"  "$APPICON/AppIcon-1024.png"
opaque "$TMP/dark.png"   "$APPICON/AppIcon-1024-dark.png"
opaque "$TMP/tinted.png" "$APPICON/AppIcon-1024-tinted.png"

# 3. macOS: 16, 32, 128, 256, 512 pt at 1x and 2x (the shape and shadow are part of the artwork).
for px in 16 32 64 128 256 512 1024; do shrink "$TMP/mac.png" "$px" "$TMP/mac-$px.png"; done
cp "$TMP/mac-16.png"   "$APPICON/mac-16.png"
cp "$TMP/mac-32.png"   "$APPICON/mac-16@2x.png"
cp "$TMP/mac-32.png"   "$APPICON/mac-32.png"
cp "$TMP/mac-64.png"   "$APPICON/mac-32@2x.png"
cp "$TMP/mac-128.png"  "$APPICON/mac-128.png"
cp "$TMP/mac-256.png"  "$APPICON/mac-128@2x.png"
cp "$TMP/mac-256.png"  "$APPICON/mac-256.png"
cp "$TMP/mac-512.png"  "$APPICON/mac-256@2x.png"
cp "$TMP/mac-512.png"  "$APPICON/mac-512.png"
cp "$TMP/mac-1024.png" "$APPICON/mac-512@2x.png"

# 4. watchOS: the light artwork, full bleed and opaque (the system masks it to a circle).
opaque "$TMP/light.png" "$WATCHICON/AppIcon-1024.png"

# 5. In-app mark (transparent): 120 / 240 / 360 px for @1x / @2x / @3x.
mkdir -p "$MARK"
"$IM" "$TMP/mark-120.png" -strip "PNG32:$MARK/NinaMark.png"
"$IM" "$TMP/mark-240.png" -strip "PNG32:$MARK/NinaMark@2x.png"
"$IM" "$TMP/mark-360.png" -strip "PNG32:$MARK/NinaMark@3x.png"

# 6. Previews: README icon, Mac icon, and the contact sheet (all appearances + small sizes).
cp "$APPICON/AppIcon-1024.png" "$DESIGN/icon-1024.png"
cp "$APPICON/mac-512@2x.png" "$DESIGN/icon-mac-1024.png"
for name in light dark tinted; do
  for px in 60 29; do shrink "$TMP/$name.png" "$px" "$TMP/$name-$px.png"; done
done
node "$DESIGN/render.js" --sheet "$TMP/contact-sheet.png" "$TMP"
"$IM" "$TMP/contact-sheet.png" -strip "PNG24:$DESIGN/contact-sheet.png"

echo "icons exported"
