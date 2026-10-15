// Nictate: a macOS menu bar app that copies text from anywhere on your screen.
// Copyright (c) 2026 jrthormann. MIT License, see LICENSE.

import AppKit

/// Something Nictate put on the clipboard, and the pasteboard's change count right after the write.
/// While the count is unchanged the clipboard still holds `text`, so it never has to be read back.
struct ClipboardWrite: Equatable, Sendable {
    let changeCount: Int
    let text: String

    /// What the clipboard holds, as far as Nictate knows without reading it: the text of its own last write
    /// while the change count is still the one after that write, otherwise nil (something else was copied).
    static func ownText(changeCount: Int, lastWrite: ClipboardWrite?) -> String? {
        guard let lastWrite, lastWrite.changeCount == changeCount else { return nil }
        return lastWrite.text
    }
}

/// The one place Nictate writes the clipboard: captures, Recent Captures, the History screen and the menu all
/// go through it. Each write is read back once, and only a write that reads back is remembered, so Append mode
/// knows what the clipboard holds while nothing else has been copied.
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

    /// Writes `text` and reads back only that text before reporting success. The previous clipboard is never read or
    /// kept, including concealed or transient entries: the write clears it first, so a refused write can leave the
    /// clipboard empty. A refused write reports failure and is not remembered as Nictate's.
    func writeVerified(_ text: String, transient: Bool = Settings.shared.hideFromClipboardManagers) -> Bool {
        let changeCount = replace(pasteboard, text, transient)
        guard pasteboard.string(forType: .string) == text else { return false }
        lastWrite = ClipboardWrite(changeCount: changeCount, text: text)
        return true
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
        if let own = ClipboardWrite.ownText(changeCount: pasteboard.changeCount, lastWrite: lastWrite) {
            return ExistingClipboard(text: own, isPrivate: false)
        }
        let isPrivate = pasteboard.types.map { types in privateTypes.contains(where: types.contains) } ?? false
        guard !isPrivate else { return ExistingClipboard(text: nil, isPrivate: true) }
        return ExistingClipboard(text: pasteboard.string(forType: .string), isPrivate: false)
    }
}
