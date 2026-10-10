// Nictate: a macOS menu bar app that copies text from anywhere on your screen.
// Copyright (c) 2026 jrthormann. MIT License, see LICENSE.

import Foundation

/// What a capture does, chosen by the shortcut or menu item that started it. The settings still decide
/// everything else (clean-up, history, notifications).
enum CaptureMode: Equatable {
    /// The normal capture: recognize text or a code, and copy it.
    case text
    /// Only QR codes and barcodes: text recognition is skipped.
    case code

    /// A code capture of a region with no code is a miss, not a text capture.
    func accepts(_ result: RecognitionResult) -> Bool { self != .code || result.isBarcode }

    var barcodesOnly: Bool { self == .code }
}
