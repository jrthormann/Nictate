// Nictate: a macOS menu bar app that copies text from anywhere on your screen.
// Copyright (c) 2026 jrthormann. MIT License, see LICENSE.

import AppKit

/// Gives focus back to the app the user was in when a Nictate action finishes, so a paste straight after a copy lands
/// where the user expects. Nictate becomes active to show its panel and selection; without this it stays active.
/// Focus moves back only when Nictate is still the active app, so an app the user has since chosen is never taken over.
/// This is the only place that keeps the app to return to.
@MainActor
final class FocusReturn {
    static let shared = FocusReturn()

    /// The app that was frontmost when the user started an action from outside Nictate. Nil when Nictate was.
    private var previous: NSRunningApplication?
    /// A return to `previous` was asked for, and Nictate has not stopped being active since. Activation is asynchronous,
    /// so a shortcut pressed in that moment (a retry straight after a miss) still finds Nictate frontmost.
    private var returnPending = false

    /// Called when an action starts from outside Nictate: a shortcut, or the status item. Actions started inside the
    /// panel keep the app remembered when the panel opened. Another app in front replaces the remembered one. Nictate in
    /// front keeps it only while a return to it is pending; otherwise the user is in Nictate on purpose (Settings).
    func remember() {
        let front = NSWorkspace.shared.frontmostApplication
        let other = front?.processIdentifier == getpid() ? nil : front
        if !FocusReturn.keepsOrigin(anotherAppFrontmost: other != nil, returnPending: returnPending,
                                    originRunning: previous?.isTerminated == false) {
            previous = other
        }
        returnPending = false
    }

    /// Called when a Nictate action has finished, whatever its outcome. The app is kept until Nictate stops being
    /// active (`nictateResignedActive`), and let go at once when there is no return to make.
    func returnIfStillActive() {
        let target = previous
        guard FocusReturn.shouldReturn(nictateIsActive: NSApp.isActive,
                                       hasTarget: target != nil,
                                       targetRunning: target?.isTerminated == false,
                                       targetIsNictate: target?.processIdentifier == getpid()) else { return forget() }
        returnPending = true
        _ = target?.activate()
    }

    /// Lets the app go: the user chose where to go next (a link opened in the browser), or there is no return to make.
    func forget() {
        previous = nil
        returnPending = false
    }

    /// Called when Nictate stops being the active app. After a return, that is the app back in front or the user gone
    /// elsewhere, so the app is let go. With no return pending, a capture or the panel still under way keeps it.
    func nictateResignedActive() {
        if returnPending { forget() }
    }

    /// The rule, apart from AppKit so it can be tested: Nictate must still be active, and the target must exist, be
    /// running, and not be Nictate itself.
    static func shouldReturn(nictateIsActive: Bool, hasTarget: Bool, targetRunning: Bool, targetIsNictate: Bool) -> Bool {
        nictateIsActive && hasTarget && targetRunning && !targetIsNictate
    }

    /// The rule, apart from AppKit: a shortcut pressed during a capture or while the panel is open finds Nictate
    /// already active, so the app to return to was remembered when that action began and must be kept.
    static func shouldRemember(captureInFlight: Bool, panelShown: Bool) -> Bool {
        !captureInFlight && !panelShown
    }

    /// The rule, apart from AppKit: an action started while Nictate is frontmost keeps the app to return to only while
    /// a return to it is pending and it still runs. Another app in front always replaces it.
    static func keepsOrigin(anotherAppFrontmost: Bool, returnPending: Bool, originRunning: Bool) -> Bool {
        !anotherAppFrontmost && returnPending && originRunning
    }
}
