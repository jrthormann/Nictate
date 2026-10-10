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
    private var expiryTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // The history loads in the background: a Keychain prompt must never hold up the menu bar. Clearing on quit
        // is skipped by a crash or a forced quit, so the launch after one clears instead, once the history is read.
        let loading = History.shared.refresh()
        Task { @MainActor in
            await loading?.value
            if BuildIdentity.isTestVariant {
                Log.app.info("Test variant: history file \(JSONHistoryStore.standardURL.path)")
                History.shared.seedFixtures(BuildIdentity.historyFixtures)
            }
            History.shared.pruneExpired()
        }
        RecognitionWarmUp.start()  // the first capture after an install would otherwise wait for Vision's models
        // Age-based removal is off (captures are limited by count only); the timer keeps the policy applied.
        expiryTimer = Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { _ in
            Task { @MainActor in History.shared.pruneExpired() }
        }

        let mainMenu = MainMenu(showSettings: { [weak self] in self?.windows.showPreferences() },
                                canFind: { [weak self] in self?.windows.isHistoryKey ?? false })
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
