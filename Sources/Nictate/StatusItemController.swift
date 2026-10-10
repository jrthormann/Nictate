// Nictate: a macOS menu bar app that copies text from anywhere on your screen.
// Copyright (c) 2026 jrthormann. MIT License, see LICENSE.

import AppKit

/// The menu bar icon and the feedback that goes with a capture: the blink, and the VoiceOver
/// announcement that makes the result accessible without seeing it.
@MainActor
final class StatusItemController {
    private let settings = Settings.shared
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let flash: StatusFlash
    /// Which icon variant is showing (nil until the first draw), so the icon is rebuilt only on change.
    private var iconShowsAppend: Bool?

    init() {
        flash = StatusFlash(button: statusItem.button, idleImage: nil)
        refresh()
    }

    private var panel: StatusPanel?

    /// The icon opens the panel on either click. There is no NSMenu: the panel is the whole menu.
    func attach(_ panel: StatusPanel) {
        self.panel = panel
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(togglePanel)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    @objc private func togglePanel() {
        guard let button = statusItem.button, let panel else { return }
        panel.toggle(relativeTo: button)
    }

    /// Keeps the menu bar icon, its tooltip and its VoiceOver label in step with Append mode, so the
    /// mode that joins captures is never invisible.
    func refresh() {
        let appending = settings.appendMode
        guard iconShowsAppend != appending, let button = statusItem.button else { return }
        iconShowsAppend = appending
        let icon = MenuBarIcon.image(appending: appending)
        button.image = icon
        flash.idleImage = icon
        flash.appending = appending
        let label = appending ? tr("Nictate, append mode on") : "Nictate"
        button.toolTip = label
        button.setAccessibilityLabel(label)
    }

    func beginWorking() { flash.beginWorking() }
    func endWorking() { flash.endWorking() }

    func cue(_ outcome: CaptureOutcome) {
        if settings.visualCue { flash.show(outcome) }
    }

    /// Tells VoiceOver the result, since the visual cue alone is not accessible.
    func announce(_ message: String) {
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                             userInfo: [.announcement: message,
                                        .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }
}
