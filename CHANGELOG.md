# Changelog

All notable changes to Nictate are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [1.0.0-beta.4] - 2026-10-20

The fourth public test release. Please report what you find: https://github.com/jrthormann/Nictate/issues

### Changed
- **Reset Settings asks about saved captures in a second dialog.** The hidden checkbox is gone: the first dialog confirms the reset, and a second one offers Keep Captures or Delete Captures. Cancel on either does nothing.

### Fixed
- The Reset dialog's "Also delete saved captures" checkbox could stay hidden on first open ([#23](https://github.com/jrthormann/Nictate/issues/23)).

### Tested
- Automated: `make check` passes on the release commit (unit checks, UI smoke, strings, source rules, release packaging).
- Manual, on the QA build: both Reset dialogs show the expected text and buttons, and Keep Captures and Delete Captures behave as described.

### Not yet tested
- A clean install of this disk image, and the Gatekeeper and Screen Recording first-launch steps, on macOS 14, 15 and 26.
- Intel hardware: Intel is verified only under Rosetta in CI.

### Known limitations
- Signed with a local certificate, not an Apple Developer ID certificate, and not notarized. macOS asks you to approve the first launch.

## [1.0.0-beta.3] - 2026-10-15

The third public test release. Please report what you find: https://github.com/jrthormann/Nictate/issues

**Two things to know before you install:**

- **Nictate isn't notarized by Apple.** macOS asks you to approve it once, on first launch. The Install steps in the
  README show how. You don't need to turn off Gatekeeper or any other system-wide security protection.
- **It is signed with the same local certificate as beta.2**, so macOS should keep the Screen Recording permission you
  granted. If it asks again, grant it once.

### Added
- **Recent Captures.** The Recent Captures shortcut (⌥⇧⌘2) opens your saved captures in a picker over the screen, including
  over full-screen apps. Arrow keys choose, Return copies, Escape closes, and Command-F jumps to the search field. It
  replaces the Cycle History rotation.
- **A clearer selection.** The selection has rounded corner brackets and a two-tone outline, so it stands out on light
  and dark content.
- **Clearer results.** Each capture says what happened: copied, no text found, the area couldn't be read, or the copy
  failed. Each has its own symbol, and a scan line sweeps the selection while the text is read.
- **VoiceOver.** The selection has an accessibility role and keyboard help.

### Changed
- **Escape cancels from the first moment.** Escape pressed right after the shortcut cancels the capture, before the
  selection appears, and no longer reaches the app you were using.
- **Focus returns after every capture.** After a copy, a miss, a failed read, or Escape, focus goes back to the app you
  came from, unless you have moved on. A retry keeps that app.
- **A selection cancels when focus leaves.** If another app or a system dialog takes focus while the selection is up,
  the selection is cancelled instead of staying on the screen.
- **Menu-bar capture.** Capture Text and Capture Code from the menu bar wait for the popover to close, so the popover is
  not in the captured image.
- **Link question.** A result pill no longer covers the Ask Before Opening question, and Escape cancels it in every
  language.
- **Open in Browser** leaves the browser in front.

