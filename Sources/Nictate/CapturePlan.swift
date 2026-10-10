// Nictate: a macOS menu bar app that copies text from anywhere on your screen.
// Copyright (c) 2026 jrthormann. MIT License, see LICENSE.

import Foundation

/// One thing a finished capture does. CaptureCoordinator carries them out in the order given.
enum CaptureEffect: Equatable {
    /// Keep what the capture detected, for the menu.
    case remember(Detections)
    case copy(String)
    case cue(CaptureOutcome)
    /// Spoken by VoiceOver.
    case announce(String)
    case addToHistory(String)
    case notify(generic: String, text: String)
    /// A link from a QR code or barcode, offered to open after showing its address.
    case offerLink(URL)
}

/// The clipboard as Append mode finds it.
struct ExistingClipboard: Equatable, Sendable {
    let text: String?
    /// Another app marked the item concealed or transient (nspasteboard.org), as password managers do. It is
    /// never republished: Nictate's copy would outlive the other app's clean-up and could lose the marker.
    let isPrivate: Bool
}

/// What a finished capture does, decided as a pure value from the recognition result, the settings and the
/// clipboard, so that every branch can be tested without a screen, a pasteboard or a status item.
enum CapturePlan {
    /// The settings a capture's outcome depends on, read once on the main thread.
    struct Choices: Equatable {
        var appendMode: Bool
        var delimiter: String
        var historyEnabled: Bool
        var barcodeAction: String
    }

    /// `existing` is only consulted in Append mode, and the caller only reads the clipboard then.
    static func effects(mode: CaptureMode, result: RecognitionResult, text: String, detections: Detections,
                        choices: Choices, existing: ExistingClipboard?) -> [CaptureEffect] {
        guard mode.accepts(result) else { return miss(tr("No code found")) }
        // Whitespace-only text is not a capture. The text itself is never trimmed: a valid capture keeps its spaces.
        guard !text.allSatisfy(\.isWhitespace) else { return miss(tr("No text found")) }

        let appendTo = existing.flatMap { $0.isPrivate ? nil : $0.text }
        let output = TextCleaner.clipboardText(new: text, existing: appendTo, appendMode: choices.appendMode,
                                               delimiter: choices.delimiter)
        let done = choices.appendMode ? tr("Text added") : tr("Text copied")
        var effects: [CaptureEffect] = [.remember(detections), .copy(output), .cue(.success), .announce(done)]
        if choices.historyEnabled { effects.append(.addToHistory(text)) }
        effects.append(.notify(generic: done, text: String(text.prefix(120))))
        // QR codes and barcodes that hold a web link: ask first, or just keep the text.
        if result.isBarcode, let url = LinkPolicy.urlToConfirm(in: text, action: choices.barcodeAction) {
            effects.append(.offerLink(url))
        }
        return effects
    }

    /// A capture that found nothing usable: visual cue, VoiceOver and (per the notification style) a banner.
    private static func miss(_ message: String) -> [CaptureEffect] {
        [.cue(.failure), .announce(message), .notify(generic: message, text: message)]
    }
}
