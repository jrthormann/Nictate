// Nictate: a macOS menu bar app that copies text from anywhere on your screen.
// Copyright (c) 2026 jrthormann. MIT License, see LICENSE.

import AppKit
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = Settings.shared
    private let windows = WindowCoordinator()
    /// The controllers that exist once the app has launched. Nil until then, so nothing can reach one that
    /// was never made.
    private var running: Running?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // The history loads in the background: a slow file read must never hold up the menu bar. Clearing on quit
        // is skipped by a crash or a forced quit, so the launch after one clears instead, once the history is read.
        let loading = History.shared.refresh()
        Task { @MainActor in
            await loading?.value
            if HistoryDeletion.clearsAtLaunch(clearOnQuit: settings.clearHistoryOnQuit, savedCount: History.shared.items.count) {
                HistoryClearing.clear()
            }
            if BuildIdentity.isTestVariant {
                Log.app.info("Test variant: history file \(JSONHistoryStore.standardURL.path)")
                History.shared.seedFixtures(BuildIdentity.historyFixtures)
            }
        }
        RecognitionWarmUp.start()  // the first capture after an install would otherwise wait for Vision's models

        // Command-F works while the panel shows its History screen, and nowhere else.
        let mainMenu = MainMenu(showSettings: { [weak self] in self?.windows.showPreferences() },
                                canFind: { [weak self] in
                                    guard let panel = self?.running?.panel else { return false }
                                    return panel.isShown && panel.model.screen == .history
                                })
        mainMenu.install()
        let status = StatusItemController()
        let capture = CaptureCoordinator(status: status, windows: windows)
        let model = StatusPanelModel(capture: capture, windows: windows)
        let panel = StatusPanel(model: model)
        status.attach(panel)
        running = Running(mainMenu: mainMenu, status: status, capture: capture, panel: panel)

        settings.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                self?.running?.status.refresh()
            }
        }.store(in: &cancellables)

        registerShortcuts()

        if !Permissions.isGranted || !UserDefaults.standard.bool(forKey: StorageKeys.didOnboard) {
            Permissions.request()
            windows.showWelcome()
        }
    }

    /// With Clear on Quit on, the history is cleared and the store's confirmation awaited before the process ends. A
    /// failure is logged by History and the choice stays on, so the next launch tries again. Without it, queued
    /// changes are written, waiting at most a few seconds.
    func applicationWillTerminate(_ notification: Notification) {
        if settings.clearHistoryOnQuit {
            // Notices may still show captured text, so they go whatever the outcome of the history write.
            Notifier.removeAllDelivered()
            _ = History.shared.clearForQuit()
        } else {
            // A failed wait is already logged by History; quit goes on, as it cannot wait longer than a few seconds.
            _ = History.shared.waitForPendingWrites()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        windows.showPreferences()
        return true
    }

    private func registerShortcuts() {
        var refused: [String] = []
        for slot in ShortcutSlot.allCases {
            HotKeyManager.shared.setAction(slot) { [weak self] in self?.perform(slot) }
            // An optional shortcut the user never set has nothing to register.
            guard let saved = settings.shortcut(for: slot) else { continue }
            if !HotKeyManager.shared.register(slot, code: saved.shortcut.code, mods: saved.shortcut.mods) {
                refused.append(saved.label)
            }
        }
        if !refused.isEmpty {
            DispatchQueue.main.async { [weak self] in self?.reportRefusedShortcuts(refused) }
        }
    }

    /// What a shortcut does.
    private func perform(_ slot: ShortcutSlot) {
        FocusReturn.shared.remember()
        guard let capture = running?.capture else { return }
        switch slot {
        case .capture: capture.capture(mode: .text)
        case .rotateHistory: capture.rotateHistory()
        case .captureCode: capture.capture(mode: .code)
        }
    }

    /// A saved shortcut the system refused at launch (another app owns it now): say so, instead of letting
    /// the key do nothing.
    private func reportRefusedShortcuts(_ labels: [String]) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = tr("Could not activate the shortcut")
        alert.informativeText = tr("%@ is already used by another app. Choose another shortcut in Settings.", labels.joined(separator: ", "))
        alert.addButton(withTitle: tr("Open Settings…"))
        alert.addButton(withTitle: tr("Cancel"))
        if alert.runModal() == .alertFirstButtonReturn { windows.showPreferences() }
    }
}

/// The main menu, the status item, the capture pipeline and the status menu: made together at launch and
/// kept for the life of the app (each menu is its items' target, which holds it only weakly).
@MainActor
private struct Running {
    let mainMenu: MainMenu
    let status: StatusItemController
    let capture: CaptureCoordinator
    let panel: StatusPanel
}
