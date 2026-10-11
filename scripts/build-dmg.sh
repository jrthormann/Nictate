#!/bin/zsh
# Nictate: a macOS menu bar app that copies text from anywhere on your screen.
# Copyright (c) 2026 jrthormann. MIT License, see LICENSE.

# The release disk image, and the only packaging path (make dmg). It packs one committed revision, never the working
# tree, into OUT_DIR/<version>/: Nictate-<version>.dmg and SHA256SUMS. The defaults are COMMIT=HEAD, OUT_DIR=build/release.
#
#   BUILD_NUMBER=22 make dmg
#   BUILD_NUMBER=22 make dmg COMMIT=<sha> OUT_DIR=<dir>
#
# These checks run before anything is built or written:
#   - BUILD_NUMBER is the build approved for the version in scripts/release-builds.txt, read from the commit, and no build
#     that repeats or regresses an earlier release (docs/RELEASING.md).
#   - The working tree is clean, so the image matches a commit.
#   - CHANGELOG.md at that commit has a section for the version in its Info.plist.
#   - OUT_DIR/<version> does not exist yet. The folder is claimed with mkdir and never reused, so no image or checksum
#     from an earlier release is overwritten.
# The app is signed only with the certificate pinned in scripts/release-signing.txt, from the dedicated keychain
# (scripts/release_signing.zsh). Before packaging, the built app and the app inside the image must pass strict
# verification, carry that certificate, and carry the requested version and build number. The build refuses to run
# while any volume named Nictate is present, so no volume the user has mounted is touched. Cleanup detaches only the
# image this build attached, found by its path, and removes the private folder only once that image is detached.
# Styling the window drives Finder, so macOS may ask to let this terminal control Finder the first time.
set -euo pipefail
cd "$(dirname "$0")/.."

fail() { echo "error: $*" >&2; exit 1; }
source scripts/release_signing.zsh

COMMIT="${COMMIT:-HEAD}"
OUT_DIR="${OUT_DIR:-build/release}"
VOLUME="Nictate"

[[ -n "${BUILD_NUMBER:-}" ]] || fail "set BUILD_NUMBER to the build approved for this version in scripts/release-builds.txt (1.0.0-beta.2 is 22), e.g. BUILD_NUMBER=22 make dmg"
case "$BUILD_NUMBER" in
    *[!0-9]*|0*) fail "BUILD_NUMBER must be a whole number without leading zeros, not '$BUILD_NUMBER'" ;;
esac
[[ -z "$(git status --porcelain)" ]] || fail "the working tree has changes; commit or stash them so the image matches a commit"
SHA="$(git rev-parse --verify --quiet "$COMMIT^{commit}")" || fail "no commit named '$COMMIT'"
# Finder styles the disk by its name, so no other volume may carry that name. Refuse while one is mounted or attached,
# rather than risk styling a volume that is not ours. diskutil lists every volume, mounted or not. The list is read into
# a variable first: under pipefail, grep -q can end a pipeline with a failure, which would skip this check.
VOLUMES="$(diskutil list)" || fail "could not list the disks"
if grep -q -w "$VOLUME" <<<"$VOLUMES"; then
    fail "a volume named $VOLUME is mounted or attached; eject it, then run again"
fi

# This build's private folder. Its physical path is the one hdiutil reports, so the image can be matched exactly.
WORK="$(cd "$(mktemp -d)" && pwd -P)"
RW="$WORK/rw.dmg"
MNT="/Volumes/$VOLUME"
CREATED_RELEASE=""

# Prints the device of the image this build attached, matched by the image's path, which only this build uses. Prints
# nothing when the image is not attached, so an image that attached without mounting, or only partly, is still found.
build_image_device() {
    hdiutil info | awk -v img="$RW" '
        /^image-path/ { p = $0; sub(/^image-path *: */, "", p); inimg = (p == img); next }
        /^=+$/ { inimg = 0 }
        inimg && /^\/dev\/disk[0-9]+[ \t]/ { print $1; exit }
    '
}

