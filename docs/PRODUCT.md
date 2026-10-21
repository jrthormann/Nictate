# Product

> Nictate makes text visible on your screen usable.

Nictate is an independent, open-source macOS utility built to make text on your screen usable. This document says what
it is for, who it is for, and what it does today. Each requirement is marked as
implemented, assumed, or an opportunity, so the three are never mixed up. For the code, see
[ARCHITECTURE.md](ARCHITECTURE.md). For the look and the wording, see [DESIGN.md](DESIGN.md).

Nictate is also a small, complete product that shows how the work was done. Each requirement below can be checked,
and the evidence sits next to it.

## Vision

Text that is on screen but cannot be selected is information you cannot use. Nictate gives any visible text the
treatment that document text already gets: select it, copy it, paste it. It stays out of the way until its shortcut
is pressed, and nothing it reads leaves your Mac.

## The problem

Much of the text people need is on screen in a form that cannot be copied directly:

- inside an image, a screenshot, or a photo of a whiteboard or a printed page;
- in a video, a paused tutorial, or a slide someone is sharing;
- in a remote desktop, a virtual machine, or an app that does not allow selection;
- in a web page or PDF that blocks selection.

The usual workarounds are retyping the text, or uploading a screenshot to an online text recognizer. Retyping is
slow and error-prone. Uploading sends the image to someone else's server.

## Target users and use cases

These users are assumptions. They describe the situations the features were built for. No user research, usability
study, or adoption measurement has been done.

| Who | Typical capture |
|:--|:--|
| Developers and students | Code from a tutorial video, a terminal in a screen share, or a screenshot |
| Anyone reading slides, PDFs, or photos | A paragraph, a list, or a table, pasted into a document or spreadsheet |
| Support and operations staff | An error message or identifier from a remote or virtual screen |
| Anyone who needs the data, not the picture | A phone number, email, link, or color from an image; a QR code's contents |

## Needs and pain points

Needs are inferred from the design decisions. They stay assumptions until people test the app.

| Need | What gets in the way today |
|:--|:--|
| Get the text in one step | Retyping, or several steps through a web tool |
| Keep the layout that matters | Code loses its indentation; a table collapses into one line |
| Keep private text private | Screenshots are uploaded to a service that may store them |
| Stay in the current task | An app that takes focus, or a copy that fails with no explanation |
| Know what happened | A tool that copies silently, or fails without saying why |
| Control what is stored | History kept without the user knowing, or no history when wanted |

## Principles

1. **The screen is the source.** Nictate reads what is visible, at the pixel boundaries the user selected.
2. **Local by default.** Recognition runs on the Mac. The one network request is Check for Updates, and only when
   the user asks. Links open in the browser only when the user chooses.
3. **Keep the shape of the text.** Code, tables and lists keep their form. Only ordinary prose is joined.
4. **Do not take focus, and read the clipboard only as needed.** Focus goes back only to the app the user came
   from, and only while Nictate is still the active app. Nictate confirms each copy by reading back the text it wrote.
   In Append mode it reads the current clipboard text, and it skips text other apps mark as concealed or transient.
5. **Say what happened.** A finished capture reports what it copied, or why nothing was copied.
6. **Few settings, plain defaults.** Each setting answers one of the needs above.

## Functional requirements

Status is **Implemented** for everything in this table. Evidence names the code, the automated tests, or the manual
check in [CONTRIBUTING.md](../CONTRIBUTING.md) that covers it.

