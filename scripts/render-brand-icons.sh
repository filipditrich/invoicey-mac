#!/usr/bin/env bash
# Rasterize the brand SVG into the macOS App Icon set, icns, and DMG chrome.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
svg="$root/docs/assets/brand/invoicey-app-icon.svg"
lockup="$root/docs/assets/brand/invoicey-lockup-on-light.svg"
iconset="$root/Sources/InvoiceyDrive/Assets.xcassets/AppIcon.appiconset"
resources="$root/Sources/InvoiceyDrive/Resources"
dmg_dir="$root/docs/assets/dmg"
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

if [[ ! -f "$svg" ]]; then
  echo "missing $svg" >&2
  exit 1
fi

render() {
  local size="$1"
  local dest="$2"
  rsvg-convert --width "$size" --height "$size" --background-color none "$svg" -o "$dest"
}

# App Icon.appiconset (Finder / Dock) + matching iconset for iconutil
mkdir -p "$iconset" "$resources" "$scratch/InvoiceyDrive.iconset"
declare -a pairs=(
  "16 icon_16x16.png"
  "32 icon_16x16@2x.png"
  "32 icon_32x32.png"
  "64 icon_32x32@2x.png"
  "128 icon_128x128.png"
  "256 icon_128x128@2x.png"
  "256 icon_256x256.png"
  "512 icon_256x256@2x.png"
  "512 icon_512x512.png"
  "1024 icon_512x512@2x.png"
)
for pair in "${pairs[@]}"; do
  size="${pair%% *}"
  name="${pair#* }"
  render "$size" "$iconset/$name"
done

# iconutil wants icon_16x16.png … icon_512x512@2x.png in an .iconset
cp "$iconset/icon_16x16.png" "$scratch/InvoiceyDrive.iconset/icon_16x16.png"
cp "$iconset/icon_16x16@2x.png" "$scratch/InvoiceyDrive.iconset/icon_16x16@2x.png"
cp "$iconset/icon_32x32.png" "$scratch/InvoiceyDrive.iconset/icon_32x32.png"
cp "$iconset/icon_32x32@2x.png" "$scratch/InvoiceyDrive.iconset/icon_32x32@2x.png"
cp "$iconset/icon_128x128.png" "$scratch/InvoiceyDrive.iconset/icon_128x128.png"
cp "$iconset/icon_128x128@2x.png" "$scratch/InvoiceyDrive.iconset/icon_128x128@2x.png"
cp "$iconset/icon_256x256.png" "$scratch/InvoiceyDrive.iconset/icon_256x256.png"
cp "$iconset/icon_256x256@2x.png" "$scratch/InvoiceyDrive.iconset/icon_256x256@2x.png"
cp "$iconset/icon_512x512.png" "$scratch/InvoiceyDrive.iconset/icon_512x512.png"
cp "$iconset/icon_512x512@2x.png" "$scratch/InvoiceyDrive.iconset/icon_512x512@2x.png"
iconutil --convert icns --output "$resources/InvoiceyDrive.icns" "$scratch/InvoiceyDrive.iconset"

# DMG window background: paper field + wordmark
mkdir -p "$dmg_dir"
rsvg-convert --width 1320 --height 880 "$dmg_dir/background.svg" -o "$scratch/bg.png"
rsvg-convert --width 360 --height 96 "$lockup" -o "$scratch/lockup.png"
magick "$scratch/bg.png" "$scratch/lockup.png" -gravity north -geometry +0+36 -composite "$dmg_dir/background.png"

echo "wrote $iconset"
echo "wrote $resources/InvoiceyDrive.icns"
echo "wrote $dmg_dir/background.png"
