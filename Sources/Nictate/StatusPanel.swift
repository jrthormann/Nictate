// Nictate: a macOS menu bar app that copies text from anywhere on your screen.
// Copyright (c) 2026 jrthormann. MIT License, see LICENSE.

import AppKit
import Combine
import SwiftUI

/// What the menu bar panel shows and does. The history is a second screen of the same panel, never a window.
@MainActor
final class StatusPanelModel: ObservableObject {
    enum Screen { case main, history }

    @Published var screen: Screen = .main {
        // Opening History highlights its first match, so Return always has a target.
        didSet { if screen == .history, selection == nil { selection = entries.isEmpty ? nil : 0 } }
    }
    @Published var query = ""
    /// Shown in the History screen when a copy fails. Cleared by the next attempt.
    @Published var copyError: String?
    /// The highlighted row in the History list, as an index into `entries`. Arrow keys move it, Return copies it.
    @Published var selection: Int?
    private let settings = Settings.shared
    private let capture: CaptureCoordinator
    private let windows: WindowCoordinator
    /// Closes the panel once an action has done its job.
    var dismiss: () -> Void = {}

    /// The history the panel shows. The app passes `History.shared`; tests pass a disposable one.
    private let history: History

    /// Changes to the history and the settings redraw the panel, not only changes to its own properties.
    private var observers = Set<AnyCancellable>()

    init(capture: CaptureCoordinator, windows: WindowCoordinator, history: History = .shared) {
        self.capture = capture
        self.windows = windows
        self.history = history
        history.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
            // The change is announced before its entries are stored, so the first match is chosen on the next pass.
            DispatchQueue.main.async { self?.keepSelectionValid() }
        }.store(in: &observers)
        Settings.shared.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &observers)
        // Command-F in the main menu asks for the search field of the History screen.
        NotificationCenter.default.publisher(for: MainMenu.findRequested)
            .sink { [weak self] _ in self?.searchFocusRequests += 1 }
            .store(in: &observers)
    }

    /// Counts each Command-F. The History screen moves focus to its search field when this changes.
    @Published var searchFocusRequests = 0

    /// Called each time the panel opens: the main screen, with a fresh search.
    func reset() {
        screen = .main
        query = ""
        history.query = ""
        // A highlight or an error from an earlier visit must not survive: the list may have changed since.
        selection = nil
        copyError = nil
        history.refresh()
    }


    // MARK: Main screen

    var lastDetections: Detections { capture.lastDetections }
    var languages: [String] { settings.languages }
    var supportedLanguages: [String] { Recognizer.supportedLanguages }
    var historyEnabled: Bool { settings.historyEnabled }
    var keepHistory: Bool { settings.historyEnabled }
    var historyCount: Int { history.items.count }
    var historyState: HistoryState { history.state }
    var historyFileUnreadable: Bool { history.fileIsUnreadable }
    var historyClosed: Bool { history.isClosed }
    var hotKeyLabel: String { settings.hotKeyLabel }
    var rotateHotKeyLabel: String { settings.rotateHotKeyLabel }
    var codeHotKeyLabel: String? { settings.shortcut(for: .captureCode)?.label }
    var codeMode: Bool { settings.codeMode }

    func captureText() { dismiss(); capture.capture(mode: .text) }
    func captureCode() { dismiss(); capture.capture(mode: .code) }
    func cycleHistory() { dismiss(); capture.rotateHistory(); FocusReturn.shared.returnIfStillActive() }
    /// Escape closes the panel and gives focus back to the app the user came from.
    func closeReturningFocus() { dismiss(); FocusReturn.shared.returnIfStillActive() }
    func setFaithful(_ faithful: Bool) { settings.codeMode = faithful }
    func setLanguage(_ code: String) { settings.languages = code.isEmpty ? [] : [code] }
    func setKeepHistory(_ on: Bool) {
        settings.historyEnabled = on
        history.refresh()
        // Asked after the menu has finished updating, and after the saved captures have loaded, so the question sees them.
        if !on { Task { await HistoryClearing.historyTurnedOff() } }
    }
    func setLaunchAtLogin(_ on: Bool) { LoginItem.shared.set(on) }
    func showPreferences() { dismiss(); windows.showPreferences() }
    func showAbout() { dismiss(); AboutPanel.show() }
    func supportDeveloper() { dismiss(); SupportDeveloper.open() }
    func checkForUpdates() { dismiss(); Task { @MainActor in await UpdateAlert.run() } }
    func quit() { NSApp.terminate(nil) }

    var appendMode: Bool {
        get { settings.appendMode }
        set { settings.appendMode = newValue }
    }

    func copyDetected(_ value: String) { dismiss(); capture.copyDetected(value); FocusReturn.shared.returnIfStillActive() }
    func openDetected(_ url: URL) { dismiss(); capture.openLink(url) }

    // MARK: History screen

    /// The captures that match the search, newest first. Matching ignores case, as the History window does.
    var entries: [(text: String, date: Date)] {
        history.items.indices.compactMap { index -> (text: String, date: Date)? in
            let text = history.items[index]
            let date = history.dates[index]
            guard query.isEmpty || text.localizedCaseInsensitiveContains(query) else { return nil }
            return (text, date)
        }
    }

    /// Entries arrive asynchronously and can also shrink. Once there are entries, the highlight is kept on a row that
    /// exists: the first match when nothing is highlighted, the last row when the highlight is past the end.
    private func keepSelectionValid() {
        guard screen == .history, !entries.isEmpty else { return }
        // A highlight past the end (its row was deleted) moves to the new last row, so Return keeps a target.
        if let selected = selection, selected >= entries.count { selection = entries.count - 1 }
        if selection == nil { selection = 0 }
    }

    func searchChanged(_ text: String) {
        // The text field reports its text again on every key, including the arrows and Return. Only a real change
        // of the search starts over; otherwise the highlight and what Return copies would be reset.
        guard text != query else { return }
        query = text
        history.query = text
        // A new search starts at its first match, so Return always has a sensible target.
        selection = entries.isEmpty ? nil : 0
    }

    /// Arrow keys: moves the highlight through the matches, stopping at the ends rather than wrapping.
    func moveSelection(by step: Int) {
        let count = entries.count
        guard count > 0 else { selection = nil; return }
        let start = selection ?? (step > 0 ? -1 : count)
        selection = min(max(start + step, 0), count - 1)
    }

    /// Return: copies the highlighted capture, exactly as a click does.
    func copySelected() {
        guard let selection, entries.indices.contains(selection) else { return }
        copyCapture(entries[selection].text)
    }

    /// Copies the whole capture, even when the row shows only its beginning. The panel closes only once the
    /// clipboard holds the text; otherwise it stays open and says why.
    func copyCapture(_ text: String) {
        if capture.copyCapture(text) {
            copyError = nil
            dismiss()
            FocusReturn.shared.returnIfStillActive()
        } else {
            copyError = tr("Couldn't copy text. Try again.")
        }
    }

    func deleteCapture(_ text: String) {
        history.remove(text)
    }

    func clearHistory() {
        HistoryClearing.confirmClear()
    }

    func discardUnreadableHistory() {
        HistoryClearing.confirmDiscardUnreadable()
    }

    func openHistory() { screen = .history }

    func backToMain() {
        screen = .main
        query = ""
        history.query = ""
        selection = nil
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
            // Remembered first: opening the panel makes Nictate active, and the app to return to is the one before.
            FocusReturn.shared.remember()
            // Activating first makes the first click land in the panel, so History opens on one click.
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    func close() {
        popover.performClose(nil)
    }
}
