# Releasing Nictate

The disk image people download is built and signed on the maintainer's Mac. CI tests the release commit, and it never
publishes anything: it does not create releases, upload images, or move tags.

The image carries a fixed local signature, not an ad-hoc one. macOS ties the Screen Recording permission to the code
signature, and an ad-hoc signature differs on every build, so each update would ask users for Screen Recording again.
The same identity on every release keeps the permission across updates. The image is not notarized, which needs a paid
Apple Developer account.

## Checklist

- [ ] The release commit is on `main`, and CI passes on it (`build-and-test` and `macos-14`).
- [ ] `Sources/Nictate/Resources/Info.plist` has the new `CFBundleShortVersionString`.
- [ ] `CHANGELOG.md` has a section for that version. Its Tested section lists only what was run.
- [ ] The Status line in `README.md` and `docs/i18n/README.es.md` names the new version.
- [ ] `make check` and `make build` pass on the release commit, with no warnings.
- [ ] The six manual checks in [CONTRIBUTING.md](../CONTRIBUTING.md) pass on the QA build (`make test-app`).
- [ ] The new tag points at the release commit. No existing tag was moved.
- [ ] `make dmg` built the image with the local identity, and the artifact checks pass.
- [ ] The draft release has the image and `SHA256SUMS`, and its notes are the CHANGELOG section.
- [ ] The published image installs on a second Mac, and the About window shows the new version.

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
   make dmg
   ```

   The image is written to `build/Nictate-X.Y.Z.dmg`. The first run may ask to let Terminal control Finder, so the
   window can be styled. Answer that prompt yourself.

   The build signs with the identity in the dedicated keychain once `make setup` has created it. Until then it uses the
   older identity in the login keychain, which is also stable. If the signing keychain is locked, the build asks for
   its password in the terminal; enter it. Read the output before you publish: a warning about signing means the build
   did not use the identity you intended. `make dmg` refuses an ad-hoc build, but it cannot tell which stable identity
   was used, so the output is the check.

6. **Check the image.**

   ```bash
   hdiutil verify build/Nictate-X.Y.Z.dmg
   hdiutil attach -readonly -nobrowse build/Nictate-X.Y.Z.dmg
   codesign --verify --strict /Volumes/Nictate/Nictate.app
   codesign -dv /Volumes/Nictate/Nictate.app 2>&1 | grep -E 'Authority|Signature'
   /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" /Volumes/Nictate/Nictate.app/Contents/Info.plist
   hdiutil detach /Volumes/Nictate
   ```

   The version must equal the tag without the `v`. The signature must list `Authority=Nictate Local Signing`, and
   must not show `Signature=adhoc`.

7. **Write the checksum**, so the file holds only the image's name.

   ```bash
   (cd build && shasum -a 256 Nictate-X.Y.Z.dmg > SHA256SUMS)
   ```

8. **Create the draft, upload, and publish.** The notes are the CHANGELOG section for the version.

   ```bash
   awk -v v="X.Y.Z" '$0 ~ "^## \\[" v "\\]" {p=1; next} /^## \[/ {p=0} p' CHANGELOG.md > release-notes.md
   gh release create vX.Y.Z --draft --prerelease --verify-tag --title "Nictate X.Y.Z" --notes-file release-notes.md
   gh release upload vX.Y.Z build/Nictate-X.Y.Z.dmg build/SHA256SUMS
   gh release edit vX.Y.Z --draft=false
   ```

   Keep `--prerelease` on beta versions. GitHub's "latest release" skips pre-releases, so stable users are never
   pointed at a beta. Never upload with `--clobber` to a published release: replacing an image changes what people
   download under the same name.

9. **Check a clean install** of the published image, as described below.

## Clean install

Run this on a Mac that has not had Nictate installed, on macOS 14 and on macOS 15 or later. Record the macOS version,
the Mac model, and the image's SHA-256.

- [ ] Download the image and `SHA256SUMS` from the release page. `shasum -a 256 -c SHA256SUMS` prints `OK`.
- [ ] Open the image. The background, the arrow, and the icon positions are as drawn.
- [ ] Follow the Install section of the README exactly. Note the wording of each dialog. If a dialog differs from the
      README, correct the README before the release.
- [ ] On first launch, Welcome opens at the Screen Recording step. Grant it, then restart Nictate from Welcome.
- [ ] Capture a short sample of text with the shortcut, and paste it: the text is correct.
- [ ] About shows the new version. Check for Updates reports that Nictate is up to date, since the new release is the
      newest one.
- [ ] While Check for Updates runs, the only connection is to `api.github.com`. Confirm with `lsof -nP -i -p <pid>`,
      and with a packet capture if you want proof that nothing else connects.
- [ ] No system protection was changed to open the app: no `xattr`, no `spctl --master-disable`.

## Signing identity

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
