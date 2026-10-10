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

/// Reset Nictate: settings back to their defaults, every saved capture deleted, then a restart. Permissions and
/// open-at-login belong to macOS and stay as they are. Cancel is the default; the reset has no key.
@MainActor
enum ResetNictate {
    static func confirm() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = tr("Reset Nictate?")
        alert.informativeText = tr("Settings go back to their defaults and every saved capture is deleted. Nictate then restarts.")
        alert.addButton(withTitle: tr("Cancel"))
        let reset = alert.addButton(withTitle: tr("Reset"))
        reset.hasDestructiveAction = true
        reset.keyEquivalent = ""
        guard alert.runModal() == .alertSecondButtonReturn else { return }
        Settings.resetToDefaults()
        History.shared.clear()
        AppRestart.now()
    }
}
