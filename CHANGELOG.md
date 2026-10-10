# Changelog

All notable changes to Nictate are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [1.0.0-beta.2] - public test release

The second public test release. Please report what you find: https://github.com/jrthormann/Nictate/issues

**If you have 1.0.0-beta.1:** that version reports itself as 1.0.0, so its Check for Updates cannot find this release.
Download 1.0.0-beta.2 from the [releases page](https://github.com/jrthormann/Nictate/releases) and replace the app.
From beta.2 on, Check for Updates offers newer betas and the stable release.

### Added
- SECURITY.md, which explains how to report a vulnerability privately, and a Code of Conduct.
- Manual checks for focus and unreadable history in CONTRIBUTING.md.
- README badges, a Support section, and FUNDING.yml.

### Changed
- **Safer history.** A capture appears in History only after the store has saved it, and every save is read back and checked before Nictate reports success.
- **Unreadable history is never overwritten.** Nictate leaves an unreadable history file alone, at startup and when a capture is saved. Discard Unreadable History appears only then, behind a confirmation whose default is Cancel.
- **Clear on Quit is reliable.** Nictate waits for the history store to confirm the deletion, so a capture that was still being written cannot come back.
- **Reset is clearer.** Reset waits for pending history writes. With "Also delete saved captures" ticked, the deletion is confirmed before the settings are reset and Nictate restarts. If it cannot be confirmed, History stays closed and Nictate says so. Launch at Login is kept.
- **Save Captures.** Turning it back on takes effect at once. The question about turning it off waits for queued writes.
- **Focus returns to where you were.** After a copy, a capture, a cancelled capture, or Escape, focus goes back to the app you came from. It does so only while Nictate is still active and that app is still running.
- **Keyboard.** The highlighted row in History stays in view as you move through the list, and Command-F focuses the search field.
- **Update checks follow your channel.** Stable users are offered stable releases, and beta users are also offered newer betas. A version that is not newer than the one you run is never offered.
- **Localization.** The Reset explanation in English and Spanish now says that Launch at Login is kept.
- **Simpler History.** The separate History window is gone. History lives in the menu bar panel. The age-based retention setting, which nothing set, and unused text are removed.

### Security and privacy
- Nictate no longer keeps or restores the clipboard you had before a copy. A copy is confirmed by reading back only the text Nictate wrote.
- In Append mode, Nictate adds the current clipboard text to a new capture, but leaves out text that another app marks as concealed or transient, as password managers do.
- SECURITY.md explains how to report a vulnerability privately.

### Tested
- Automated: `make check` (unit tests, UI smoke tests, the localization and source checks) and `make build`, on the release commit, on the maintainer's Mac. The app code is the same as commit `25e13c2`, whose CI jobs `build-and-test` and `macos-14` passed on GitHub. The `macos-14` job runs the prebuilt tests on a macOS 14 runner.
- Manual, recorded by the maintainer for the QA build on macOS 27: the focus checks and the unreadable-history check. Not run again for this release.

### Not yet tested
- macOS 14, 15 and 26 beyond the CI runs ([#2](https://github.com/jrthormann/Nictate/issues/2)).
- VoiceOver and other accessibility behaviour beyond the native labels ([#1](https://github.com/jrthormann/Nictate/issues/1)).

### Known limitations
- Signed with a local certificate, not an Apple Developer ID certificate, and not notarized by Apple. macOS may block the first launch; the README explains how to open it with the system's own controls.
- Built for macOS 14 and later. The maintainer has tested it on macOS 27 only.
- History is a plain file of the 15 most recent captures. It is not encrypted separately.
- Users with an earlier encrypted History can import it once from Settings > General > History.

## [1.0.0-beta.1] - public test release

The first public test release of Nictate. Please report what you find: https://github.com/jrthormann/Nictate/issues

### Tested (macOS 27, the maintainer's Mac)
- Text capture with ⇧⌘2: a two-line sample was recognised exactly, and the text was copied to the clipboard.
- Cancelling a capture with Escape left the clipboard unchanged.
- QR code recognition: a generated QR code was recognised and copied exactly.
- The menu opens under its icon, and History opens from it with one click.
- In History: copying an entry, Return to copy, search, Escape steps, and delete.
- History is kept after the app quits and starts again.
- The app starts without an authorization or Keychain prompt.

### Not yet tested
- Barcodes other than QR codes.
- Settings persistence after a restart, Reset Settings, and shortcut recording.
- Light and Dark appearance, and the Spanish layout.
- The 15-capture limit in the running app (covered by automated tests only).
- VoiceOver and other accessibility behaviour beyond the native labels.
- macOS 14, 15 and 26: not tested by the maintainer. Compatibility testing is tracked at https://github.com/jrthormann/Nictate/issues/2

### Known limitations
- Not signed with an Apple Developer ID and not notarized. macOS asks you to confirm the app once; see the README.
- History is a plain file of the 15 most recent captures. It is not encrypted separately.
- Users with an earlier encrypted History can import it once from Settings > General > History.
- Accessibility has not been audited: https://github.com/jrthormann/Nictate/issues/1

