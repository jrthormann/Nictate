// Nictate: a macOS menu bar app that copies text from anywhere on your screen.
// Copyright (c) 2026 jrthormann. MIT License, see LICENSE.

import AppKit
import Combine
import SwiftUI

/// What the Recent Captures list says above, or instead of, its entries. Kept apart from the view so the rules are tested.
enum RecentCapturesNotice: Equatable {
    case nothing, loading, unavailable, savingOff, savingOffWithCaptures, noCaptures

    static func of(state: HistoryState, count: Int, historyEnabled: Bool) -> RecentCapturesNotice {
        if state == .loading { return .loading }
        if state == .unavailable { return .unavailable }
        if !historyEnabled { return count == 0 ? .savingOff : .savingOffWithCaptures }
        return count == 0 ? .noCaptures : .nothing
    }
}

/// What the menu bar panel shows and does. The history is a second screen of the same panel, never a window.
@MainActor
final class StatusPanelModel: ObservableObject {
    enum Screen { case main, history }
    enum EscapeAction: Equatable { case clearSearch, back, close }

    /// What Escape does on each screen. A list opened with the shortcut is a picker: Escape closes it.
    static func escape(screen: Screen, query: String, isPicker: Bool) -> EscapeAction {
        switch screen {
        case .history where !query.isEmpty: return .clearSearch
        case .history where isPicker: return .close
        case .history: return .back
        case .main: return .close
        }
    }

    /// True when the list was opened with the shortcut. A picker has no Back row, and Escape closes it.
    @Published private(set) var isPicker = false

    @Published var screen: Screen = .main {
        // Opening History highlights its first match, so Return always has a target.
        didSet { if screen == .history, selection == nil { selection = entries.isEmpty ? nil : 0 } }
    }
    @Published var query = ""
    /// Shown in the History screen when a copy fails. Cleared by the next attempt.
    @Published var copyError: String?
    /// The highlighted row in the History list, as an index into `entries`. Arrow keys move it, Return copies it.
    @Published var selection: Int?
    private let settings: Settings
    private let capture: CaptureCoordinator
    private let windows: WindowCoordinator
    /// Closes the panel once an action has done its job.
    var dismiss: () -> Void = {}
    /// Closes the panel and runs the action once it is off the screen. With no panel to wait for, it runs at once.
    var dismissThen: (@escaping () -> Void) -> Void = { $0() }

    /// The history the panel shows. The app passes its shared history; tests pass a disposable one.
    private let history: History

    /// Changes to the history and the settings redraw the panel, not only changes to its own properties.
    private var observers = Set<AnyCancellable>()

    init(capture: CaptureCoordinator, windows: WindowCoordinator, history: History = .shared, settings: Settings = .shared) {
        self.capture = capture
        self.windows = windows
        self.history = history
        self.settings = settings
        history.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
            // The change is announced before its entries are stored, so the first match is chosen on the next pass.
            DispatchQueue.main.async { self?.keepSelectionValid() }
        }.store(in: &observers)
        settings.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &observers)
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
        isPicker = false
        query = ""
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
    var historyCount: Int { history.items.count }
    var historyState: HistoryState { history.state }
    var historyFileUnreadable: Bool { history.fileIsUnreadable }
    var historyClosed: Bool { history.isClosed }
    var hotKeyLabel: String { settings.shortcutLabel(for: .capture) ?? "" }
    var rotateHotKeyLabel: String { settings.shortcutLabel(for: .rotateHistory) ?? "" }
    var codeHotKeyLabel: String? { settings.shortcutLabel(for: .captureCode) }
    var codeMode: Bool { settings.codeMode }

    /// A capture takes its stills straight away, so it starts only once the panel is gone: its fade-out would be in the picture.
    func captureText() { dismissThen { [capture] in capture.capture(mode: .text) } }
    func captureCode() { dismissThen { [capture] in capture.capture(mode: .code) } }
    /// The shortcut's list: the saved captures, opened as a picker. Nothing is copied until a row is chosen.
    func openPicker() {
        isPicker = true
        screen = .history
    }
    /// Escape closes the panel and gives focus back to the app the user came from.
    func closeReturningFocus() { dismiss(); FocusReturn.shared.returnIfStillActive() }
    func setFaithful(_ faithful: Bool) { settings.codeMode = faithful }
    func setLanguage(_ code: String) { settings.languages = code.isEmpty ? [] : [code] }
    func setKeepHistory(_ on: Bool) {
        HistoryClearing.setSaveCaptures(on, history: history, settings: settings)
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
    /// Open leaves the browser in front. Cancel gives focus back, as the panel has already closed.
    func openDetected(_ url: URL) { dismiss(); capture.openLink(url); FocusReturn.shared.returnIfStillActive() }

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
        Notifier.withdrawAll()
    }

    func clearHistory() {
        HistoryClearing.confirmClear(history)
    }

    func discardUnreadableHistory() {
        HistoryClearing.confirmDiscardUnreadable(history)
    }

    func openHistory() { screen = .history }

    func backToMain() {
        screen = .main
        query = ""
        selection = nil
    }
}

/// The menu bar popover that holds the panel. It closes on a click outside, which is the expected behaviour here.
@MainActor
final class StatusPanel: NSObject, NSPopoverDelegate {
    let model: StatusPanelModel
    private let popover = NSPopover()
    /// What waits for the popover to finish closing. Its fade-out takes about half a second, and the window server draws it
    /// until then, though the window already reports itself as not visible.
    private var afterClose: (() -> Void)?

    init(model: StatusPanelModel, animates: Bool = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion) {
        self.model = model
        super.init()
        popover.delegate = self
        model.dismiss = { [weak self] in self?.close() }
        model.dismissThen = { [weak self] action in
            guard let self else { return action() }
            self.close(then: action)
        }
        popover.behavior = .transient
        popover.animates = animates
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

    /// Closes the popover and runs `action` once it has closed, or at once when it is not shown. One action waits at a time.
    func close(then action: @escaping () -> Void) {
        guard popover.isShown else { return action() }
        guard afterClose == nil else { return } // Already closing for another choice: this one finds the panel gone.
        // Stored before the close: without animation the popover can report its close from inside `performClose`.
        afterClose = action
        popover.performClose(nil)
    }

    func popoverDidClose(_ notification: Notification) {
        runAfterClose()
    }

    private func runAfterClose() {
        guard let action = afterClose else { return }
        afterClose = nil
        action()
    }

    /// The shortcut's action: the Recent Captures list, anchored to the menu bar icon. Nothing is copied on open. The app
    /// the user is in is remembered first, so focus can return to it after a copy or Escape. If the icon cannot be seen,
    /// the panel cannot anchor, so the user is told why instead.
    func showRecentCaptures(relativeTo button: NSView) {
        guard !popover.isShown else { return }
        guard let window = button.window, window.isVisible else {
            showIconHidden()
            return
        }
        FocusReturn.shared.remember()
        model.reset()
        model.openPicker()
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    private func showIconHidden() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = tr("Recent Captures can't open")
        alert.informativeText = tr("Nictate's icon is hidden in the menu bar or off screen. Show it, then press the shortcut again.")
        alert.addButton(withTitle: tr("OK"))
        alert.runModal()
    }
}

extension History {
    /// "5 min. ago" style text for a capture time, or nil when the time is unknown.
    static func ageLabel(for date: Date, now: Date = Date(), locale: Locale = .current) -> String? {
        guard date != .distantPast else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        formatter.dateTimeStyle = .named
        formatter.locale = locale
        return formatter.localizedString(for: date, relativeTo: now)
    }
}
