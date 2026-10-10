# Changelog

All notable changes to Nictate are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [1.0.0-beta.2] - public test release

The second public test release. Please report what you find: https://github.com/jrthormann/Nictate/issues

**If you have 1.0.0-beta.1:** that version reports itself as 1.0.0, so its Check for Updates cannot find this release.
Download 1.0.0-beta.2 from the [releases page](https://github.com/jrthormann/Nictate/releases) and replace the app.
From beta.2 on, Check for Updates offers newer betas and the stable release.

### Added
- SECURITY.md, with private vulnerability reporting, and a Code of Conduct.
- Manual checks for focus and unreadable history in CONTRIBUTING.md.
- README badges, a Support section, and FUNDING.yml.

### Changed
- Focus returns to the app you came from after a copy, a capture, a cycle, a cancelled capture, or Escape. It does so only while Nictate is still active and that app is still running.
- Clear on Quit waits until the history store confirms the deletion, so pending writes cannot bring cleared captures back.
- A capture appears in History only after the store has saved it.
- Reset Nictate: with "Also delete saved captures" ticked, the deletion is confirmed before the settings are reset and the app restarts. If it cannot be confirmed, history stays closed and Nictate says so. Launch at Login is unchanged.
- Turning Save Captures back on keeps the next capture at once. The question about turning it off waits for queued writes.
- An unreadable history file is never overwritten, at startup or by a capture. Discard Unreadable History appears only when the file is detected as unreadable, behind a confirmation whose default is Cancel.
- Check for Updates follows the release channel: stable users are offered stable releases, and beta users are also offered newer betas. A version that is not newer is never offered.
- A copy is confirmed by reading back only the text Nictate wrote. Nictate no longer keeps or restores the previous clipboard.
- The History list keeps the highlighted row in view. Command-F focuses the search field.
- Importing an earlier encrypted history keeps every capture, even when its stored times do not match the texts.

### Removed
- The separate History window. History is in the menu bar panel.
- The age-based retention setting, which nothing set, along with retired settings and unused strings.

### Tested
- Automated, in CI: unit tests, UI smoke tests, the localization and source checks, and the prebuilt tests on macOS 14.
- Manual, on the QA build on the maintainer's Mac (macOS 27): the focus checks and the unreadable-history check.

### Not yet tested
- macOS 14, 15 and 26 beyond the CI runs ([#2](https://github.com/jrthormann/Nictate/issues/2)).
- VoiceOver and other accessibility behaviour beyond the native labels ([#1](https://github.com/jrthormann/Nictate/issues/1)).

### Known limitations
- Not signed with an Apple Developer ID and not notarized. macOS asks you to confirm the app once; see the README.
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

