// Nictate: a macOS menu bar app that copies text from anywhere on your screen.
// Copyright (c) 2026 jrthormann. MIT License, see LICENSE.

import AppKit

/// What the background part of a capture hands to the main thread.
private struct Capture: Sendable {
    let result: RecognitionResult
    let text: String
    let detections: Detections
}

/// What a capture takes from the system. Tests replace it to stand in for the screen and the permission.
struct CaptureSource {
    /// Whether Screen Recording is granted.
    var permitted: @MainActor () -> Bool = { Permissions.isGranted }
    /// Whether another app is in front. Until the selection opens the keys go to the front app, so only then is the key panel needed:
    /// started from Nictate's own panel or windows, Nictate is already the active app.
    var otherAppInFront: @MainActor () -> Bool = {
        NSWorkspace.shared.frontmostApplication.map { $0.processIdentifier != getpid() } ?? false
    }
    /// The stills of every display, or nil when none can be read.
    var stills: @MainActor () async -> [DisplayStill]? = { await ScreenStill.captureAll() }
}

/// Runs a capture from selection to output: recognition off the main thread, then the clipboard,
/// history and feedback on it. Also owns what the latest capture detected.
@MainActor
final class CaptureCoordinator {
    private let settings = Settings.shared
    private let status: StatusItemController
    private let windows: WindowCoordinator
    private let notifier = Notifier()
    private let source: CaptureSource
    /// Holds the keyboard from the shortcut until the selection opens, so an Esc in that gap cancels the capture instead of
    /// reaching the app the user is in. Made once at launch, hidden until a capture needs it.
    private let keyPanel = EscapeKeyPanel()
    /// The capture under way, from the shortcut until it ends or an Esc cancels it. Nil between captures.
    private var session: CaptureSession?
    var isCapturing: Bool { session != nil }
    /// Colors, links and emails found in the latest capture, offered in the menu.
    private(set) var lastDetections = Detections()
    /// Shared with the History screen and Append mode, so both know about its copies too.
    private let clipboard: ClipboardWriter

    init(status: StatusItemController, windows: WindowCoordinator, clipboard: ClipboardWriter = .shared,
         source: CaptureSource = CaptureSource()) {
        self.status = status
        self.windows = windows
        self.clipboard = clipboard
        self.source = source
        keyPanel.onEscape = { [weak self] in self?.escapePressed() }
    }

    func capture(mode: CaptureMode) {
        guard session == nil else { return }
        let session = CaptureSession()
        self.session = session
        // First of all, before even the permission check (about 13 ms while it is granted): until the key panel is key, an Esc
        // still reaches the app the user is in.
        if source.otherAppInFront() { keyPanel.present(near: NSEvent.mouseLocation) }
        guard source.permitted() else {
            end(session)
            Permissions.request()
            windows.showWelcome()
            return
        }
        // Faithful mode fixes the layout rules: every line break, columns read in order, no correction.
        let faithful = settings.codeMode
        let options = RecognitionOptions(
            languages: settings.languages,
            keepLineBreaks: faithful || settings.keepLineBreaks,
            languageCorrection: !faithful && settings.languageCorrection,
            preserveIndentation: faithful,
            detectColumns: faithful || settings.detectColumns,
            tablesAsTabs: TextPipeline.tablesAsTabs(setting: settings.tablesAsTabs, codeClean: settings.codeClean),
            barcodesOnly: mode.barcodesOnly)
        let codeClean = settings.codeClean, cleanText = settings.cleanText, detect = settings.detectContent

        Task { @MainActor in
            defer { end(session) }
            let stills = await source.stills()
            switch session.stillsReturned(available: stills != nil) {
            case .stop: return // An Esc cancelled it while the stills were taken: no selection, no cue, nothing copied.
            case .reportFailure: return reportUnreadableScreen()
            case .selectArea: break
            }
            guard let stills else { return }
            // The key panel stays up until the selection has activated Nictate and keyed its windows, so the keyboard is never
            // without a Nictate window (an Esc in that gap would reach the app the user is in). Esc or a click without a drag:
            // nothing to copy.
            guard let region = await SelectionOverlay.select(stills, whenOpen: { [keyPanel] in keyPanel.dismiss() }) else {
                FocusReturn.shared.returnIfStillActive()
                return
            }
            // The scan line and "Reading…" appear only when recognition is slow enough to notice. The line is closed
            // before the copy, so it is never on screen when the next capture takes its stills.
            let reading = ReadingPresentation(rect: region.rect, screen: region.screen)
            reading.start()
            // Any later exit cancels the timer, closes the line and stops the pulse. The explicit calls below run first
            // on the normal path. It cannot take down a "Reading…" pill the timer has shown, so an early exit added
            // between the timer and the result must show a result (through showResult) or hide the pill.
            defer { reading.end(); status.endWorking() }
            status.beginWorking()
            let outcome = await Task.detached(priority: .userInitiated) {
                CaptureCoordinator.process(region.image, options: options, codeClean: codeClean, cleanText: cleanText,
                                           faithful: faithful, detect: detect)
            }.value
            reading.end() // Before the clipboard write, the result pill and focus return.
            status.endWorking()
            finish(outcome, mode: mode, region: region)
        }
    }

