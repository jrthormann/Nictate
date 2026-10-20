# Releasing Nictate

The disk image people download is built and signed on the maintainer's Mac. CI tests the release commit, and it never
publishes anything: it does not create releases, upload images, or move tags.

The image is signed with the local identity `Nictate Local Signing`. That is local code signing, not Apple Developer ID
signing, and the image is not notarized. Nictate is an independent open-source project, and it does not use the paid
Apple Developer Program. A fixed local identity gives every release the same signature, which keeps the Screen Recording
permission across updates (an ad-hoc signature differs on every build). Because the image is not notarized, macOS may
block its first launch; `docs/INSTALL.md` explains how to open it with the system's own controls.

This checklist covers `1.0.0-beta.N` releases. A `1.0.0` stable release uses the Developer ID signing and notarization
procedure instead, which is written when that path exists. Do not use this checklist to publish a stable release.

## Release environment

The official image for each release is produced in the verified release environment: macOS 27 with Xcode 27, on the maintainer's Mac
(macOS 27.0.1, Xcode 27.0, build 27A266a). This constrains how the image is built, not what it runs on. Nictate's minimum
deployment target is still macOS 14 (`LSMinimumSystemVersion` in `Sources/Nictate/Resources/Info.plist`). The CI runners,
macOS 26 and macOS 14, test the release commit, and they do not produce the image.

## Checklist

- [ ] The release commit is on `main`, and CI passes on it (every job: `build-and-test`, `intel-tests`, `ui-smoke`, `macos-14`).
- [ ] The image is built from that commit: `git status` is clean, and `git rev-parse --short HEAD` matches the tag.
- [ ] `scripts/release-builds.txt` lists this version with its approved build (beta.3: 23), and that build is higher than
      the builds listed above it. `BUILD_NUMBER` must equal that approved build. The commit count and the CI run number
      are not release numbers.
- [ ] `Sources/Nictate/Resources/Info.plist` has the new `CFBundleShortVersionString`.
- [ ] `CHANGELOG.md` has a section for that version. Its Tested section lists only what was run.
- [ ] The Status line in `README.md` and `docs/i18n/README.es.md`, and the version named in `docs/INSTALL.md` and `docs/i18n/INSTALL.es.md`, name the new version.
- [ ] `make check` and `make build` pass on the release commit, with no warnings.
- [ ] The six manual checks in [CONTRIBUTING.md](../CONTRIBUTING.md) pass on the QA build (`make test-app`).
- [ ] The new tag points at the release commit. No existing tag was moved.
- [ ] The `Nictate Local Signing` identity is backed up encrypted on two separate offline media, with the passphrase
      stored apart from both. The private key's exportability has been checked, and at least one backup has been
      validated.
- [ ] `BUILD_NUMBER=<n> make dmg` built the image in a new `build/release/<version>/` folder with the local identity, and
      the artifact checks in step 6 pass.
- [ ] The draft release has the image and `SHA256SUMS`, and its notes are the CHANGELOG section.
- [ ] The About window shows the new version. Clean installs on macOS 14 and on macOS 15 or later are run, or listed as
      untested in the release notes.
- [ ] The release notes say what CI does not check: CI runs builds, unit, OCR, UI smoke and app-signature checks. It does not install the DMG, complete the Gatekeeper flow, or grant Screen Recording permission. A person checks those, plus the restart, capture, clipboard and History, and the notes list the versions they were run on.
- [ ] The release notes say Save Captures is off by default, and that users who already have a saved history file keep their setting.
- [ ] The release notes say the app is locally signed and not notarized, and they do not call it Apple-verified.
- [ ] The release notes give both notices: the app is not notarized and needs approval on first launch, and users of
      beta.1 must install the current release by hand.
- [ ] `codesign --verify --strict` passes, the app is signed with the certificate pinned in `scripts/release-signing.txt`,
      and `spctl` reports the app as rejected, which is expected for this distribution.
- [ ] The Install steps in `docs/INSTALL.md` and `docs/i18n/INSTALL.es.md` match the dialogs seen on macOS 14 and on macOS 15 or
      later, or the release notes list the versions that were not checked.

## Steps

