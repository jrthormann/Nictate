// Nictate: a macOS menu bar app that copies text from anywhere on your screen.
// Copyright (c) 2026 jrthormann. MIT License, see LICENSE.

import AppKit
import SwiftUI

/// Owns the settings, history and welcome windows: each is created on first use and then just brought forward.
/// Nictate lives in the menu bar; while one of these windows is open it also has a Dock icon and the menu bar,
/// so the window can be found with ⌘Tab and its Window menu, and goes back to the menu bar alone when the
/// last one closes.
@MainActor
final class WindowCoordinator: NSObject {
    private var prefsWindow: NSWindow?
    private var historyWindow: NSWindow?
    private var welcomeWindow: NSWindow?

    override init() {
        super.init()
        // A selector-based observer is removed by NotificationCenter itself when this object goes away.
        NotificationCenter.default.addObserver(self, selector: #selector(windowWillClose(_:)),
                                               name: NSWindow.willCloseNotification, object: nil)
    }

    /// Leaves the Dock when the last of these windows closes, and drops the welcome window once closed, so
    /// its permission poller stops with it. Windows close on the main thread; the window is released on the
    /// next turn, not while it is still closing. Other windows (alerts, the About panel) are not counted.
    @objc private func windowWillClose(_ note: Notification) {
        guard let window = note.object as? NSWindow, ownWindows.contains(where: { $0 === window }) else { return }
        // A minimized window still counts: without the Dock it could not be brought back.
        let stillOpen = ownWindows.filter { $0 !== window && ($0.isVisible || $0.isMiniaturized) }.count
        setActivationPolicy(Self.activationPolicy(openWindows: stillOpen))
        if window === welcomeWindow { DispatchQueue.main.async { [weak self] in self?.welcomeWindow = nil } }
    }

    /// In the Dock (and the menu bar) while any of Nictate's windows is open, only in the menu bar otherwise.
    static func activationPolicy(openWindows: Int) -> NSApplication.ActivationPolicy {
        openWindows > 0 ? .regular : .accessory
    }

    private var ownWindows: [NSWindow] { [prefsWindow, historyWindow, welcomeWindow].compactMap { $0 } }

    private func setActivationPolicy(_ policy: NSApplication.ActivationPolicy) {
        if NSApp.activationPolicy() != policy { NSApp.setActivationPolicy(policy) }
    }

    /// Whether the History window has the keyboard focus, so Find… has a search field to go to.
    var isHistoryKey: Bool { historyWindow?.isKeyWindow ?? false }

    func showPreferences() {
        if prefsWindow == nil {
            let window = NSWindow(contentViewController: PreferencesController())
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            prefsWindow = window
        }
        bringForward(prefsWindow)
    }

    func showHistory() {
        show(&historyWindow, title: tr("Nictate History"),
             style: [.titled, .closable, .resizable, .miniaturizable],
             autosaveName: StorageKeys.WindowFrame.history) { HistoryView() }
    }

    func showWelcome() {
        show(&welcomeWindow, title: tr("Welcome to Nictate"), style: [.titled, .closable]) {
            WelcomeView { [weak self] in
                UserDefaults.standard.set(true, forKey: StorageKeys.didOnboard)
                self?.welcomeWindow?.close()
            }
        }
    }

    /// Creates the window on first use, then just brings it to the front.
    private func show<Content: View>(_ window: inout NSWindow?, title: String, style: NSWindow.StyleMask,
                                     autosaveName: String? = nil, @ViewBuilder content: () -> Content) {
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: content()))
            w.title = title
            w.styleMask = style
            w.isReleasedWhenClosed = false
            w.center()
            if let autosaveName { w.setFrameAutosaveName(autosaveName) }
            window = w
        }
        bringForward(window)
    }

    private func bringForward(_ window: NSWindow?) {
        setActivationPolicy(Self.activationPolicy(openWindows: 1))
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
