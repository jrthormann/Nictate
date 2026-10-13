// Nictate: a macOS menu bar app that copies text from anywhere on your screen.
// Copyright (c) 2026 jrthormann. MIT License, see LICENSE.

import AppKit

/// What the background part of a capture hands to the main thread.
private struct Capture: Sendable {
    let result: RecognitionResult
    let text: String
    let detections: Detections
}

/// Runs a capture from selection to output: recognition off the main thread, then the clipboard,
/// history and feedback on it. Also owns what the latest capture detected.
@MainActor
final class CaptureCoordinator {
    private let settings = Settings.shared
    private let status: StatusItemController
    private let windows: WindowCoordinator
    private let notifier = Notifier()
    private var isCapturing = false
    /// Colors, links and emails found in the latest capture, offered in the menu.
    private(set) var lastDetections = Detections()
    /// Shared with the History screen, so Cycle History and Append mode know about its copies too.
    private let clipboard: ClipboardWriter

    init(status: StatusItemController, windows: WindowCoordinator, clipboard: ClipboardWriter = .shared) {
        self.status = status
        self.windows = windows
        self.clipboard = clipboard
    }

    func capture(mode: CaptureMode) {
        guard !isCapturing else { return }
        guard Permissions.isGranted else {
            Permissions.request()
            windows.showWelcome()
            return
        }
        isCapturing = true
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
            defer { isCapturing = false }
            guard let stills = await ScreenStill.captureAll() else {
                // Without the stills there is nothing to select: a revoked permission, or a screen that cannot be read.
                if Permissions.isGranted {
                    status.cue(.failure)
                    status.announce(tr("The screen could not be read"))
                } else {
                    Permissions.request()
                    windows.showWelcome()
                }
                return
            }
            // Esc or a click without a drag: nothing to copy.
            guard let region = await SelectionOverlay.select(stills) else {
                FocusReturn.shared.returnIfStillActive()
                return
            }
            // "Reading…" appears only when recognition is slow enough to notice.
            let reading = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                ResultPill.shared.show(.reading, near: region.rect, screen: region.screen)
            }
            status.beginWorking()
            let outcome = await Task.detached(priority: .userInitiated) {
                CaptureCoordinator.process(region.image, options: options, codeClean: codeClean, cleanText: cleanText,
                                           faithful: faithful, detect: detect)
            }.value
            reading.cancel()
            status.endWorking()
            finish(outcome, mode: mode, region: region)
        }
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
        if copied == true { FocusReturn.shared.returnIfStillActive() }
    }

    /// The pill beside the selection: the word count when text was copied, the refusal when the clipboard did not take
    /// it, otherwise what was missing (`copied` is nil when there was nothing to copy).
    private func showResult(_ capture: Capture, mode: CaptureMode, copied: Bool?, region: SelectedRegion) {
        let style: ResultPill.Style
        switch copied {
        case .some(true):
            let words = capture.text.split(whereSeparator: \.isWhitespace).count
            style = .success(words == 1 ? tr("Copied · 1 word") : tr("Copied · %d words", words))
        case .some(false):
            style = .miss(tr("Couldn't copy text. Try again."))
        case .none where capture.result.failed:
            style = .miss(tr("Couldn't read this area. Try again."))
        case .none:
            style = .miss(mode == .code ? tr("No code found · try a larger area") : tr("No text found · try a larger area"))
        }
        ResultPill.shared.show(style, near: region.rect, screen: region.screen)
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
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = tr("Open this link?")
            alert.informativeText = url.absoluteString
            alert.addButton(withTitle: tr("Open"))
            alert.addButton(withTitle: tr("Cancel"))
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        NSWorkspace.shared.open(url)
    }

    /// Puts the next older capture on the clipboard, wrapping around after the oldest in the rotation.
    func rotateHistory() {
        // Cycle History walks through every saved capture: the history itself is the limit.
        let items = HistoryRotation.items(History.shared.items, depth: HistoryPolicy.maximumHistoryEntries, historyEnabled: settings.historyEnabled)
        guard let index = HistoryRotation.nextIndex(items: items, clipboard: clipboard.ownText) else {
            status.cue(.failure)
            status.announce(tr("History is empty"))
            return
        }
        guard clipboard.writeVerified(items[index]) else { refuseCopy(); return }
        status.cue(.success)
        let position = tr("Capture %d of %d", index + 1, items.count)
        status.announce(position)
        notifier.notify(generic: position, text: "\(position): \(items[index].prefix(80))")
    }

    /// Copies a capture chosen from the history, with the same cue and announcement as a fresh capture.
    /// Returns false, with a spoken message, when the clipboard did not take the text.
    @discardableResult
    func copyCapture(_ text: String) -> Bool {
        guard clipboard.writeVerified(text) else {
            status.announce(tr("Couldn't copy text. Try again."))
            return false
        }
        // Silent for sighted users: the panel closes and nothing else appears. VoiceOver still hears the result.
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
