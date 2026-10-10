// Nictate: a macOS menu bar app that copies text from anywhere on your screen.
// Copyright (c) 2026 jrthormann. MIT License, see LICENSE.

import AppKit

/// "Reset Settings…". It resets preferences. Saved captures stay unless the user also ticks the box to delete them.
@MainActor
enum ResetNictate {
    static func confirm() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = tr("Reset Settings?")
        alert.informativeText = tr("Every setting goes back to its default, and Nictate restarts. Saved captures are kept unless you tick the box below.")
        let deleteCaptures = NSButton(checkboxWithTitle: tr("Also delete saved captures"), target: nil, action: nil)
        alert.accessoryView = deleteCaptures
        alert.addButton(withTitle: tr("Cancel"))
        let reset = alert.addButton(withTitle: tr("Reset"))
        reset.hasDestructiveAction = true
        reset.keyEquivalent = ""
        guard alert.runModal() == .alertSecondButtonReturn else { return }
        // The restart ends this process, so the history must be on disk first: the deletion is confirmed by the
        // store, and pending changes are written. If either fails, nothing is reset and the user is told why.
        let deletes = deleteCaptures.state == .on
        let ready = deletes ? History.shared.clearForReset() : History.shared.waitForPendingWrites()
        guard ready else {
            stop(deletes ? tr("Saved captures could not be deleted. Nothing was reset.")
                         : tr("Recent changes to saved captures could not be written yet. Nothing was reset."))
            return
        }
        Settings.resetToDefaults()
        AppRestart.now()
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
