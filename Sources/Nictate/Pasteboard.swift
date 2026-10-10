// Nictate: a macOS menu bar app that copies text from anywhere on your screen.
// Copyright (c) 2026 jrthormann. MIT License, see LICENSE.

import AppKit

extension NSPasteboard {
    /// Replaces the clipboard with `text`. When `transient` is on (by default, the user's "keep captures
    /// private" setting) the capture stays on this Mac, so Universal Clipboard and Handoff never carry it
    /// to another device, and it is marked transient and concealed, which asks well-behaved clipboard
    /// managers to skip it (nspasteboard.org convention). When off, this is a plain write.
    /// Returns the change count the write produced, as reported by the call that took ownership, so it is
    /// never confused with a later write by another app.
    @MainActor @discardableResult
    func replaceContents(with text: String, transient: Bool = Settings.shared.hideFromClipboardManagers) -> Int {
        // The host-only option must be set while the contents are prepared, before anything is written.
        let changeCount = transient ? prepareForNewContents(with: .currentHostOnly) : clearContents()
        setString(text, forType: .string)
        if transient {
            setData(Data(), forType: PasteboardType("org.nspasteboard.TransientType"))
            setData(Data(), forType: PasteboardType("org.nspasteboard.ConcealedType"))
        }
        return changeCount
    }
}
