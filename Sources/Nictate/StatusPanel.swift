// Nictate: a macOS menu bar app that copies text from anywhere on your screen.
// Copyright (c) 2026 jrthormann. MIT License, see LICENSE.

import AppKit
import SwiftUI

/// What the menu bar panel shows and does. The history is a second screen of the same panel, never a window.
@MainActor
final class StatusPanelModel: ObservableObject {
    enum Screen { case main, history }

    @Published var screen: Screen = .main
    @Published var query = ""
    private let settings = Settings.shared
    private let capture: CaptureCoordinator
    private let windows: WindowCoordinator
    /// Closes the panel once an action has done its job.
    var dismiss: () -> Void = {}

    init(capture: CaptureCoordinator, windows: WindowCoordinator) {
        self.capture = capture
        self.windows = windows
    }

    /// Called each time the panel opens: the main screen, with a fresh search.
    func reset() {
        screen = .main
        query = ""
        History.shared.query = ""
        History.shared.refresh()
        History.shared.pruneExpired()
    }

    // MARK: Main screen

    var lastDetections: Detections { capture.lastDetections }
    var languages: [String] { settings.languages }
    var supportedLanguages: [String] { Recognizer.supportedLanguages }
    var historyEnabled: Bool { settings.historyEnabled }
    var historyCount: Int { History.shared.items.count }
    var historyState: HistoryState { History.shared.state }
    var hotKeyLabel: String { settings.hotKeyLabel }
    var rotateHotKeyLabel: String { settings.rotateHotKeyLabel }
    var codeHotKeyLabel: String? { settings.shortcut(for: .captureCode)?.label }
    var codeMode: Bool { settings.codeMode }

    func captureText() { dismiss(); capture.capture(mode: .text) }
    func captureCode() { dismiss(); capture.capture(mode: .code) }
    func cycleHistory() { dismiss(); capture.rotateHistory() }
    func setFaithful(_ faithful: Bool) { settings.codeMode = faithful }
    func setLanguage(_ code: String) { settings.languages = code.isEmpty ? [] : [code] }
    func showPreferences() { dismiss(); windows.showPreferences() }
    func showAbout() { dismiss(); AboutPanel.show() }
    func checkForUpdates() { dismiss(); Task { @MainActor in await UpdateAlert.run() } }
    func quit() { NSApp.terminate(nil) }

    var appendMode: Bool {
        get { settings.appendMode }
        set { settings.appendMode = newValue }
    }

    func copyDetected(_ value: String) { dismiss(); capture.copyDetected(value) }
    func openDetected(_ url: URL) { dismiss(); capture.openLink(url) }

    // MARK: History screen

    /// The captures that match the search, newest first. Matching ignores case, as the History window does.
    var entries: [(text: String, date: Date)] {
        History.shared.items.indices.compactMap { index -> (text: String, date: Date)? in
            let text = History.shared.items[index]
            let date = History.shared.dates[index]
            guard query.isEmpty || text.localizedCaseInsensitiveContains(query) else { return nil }
            return (text, date)
        }
    }

    func searchChanged(_ text: String) {
        query = text
        History.shared.query = text
    }

    /// Copies the whole capture, even when the row shows only its beginning, and closes the panel.
    func copyCapture(_ text: String) {
        dismiss()
        capture.copyCapture(text)
    }

    func deleteCapture(_ text: String) {
        History.shared.remove(text)
    }

    func clearHistory() {
        HistoryClearing.confirmClear()
    }

    func backToMain() {
        screen = .main
        query = ""
        History.shared.query = ""
    }
}

/// The menu bar popover that holds the panel. It closes on a click outside, which is the expected behaviour here.
@MainActor
final class StatusPanel {
    let model: StatusPanelModel
    private let popover = NSPopover()

    init(model: StatusPanelModel) {
        self.model = model
        model.dismiss = { [weak self] in self?.close() }
        popover.behavior = .transient
        popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        // The popover places itself from the content size it knows when it opens. Without this, SwiftUI's later
        // growth moves the bottom edge and the panel rises over the menu bar.
        let host = NSHostingController(rootView: StatusPanelView(model: model))
        host.sizingOptions = [.preferredContentSize]
        popover.contentViewController = host
    }

    var isShown: Bool { popover.isShown }
    /// The window that draws the panel, once it is shown.
    var window: NSWindow? { popover.contentViewController?.view.window }

    func toggle(relativeTo button: NSView) {
        if popover.isShown {
            close()
        } else {
            model.reset()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    func close() {
        popover.performClose(nil)
    }
}
