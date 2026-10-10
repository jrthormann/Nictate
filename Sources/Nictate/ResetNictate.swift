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
        Settings.resetToDefaults()
        if deleteCaptures.state == .on {
            History.shared.clear()
            // The restart ends this process, so the deletion must reach the file first.
            History.flushWrites()
        }
        AppRestart.now()
    }
}
