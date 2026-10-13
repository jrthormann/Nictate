# Architecture

Nictate is a single-process AppKit app with SwiftUI views. It depends only on system frameworks, runs in the App Sandbox with the hardened runtime, and makes no network requests except Check for Updates, which runs only when you ask for it.

## Capture flow

```
global shortcut (HotKeyManager, Carbon)
  -> CaptureCoordinator.capture
       permission missing? -> WelcomeView
  -> ScreenStill.captureAll        ScreenCaptureKit stills of every display, in memory
  -> SelectionOverlay.select       frozen stills, dimming, drag or keyboard selection
  -> Recognizer.recognize          Vision text + barcode requests, small images upscaled
  -> TextLayout.compose            reading order, columns, gaps, indentation
  -> CodeClean.apply               optional: prompts, line numbers, curly quotes
  -> TextCleaner.finalize          optional hyphen joining / space collapsing
  -> ContentDetector.detect        colors, links, emails, phone numbers -> menu section
  -> clipboard (append mode), history, status icon cue, VoiceOver, notification
```

## Modules (`Sources/Nictate/`)

| File | Responsibility |
| --- | --- |
| `main.swift` | Entry point: creates the `AppDelegate` and runs the application. |
| `AppDelegate.swift` | Launch sequence (background history load, and the Clear on Quit steps), global shortcuts, quit handling, and the alert for a shortcut the system refuses. |
| `AppRestart.swift` | Restarts Nictate: a new instance starts, then this one quits. Used after a permission is granted and after a reset. |
| `StatusItemController.swift` | The menu bar item: icon, tooltip and VoiceOver label (in step with Append mode), the capture cue and the VoiceOver announcement. |
| `StatusPanel.swift` / `StatusPanelView.swift` | The menu bar panel and its History screen: the model (keyboard selection, copying, search) and the SwiftUI view, styled as a compact native menu. |
| `CaptureCoordinator.swift` | One capture from selection to output: recognition off the main thread, then clipboard, history and feedback. Also rotates the history and holds the latest capture's detections. |
| `CapturePlan.swift` | What a finished capture does (copy, history, cue, notice). `CaptureCoordinator` carries the steps out in order. |
| `Log.swift` | `os.Logger` loggers per area (subsystem `com.jrthormann.nictate`); captured text is never logged. |
| `Recognizer.swift` | Region selection and Vision requests. Returns `RecognitionResult`. |
| `RecognitionWarmUp.swift` | Warms up Vision at launch on a utility queue, so the first capture is not slow. Returns at once and never delays the main thread. |
| `TextProcessing.swift` | Pure logic: `TextLayout` (layout from bounding boxes; a table, found by wide gutters or by rows with the same number of aligned short cells, marks its cells with a column index and, optionally, joins them with tabs) and `TextCleaner`. Unit tested. |
| `Design.swift` | The measurements every surface draws from: spacing grid, corner radius, secondary ink, window sizes. |
| `ColorTokens.swift` | The design system's colours, one per token, with light and dark values. |
| `AccessibilityLook.swift` | Which colour variant a surface draws with: the standard tokens, or the Increase Contrast ones. |
| `StorageKeys.swift` | Every persisted key and window autosave name. Values are frozen: they are what users already have saved. |
| `Settings.swift` | `ObservableObject` over `UserDefaults`; shortcut helpers, and `Settings.shortcutLabel(for:)`, the shortcut label as shown. |
| `BuildIdentity.swift` | The names that keep a build's data apart from the production app's. The QA build uses `scripts/variants/BuildIdentity.test.swift` instead. |
| `Updates.swift` | Check for Updates: one request to GitHub's latest-release API, only on the user's click; version order and the accepted release pages are unit tested. |
| `ResetNictate.swift` | Reset Nictate: confirmation, then every setting returns to its default and the app relaunches. Saved captures are deleted only if the box in the dialog is ticked. |
| `History.swift` | Capture history (texts and capture times, kept aligned), at most `HistoryPolicy.maximumHistoryEntries` (15). A change is shown only after the store has saved it; Clear on Quit waits for the store's answer. Unit tested. |
| `HistoryStore.swift` | The history as `history.json` in Application Support, written atomically and read back before a write counts as saved. No Keychain and no encryption of its own. Unit tested. |
| `HistoryDeletion.swift` | When saved captures are deleted, and which question is asked first: the switch-off and clear alerts, and `HistoryClearing.setSaveCaptures`, the one Save Captures command. |
| `HistoryRotation.swift` | Pure logic: which capture comes next when cycling the clipboard. |
| `ClipboardWriter.swift` | The one place Nictate writes the clipboard. A copy counts only after its text reads back. Only Append mode reads the current clipboard, and it skips text other apps mark as concealed or transient. |
| `Pasteboard.swift` | `NSPasteboard.replaceContents`: replaces the clipboard with a string, marked transient when the setting asks, and returns the change count. Used by `ClipboardWriter`. |
| `LegacyHistoryMigration.swift` / `ImportPreviousHistory.swift` | The one explicit import of an earlier encrypted `history.sealed`, the only code that reads the old Keychain key. Merged with current captures; the old file is never changed. Unit tested with fixtures. |
| `PreferencesController.swift` | Settings window: toolbar tabs (`GeneralTab`, `RecognitionTab`, `OutputTab`); the window resizes to each tab, capped at 80% of the screen. |
| `GeneralTab.swift` | Shortcuts, History (Save Captures, Clear on Quit, import, clear), notifications, startup and Reset. |
| `RecognitionTab.swift` | Text recognition options, languages, and the Advanced section. |
| `OutputTab.swift` | Clipboard options (Append mode, separator, private clipboard) and smart detection. |
| `SettingsForm.swift` | Shared Settings components on a native grouped Form: sections, toggles, rows, captions, and the `dimmed(when:)` modifier. |
| `ShortcutRecorder.swift` | Click-to-record shortcut control. |
| `KeyGlyph.swift` | How a key with no character is written in a shortcut label, and the matching menu key equivalent. |
| `MainMenu.swift` | The app's main menu: the application, Edit and Window menus. |
| `WelcomeView.swift` / `Permissions.swift` | Onboarding and Screen Recording permission. `ScreenRecordingStep.swift` decides which state the permission step shows (unit tested). |
| `NotificationStyle.swift` | None, notice only or with the text: what a capture banner says (unit tested). |
| `ShortcutBinding.swift` | `ShortcutSlot` (three actions, one optional) and the rule for replacing a shortcut: refused if any other action uses it, and the old one is restored if the system refuses (unit tested). |
| `CaptureMode.swift` | What a shortcut makes a capture do: normal, or QR/barcodes only (unit tested). |
| `NotificationGate.swift` | Asks for notification permission once, at the first notification actually sent. Unit tested. |
| `HotKeyManager.swift` | Global shortcuts, one per `ShortcutSlot`; no Accessibility permission needed. |
| `ContentDetector.swift` / `DetectionUI.swift` | Pure detection of colors, web links, emails and phone numbers (and the color format conversions), plus the menu swatch image. Unit tested. |
| `CodeClean.swift` | Pure logic: prompt, line-number and quote clean-up for code. Unit tested. |
| `StatusFlash.swift` | Menu bar icon feedback: soft pulse while a capture is read, then the blink (once green on success, twice red on failure), played frame by frame. |
| `EyelidTimeline.swift` | The blink as a pure function of time: how open the aperture is and how strong the line across it is. Tested without AppKit. |
| `MenuBarIcon.swift` | The menu bar glyph, drawn as template vector paths (corner brackets; a centered "+" in Append mode), and the colored blink frames with the aperture partly closed. |
| `Localization.swift` | `tr()` helper; the English text is the string key. |
| `DocumentTables.swift` | macOS 26+: Apple's document reader as a second opinion when the layout finds no table; its table is used only if its cells match Nictate's own reading (unit tested). |
| `TextPipeline.swift` / `LinkPolicy.swift` | Pure rules extracted from the capture code: what a recognized capture becomes before it is copied, and which QR/barcode links may be offered to open (unit tested). |
| `ScreenStill.swift` | ScreenCaptureKit stills per display; the first complete frame of a short stream. Nothing is written to disk. |
| `SelectionOverlay.swift` | The selection windows and their view: dimming, outline, keyboard and mouse. |
| `SelectionDrawing.swift` | What the overlay paints over its still: the still, the dim, and the selection with its edge. Drawn on a bare `CGContext`, so `make render` (`Tests/render_capture.swift`) draws the same pixels into PNG files. |
| `ContentClassifier.swift` | Pure rules that decide whether a capture is code, a table, a list or prose from its text and layout. Only confident prose loses its line breaks. Tested on a 40-text corpus (`Tests/corpus/captures.tsv`) and a held-out set. |
| `ResultPill.swift` | The line beside the selection: "Reading…" when slow, then "Copied · N words" or the reason nothing was copied. Fades after 1.5 s, stays while hovered, a click dismisses it. |
| `SelectionGeometry.swift` | Pure selection arithmetic: drag rectangle, step, points to pixels, pill placement, the outline bands (a closed ring outside the selection), and the four corner brackets (`SelectionBracket`, unit tested). |
| `ScanLine.swift` | The scan line over the selection while a slow read runs: a borderless, click-through window with no image, shown after the 300 ms working delay and closed before the result. |
| `Notifier.swift` / `WindowCoordinator.swift` | Capture banner delivery, and the settings and welcome windows, split out of the app delegate. The Dock icon shows only while one of these windows is open. Deleting saved captures withdraws every banner; the system's notification center sits behind the `NoticeCenter` seam, so tests answer it by hand. |