cleanup() {
    local dev kept=""
    dev="$(build_image_device || true)"
    if [[ -n "$dev" ]]; then
        hdiutil detach "$dev" -force >/dev/null 2>&1 || true
        [[ -z "$(build_image_device || true)" ]] || kept=1
    fi
    if [[ -n "$CREATED_RELEASE" ]]; then rm -rf "$CREATED_RELEASE"; fi
    if [[ -n "$kept" ]]; then
        echo "warning: $RW is still attached, so $WORK was kept. Detach it with: hdiutil detach $dev -force" >&2
    else
        rm -rf "$WORK"
    fi
}
trap cleanup EXIT
# A signal (Ctrl-C, a kill, a closed terminal) ends the script through EXIT, so the cleanup above still runs.
trap 'exit 130' INT TERM HUP

# The version comes from the commit, and the commit's changelog must describe it.
git show "$SHA:Sources/Nictate/Resources/Info.plist" > "$WORK/Info.plist"
VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$WORK/Info.plist")"
git show "$SHA:CHANGELOG.md" > "$WORK/CHANGELOG.md"
grep -q -F "## [$VERSION]" "$WORK/CHANGELOG.md" || fail "CHANGELOG.md at ${SHA:0:7} has no '## [$VERSION]' section"

# The approved build and the release certificate come from the commit too, so the image matches what was reviewed.
git show "${SHA}:scripts/release-builds.txt" > "$WORK/release-builds.txt" 2>/dev/null \
    || fail "${SHA:0:7} has no scripts/release-builds.txt"
git show "${SHA}:scripts/release-signing.txt" > "$WORK/release-signing.txt" 2>/dev/null \
    || fail "${SHA:0:7} has no scripts/release-signing.txt"
RELEASE_SIGNING_PIN_FILE="$WORK/release-signing.txt"
release_check_build_number "$VERSION" "$BUILD_NUMBER" "$WORK/release-builds.txt" || exit 1

# A release folder is claimed with mkdir, which fails when it exists, so nothing from an earlier release is touched.
mkdir -p "$OUT_DIR"
OUT_DIR="$(cd "$OUT_DIR" && pwd)"
RELEASE_DIR="$OUT_DIR/$VERSION"
[[ ! -e "$RELEASE_DIR" ]] || fail "$RELEASE_DIR already exists; release outputs are never overwritten (move it aside or set OUT_DIR)"

# Build the exact commit in a clean export, so the working tree cannot leak into the image.
SRC="$WORK/src"
mkdir "$SRC"
git archive "$SHA" | tar -x -C "$SRC"
cd "$SRC"
NICTATE_RELEASE=1 RELEASE_SIGNING_PIN_FILE="$RELEASE_SIGNING_PIN_FILE" BUILD_NUMBER="$BUILD_NUMBER" ./scripts/build-app.sh

APP="$SRC/build/Nictate.app"
PLIST="$APP/Contents/Info.plist"
[[ "$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$PLIST")" == "$VERSION" ]] \
    || fail "the built app's version differs from the commit's Info.plist"
[[ "$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$PLIST")" == "$BUILD_NUMBER" ]] \
    || fail "the built app's build number is not $BUILD_NUMBER"

# The staged app must pass strict verification and be signed with the pinned certificate before it is packaged.
release_verify_app "$APP" || exit 1

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

# Attached at /Volumes/Nictate, the one place Finder lists disks by name, so the styling below can address it. The guard
# above guarantees that name belongs to this build alone.
hdiutil attach "$RW" -readwrite -noverify -noautoopen -mountpoint "$MNT" >/dev/null \
    || fail "could not attach the disk image; nothing was released"

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
        close win
    end tell
end tell
end timeout
EOF
then
    sync; sleep 2   # let Finder write .DS_Store before the volume goes away
else
    echo "warning: Finder could not style the window; the image will open with default placement" >&2
fi

# The app inside the image is the one released: it must carry the pinned certificate, the requested version, and the
# requested build number. A failure here detaches this build's image through the cleanup and releases nothing.
release_verify_app "$MNT/Nictate.app" || exit 1
[[ "$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$MNT/Nictate.app/Contents/Info.plist")" == "$VERSION" ]] \
    || fail "the app in the image does not carry version $VERSION"
[[ "$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$MNT/Nictate.app/Contents/Info.plist")" == "$BUILD_NUMBER" ]] \
    || fail "the app in the image does not carry build $BUILD_NUMBER"

DEV="$(build_image_device || true)"
[[ -n "$DEV" ]] || fail "this build's image is not attached, so there is nothing to package"
hdiutil detach "$DEV" >/dev/null
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
