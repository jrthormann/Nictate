# Architecture

Nictate is a single-process AppKit app with SwiftUI windows. It has no dependencies beyond system frameworks, runs in the App Sandbox with the hardened runtime, and has no network access.

## Capture flow

```
global hotkey (HotKeyManager, Carbon)
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
| `AppDelegate.swift` | Launch sequence (history expiry), Dock policy, global shortcuts and the alert for a shortcut the system refuses. |
| `StatusItemController.swift` | The menu bar item: icon, tooltip and VoiceOver label (in step with Append mode), the capture cue and the VoiceOver announcement. |
| `CaptureCoordinator.swift` | One capture from selection to output: recognition off the main thread, then clipboard, history and feedback. Also rotates the history and holds the latest capture's detections. |
| `MenuController.swift` | The status item's menu, rebuilt each time it opens. |
| `Log.swift` | `os.Logger` loggers per area (subsystem `com.jrthormann.nictate`); captured text is never logged. |
| `Recognizer.swift` | Region selection and Vision requests. Returns `RecognitionResult`. |
| `TextProcessing.swift` | Pure logic: `TextLayout` (layout from bounding boxes; a table, found by wide gutters or by rows with the same number of aligned short cells, marks its cells with a column index and, optionally, joins them with tabs) and `TextCleaner`. Unit tested. |
| `Design.swift` | The measurements every surface draws from: spacing grid, corner radius, secondary ink, window sizes. |
| `StorageKeys.swift` | Every persisted key and window autosave name. Values are frozen: they are what users already have saved. |
| `Settings.swift` | `ObservableObject` over `UserDefaults`; shortcut helpers. |
| `Updates.swift` | Check for Updates: one request to GitHub's latest-release API, only on the user's click; version order and the accepted release pages are unit tested. |
| `ResetNictate.swift` | Reset Nictate: confirmation, then settings and captures are cleared and the app relaunches. |
| `History.swift` / `HistoryView.swift` | Capture history (texts and capture times, kept aligned, with optional expiry) and its searchable window: Return copies, Command-F searches. Unit tested. |
| `HistoryStore.swift` | The history as one AES-GCM sealed file; the 256-bit key lives in the login Keychain (file-based, not the data protection Keychain). Tampering and a locked key are handled as separate cases. Unit tested except the Keychain itself. |
| `PreferencesController.swift` | Settings window: toolbar tabs (`GeneralTab`, `RecognitionTab`, `OutputTab`); the window resizes to each tab, capped at 80% of the screen. |
| `SettingsForm.swift` | Shared Settings components on a native grouped Form: sections, toggles, rows, captions, and the `dimmed(when:)` modifier. |
| `ShortcutRecorder.swift` | Click-to-record shortcut control. |
| `WelcomeView.swift` / `Permissions.swift` | Onboarding and Screen Recording permission. `ScreenRecordingStep.swift` decides which state the permission step shows (unit tested). |
| `NotificationStyle.swift` | None, notice only or with the text: what a capture banner says (unit tested). |
| `ShortcutBinding.swift` | `ShortcutSlot` (three actions, one optional) and the rule for replacing a shortcut: refused if any other action uses it, and the old one is restored if the system refuses (unit tested). |
| `CaptureMode.swift` | What a shortcut makes a capture do: normal, or QR/barcodes only (unit tested). |
| `NotificationGate.swift` | Asks for notification permission once, at the first notification actually sent. Unit tested. |
| `HotKeyManager.swift` | Global hotkeys, one per `ShortcutSlot`; no Accessibility permission needed. |
| `ContentDetector.swift` / `DetectionUI.swift` | Pure detection of colors, web links, emails and phone numbers (and the color format conversions), plus the menu swatch image. Unit tested. |
| `CodeClean.swift` | Pure logic: prompt, line-number and quote clean-up for code. Unit tested. |
| `HistoryRotation.swift` | Pure logic: which capture comes next when cycling the clipboard. |
| `StatusFlash.swift` | Menu bar icon feedback: soft pulse while a capture is read, then the blink (once green on success, twice red on failure), played frame by frame. |
| `EyelidTimeline.swift` | The blink as a pure function of time: how open the aperture is and how strong the line across it is. Tested without AppKit. |
| `MenuBarIcon.swift` | The menu bar glyph, drawn as template vector paths (corner brackets; a centered "+" in Append mode), and the colored blink frames with the aperture partly closed. |
| `Localization.swift` | `tr()` helper; the English text is the string key. |
| `DocumentTables.swift` | macOS 26+: Apple's document reader as a second opinion when the layout finds no table; its table is used only if its cells match Blink's own reading (unit tested). |
| `TextPipeline.swift` / `LinkPolicy.swift` | Pure rules extracted from the capture code: what a recognized capture becomes before it is copied, and which QR/barcode links may be offered to open (unit tested). |
| `ScreenStill.swift` | ScreenCaptureKit stills per display; the first complete frame of a short stream. Nothing is written to disk. |
| `SelectionOverlay.swift` | The selection windows and their view: dimming, outline, keyboard and mouse. |
| `ContentClassifier.swift` | Pure rules that decide whether a capture is code, a table, a list or prose from its text and layout. Only confident prose loses its line breaks. Tested on a 40-text corpus (`Tests/corpus/captures.tsv`) and a held-out set. |
| `ResultPill.swift` | The line beside the selection: "Reading…" when slow, then "Copied · N words" or the reason nothing was copied. Fades after 1.5 s, stays while hovered, a click dismisses it. |
| `SelectionGeometry.swift` | Pure selection arithmetic: drag rectangle, step, points to pixels and pill placement (unit tested). |
| `Notifier.swift` / `WindowCoordinator.swift` | Capture banner delivery, and the settings, history and welcome windows, split out of the app delegate. |

## Design decisions

- **Native selector:** the system tool gives the familiar crosshair, multi-display support and `Esc` handling for free, so the app draws no overlay.
- **Layout from geometry:** Vision returns one box per line. Indentation and column gaps are derived from box positions and the median character width, which is why faithful mode needs no font assumptions.
- **Pure logic, tested without Xcode:** everything that decides text output lives in `TextProcessing.swift`; `Tests/run_tests.sh` compiles it with a tiny runner and also runs Vision on rendered code.
- **English keys:** English is the development language, so the English text is the localization key and `en.lproj` maps each key to itself; `es.lproj` holds the Spanish translation. `scripts/check_strings.py` keeps both languages complete, with the same keys and the same `%@` and `%d` placeholders.
- **Settings UI:** tabs are native grouped Forms (`SettingsForm.swift`), so the system supplies the materials. Rules that faithful mode overrides are dimmed and disabled in the UI, and the engine enforces the same override in `CaptureCoordinator.capture`, so what the screen shows is what runs.
- **Clipboard privacy:** AppKit has no transient pasteboard type, so the nspasteboard.org convention (`org.nspasteboard.TransientType`) is used.
- **Deployment target:** macOS 14. `scripts/build-app.sh` passes `-target` so newer APIs are flagged at compile time.
- **Build:** `scripts/build-app.sh` compiles with `swiftc` once per architecture (`-warnings-as-errors`, `-strict-concurrency=complete`) and joins the results with `lipo`. The app is signed with the hardened runtime and `Sources/Nictate/Resources/Nictate.entitlements`.
- **Sandbox:** the entitlements enable the App Sandbox and the network client entitlement, which only Check for Updates uses (one request to GitHub's release API when the user asks).

## Known limits

- Vision can misread isolated symbols in very large or dark-theme text.
- Trailing whitespace on a line is not detectable.
- Side-by-side blocks of long lines are treated as columns; a table of long cells could be split.
- Aligned columns of very short lines (average under 20 characters, sharing an edge) are read as a table. The "known limit" tests pin this behavior and its boundary.
