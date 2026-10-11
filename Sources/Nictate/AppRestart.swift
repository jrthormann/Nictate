// Nictate: a macOS menu bar app that copies text from anywhere on your screen.
// Copyright (C) 2026  jrthormann
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

import AppKit

/// Restarts Nictate: a new instance starts, then this one quits. Used after a permission is granted, and after a reset.
enum AppRestart {
    @MainActor private static var isRestarting = false

    /// macOS applies a newly granted permission only to a freshly launched process. The hotkeys are released
    /// first, or the new instance would find its own shortcuts taken and report them unavailable. This one
    /// quits only once the new one is running; if it cannot start, the hotkeys come back and this one stays.
    @MainActor
    static func now() {
        // A second press while the new instance is starting would start a third.
        guard !isRestarting else { return }
        isRestarting = true
        Task { @MainActor in
            // The new instance reads the history file, so this one hands it over first: changes still in flight are
            // written, and nothing is written after that. The handoff is given back if the new instance cannot start.
            guard await History.shared.handOff() else {
                isRestarting = false
                showNotRestarted()
                return
            }
            HotKeyManager.shared.suspend()
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.createsNewApplicationInstance = true
            NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, error in
                Task { @MainActor in
                    if let error {
                        Log.app.error("restart failed: \(error.localizedDescription, privacy: .public)")
                        History.shared.cancelHandOff()
                        HotKeyManager.shared.resume()
                        isRestarting = false
                        return
                    }
                    NSApp.terminate(nil)
                }
            }
        }
    }

    /// Shown when the history could not be written in time, so the restart did not start.
    @MainActor
    private static func showNotRestarted() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = tr("Nictate didn't restart")
        alert.informativeText = tr("Recent changes to saved captures aren't on disk yet. Try again in a moment.")
        alert.addButton(withTitle: tr("OK"))
        alert.runModal()
    }
}