    /// An Esc taken by the key panel cancels the capture. The panel comes down first: while it is key, NSApp.isActive reads true
    /// although Nictate never became the active app, and the focus code reads that.
    private func escapePressed() {
        guard let session else { return }
        let selectionOpen = session.phase == .selecting
        guard session.escape() else { return }
        keyPanel.dismiss()
        if selectionOpen {
            // The selection is on screen and Nictate is the active app: cancelled as its own Esc does, which returns focus.
            SelectionOverlay.cancelActive()
            return
        }
        // The app the user is in never lost the front, so it is forgotten, not returned to: activating it would only churn focus.
        end(session)
        FocusReturn.shared.forget()
        Log.capture.notice("Capture cancelled before the selection opened")
    }

    /// Without the stills there is nothing to select: a revoked permission, or a screen that cannot be read.
    private func reportUnreadableScreen() {
        keyPanel.dismiss() // Before NSApp.isActive is read below, as in `escapePressed`.
        if source.permitted() {
            status.cue(.failure)
            status.announce(tr("The screen could not be read"))
            FocusReturn.shared.returnIfStillActive() // Started from the panel, Nictate is active.
        } else {
            Permissions.request()
            windows.showWelcome()
        }
    }

    /// The one teardown, for every way a capture ends: cancelled, unreadable, finished. It takes the key panel down and clears the
    /// session, and a second call finds nothing to do. Only the current capture touches the panel: after a cancel a new shortcut
    /// can start another capture while the cancelled one still waits for its stills.
    private func end(_ finished: CaptureSession) {
        finished.end()
        guard session === finished else { return }
        keyPanel.dismiss()
        session = nil
    }

    /// Recognition and text work, off the main thread: detection is pure and can take tens of milliseconds
    /// on digit-heavy text, so only the result comes back to the main thread.
    private nonisolated static func process(_ image: CGImage, options: RecognitionOptions, codeClean: Bool,
                                            cleanText: Bool, faithful: Bool, detect: Bool) -> Capture {
        let result = Recognizer.recognize(image, options: options)
        let text = TextPipeline.process(result, codeClean: codeClean, faithful: faithful, cleanText: cleanText)
        let detections = detect && !result.isBarcode && !text.isEmpty
            ? ContentDetector.detect(in: String(text.prefix(20_000))) : Detections()
        return Capture(result: result, text: text, detections: detections)
    }

    private func finish(_ capture: Capture, mode: CaptureMode, region: SelectedRegion) {
        // The clipboard is read only in Append mode: nothing of an earlier capture can reach this one
        // otherwise, and macOS can ask the user for permission when an app reads the pasteboard.
        let existing = settings.appendMode ? clipboard.existingForAppend() : nil
        let choices = CapturePlan.Choices(appendMode: settings.appendMode, delimiter: settings.appendDelimiter,
                                          historyEnabled: settings.historyEnabled, barcodeAction: settings.barcodeAction)
        let planned = CapturePlan.effects(mode: mode, result: capture.result, text: capture.text,
                                          detections: capture.detections, choices: choices, existing: existing)
        // The copy is made first and read back: whether the clipboard took the text decides everything after it.
        // nil: the plan has nothing to copy (a miss).
        let copied = planned.compactMap(\.copiedText).first.map { clipboard.writeVerified($0) }
        for effect in CapturePlan.settled(planned, copied: copied ?? false) { perform(effect) }
        showResult(capture, mode: mode, copied: copied, region: region)
        // Every outcome gives focus back, copied or not (FR-15). A link the user opened has already let it go.
        FocusReturn.shared.returnIfStillActive()
    }

