#!/bin/zsh
# Nictate: a macOS menu bar app that copies text from anywhere on your screen.
# Copyright (c) 2026 jrthormann. MIT License, see LICENSE.

# The release disk image, and the only packaging path (make dmg). It packs one committed revision, never the working
# tree, into OUT_DIR/<version>/: Nictate-<version>.dmg and SHA256SUMS. The defaults are COMMIT=HEAD, OUT_DIR=build/release.
#
#   BUILD_NUMBER=22 make dmg
#   BUILD_NUMBER=22 make dmg COMMIT=<sha> OUT_DIR=<dir>
#
# These checks run before anything is built:
#   - BUILD_NUMBER is required and must be a whole number. It must be above the previous release's build (docs/RELEASING.md).
#   - The working tree is clean, so the image matches a commit.
#   - CHANGELOG.md at that commit has a section for the version in its Info.plist.
#   - OUT_DIR/<version> does not exist yet. The folder is claimed with mkdir and never reused, so no image or checksum
#     from an earlier release is overwritten.
# After the build, the app must carry the same version and build number, and be signed with "Nictate Local Signing",
# never ad hoc. Temporary files live in a mktemp folder that is removed on exit, so they never land in a release folder.
# Styling the window drives Finder, so macOS may ask to let this terminal control Finder the first time.
set -euo pipefail
cd "$(dirname "$0")/.."

fail() { echo "error: $*" >&2; exit 1; }

COMMIT="${COMMIT:-HEAD}"
OUT_DIR="${OUT_DIR:-build/release}"
VOLUME="Nictate"
MOUNT="/Volumes/$VOLUME"
SIGN_NAME="Nictate Local Signing"

[[ -n "${BUILD_NUMBER:-}" ]] || fail "set BUILD_NUMBER above the previous release's build (beta.1 is 21), e.g. BUILD_NUMBER=22 make dmg"
[[ "$BUILD_NUMBER" =~ '^[0-9]+$' ]] || fail "BUILD_NUMBER must be a whole number, not '$BUILD_NUMBER'"
[[ -z "$(git status --porcelain)" ]] || fail "the working tree has changes; commit or stash them so the image matches a commit"
SHA="$(git rev-parse --verify --quiet "$COMMIT^{commit}")" || fail "no commit named '$COMMIT'"

WORK="$(mktemp -d)"
ATTACHED=""
CREATED_RELEASE=""
cleanup() {
    if [[ -n "$ATTACHED" ]]; then hdiutil detach "$MOUNT" -force >/dev/null 2>&1 || true; fi
    if [[ -n "$CREATED_RELEASE" ]]; then rm -rf "$CREATED_RELEASE"; fi
    rm -rf "$WORK"
}
trap cleanup EXIT

# The version comes from the commit, and the commit's changelog must describe it.
git show "$SHA:Sources/Nictate/Resources/Info.plist" > "$WORK/Info.plist"
VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$WORK/Info.plist")"
git show "$SHA:CHANGELOG.md" > "$WORK/CHANGELOG.md"
grep -q -F "## [$VERSION]" "$WORK/CHANGELOG.md" || fail "CHANGELOG.md at ${SHA:0:7} has no '## [$VERSION]' section"

# A release folder is claimed with mkdir, which fails when it exists, so nothing from an earlier release is touched.
mkdir -p "$OUT_DIR"
OUT_DIR="$(cd "$OUT_DIR" && pwd)"
RELEASE_DIR="$OUT_DIR/$VERSION"
[[ ! -e "$RELEASE_DIR" ]] || fail "$RELEASE_DIR already exists; release outputs are never overwritten (move it aside or set OUT_DIR)"
# A volume of the same name left mounted would make Finder address the wrong disk. It is not ours, so it is not detached.
[[ ! -d "$MOUNT" ]] || fail "$MOUNT is already mounted; eject it and run again"

# Build the exact commit in a clean export, so the working tree cannot leak into the image.
SRC="$WORK/src"
mkdir "$SRC"
git archive "$SHA" | tar -x -C "$SRC"
cd "$SRC"
BUILD_NUMBER="$BUILD_NUMBER" ./scripts/build-app.sh

APP="$SRC/build/Nictate.app"
PLIST="$APP/Contents/Info.plist"
[[ "$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$PLIST")" == "$VERSION" ]] \
    || fail "the built app's version differs from the commit's Info.plist"
[[ "$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$PLIST")" == "$BUILD_NUMBER" ]] \
    || fail "the built app's build number is not $BUILD_NUMBER"

# An ad-hoc signature changes with every build, so macOS would ask for Screen Recording again after each update.
# The Authority lines are printed only at -dvv.
SIGNING="$(codesign -dvv "$APP" 2>&1 || true)"
if [[ "$SIGNING" == *"Signature=adhoc"* ]]; then
    fail "$APP is signed ad hoc; run make setup, then build again so the local identity signs it"
fi
if [[ "$SIGNING" != *"Authority=$SIGN_NAME"* ]]; then
    fail "$APP is not signed with \"$SIGN_NAME\"; the release must use that identity"
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
RW="$WORK/rw.dmg"
SIZE_KB=$(( $(du -sk "$STAGING" | cut -f1) + 4096 ))
hdiutil create -srcfolder "$STAGING" -volname "$VOLUME" -fs HFS+ -format UDRW -size "${SIZE_KB}k" "$RW" >/dev/null
hdiutil attach "$RW" -readwrite -noverify -noautoopen >/dev/null
ATTACHED=1

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
ATTACHED=""
IMAGE="$WORK/Nictate-$VERSION.dmg"
hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -o "$IMAGE" >/dev/null

# Only now is the release folder claimed, so a failed build leaves nothing behind.
mkdir "$RELEASE_DIR" || fail "$RELEASE_DIR was created while this build ran; nothing was overwritten"
CREATED_RELEASE="$RELEASE_DIR"
DMG="$RELEASE_DIR/Nictate-$VERSION.dmg"
cp "$IMAGE" "$DMG"
hdiutil verify "$DMG" >/dev/null
(cd "$RELEASE_DIR" && shasum -a 256 "Nictate-$VERSION.dmg" > SHA256SUMS && shasum -a 256 -c SHA256SUMS)
chmod 444 "$DMG" "$RELEASE_DIR/SHA256SUMS"
CREATED_RELEASE=""

echo "Created $DMG from commit ${SHA:0:7} (build $BUILD_NUMBER)"
cat "$RELEASE_DIR/SHA256SUMS"