## Scripts

| Script | What it does |
| --- | --- |
| `scripts/build-app.sh` | Builds, signs and stages `build/Nictate.app` (`make build`). |
| `scripts/build-dmg.sh` | The release image: exports one commit, builds and signs the app, and writes `build/release/<version>/Nictate-<version>.dmg` with its `SHA256SUMS` (`make dmg`). It never overwrites a release folder. See [RELEASING.md](RELEASING.md). |
| `scripts/make_dmg_background.swift` | Draws the disk image window's background. Run by `build-dmg.sh`. |
| `scripts/check_sources.sh` | Source rules: no `NSLog` or `print`, and no file over 400 lines (`make sources`). |
| `scripts/check_strings.py` | Checks that `en` and `es` have the same keys and placeholders (`make strings`). |
| `scripts/create_signing_cert.sh` | One-time setup of the local signing identity (`make setup`), with `signing_keychain.zsh` as its helper. |
| `scripts/make_icon.swift` | Draws the app icon. Run by hand; `AppIcon.icns` is the tracked result. |
| `scripts/make_readme_art.swift` | Renders the README images, in English or another language. Run by hand. |
| `scripts/variants/BuildIdentity.test.swift` | The QA build's names, used in place of `BuildIdentity.swift` by `make test-app`. |