### Tested
- Automated: CI passed on the merged code of this release (PR #30, merged as `0e3feec` on `main`): build-and-test,
  intel-tests, macos-14 and ui-smoke. `make check` and `make build` pass on the release commit.
- Manual QA on the NictateTest build of this code, not the final disk image: menu-bar capture from the popover, Recent
  Captures opening, navigation and copying, Find in Recent Captures, Escape, clipboard contents after copies and cancels,
  and focus returning to the app you came from.
- Earlier builds, not this release: VoiceOver speech and keyboard guidance, Reduce Motion, and Increase Contrast on the
  capture overlay, verified by the maintainer.

### Not yet tested
- A clean install of this disk image on macOS 14, and on macOS 15 or later, on a Mac where Nictate was never installed.
- The Screen Recording consent prompt on a fresh permission state. It was not reproduced on this build.
- VoiceOver speech of "No text found" and "Couldn't copy text. Try again." on this build.
- Recent Captures while a link question is showing.
- macOS 26 beyond the CI runs ([#2](https://github.com/jrthormann/Nictate/issues/2)).

### Known limitations
- Signed with a local certificate, not an Apple Developer ID certificate, and not notarized. macOS asks you to approve the
  first launch.
- Built for macOS 14 and later. The maintainer has tested it on macOS 27 only.
- History is a plain file of the 15 most recent captures. It is not encrypted separately.
- Users with an earlier encrypted History can import it once from Settings > General > History.

## [1.0.0-beta.2] - 2026-10-11

The second public test release. Please report what you find: https://github.com/jrthormann/Nictate/issues

**Two things to know before you install:**

- **Nictate isn't notarized by Apple.** macOS asks you to approve it once, on first launch. The Install steps in the
  README show how. You don't need to turn off Gatekeeper or any other system-wide security protection.
- **If you have 1.0.0-beta.1, install beta.2 by hand.** Beta.1 reports itself as version 1.0.0, so its
  Check for Updates can't see newer releases. Download beta.2 from the [releases page](https://github.com/jrthormann/Nictate/releases) and
  replace the app in Applications. From beta.2 on, Check for Updates offers newer betas and the stable release.

### Added
- SECURITY.md, which explains how to report a vulnerability privately, and a Code of Conduct.
- A plain Install guide in the README, in English and Spanish, and a distribution section in SECURITY.md.

### Changed
- **More reliable history.** A capture appears in History only after it has been saved. Every save is read back and checked before Nictate counts it as saved.
- **Safer recovery.** Nictate never overwrites an unreadable history file, at startup or when a capture is saved. If it finds one, Discard Unreadable History appears behind a confirmation whose default is Cancel.
- **Clearing is reliable.** Clear on Quit waits until the history store confirms the deletion, so a capture that was still being saved can't come back.
- **Predictable reset.** Reset waits for pending history writes. With "Also delete saved captures" ticked, the deletion is confirmed before the settings are reset and Nictate restarts. If it can't be confirmed, History stays closed and Nictate says so. Launch at Login is kept.
- **Save Captures.** Turning it back on takes effect at once. The question about turning it off waits for pending saves.
- **Focus returns to where you were.** After a copy, a capture, a cancelled capture, or Escape, focus goes back to the app you came from, as long as Nictate is still active and that app is still running.
- **Better keyboard use in History.** The highlighted row stays in view as you move through the list, and Command-F jumps to the search field.
- **Update checks follow your channel.** Stable users get stable releases, and beta users also get newer betas. Nictate never offers a version that isn't newer than the one you run.
- **Localization.** The Reset explanation in English and Spanish now says that Launch at Login is kept.
- **Simpler History.** The separate History window is gone. History lives in the menu bar panel. The age-based retention setting, which nothing set, is removed.

### Security and privacy
- Nictate no longer keeps or restores the clipboard you had before a copy. It confirms a copy by reading back only the text it wrote.
- In Append mode, Nictate adds the current clipboard text to a new capture, but leaves out text that another app marks as concealed or transient, as password managers do.
- The README and SECURITY.md now say what the signature does and doesn't mean, and that the app isn't notarized.

### Tested
- Automated: `make check` (unit tests, UI smoke tests, the localization, source and release packaging checks) and `make build` pass on commit `9aa6b39` on `main`. The app code of this release is the same as at that commit; later changes are documentation only. CI passed for that commit on `build-and-test`, and on `macos-14`, which runs the prebuilt tests on a macOS 14 runner.
- Manual QA before publication, on QA builds of this code (not the final disk image): History selection, deletion, reopening and scrolling; copying from History, with focus returning to the previous app; Clear on Quit on and off; and Reset with its default settings. The version and build numbers were checked in the app bundle.
- Earlier QA build, not the final beta.2 build: the focus checks and the unreadable-history check, recorded by the maintainer on macOS 27.
- Earlier test build, not the final beta.2 build, checked on macOS 27.0.1: the first-launch message for a copy that is not notarized, its entry in Privacy & Security, the welcome window in English and Spanish, and the About panel and update check.

### Not yet tested
- The final beta.2 disk image: installing it, first launch, the Gatekeeper steps, and the About window's version in a running copy.
- The Install steps on macOS 14 and on macOS 15 or later, on a Mac where Nictate was never installed.
- Screen Recording permission and clipboard use in other apps, on a clean user account.
- macOS 26 beyond the CI runs ([#2](https://github.com/jrthormann/Nictate/issues/2)).
- VoiceOver and other accessibility behaviour beyond the native labels ([#1](https://github.com/jrthormann/Nictate/issues/1)).

### Known limitations
- Signed with a local certificate, not an Apple Developer ID certificate, and not notarized by Apple. macOS asks you to approve the first launch.
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

