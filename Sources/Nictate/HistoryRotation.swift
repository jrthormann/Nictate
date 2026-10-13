// Nictate: a macOS menu bar app that copies text from anywhere on your screen.
// Copyright (c) 2026 jrthormann. MIT License, see LICENSE.

import Foundation

/// Something Nictate put on the clipboard, and the pasteboard's change count right after the write.
/// While the count is unchanged the clipboard still holds `text`, so it never has to be read back.
struct ClipboardWrite: Equatable, Sendable {
    let changeCount: Int
    let text: String
}

enum HistoryRotation {
    /// What the clipboard holds, as far as Nictate knows without reading it: the text of its own last write
    /// while the change count is still the one after that write, otherwise nil (something else was copied).
    static func ownClipboard(changeCount: Int, lastWrite: ClipboardWrite?) -> String? {
        guard let lastWrite, lastWrite.changeCount == changeCount else { return nil }
        return lastWrite.text
    }
}
