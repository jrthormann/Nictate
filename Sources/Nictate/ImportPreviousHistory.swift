// Nictate: a macOS menu bar app that copies text from anywhere on your screen.
// Copyright (c) 2026 jrthormann. MIT License, see LICENSE.

import AppKit

/// Whether the import row is shown, observed by Settings. Refreshed after an import.
@MainActor
final class LegacyImportState: ObservableObject {
    @Published private(set) var available = ImportPreviousHistory.isAvailable

    func refresh() { available = ImportPreviousHistory.isAvailable }
}

/// "Import Previous History…": offered only when an encrypted history from an earlier version is on this Mac. It runs
/// once, only after the user confirms, and it says what happens. Normal startup never reads the old key.
@MainActor
enum ImportPreviousHistory {
    static var isAvailable: Bool {
        LegacyHistoryMigration.isOffered && !UserDefaults.standard.bool(forKey: StorageKeys.legacyHistoryImported)
    }

    /// The history is closed: a restart or a reset is taking it over, or a deletion stopped saving. Nothing is imported.
    private static func showUnavailable() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = tr("Import didn't start")
        alert.informativeText = tr("Saved captures can't be imported right now. Restart Nictate, then try again.")
        alert.addButton(withTitle: tr("OK"))
        alert.runModal()
    }

    /// Asks for confirmation, runs the import off the main thread, and reports the result. `finished` runs afterwards
    /// so the Settings row can hide itself after a successful import.
    static func confirmAndRun(finished: @escaping @MainActor () -> Void) {
        guard !History.shared.importing else { return }
        guard History.shared.isOpenForImport else { showUnavailable(); return }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = tr("Import Previous History?")
        var explanation = tr("Earlier versions of Nictate encrypted their history with a key in your Keychain. macOS may ask once for permission to read that key. The 15 most recent captures are imported into the new History, which stores them on this Mac without additional encryption. Your original file and Keychain item are not changed.")
        if History.shared.items.count > 0 {
            explanation += "\n\n" + tr("Your current captures are kept. If the total is more than 15, the oldest are removed.")
        }
        alert.informativeText = explanation
        alert.addButton(withTitle: tr("Cancel"))
        alert.addButton(withTitle: tr("Import"))
        guard alert.runModal() == .alertSecondButtonReturn else { return }
        // Refused while another import runs, or once the history is handed over for a restart or a quit.
        guard History.shared.beginImport() else { return }

        let legacy = LegacyHistoryMigration.legacyURL
        let destination = JSONHistoryStore(fileURL: JSONHistoryStore.standardURL)
        Task { @MainActor in
            let outcome = await History.performFileWork {
                LegacyHistoryMigration.run(legacy: legacy, destination: destination) { try LegacyHistoryKeychain.existingKey() }
            }
            if case .imported = outcome {
                UserDefaults.standard.set(true, forKey: StorageKeys.legacyHistoryImported)
            }
            History.shared.endImport()
            report(outcome)
            finished()
        }
    }

    private static func report(_ outcome: LegacyHistoryMigration.Outcome) {
        let message: String
        switch outcome {
        case .imported: message = tr("Previous history imported.")
        case .cancelled: message = tr("Import canceled. Nothing was changed.")
        case .failed(let reason):
            Log.app.error("Legacy import failed: \(reason)")
            message = tr("Couldn't import your previous history. Your original data has not been changed.")
        }
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: tr("OK"))
        alert.runModal()
    }
}
