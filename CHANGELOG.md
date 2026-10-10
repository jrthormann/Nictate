# Changelog

All notable changes to Nictate are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

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