1. **Prepare the version.** Set the version in `Info.plist`, add the CHANGELOG section, and update the Status lines.
   Merge that through a pull request, then check that CI passes on the merge commit.

2. **Check the commit.**

   ```bash
   make check
   make build
   ```

3. **Run the manual checks** in [CONTRIBUTING.md](../CONTRIBUTING.md) on the QA build. Update the Tested section of
   the CHANGELOG to name what you ran, and nothing more.

4. **Tag the release commit** and push the tag. Create a new tag only. Never move one that exists.

   ```bash
   git tag -a vX.Y.Z -m "Nictate X.Y.Z" <commit>
   git push origin vX.Y.Z
   ```

5. **Build the image.**

   ```bash
   BUILD_NUMBER=24 make dmg
   ```

   `make dmg` builds one committed revision: `HEAD` by default, or `COMMIT=<sha>`. It never builds the working tree.
   The app's version comes from `Info.plist`, and the output goes to a new folder named after that version:

   - `build/release/X.Y.Z/Nictate-X.Y.Z.dmg`, the image
   - `build/release/X.Y.Z/SHA256SUMS`, its checksum, listing only the image's name

   `make dmg` stops before building if `BUILD_NUMBER` is not the build approved for the version in
   `scripts/release-builds.txt`, if the working tree has changes, if `CHANGELOG.md` has no section for the version, or
   if `build/release/X.Y.Z/` already exists. It never reuses or overwrites a release folder, so an image or checksum
   from an earlier release is never replaced. To write elsewhere, set `OUT_DIR=<dir>`. Use the same `BUILD_NUMBER` for
   every build of this release.

   The first run may ask to let Terminal control Finder, so the window can be styled. Answer that prompt yourself.

   The build signs with the certificate pinned in `scripts/release-signing.txt`, from the dedicated keychain. If the
   keychain is locked, the build asks for its password in the terminal; enter it. The build never falls back to another
   certificate. If the pinned certificate cannot be used, the build stops before anything is packaged, and the message
   says what to do.

6. **Check the image.**

   ```bash
   hdiutil verify build/release/X.Y.Z/Nictate-X.Y.Z.dmg
   hdiutil attach -readonly -nobrowse build/release/X.Y.Z/Nictate-X.Y.Z.dmg
   codesign --verify --strict /Volumes/Nictate/Nictate.app
   codesign -dvv /Volumes/Nictate/Nictate.app 2>&1 | grep -E 'Authority|Signature'
   /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" /Volumes/Nictate/Nictate.app/Contents/Info.plist
   hdiutil detach /Volumes/Nictate
   ```

   The version must equal the tag without the `v`. The signature must list `Authority=Nictate Local Signing`, and
   must not show `Signature=adhoc`.

7. **Verify the checksum.** `make dmg` wrote `SHA256SUMS` next to the image. Check that it matches the image.

   ```bash
   (cd build/release/X.Y.Z && shasum -a 256 -c SHA256SUMS)
   ```

8. **Create the draft, upload, and publish.** The notes are the CHANGELOG section for the version.

   ```bash
   awk -v v="X.Y.Z" '$0 ~ "^## \\[" v "\\]" {p=1; next} /^## \[/ {p=0} p' CHANGELOG.md > release-notes.md
   gh release create vX.Y.Z --draft --prerelease --verify-tag --title "Nictate X.Y.Z" --notes-file release-notes.md
   gh release upload vX.Y.Z build/release/X.Y.Z/Nictate-X.Y.Z.dmg build/release/X.Y.Z/SHA256SUMS
   gh release edit vX.Y.Z --draft=false
   ```

   Keep `--prerelease` on beta versions. GitHub's "latest release" skips pre-releases, so stable users are never
   pointed at a beta. Never upload with `--clobber` to a published release: replacing an image changes what people
   download under the same name.

9. **Check a clean install** of the published image, as described below.

## Clean install

Run this on a Mac that has not had Nictate installed, on macOS 14 and on macOS 15 or later, wherever you can. A version
you cannot test is listed as untested in the release notes. For this experimental beta that is a compatibility
limitation, not a release blocker, as long as the app builds and no known incompatibility exists. Record the macOS version,
the Mac model, and the image's SHA-256.