## Design decisions

- **Native selector:** the system tool gives the familiar crosshair, multi-display support and `Esc` handling for free, so the app draws no overlay.
- **Layout from geometry:** Vision returns one box per line. Indentation and column gaps are derived from box positions and the median character width, which is why faithful mode needs no font assumptions.
- **Pure logic, tested without Xcode:** everything that decides text output lives in `TextProcessing.swift`; `Tests/run_tests.sh` compiles it with a tiny runner and also runs Vision on rendered code.
- **English keys:** English is the development language, so the English text is the localization key and `en.lproj` maps each key to itself; `es.lproj` holds the Spanish translation. `scripts/check_strings.py` keeps both languages complete, with the same keys and the same `%@` and `%d` placeholders.
- **Settings UI:** tabs are native grouped Forms (`SettingsForm.swift`), so the system supplies the materials. Rules that faithful mode overrides are dimmed and disabled in the UI, and the engine enforces the same override in `CaptureCoordinator.capture`, so what the screen shows is what runs.
- **Clipboard privacy:** AppKit has no transient pasteboard type, so the nspasteboard.org convention (`org.nspasteboard.TransientType`) is used. Nictate confirms each copy by reading back its own text. Append mode is the one place it reads the current clipboard text, and it skips text marked concealed or transient.
- **Deployment target:** macOS 14. `scripts/build-app.sh` passes `-target` so newer APIs are flagged at compile time.
- **Build:** `scripts/build-app.sh` compiles with `swiftc` once per architecture (`-warnings-as-errors`, `-strict-concurrency=complete`) and joins the results with `lipo`. The app is signed with the hardened runtime and `Sources/Nictate/Resources/Nictate.entitlements`, using the local identity. It is not signed with an Apple Developer ID and is not notarized.
- **Sandbox:** the entitlements enable the App Sandbox and the network client entitlement, which only Check for Updates uses (one request to GitHub's release API when the user asks).

## Known limits

- Vision can misread isolated symbols in very large or dark-theme text.
- Trailing whitespace on a line is not detectable.
- Side-by-side blocks of long lines are treated as columns; a table of long cells could be split.
- Aligned columns of very short lines (average under 20 characters, sharing an edge) are read as a table. The "known limit" tests pin this behavior and its boundary.
