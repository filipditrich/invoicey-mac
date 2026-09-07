#!/usr/bin/env bash
# Build a drag-to-Applications DMG with the Invoicey volume icon and background.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
app="${1:-}"
out="${2:-$root/dist/InvoiceyDrive.dmg}"

if [[ -z "$app" || ! -d "$app" ]]; then
  echo "usage: $0 /path/to/Invoicey Drive.app [InvoiceyDrive.dmg]" >&2
  exit 1
fi

icns="$root/Sources/InvoiceyDrive/Resources/InvoiceyDrive.icns"
bg="$root/docs/assets/dmg/background.png"
if [[ ! -f "$icns" || ! -f "$bg" ]]; then
  "$root/scripts/render-brand-icons.sh"
fi

work="$(mktemp -d)"
trap 'hdiutil detach "$vol" -force >/dev/null 2>&1 || true; rm -rf "$work"' EXIT

stage="$work/stage"
mkdir -p "$stage/.background"
ditto "$app" "$stage/Invoicey Drive.app"
ln -s /Applications "$stage/Applications"
cp "$bg" "$stage/.background/background.png"
cp "$icns" "$stage/.VolumeIcon.icns"
SetFile -c icnC "$stage/.VolumeIcon.icns"
# hide chrome from the icon view
SetFile -a V "$stage/.background"

rw="$work/rw.dmg"
hdiutil create \
  -volname "Invoicey Drive" \
  -srcfolder "$stage" \
  -fs HFS+ \
  -fsargs "-c c=64,a=16,e=16" \
  -format UDRW \
  -ov \
  "$rw" >/dev/null

# attach without opening Finder automatically
hdiutil detach "/Volumes/Invoicey Drive" -force >/dev/null 2>&1 || true
attach="$(hdiutil attach -readwrite -noverify -noautoopen "$rw")"
vol="/Volumes/Invoicey Drive"
dev="$(echo "$attach" | awk '/^\/dev\/disk[0-9]+[ \t]/{print $1; exit}')"
if [[ ! -d "$vol" || -z "$dev" ]]; then
  echo "failed to mount writable DMG" >&2
  echo "$attach" >&2
  exit 1
fi

# Finder must apply icon positions and the background picture.
osascript <<EOF
tell application "Finder"
  tell disk "Invoicey Drive"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 140, 860, 580}
    set theViewOptions to the icon view options of container window
    set arrangement of theViewOptions to not arranged
    set icon size of theViewOptions to 128
    set text size of theViewOptions to 13
    set background picture of theViewOptions to file ".background:background.png"
    set position of item "Invoicey Drive.app" of container window to {160, 220}
    set position of item "Applications" of container window to {500, 220}
    close
    open
    update without registering applications
    delay 1
  end tell
end tell
EOF

# Finder's update deletes a pre-seeded volume icon; put it back after layout.
cp "$icns" "$vol/.VolumeIcon.icns"
SetFile -c icnC "$vol/.VolumeIcon.icns"
SetFile -a V "$vol/.VolumeIcon.icns"
SetFile -a C "$vol"

chmod -Rf go-w "$vol" || true
sync
hdiutil detach "$dev" -quiet
vol=""

mkdir -p "$(dirname "$out")"
rm -f "$out"
hdiutil convert "$rw" -format UDZO -imagekey zlib-level=9 -o "$out" >/dev/null
# custom volume icon survives convert
echo "wrote $out"
