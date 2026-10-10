// Nictate: a macOS menu bar app that copies text from anywhere on your screen.
// Copyright (c) 2026 jrthormann. MIT License, see LICENSE.

import AppKit

/// Gives focus back to the app the user was in when a Nictate action finishes, so a paste straight after a copy lands
/// where the user expects. Nictate becomes active to show its panel and selection; without this it stays active.
/// Focus moves back only when Nictate is still the active app, so an app the user has since chosen is never taken over.
@MainActor
final class FocusReturn {
    static let shared = FocusReturn()

    /// The app that was frontmost when the user started an action from outside Nictate. Nil when Nictate was.
    private var previous: NSRunningApplication?

    /// Called when an action starts from outside Nictate: a shortcut, or the status item. Actions started inside the
    /// panel keep the app remembered when the panel opened.
    func remember() {
        let front = NSWorkspace.shared.frontmostApplication
        previous = front?.processIdentifier == getpid() ? nil : front
    }

    /// Called when a Nictate action has finished and the user is back to their work. The remembered app is forgotten
    /// either way, so it is never used for a later action by mistake.
    func returnIfStillActive() {
        let target = previous
        previous = nil
        guard FocusReturn.shouldReturn(nictateIsActive: NSApp.isActive,
                                       hasTarget: target != nil,
                                       targetRunning: target?.isTerminated == false,
                                       targetIsNictate: target?.processIdentifier == getpid()) else { return }
        _ = target?.activate()
    }

    /// The rule, apart from AppKit so it can be tested: Nictate must still be active, and the target must exist, be
    /// running, and not be Nictate itself.
    static func shouldReturn(nictateIsActive: Bool, hasTarget: Bool, targetRunning: Bool, targetIsNictate: Bool) -> Bool {
        nictateIsActive && hasTarget && targetRunning && !targetIsNictate
    }
}
