// Nictate: a macOS menu bar app that copies text from anywhere on your screen.
// Copyright (c) 2026 jrthormann. MIT License, see LICENSE.

import AppKit

/// When saved captures are deleted, and what is asked first. Kept apart from the alerts that ask, so every
/// rule can be tested without one on screen.
enum HistoryDeletion {
    /// The answer to "Delete the saved captures too?" after "Save Captures" is turned off. Cancel leaves the
    /// switch on again, as if it had never moved.
    enum Answer: Equatable {
        case delete
        case keep
        case cancel

        /// Cancel is the first button, so it is also what any other dismissal means: nothing is deleted.
        init(response: NSApplication.ModalResponse) {
            switch response {
            case .alertSecondButtonReturn: self = .keep
            case .alertThirdButtonReturn: self = .delete
            default: self = .cancel
            }
        }
    }

    /// Turning history off asks about what is saved, and only when something is.
    static func asksOnSwitchOff(savedCount: Int) -> Bool { savedCount > 0 }

    /// The question is asked only while saving is still off, and only when something is saved.
    static func shouldAskOnSwitchOff(savedCount: Int, stillOff: Bool) -> Bool {
        stillOff && asksOnSwitchOff(savedCount: savedCount)
    }

    /// Captures go only on an explicit Delete; Keep leaves them for a later Clear History.
    static func clearsOnSwitchOff(savedCount: Int, answer: Answer) -> Bool { savedCount > 0 && answer == .delete }

    /// Clear History stays reachable while history is on, and while captures kept from before remain after it
    /// was turned off, so they can always be deleted.
    static func showsClearControl(historyEnabled: Bool, savedCount: Int) -> Bool { historyEnabled || savedCount > 0 }

    /// Clear History asks once, when there is something to delete.
    static func asksBeforeClear(savedCount: Int) -> Bool { savedCount > 0 }

    /// With "Clear on Quit" on, history is cleared at launch too: a crash, a forced quit or a power
    /// loss skips the quit, and the captures would otherwise outlive the choice.
    static func clearsAtLaunch(clearOnQuit: Bool, savedCount: Int) -> Bool { clearOnQuit && savedCount > 0 }

    static func switchOffQuestion(savedCount: Int) -> String {
        savedCount == 1 ? tr("Delete the saved capture too?") : tr("Delete the %d saved captures too?", savedCount)
    }

    static func clearQuestion(savedCount: Int) -> String {
        savedCount == 1 ? tr("Delete the saved capture?") : tr("Delete all %d saved captures?", savedCount)
    }
}

/// The alerts of `HistoryDeletion` and the clearing itself, shared by Settings, the History screen and the menu.
@MainActor
enum HistoryClearing {
    /// Deletes every saved capture and the notices that may still show one.
    static func clear(_ history: History = .shared) {
        history.clear()
        Notifier.removeAllDelivered()
    }

    /// Clear History…: one confirmation, then everything goes.
    static func confirmClear(_ history: History = .shared) {
        let count = history.items.count
        guard HistoryDeletion.asksBeforeClear(savedCount: count) else { return }
        if run(clearAlert(savedCount: count)) == .alertSecondButtonReturn { clear(history) }
    }

    /// "Discard Unreadable History": asks first, and says the deletion cannot be undone. Cancel is the default.
    static func confirmDiscardUnreadable(_ history: History = .shared) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = tr("Discard unreadable history?")
        alert.informativeText = tr("Nictate can't load the saved captures in this file, so they can't be shown. Discarding the file deletes them permanently. This can't be undone.")
        alert.addButton(withTitle: tr("Cancel")).keyEquivalent = "\r"
        alert.addButton(withTitle: tr("Discard")).hasDestructiveAction = true
        guard run(alert) == .alertSecondButtonReturn else { return }
        Task { @MainActor in
            guard await history.discardUnreadableFile() else {
                let failure = NSAlert()
                failure.alertStyle = .warning
                failure.messageText = tr("Discard didn't work")
                failure.informativeText = tr("The file couldn't be replaced, so it was left unchanged.")
                failure.addButton(withTitle: tr("OK"))
                _ = run(failure)
                return
            }
        }
    }

    /// After "Save Captures" is turned off: asks whether the saved captures go too. Cancel turns the switch back on.
    /// It waits for a load in flight first, so a history that is still reading is counted, not shown as empty.
    static func historyTurnedOff(_ history: History = .shared, settings: Settings = .shared) async {
        await history.finishLoading()
        let count = history.items.count
        // Saving may have been turned back on while the load was in flight: then there is nothing to decide.
        guard HistoryDeletion.shouldAskOnSwitchOff(savedCount: count, stillOff: !settings.historyEnabled) else { return }
        let answer = HistoryDeletion.Answer(response: run(switchOffAlert(savedCount: count)))
        if answer == .cancel {
            settings.historyEnabled = true
            // The switch went off with refresh; turning it back on must load the history again.
            history.refresh()
        }
        if HistoryDeletion.clearsOnSwitchOff(savedCount: count, answer: answer) { clear(history) }
        // Keep Captures stops saving and deletes nothing; the switch stays off.
    }

    /// Every destructive choice needs a click on its own button. Nothing is a default that deletes:
    /// - Cancel (first, Return, the default, and Esc): nothing changes and the switch goes back on.
    /// - Keep Captures (no key): stop saving, delete nothing.
    /// - Delete Captures (no key, destructive): stop saving and delete what is saved.
    static func switchOffAlert(savedCount: Int) -> NSAlert {
        let alert = NSAlert()
        alert.messageText = HistoryDeletion.switchOffQuestion(savedCount: savedCount)
        alert.informativeText = tr("New captures are no longer saved. If you keep the saved ones, Clear History… stays in Settings and in the menu.")
        alert.addButton(withTitle: tr("Cancel")).keyEquivalent = "\r"
        alert.addButton(withTitle: tr("Keep Captures"))
        let delete = alert.addButton(withTitle: tr("Delete Captures"))
        delete.hasDestructiveAction = true
        return alert
    }

    /// Cancel (first, Return, the default, and Esc) or Clear History (no key, destructive).
    static func clearAlert(savedCount: Int) -> NSAlert {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = HistoryDeletion.clearQuestion(savedCount: savedCount)
        alert.informativeText = tr("This can't be undone.")
        alert.addButton(withTitle: tr("Cancel")).keyEquivalent = "\r"
        alert.addButton(withTitle: tr("Clear History")).hasDestructiveAction = true
        return alert
    }

    /// A menu bar app is not active when its menu is used, so it comes forward for the alert to be seen.
    private static func run(_ alert: NSAlert) -> NSApplication.ModalResponse {
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal()
    }
}
