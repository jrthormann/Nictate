// Nictate: a macOS menu bar app that copies text from anywhere on your screen.
// Copyright (c) 2026 jrthormann. MIT License, see LICENSE.

import Foundation

/// What the welcome window's main button does.
/// The first step of Welcome, from what macOS lets this process observe.
///
/// `CGPreflightScreenCaptureAccess` reports only whether this process has access right now. It cannot tell
/// "not yet decided" from "denied", and a grant made in System Settings applies to a process only after it
/// starts again. So the step never claims a grant it has not seen, and it never says "denied". Its text is
/// neutral and its action is the recovery that fits the state.
enum ScreenRecordingStep: Equatable {
    /// This process has access. The step keeps its title, drops its text and offers no action.
    case granted
    /// No access, and the user has not come back from System Settings yet: offer to open it.
    case pending
    /// The user came back from System Settings and this process still has no access. It may be a grant
    /// that needs a restart, or no grant at all, so the step offers a restart and System Settings, and says both.
    case notActiveYet

    static func state(granted: Bool, returnedFromSettings: Bool) -> ScreenRecordingStep {
        if granted { return .granted }
        return returnedFromSettings ? .notActiveYet : .pending
    }

    /// Whether the step says that Nictate was updated and that macOS asks for Screen Recording again.
    /// A beta is signed ad hoc, so macOS treats each beta update as a new app. A stable version never shows the note.
    /// A version that differs from the last launch is an update. Versions before this record stored no version: there,
    /// an install that finished Welcome is an update, and a new install is not.
    static func showsUpdateNote(current: String, lastLaunched: String?, onboarded: Bool) -> Bool {
        guard UpdateCheck.offersPrereleases(to: current) else { return false }
        guard let lastLaunched else { return onboarded }
        return lastLaunched != current
    }
}
