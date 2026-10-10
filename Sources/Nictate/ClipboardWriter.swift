// Nictate: a macOS menu bar app that copies text from anywhere on your screen.
// Copyright (c) 2026 jrthormann. MIT License, see LICENSE.

import AppKit

/// The one place Nictate writes the clipboard: captures, Cycle History, the History window and the menu all
/// go through it. It remembers its latest write, so Cycle History and Append mode know what the clipboard
/// holds while nothing else has been copied, without reading it back.
@MainActor
final class ClipboardWriter {
    static let shared = ClipboardWriter()

    private let pasteboard: NSPasteboard
    /// The write itself. Tests replace it to simulate a clipboard that refuses the text.
    private let replace: (NSPasteboard, String, Bool) -> Int
    private(set) var lastWrite: ClipboardWrite?

    init(pasteboard: NSPasteboard = .general,
         replace: @escaping (NSPasteboard, String, Bool) -> Int = { $0.replaceContents(with: $1, transient: $2) }) {
        self.pasteboard = pasteboard
        self.replace = replace
    }

    /// Replaces the clipboard with `text` and returns the change count of this write.
    @discardableResult
    func write(_ text: String, transient: Bool = Settings.shared.hideFromClipboardManagers) -> Int {
        let changeCount = replace(pasteboard, text, transient)
        lastWrite = ClipboardWrite(changeCount: changeCount, text: text)
        return changeCount
    }

    /// Writes `text` and reads back only that text before reporting success. The previous clipboard is never read,
    /// so other apps' contents (including concealed or transient entries) are not touched or kept. A refused write
    /// reports failure and is not remembered as Nictate's.
    func writeVerified(_ text: String, transient: Bool = Settings.shared.hideFromClipboardManagers) -> Bool {
        let changeCount = replace(pasteboard, text, transient)
        guard pasteboard.string(forType: .string) == text else { return false }
        lastWrite = ClipboardWrite(changeCount: changeCount, text: text)
        return true
    }

    /// The text of the latest write while it is still on the clipboard, otherwise nil.
    var ownText: String? {
        HistoryRotation.ownClipboard(changeCount: pasteboard.changeCount, lastWrite: lastWrite)
    }

    /// What Append mode would add to.
    func existingForAppend() -> ExistingClipboard {
        ExistingClipboard.read(from: pasteboard, lastWrite: lastWrite)
    }
}

extension ExistingClipboard {
    private static let privateTypes = [NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"),
                                       NSPasteboard.PasteboardType("org.nspasteboard.TransientType")]

    /// What Append mode would add to. Nictate's own latest write is known without reading the pasteboard and
    /// is never private to itself (the private setting marks it for other apps). Anything else is private when
    /// its owner marked it concealed or transient, and then its text is not even read.
    @MainActor
    static func read(from pasteboard: NSPasteboard, lastWrite: ClipboardWrite?) -> ExistingClipboard {
        if let own = HistoryRotation.ownClipboard(changeCount: pasteboard.changeCount, lastWrite: lastWrite) {
            return ExistingClipboard(text: own, isPrivate: false)
        }
        let isPrivate = pasteboard.types.map { types in privateTypes.contains(where: types.contains) } ?? false
        guard !isPrivate else { return ExistingClipboard(text: nil, isPrivate: true) }
        return ExistingClipboard(text: pasteboard.string(forType: .string), isPrivate: false)
    }
}
