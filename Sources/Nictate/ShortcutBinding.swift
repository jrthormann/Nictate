// Nictate: a macOS menu bar app that copies text from anywhere on your screen.
// Copyright (c) 2026 jrthormann. MIT License, see LICENSE.

import Carbon.HIToolbox
import Foundation

/// A global shortcut: a key code and its Carbon modifier mask.
struct Shortcut: Equatable {
    let code: Int
    let mods: Int
}

/// The actions that can have a global shortcut. The first two always have one; the code capture starts without.
/// The raw values are hot key ids. The id 3 is reserved and never reused.
enum ShortcutSlot: UInt32, CaseIterable {
    case capture = 1
    case rotateHistory = 2
    case captureCode = 4

    /// An optional slot may have no shortcut at all.
    var isOptional: Bool { self == .captureCode }
}

/// Which modifier combinations the recorder accepts for a new global shortcut.
enum ShortcutRule {
    /// A new shortcut must include ⌘ or ⌃. ⌥ (alone or with ⇧) plus a letter types a character in every app,
    /// so a global hotkey on it would swallow ordinary typing.
    static func isAcceptableForRecording(mods: Int) -> Bool {
        mods & (cmdKey | controlKey) != 0
    }
}

/// Decides whether a newly recorded shortcut can replace the current one.
enum ShortcutBinding {
    enum Outcome: Equatable {
        case accepted
        /// The other action already uses it.
        case conflictsWithOther
        /// The system refused it, usually because another app owns the combination.
        case unavailable
    }

    /// Tries to register `new`. If the system refuses it, the current shortcut (if the action had one) is
    /// registered again, so the action never loses the one it had. `others` are the shortcuts of the other
    /// actions. Nothing should be saved unless the outcome is `.accepted`.
    static func apply(new: Shortcut, current: Shortcut?, others: [Shortcut], register: (Shortcut) -> Bool) -> Outcome {
        guard !others.contains(new) else { return .conflictsWithOther }
        if register(new) { return .accepted }
        if let current { _ = register(current) }
        return .unavailable
    }
}
