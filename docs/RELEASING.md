# Releasing Nictate

The disk image people download is built and signed on the maintainer's Mac. CI tests the release commit, and it never
publishes anything: it does not create releases, upload images, or move tags.

The image is signed with the local identity `Nictate Local Signing`. That is local code signing, not Apple Developer ID
signing, and the image is not notarized. Nictate is an independent open-source project, and it does not use the paid
Apple Developer Program. A fixed local identity gives every release the same signature, which keeps the Screen Recording
permission across updates (an ad-hoc signature differs on every build). Because the image is not notarized, macOS may
block its first launch; the README explains how to open it with the system's own controls.

## Checklist

- [ ] The release commit is on `main`, and CI passes on it (`build-and-test` and `macos-14`).
- [ ] The image is built from that commit: `git status` is clean, and `git rev-parse --short HEAD` matches the tag.
- [ ] `BUILD_NUMBER` is set and is above the previous release's build: beta.1 is 21, beta.2 is 22. The commit count is
      not a release number, since the history restarted when the project moved to `jrthormann/Nictate`. CI builds use
      the run number, which is not a release number either.
- [ ] `Sources/Nictate/Resources/Info.plist` has the new `CFBundleShortVersionString`.
- [ ] `CHANGELOG.md` has a section for that version. Its Tested section lists only what was run.
- [ ] The Status line in `README.md` and `docs/i18n/README.es.md` names the new version.
- [ ] `make check` and `make build` pass on the release commit, with no warnings.
- [ ] The six manual checks in [CONTRIBUTING.md](../CONTRIBUTING.md) pass on the QA build (`make test-app`).
- [ ] The new tag points at the release commit. No existing tag was moved.
- [ ] `BUILD_NUMBER=<n> make dmg` built the image in a new `build/release/<version>/` folder with the local identity, and
      the artifact checks in step 6 pass.
- [ ] The draft release has the image and `SHA256SUMS`, and its notes are the CHANGELOG section.
- [ ] The About window shows the new version. Clean installs on macOS 14 and on macOS 15 or later are run, or listed as
      untested in the release notes.
- [ ] The release notes say the app is locally signed and not notarized, and they do not call it Apple-verified.
- [ ] The release notes give both notices: the app is not notarized and needs approval on first launch, and beta.1 users
      must install beta.2 by hand.
- [ ] `codesign --verify --strict` passes, the signature lists `Nictate Local Signing`, and `spctl` reports the app as
      rejected, which is expected for this distribution.
- [ ] The Install steps in `README.md` and `docs/i18n/README.es.md` match the dialogs seen on macOS 14 and on macOS 15 or
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
   BUILD_NUMBER=22 make dmg
   ```

   `make dmg` builds one committed revision: `HEAD` by default, or `COMMIT=<sha>`. It never builds the working tree.
   The app's version comes from `Info.plist`, and the output goes to a new folder named after that version:

   - `build/release/X.Y.Z/Nictate-X.Y.Z.dmg`, the image
   - `build/release/X.Y.Z/SHA256SUMS`, its checksum, listing only the image's name

   `make dmg` stops before building if `BUILD_NUMBER` is missing or is not a whole number, if the working tree has
   changes, if `CHANGELOG.md` has no section for the version, or if `build/release/X.Y.Z/` already exists. It never
   reuses or overwrites a release folder, so an image or checksum from an earlier release is never replaced. To write
   elsewhere, set `OUT_DIR=<dir>`. Use the same `BUILD_NUMBER` for every build of this release.

   The first run may ask to let Terminal control Finder, so the window can be styled. Answer that prompt yourself.

   The build signs with the identity in the dedicated keychain once `make setup` has created it. Until then it uses the
   older identity in the login keychain, which is also stable. If the signing keychain is locked, the build asks for
   its password in the terminal; enter it. The build refuses any app that is not signed with `Nictate Local Signing`,
   so a successful build used the identity it should have.

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
- [ ] Follow the Install steps of the README exactly, in English or Spanish. Note the wording of each dialog. If a dialog
      differs from the README, correct the README before the release. The steps need no Terminal command, apart from the
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

Three different things are easy to confuse:

- **A valid code signature** shows that the app is unchanged since it was signed. `codesign --verify --strict` checks
  it. Nictate has one, made with the local identity. The signature identifies the signer; it does not show that Apple
  has checked the app.
- **Apple Developer ID signing** uses a certificate that Apple issues to a registered developer. It requires the paid
  Apple Developer Program. Nictate does not have it.
- **Notarization** is Apple's automated check of a signed app. A notarized app can pass Gatekeeper without the
  approval step. It also requires the paid program. Nictate is not notarized.

Gatekeeper accepts the second and third kinds. `spctl` therefore reports a Nictate build as rejected. That is expected for
this distribution, and the release notes say so. It is not a failure of the build.

`make setup` creates the "Nictate Local Signing" identity in its own keychain,
`~/Library/Keychains/nictate-signing.keychain-db`. You choose its password, and nothing stores it. The keychain locks
when the Mac sleeps, and it is not in the search list, so only the build script names it. While it is unlocked, any
program running as you can still sign with the key, so lock it when you are done:
`security lock-keychain ~/Library/Keychains/nictate-signing.keychain-db`. Keep the same identity for every release.

Older builds used a certificate in the login keychain, which `build-app.sh` still uses as a fallback. A different
certificate asks users for Screen Recording again, so move to the new one once and then stop using the old one. To
remove the old identity and its trust setting, run these by hand:

```bash
security find-certificate -c "Nictate Local Signing" -Z ~/Library/Keychains/login.keychain-db | grep SHA-1
security delete-identity -t -Z <that SHA-1> ~/Library/Keychains/login.keychain-db
```
