// Nictate: a macOS menu bar app that copies text from anywhere on your screen.
// Copyright (c) 2026 jrthormann. MIT License, see LICENSE.

import AppKit
import Combine
import SwiftUI

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

    /// A model of its own for the Recent Captures panel, already showing the list. The popover and the picker share the same
    /// history and settings but never a screen, a search or a highlight: with one model for both, the picker's keys stopped
    /// reaching its list after the popover had been used, and Escape in the popover's History closed it instead of going back.
    func makePickerModel() -> StatusPanelModel {
        let picker = StatusPanelModel(capture: capture, windows: windows, history: history, settings: settings)
        picker.reset()
        picker.openPicker()
        return picker
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

    var isShown: Bool { popover.isShown || isPickerShown }
    /// Whether the Recent Captures panel is on screen.
    var isPickerShown: Bool { floating?.isVisible ?? false }
    /// Whether the picker is on screen or the popover is closing for it. A capture started now would take its picture with it, or the
    /// popover's fade-out.
    var isPickerShownOrOpening: Bool { RecentCapturesPicker.isShown(panelVisible: isPickerShown, opening: pickerOpening) }
    /// The popover is closing, and the picker opens once it has. Until then the popover still draws, though it reports itself closed.
    private var pickerOpening = false
    /// The Recent Captures panel, used by the shortcut. It can show over full-screen apps, where the menu bar is hidden.
    private(set) var floating: FloatingPanel?
    private var floatingHost: NSHostingController<StatusPanelView>?
    /// Keeps the panel as tall as its list: the saved captures can arrive after it has opened.
    private var floatingSize: AnyCancellable?
    /// A press on the menu bar icon took key status from the picker, and the icon's action follows.
    private var pickerLeftForIcon = false
    /// The window that draws the panel, once it is shown.
    var window: NSWindow? { popover.contentViewController?.view.window }

    func toggle(relativeTo button: NSView) {
        if popover.isShown {
            close()
        } else {
            // The icon pressed over the picker replaces it. Nictate is in front then, and the app saved when the picker opened stays.
            let replacingPicker = floating != nil || (pickerLeftForIcon && NSApp.isActive)
            pickerLeftForIcon = false
            pickerOpening = false // The icon's popover takes the place of the picker the shortcut asked for.
            dismissFloating()
            model.reset()
            // Remembered first: opening the panel makes Nictate active, and the app to return to is the one before.
            if RecentCapturesPicker.remembersOrigin(replacingPicker: replacingPicker) { FocusReturn.shared.remember() }
            // Activating first makes the first click land in the panel, so History opens on one click.
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    func close() {
        popover.performClose(nil)
        dismissFloating()
    }

    /// Takes the Recent Captures panel off the screen and lets it go, so no hidden panel stays behind with its own copy of the
    /// list. It is released after the current event, because an Escape or a click inside it is what usually closes it.
    private func dismissFloating() {
        guard let panel = floating else { return }
        let host = floatingHost
        floating = nil
        floatingHost = nil
        floatingSize = nil
        panel.orderOut(nil)
        DispatchQueue.main.async {
            panel.contentView = nil
            _ = host
        }
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

    /// The shortcut's action: the Recent Captures list in a panel that also shows over full-screen apps. Nothing is copied
    /// on open. The app the user is in is remembered first, so focus can return to it after a copy or Escape.
    func showRecentCaptures(relativeTo button: NSView) {
        switch RecentCapturesPicker.opening(popoverShown: popover.isShown, closePending: afterClose != nil, pickerShown: isPickerShown) {
        case .ignore: return
        case .openNow:
            FocusReturn.shared.remember()
            presentPicker(below: button)
        case .closePopoverFirst:
            // Nothing is captured, so only the popover's own fade-out is waited for. The app saved when it opened stays.
            pickerOpening = true // Before the close: without animation the picker can open from inside it.
            close { [weak self] in self?.presentPicker(below: button) }
        }
    }

    private func presentPicker(below button: NSView) {
        pickerOpening = false
        let picker = model.makePickerModel()
        picker.dismiss = { [weak self] in self?.dismissFloating() }
        presentFloating(model: picker, below: button)
    }

    private func presentFloating(model: StatusPanelModel, below button: NSView) {
        let host = NSHostingController(rootView: StatusPanelView(model: model))
        // As in the popover, the content reports the size it wants, and the panel follows it below.
        host.sizingOptions = [.preferredContentSize]
        host.view.layoutSubtreeIfNeeded()
        let size = host.view.fittingSize
        let backdrop = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        backdrop.material = .popover
        backdrop.blendingMode = .behindWindow
        backdrop.state = .active
        backdrop.wantsLayer = true
        backdrop.layer?.cornerRadius = 10
        backdrop.layer?.masksToBounds = true
        host.view.frame = backdrop.bounds
        host.view.autoresizingMask = [.width, .height]
        backdrop.addSubview(host.view)
        let panel = FloatingPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .fullSizeContentView],
                                  backing: .buffered, defer: false)
        panel.contentView = backdrop
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        let placed = RecentCapturesPicker.placement(for: size, below: button)
        panel.visibleScreenFrame = placed.visible
        panel.setFrameTopLeftPoint(placed.topLeft)
        panel.onResignKey = { [weak self, weak panel, weak button] in
            guard let self, let panel, self.floating === panel else { return }
            // A press on the menu bar icon ends the picker's key status first, and the icon's action then opens the popover.
            self.pickerLeftForIcon = button?.window != nil && NSApp.currentEvent?.window === button?.window
            self.dismissFloating()
        }
        floatingHost = host
        floating = panel
        pickerLeftForIcon = false
        // One turn later: the size changes while SwiftUI lays the view out.
        floatingSize = (host as NSViewController).publisher(for: \.preferredContentSize)
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak panel] size in if self?.floating === panel { panel?.fit(to: size) } }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
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
