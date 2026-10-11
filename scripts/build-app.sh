#!/bin/zsh
# Nictate: a macOS menu bar app that copies text from anywhere on your screen.
# Copyright (c) 2026 jrthormann. MIT License, see LICENSE.

# Builds build/Nictate.app, a universal binary for Apple silicon and Intel (ARCHS="arm64" builds one). Signs with a stable local identity when available
# (`make setup` creates it, see scripts/create_signing_cert.sh), otherwise ad-hoc.
set -euo pipefail
cd "$(dirname "$0")/.."
# The SDK that belongs to the active swiftc (Xcode or Command Line Tools); a mismatched pair fails to compile.
export SDKROOT="${SDKROOT:-$(xcrun --show-sdk-path 2>/dev/null || ls -d /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk)}"
echo "SDK: $SDKROOT"

# Everything is built in a staging folder and moves into place only once compiled and signed, so a
# failed build leaves the previous app untouched. The folder is unique per run, so two builds at once
# (a terminal and an editor task, say) do not delete each other's files.
# NICTATE_VARIANT=test builds the isolated test app: its own bundle identifier, Keychain service, history folder and
# fixtures (see scripts/variants/BuildIdentity.test.swift). It is a separate app, build/NictateTest.app, that runs
# beside the production app and never reads its data. Anything else builds the production app.
VARIANT="${NICTATE_VARIANT:-}"
case "$VARIANT" in
    "") APP_NAME=Nictate ;;
    test) APP_NAME=NictateTest ;;
    *) echo "error: unknown NICTATE_VARIANT '$VARIANT' (use test or leave it unset)" >&2; exit 1 ;;
esac
SOURCE_FILES=(Sources/Nictate/*.swift)
if [[ "$VARIANT" == test ]]; then
    SOURCE_FILES=(${SOURCE_FILES:#*/BuildIdentity.swift} scripts/variants/BuildIdentity.test.swift)
fi
FINAL=build/$APP_NAME.app
mkdir -p build
STAGE=$(mktemp -d build/.stage.XXXXXX)
APP=$STAGE/$APP_NAME.app
mkdir -p $APP/Contents/MacOS $APP/Contents/Resources
trap 'rm -rf $STAGE' EXIT
# One compile per architecture, in parallel, then lipo joins them. The x86_64 link reports that
# libswiftCompatibilityPacks has no Intel slice; nothing in Nictate needs it, or the link would fail.
ARCHS=(${=ARCHS:-arm64 x86_64})
pids=()
for arch in $ARCHS; do
    mkdir -p $STAGE/$arch
    swiftc -O -wmo -swift-version 5 -warnings-as-errors -strict-concurrency=complete -enable-upcoming-feature NonisolatedNonsendingByDefault -enable-upcoming-feature InferIsolatedConformances -enable-upcoming-feature ImmutableWeakCaptures -enable-upcoming-feature GlobalActorIsolatedTypesUsability -enable-upcoming-feature DisableOutwardActorInference -enable-upcoming-feature ExistentialAny -target "$arch-apple-macos14.0" "${SOURCE_FILES[@]}" \
        -o $STAGE/$arch/Nictate 2> $STAGE/$arch/stderr.txt &
    pids+=($!)
done
# The diagnostics go to files and are filtered after the compiles end, so none is lost to a filter
# that is still running when the script exits.
failed=0
for pid in $pids; do wait $pid || failed=1; done
for arch in $ARCHS; do grep -v "libswiftCompatibilityPacks" $STAGE/$arch/stderr.txt >&2 || true; done
(( failed == 0 )) || { echo "error: compile failed" >&2; exit 1; }
lipo -create $STAGE/${^ARCHS}/Nictate -output $APP/Contents/MacOS/Nictate

cp Sources/Nictate/Resources/AppIcon.icns $APP/Contents/Resources/
for lproj in Sources/Nictate/Resources/*.lproj(N); do cp -R "$lproj" $APP/Contents/Resources/; done
cp Sources/Nictate/Resources/Info.plist $APP/Contents/Info.plist
# The build number is the commit count unless BUILD_NUMBER is set. CI sets it to the run number, so a short
# history never ships a lower build than an earlier one; a shallow clone outside CI is caught by its low count.
if [[ -z "${BUILD_NUMBER:-}" ]]; then
    BUILD_NUMBER="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
    if [[ -n "${GITHUB_ACTIONS:-}" ]] && (( BUILD_NUMBER < 100 )); then
        echo "error: build number $BUILD_NUMBER looks like a shallow clone (use fetch-depth: 0 or set BUILD_NUMBER)" >&2; exit 1
    fi
fi
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" $APP/Contents/Info.plist
if [[ "$VARIANT" == test ]]; then
    # A separate identity: its own bundle identifier, so macOS keeps its preferences, sandbox container and
    # Keychain access apart from the production app.
    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.jrthormann.nictate.test" $APP/Contents/Info.plist
    /usr/libexec/PlistBuddy -c "Set :CFBundleName Nictate Test" $APP/Contents/Info.plist
    /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName Nictate Test" $APP/Contents/Info.plist
fi

# Signing: scripts/release_signing.zsh. A release (NICTATE_RELEASE=1, set by make dmg) is signed only with the certificate
# pinned in scripts/release-signing.txt, from the dedicated keychain, and never falls back. Any other build takes the
# development fallbacks (SIGN_IDENTITY, the dedicated keychain, the login-keychain certificate, ad hoc), each named in a
# warning. The dedicated keychain locks when the Mac sleeps: the first build after a wake asks for its password in the
# terminal, and pressing Return there, or building without a terminal, skips it.
source scripts/signing_keychain.zsh
source scripts/release_signing.zsh
NICTATE_SIGN_FLAGS=(--force --options runtime --entitlements Sources/Nictate/Resources/Nictate.entitlements)
if [[ "${NICTATE_RELEASE:-}" == 1 ]]; then
    sign_for_release "$APP" || exit 1
else
    sign_for_development "$APP"
fi
codesign --verify --strict $APP
rm -rf $FINAL && mv $APP $FINAL
echo "Built $FINAL (build $BUILD_NUMBER)"
