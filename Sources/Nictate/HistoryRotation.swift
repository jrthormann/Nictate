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
    /// The captures Cycle History walks through: the newest `depth`, or none when history is off. A stored
    /// depth below zero (a hand-edited preference) counts as zero.
    static func items(_ history: [String], depth: Int, historyEnabled: Bool) -> [String] {
        historyEnabled ? Array(history.prefix(max(depth, 0))) : []
    }

    /// What the clipboard holds, as far as Nictate knows without reading it: the text of its own last write
    /// while the change count is still the one after that write, otherwise nil (something else was copied).
    static func ownClipboard(changeCount: Int, lastWrite: ClipboardWrite?) -> String? {
        guard let lastWrite, lastWrite.changeCount == changeCount else { return nil }
        return lastWrite.text
    }

    /// Which capture to put on the clipboard next, walking from newest to oldest and wrapping around.
    /// If the clipboard holds none of them (something else was copied since), start again at the newest.
    static func nextIndex(items: [String], clipboard: String?) -> Int? {
        guard !items.isEmpty else { return nil }
        guard let clipboard, let current = items.firstIndex(of: clipboard) else { return 0 }
        return (current + 1) % items.count
    }
}