| ID | Requirement | Evidence |
|:--|:--|:--|
| FR-1 | A global shortcut (default ⇧⌘2) selects an area on any display and copies its text. Esc cancels, including an Esc pressed before the selection has opened: Nictate takes it, so it does not reach the app the user is in. An Esc within a few milliseconds of the shortcut can still reach that app. | `SelectionOverlay.swift`, `EscapeKeyPanel.swift`, `CaptureSession.swift`, `HotKeyManager.swift`; manual checks 2, 7 |
| FR-2 | Text is recognized on the Mac with Apple's Vision framework, in the languages Vision supports. | `Recognizer.swift`; OCR tests in `Tests/run_tests.swift` |
| FR-3 | The output follows the layout of the screen: reading order, columns, and indentation. | `TextProcessing.swift`; layout tests |
| FR-4 | With the tables option on, cells in a table are separated by tabs. | `TextProcessing.swift`, `tablesAsTabs` |
| FR-5 | Code, tables and lists keep their line breaks. Only confident prose loses them. | `ContentClassifier.swift`; `Tests/corpus/` |
| FR-6 | Optional clean-up: code prompts and line numbers removed, curly quotes straightened, hyphenated words joined. | `CodeClean.swift`, `TextCleaner`; tests |
| FR-7 | Colors, links, emails and phone numbers in the last capture are offered from the menu. | `ContentDetector.swift`, `DetectionUI.swift` |
| FR-8 | QR codes and barcodes copy their contents. A link inside one opens only when the user chooses. | `LinkPolicy.swift`, `CaptureMode.swift` |
| FR-9 | Append mode adds each capture to the clipboard with a chosen separator. Copies can be marked transient, so clipboard managers that follow the convention skip them. | `ClipboardWriter.swift`, `Pasteboard.swift` |
| FR-10 | A copy counts only after the clipboard reads back the text Nictate wrote. | `ClipboardWriter.swift` |
| FR-11 | Feedback comes as a menu bar cue, a result line beside the selection, and an optional notification. | `ResultPill.swift`, `StatusFlash.swift`, `Notifier.swift` |
| FR-12 | Up to 15 recent captures can be kept, searched, copied, and cleared. History can be cleared on quit. | `History.swift`, `HistoryStore.swift` |
| FR-13 | Captures are saved only while Save Captures is on. Turning it off asks before anything is deleted. | `HistoryDeletion.swift` |
| FR-14 | An unreadable history file is never overwritten silently. Discard is offered only after detection, behind a confirmation whose default is Cancel. | `HistoryRecovery.swift`; manual check 6 |
| FR-15 | When a capture ends, whatever the outcome (copied, nothing found, unreadable, a refused copy, or Esc), focus returns to the app the user came from, only while Nictate is still active and that app still runs. A shortcut pressed straight after keeps that app. A link the user opens stays in front, and a capture started in Settings leaves Settings in front. | `FocusReturn.swift`; focus tests; manual checks 1, 2, 3, 4, 5, 7, 8 |
| FR-16 | Reset Nictate returns settings to their defaults. Launch at Login is kept. Saved captures are deleted only if the box is ticked. | `ResetNictate.swift` |
| FR-17 | Check for Updates makes one request, when the user clicks. Stable users are offered stable releases; beta users are also offered newer betas. | `Updates.swift`; channel tests |
| FR-18 | The interface is in English and Spanish, with the same keys in both. | `make strings` (`scripts/check_strings.py`) |
| FR-19 | A welcome window asks for Screen Recording permission and explains the restart it needs. | `WelcomeView.swift`, `Permissions.swift` |

### Non-functional requirements

| ID | Requirement | Status |
|:--|:--|:--|
| NFR-1 | No account, no analytics, and no network request except Check for Updates. | Implemented; `SECURITY.md` states the scope |
| NFR-2 | History is a plain file. Nictate does not encrypt it. | Implemented; stated in the README |
| NFR-3 | macOS 14 or later, as a universal app for Apple silicon and Intel. | Implemented; CI verifies the Intel test binary only under Rosetta. No Intel-hardware run has been recorded. |
| NFR-4 | The selection appears immediately after the shortcut, and recognition is warmed up at launch. | Design goal; no latency target is measured or promised |
| NFR-5 | Light and Dark appearance, Increase Contrast, Reduce Motion, and Reduce Transparency are respected. | Partly implemented; VoiceOver not audited ([#1](https://github.com/jrthormann/Nictate/issues/1)) |
| NFR-6 | Every release is built from source with warnings treated as errors. | Implemented; `.github/workflows/ci.yml` |

## Acceptance criteria

A release is ready when all of these hold for the release commit:

1. The `build-and-test` and `macos-14` CI jobs pass.
2. The manual checks in [CONTRIBUTING.md](../CONTRIBUTING.md) pass on the QA build, on a Mac the maintainer runs.
3. The disk image installs after the Gatekeeper step in `docs/INSTALL.md` on the macOS versions the release notes list as tested.
   A version that was not tested is listed as untested. For an experimental beta, that is a limitation, not a blocker.
4. The CHANGELOG has a section for the version, and the app reports the same version.

Individual needs have their own checks. For example, "get the text in one step" holds when a two-line sample is
recognized exactly and copied after one shortcut and one drag. The 1.0.0-beta.1 CHANGELOG records that check as done.

## Distribution

1.0.0 stable will be Developer ID signed and notarized by Apple, so it can open without a Gatekeeper workaround.
Until then, public releases are 1.0.0-beta.N test releases: they are locally signed, not notarized, and require
the first-launch approval steps in [docs/INSTALL.md](INSTALL.md). They are not Apple-verified.

## Roadmap

**Now: 1.0.0-beta.5, the current public test release.** The
scope is frozen. Only fixes go in, and the feedback decides what follows. The reset-checkbox issue was resolved in
1.0.0-beta.4 by replacing the checkbox with a second dialog; see [#23](https://github.com/jrthormann/Nictate/issues/23) and the [CHANGELOG](../CHANGELOG.md).

**Before 1.0.0 stable.** These are the plan, not promises:

- Compatibility tests on macOS 14, 15 and 26 ([#2](https://github.com/jrthormann/Nictate/issues/2)).
- Every beta report labelled `blocker` has a triage decision: fixed, non-blocker, or deferred past 1.0.
- Fixes for the problems beta users report.
- Developer ID signing and Apple notarization.

**Later (1.1 at the earliest, not committed).**

- Changes that come from the first reports.
- Evaluating Swift Package Manager, only if it brings a concrete benefit.
- More automation for the release process.

**Opportunities, not planned.** A Spanish translation of this document, and a short guide with screenshots for people
who never read the source.
