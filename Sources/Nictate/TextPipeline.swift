// Nictate: a macOS menu bar app that copies text from anywhere on your screen.
// Copyright (c) 2026 jrthormann. MIT License, see LICENSE.

import Foundation

/// What a recognized capture becomes before it reaches the clipboard.
enum TextPipeline {
    /// Whether table cells get tabs. With code clean-up on, the capture is code: a comment aligned to the
    /// right of each line would otherwise be read as a second column and get a tab.
    static func tablesAsTabs(setting: Bool, codeClean: Bool) -> Bool { setting && !codeClean }

    /// A QR or barcode payload is returned untouched. Otherwise: optional code clean-up, then trimming, and
    /// (outside faithful mode) joining split words and collapsing spaces when `cleanText` is on.
    static func process(_ result: RecognitionResult, codeClean: Bool, faithful: Bool, cleanText: Bool) -> String {
        guard !result.isBarcode else { return result.text }
        let source = codeClean ? CodeClean.apply(result.text, CodeCleanOptions()) : result.text
        return TextCleaner.finalize(source, preserveIndentation: faithful, dehyphenate: cleanText, collapseSpaces: cleanText)
    }
}