    private func showResult(_ capture: Capture, mode: CaptureMode, copied: Bool?, region: SelectedRegion) {
        let style = Self.resultStyle(copied: copied, failed: capture.result.failed, mode: mode, text: capture.text)
        ResultPill.shared.show(style, near: region.rect, screen: region.screen)
    }

    /// The pill beside the selection: "Copied" with the word count only when the clipboard took the text, a failure when
    /// it refused the text or Vision could not read the area, and otherwise what was missing. `copied` is nil when there
    /// was nothing to copy.
    static func resultStyle(copied: Bool?, failed: Bool, mode: CaptureMode, text: String) -> ResultPill.Style {
        switch copied {
        case .some(true):
            let words = text.split(whereSeparator: \.isWhitespace).count
            return .success(words == 1 ? tr("Copied · 1 word") : tr("Copied · %d words", words))
        case .some(false):
            return .failure(tr("Couldn't copy text. Try again."))
        case .none where failed:
            return .failure(tr("Couldn't read this area. Try again."))
        case .none:
            return .miss(mode == .code ? tr("No code found · try a larger area") : tr("No text found · try a larger area"))
        }
    }

    private func perform(_ effect: CaptureEffect) {
        switch effect {
        case .remember(let detections): lastDetections = detections
        case .copy: break // Made in finish, before the effects that depend on it.
        case .cue(let outcome): status.cue(outcome)
        case .announce(let message): status.announce(message)
        case .addToHistory(let text): History.shared.add(text)
        case .notify(let generic, let text): notifier.notify(generic: generic, text: text)
        case .offerLink(let url): openLink(url)
        }
    }

    /// Opens a link, first showing its full address when the user chose "ask before opening".
    /// Links found in recognized text are only ever opened through an explicit action like this one.
    func openLink(_ url: URL) {
        let opening = LinkPolicy.opening(url, action: settings.barcodeAction)
        guard opening != .refuse else {
            Log.app.notice("Refused to open a link whose scheme is not http, https or mailto")
            return
        }
        if opening == .ask {
            // Nothing of a capture may sit over the question: "Reading…" has ended, and the result shows once it is answered.
            ResultPill.shared.hide(animated: false)
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = tr("Open this link?")
            alert.informativeText = url.absoluteString
            alert.addButton(withTitle: tr("Open"))
            // Escape cancels the question in every language: the Cancel button's key equivalent is set explicitly.
            alert.addButton(withTitle: tr("Cancel")).keyEquivalent = "\u{1B}"
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        // The user chose the browser, so the app they came from is let go and never brought back over the page.
        if NSWorkspace.shared.open(url) { FocusReturn.shared.forget() }
    }

    /// Copies a capture chosen from Recent Captures. The menu bar icon blinks to confirm it, and VoiceOver hears the result.
    /// Returns false, with a spoken message, when the clipboard did not take the text.
    @discardableResult
    func copyCapture(_ text: String) -> Bool {
        guard clipboard.writeVerified(text) else {
            refuseCopy()
            return false
        }
        status.cue(.success)
        status.announce(tr("Text copied"))
        return true
    }

    /// Copies a value found in the latest capture, from the menu.
    func copyDetected(_ value: String) {
        guard clipboard.writeVerified(value) else { refuseCopy(); return }
        status.cue(.success)
        status.announce(tr("Text copied"))
    }

    /// A copy the clipboard did not take: the failure cue, and VoiceOver says so. Nothing is recorded as copied.
    private func refuseCopy() {
        status.cue(.failure)
        status.announce(tr("Couldn't copy text. Try again."))
    }
}
