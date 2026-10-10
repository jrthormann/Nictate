#!/bin/zsh
# Nictate: a macOS menu bar app that copies text from anywhere on your screen.
# Copyright (c) 2026 jrthormann. MIT License, see LICENSE.

# Builds the app and packs it into build/Nictate-<version>.dmg: a 540x360 icon-view window with Nictate.app on the
# left, the Applications folder on the right, and a background drawn by scripts/make_dmg_background.swift.
# Refuses to pack an app signed ad hoc, because a release must keep the local signing identity (docs/RELEASING.md).
# Styling the window drives Finder, so macOS may ask to let this terminal control Finder the first time.
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/build-app.sh

APP=build/Nictate.app
VOLUME="Nictate"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
FINAL="build/Nictate-$VERSION.dmg"
MOUNT="/Volumes/$VOLUME"

# An ad-hoc signature changes with every build, so macOS would ask for Screen Recording again after each update.
SIGNING=$(codesign -dv "$APP" 2>&1 || true)
if [[ "$SIGNING" == *"Signature=adhoc"* ]]; then
    echo "error: $APP is signed ad hoc; run make setup, then build again so the local identity signs it" >&2
    exit 1
fi

WORK=$(mktemp -d)
RW="$WORK/rw.dmg"

cleanup() {
    hdiutil detach "$MOUNT" -force >/dev/null 2>&1 || true
    rm -rf "$WORK"
}
trap cleanup EXIT

# A volume of the same name left mounted would make Finder address the wrong disk.
if [[ -d "$MOUNT" ]]; then
    echo "error: $MOUNT is already mounted; eject it and run again" >&2
    exit 1
fi

STAGING="$WORK/staging"
mkdir "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

# The window background, drawn in code at 1x and 2x and joined into one TIFF for Retina screens.
swiftc -O scripts/make_dmg_background.swift -o "$WORK/make_dmg_background"
"$WORK/make_dmg_background" "$WORK/background.png" 1
"$WORK/make_dmg_background" "$WORK/background@2x.png" 2
mkdir "$STAGING/.background"
tiffutil -cathidpicheck "$WORK/background.png" "$WORK/background@2x.png" -out "$STAGING/.background/background.tiff" >/dev/null 2>&1

# Room for the app plus slack for the Finder view settings (.DS_Store).
SIZE_KB=$(( $(du -sk "$STAGING" | cut -f1) + 4096 ))
hdiutil create -srcfolder "$STAGING" -volname "$VOLUME" -fs HFS+ -format UDRW -size "${SIZE_KB}k" "$RW" >/dev/null
hdiutil attach "$RW" -readwrite -noverify -noautoopen >/dev/null

if osascript <<EOF
with timeout of 20 seconds
tell application "Finder"
    tell disk "$VOLUME"
        open
        set win to container window
        set current view of win to icon view
        set toolbar visible of win to false
        set statusbar visible of win to false
        set sidebar width of win to 0
        set bounds of win to {200, 120, 740, 480}
        set opts to icon view options of win
        set arrangement of opts to not arranged
        set icon size of opts to 96
        set text size of opts to 12
        set label position of opts to bottom
        set background picture of opts to file ".background:background.tiff"
        set position of item "Nictate.app" of win to {140, 180}
        set position of item "Applications" of win to {400, 180}
        update without registering applications
        delay 1
        close
    end tell
end tell
end timeout
EOF
then
    sync; sleep 2   # let Finder write .DS_Store before the volume goes away
else
    echo "warning: Finder could not style the window; the image will open with default placement" >&2
fi

hdiutil detach "$MOUNT" >/dev/null
rm -f "$FINAL"
hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -o "$FINAL" >/dev/null
echo "Created $FINAL"