- [ ] Download the image and `SHA256SUMS` from the release page. `shasum -a 256 -c SHA256SUMS` prints `OK`.
- [ ] Open the image. The background, the arrow, and the icon positions are as drawn.
- [ ] Follow the Install steps of `docs/INSTALL.md` exactly, in English or Spanish. Note the wording of each dialog. If a dialog
      differs from the guide, correct the guide before the release. The steps need no Terminal command, apart from the
      optional checksum check.
- [ ] On first launch, Welcome opens at the Screen Recording step. Grant it, then restart Nictate from Welcome.
- [ ] Capture a short sample of text with the shortcut, and paste it: the text is correct.
- [ ] About shows the new version. Check for Updates reports that Nictate is up to date, since the new release is the
      newest one.
- [ ] While Check for Updates runs, the only connection is to `api.github.com`. Confirm with `lsof -nP -i -p <pid>`,
      and with a packet capture if you want proof that nothing else connects.
- [ ] No system protection was changed to open the app: no `xattr`, no `spctl --master-disable`.

## Signing identity

This is local code signing. It is not Apple Developer ID signing, and nothing here is notarized or Apple-verified.
Developer ID signing and notarization need the paid Apple Developer Program. They are a future step, to be taken when
adoption, contributor interest, or demonstrated demand justifies the cost. Until then, the beta is distributed without
them, and that limit is stated in the README and the release notes.

Four separate things are involved. Keep them apart when writing release notes or answering users:

- **Local code signing** (what Nictate uses). The app is signed with `Nictate Local Signing`, a certificate the maintainer
  created. A valid signature shows that the app is unchanged since it was signed, and that this certificate signed it.
  macOS does not trust that certificate for distribution, so Gatekeeper does not accept the app on its own.
- **Apple Developer ID signing.** The app is signed with a certificate that Apple issues to a registered developer
  through the Apple Developer Program, which is a paid program. Nictate does not use one.
- **Apple notarization.** Apple scans a Developer ID-signed app and issues a ticket. The ticket is attached to the app or
  fetched by Gatekeeper. Notarization also needs the paid program. Nictate is not notarized.
- **Gatekeeper's normal distribution requirement.** For software downloaded from the internet and distributed outside the
  Mac App Store, Gatekeeper's standard policy generally requires both Developer ID signing and notarization. An app that
  meets both opens without an approval step. Nictate meets neither, so macOS blocks its first launch until the user
  approves it in System Settings, Privacy & Security ("Open Anyway"). That manual step is expected for this beta. See
  [Apple's notarization guidance](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).

`spctl` therefore reports a Nictate build as rejected. That is expected for this distribution. It is not a build failure.

`make setup` creates the "Nictate Local Signing" identity in its own keychain,
`~/Library/Keychains/nictate-signing.keychain-db`, and prints its SHA-1. You choose its password, and nothing stores it.
The keychain locks when the Mac sleeps, and it is not in the search list, so only the build scripts name it. While it is
unlocked, any program running as you can still sign with the key, so lock it when you are done:
`security lock-keychain ~/Library/Keychains/nictate-signing.keychain-db`.

`scripts/release-signing.txt` pins the SHA-1 of the release certificate. `make dmg` signs only with that certificate,
from the dedicated keychain, and checks the signed app against the pin before it packages anything. It never falls
back to another certificate. If the pinned certificate is missing from the keychain, the keychain holds a different
certificate with the same name, or the keychain stays locked, the build stops with a message that says what to do.
Change the pin only on purpose, in a commit: a different certificate makes macOS ask every user to grant Screen
Recording again.

Development and QA builds (`make build`, `make install`, `make test-app`) keep their fallbacks: the dedicated keychain,
then the login-keychain certificate with the same name, then ad hoc. Each one prints a warning that names the identity
it used.

To release with the pinned certificate, that certificate must be in the dedicated keychain. Either move the existing
certificate there, if its private key can be exported, or create a new identity with `make setup`, pin its SHA-1, and
tell users that Screen Recording must be granted once more. Then remove the old identity and its trust setting by hand
(this script never does):

```bash
security find-certificate -c "Nictate Local Signing" -Z ~/Library/Keychains/login.keychain-db | grep SHA-1
security delete-identity -t -Z <that SHA-1> ~/Library/Keychains/login.keychain-db
```
