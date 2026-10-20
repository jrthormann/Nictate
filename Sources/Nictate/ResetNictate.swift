// Nictate: a macOS menu bar app that copies text from anywhere on your screen.
// Copyright (c) 2026 jrthormann. MIT License, see LICENSE.

import AppKit

/// "Reset Settings…". It resets preferences. A second dialog asks whether the saved captures go too; they stay unless the user chooses to delete them.
/// What the two dialogs decide. `cancel` resets nothing.
enum ResetPlan: Equatable {
    case cancel
    case resetKeepingCaptures
    case resetDeletingCaptures
}

@MainActor
enum ResetNictate {
    /// True while a reset waits for the history to be handed over. A second Reset meanwhile is ignored.
    private static var isRunning = false

    /// The first answer confirms the reset. Only then does the second dialog ask about the saved captures.
    static func plan(resetResponse: NSApplication.ModalResponse, captureResponse: NSApplication.ModalResponse?) -> ResetPlan {
        guard resetResponse == .alertSecondButtonReturn, let captureResponse else { return .cancel }
        switch captureResponse {
        case .alertSecondButtonReturn: return .resetKeepingCaptures
        case .alertThirdButtonReturn: return .resetDeletingCaptures
        default: return .cancel
        }
    }

    static func confirm() {
        guard !isRunning else { return }
        NSApp.activate(ignoringOtherApps: true)
        let resetResponse = resetDialog().runModal()
        var captureResponse: NSApplication.ModalResponse?
        if resetResponse == .alertSecondButtonReturn {
            captureResponse = capturesDialog().runModal()
        }
        let outcome = plan(resetResponse: resetResponse, captureResponse: captureResponse)
        guard outcome != .cancel else { return }
        // The restart ends this process, so the history must be on disk first: the deletion is confirmed by the
        // store, and pending changes are written. If either fails, nothing is reset and the user is told why.
        let deletes = outcome == .resetDeletingCaptures
        if deletes {
            Notifier.withdrawAll()
            switch History.shared.clearForReset() {
            case .confirmed:
                break
            case .notWritten:
                stop(tr("Saved captures could not be deleted, so nothing was reset. Restart Nictate, then try again."))
                return
            case .unconfirmed:
                stop(tr("Nictate couldn't confirm that saved captures were deleted, so nothing was reset. Restart Nictate, then try again."))
                return
            }
        }
        isRunning = true
        Task { @MainActor in
            defer { isRunning = false }
            if !deletes {
                // Changes still in flight must reach the file before the restart; if they cannot, nothing is reset.
                guard await History.shared.handOff() else {
                    stop(History.shared.importing
                        ? tr("Saved captures are being imported. Try again when the import finishes.")
                        : tr("Recent changes to saved captures could not be written yet, so nothing was reset. Try again in a moment."))
                    return
                }
            }
            Settings.resetToDefaults()
            AppRestart.now()
        }
    }

    private static func resetDialog() -> NSAlert {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = tr("Reset Settings?")
        alert.informativeText = tr("Every setting goes back to its default, except Launch at Login, which stays as it is. Nictate restarts.")
        alert.addButton(withTitle: tr("Cancel"))
        let reset = alert.addButton(withTitle: tr("Reset"))
        reset.hasDestructiveAction = true
        reset.keyEquivalent = ""
        return alert
    }

    static func capturesDialog() -> NSAlert {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = tr("Also delete saved captures?")
        alert.informativeText = tr("Saved captures are kept unless you delete them. Deleting them cannot be undone.")
        let cancel = alert.addButton(withTitle: tr("Cancel"))
        cancel.keyEquivalent = "\u{1b}"
        let keep = alert.addButton(withTitle: tr("Keep Captures"))
        keep.keyEquivalent = "\r"
        let delete = alert.addButton(withTitle: tr("Delete Captures"))
        delete.hasDestructiveAction = true
        return alert
    }

    private static func stop(_ message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = tr("Reset stopped")
        alert.informativeText = message
        alert.addButton(withTitle: tr("OK"))
        alert.runModal()
    }
}
