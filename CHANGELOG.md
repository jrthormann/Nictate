# Changelog

All notable changes to Nictate are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [1.0.0-beta.1] - public test release

The first public test release of Nictate. It works as described below. It is not a fully verified
production release: see "Tested" and "Not yet tested".

### Tested
- macOS 27 (the development machine): the menu and its History (one-click copy, keyboard return, search, Escape, delete),
  and the Settings window in its default appearance.
- Nothing else is verified yet. macOS 14, 15 and 26 have not been tested by the maintainer.

### Not yet tested
- Screen capture and recognition in this release candidate (being checked before publication).
- Light and Dark appearance, and Spanish layout.
- VoiceOver and other accessibility behaviour beyond the native labels.
- Installation on a second Mac, and the Gatekeeper steps on any macOS version other than the one above.
- Signing with an Apple Developer ID and notarization (the app uses a local certificate).

### Known limitations
- The app is not notarized, so macOS asks you to confirm it once (see the README).
- History is a plain file of the 15 most recent captures. It is not encrypted separately.
- Users with an earlier encrypted History can import it once from Settings > General > History.

### Added
- **Copy the text you can see.** Press ⇧⌘2 and select an area: the text is on the clipboard in about a second.
  Recognition runs on this Mac, offline, in every language Vision supports.
- **Precise selection.** The area snaps to whole screen pixels. Arrow keys move the corner one pixel at a time, Shift with an arrow ten.
- **Codes.** QR codes and barcodes copy their content. Links from a code can be copied only, or confirmed before opening.
- **Detected content.** Colors, links, emails and phone numbers from the last capture are in the menu.
- **History.** The 15 most recent captures, searchable, with one-click copy. Saved on your Mac without additional encryption; turn it off or clear it in Settings.
- **Cycle History** through recent captures with its own shortcut, and **Append to Clipboard** to collect several captures in one paste.
- **Private Clipboard.** With the option on, Nictate asks Universal Clipboard, Handoff and clipboard managers to skip each capture, where macOS supports it. Other apps may still store what you copy.
- **Check for Updates** asks GitHub for the latest release, only when you choose it.
- **Reset Settings** returns settings to their defaults. Saved captures are kept unless you also choose to delete them.
- English and Spanish interface.
