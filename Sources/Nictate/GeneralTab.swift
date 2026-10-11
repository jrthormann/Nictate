// Nictate: a macOS menu bar app that copies text from anywhere on your screen.
// Copyright (c) 2026 jrthormann. MIT License, see LICENSE.

import ServiceManagement
import SwiftUI

@MainActor
final class LoginItem: ObservableObject {
    static let shared = LoginItem()
    @Published var enabled = SMAppService.mainApp.status == .enabled

    func set(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch { Log.app.error("login item: \(error.localizedDescription, privacy: .public)") }
        enabled = SMAppService.mainApp.status == .enabled
    }
}

struct GeneralTab: View {
    @ObservedObject private var settings = Settings.shared
    @ObservedObject private var login = LoginItem.shared
    @ObservedObject private var history = History.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Shown only while an earlier encrypted history is on this Mac and has not been imported yet.
    @StateObject private var legacyImport = LegacyImportState()

    var body: some View {
        SettingsPage {
            SettingsSection("Keyboard Shortcuts") {
                SettingRow("Capture Text") { shortcutControl(.capture, name: tr("Capture Text")) }
                SettingRow("Cycle History") { shortcutControl(.rotateHistory, name: tr("Cycle History")) }
                SettingRow("Scan QR or Barcode") { shortcutControl(.captureCode, name: tr("Scan QR or Barcode")) }
                SettingCaption("Click a shortcut to change it.")
            }

            SettingsSection("History") {
                SettingToggle("Save Captures", isOn: keepHistory.animated(reduceMotion: reduceMotion))
                SettingToggle("Clear on Quit", isOn: $settings.clearHistoryOnQuit)
                if legacyImport.available {
                    SettingRow("Import Previous History…") {
                        Button("Import Previous History…") {
                            ImportPreviousHistory.confirmAndRun { legacyImport.refresh() }
                        }
                        .disabled(history.importing)
                    }
                    SettingCaption("Import captures saved by an earlier version of Nictate.")
                }
                if history.fileIsUnreadable {
                    SettingRow("Unreadable history") {
                        Button("Discard Unreadable History…") { HistoryClearing.confirmDiscardUnreadable() }
                    }
                }
                if HistoryDeletion.showsClearControl(historyEnabled: settings.historyEnabled, savedCount: history.items.count) {
                    SettingRow("Saved captures") {
                        Button("Clear History…") { HistoryClearing.confirmClear() }
                            .disabled(history.items.isEmpty)
                    }
                }
                SettingCaption("Keep your last 15 captures on this Mac. With Clear on Quit, they are deleted each time Nictate quits.")
            }

            SettingsSection("Notifications") {
                SettingRow("Copy Feedback") {
                    Picker("Copy Feedback", selection: $settings.notificationStyle) {
                        Text(tr("None")).tag(NotificationStyle.none)
                        Text(tr("Notice Only")).tag(NotificationStyle.generic)
                        Text(tr("Notice and Text")).tag(NotificationStyle.text)
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                SettingToggle("Menu Bar Indicator", isOn: $settings.visualCue)
            }

            SettingsSection("Startup") {
                SettingToggle("Launch at Login", isOn: Binding(
                    get: { login.enabled }, set: { login.set($0) }))
                SettingRow("Reset Settings…") {
                    Button("Reset…", role: .destructive) { ResetNictate.confirm() }
                }
                SettingCaption("Restores every setting to its default, except Launch at Login. Saved captures are kept unless you also delete them.")
            }
        }
    }

    /// "Save Captures". Turning it off then asks whether the captures already saved go too; the question
    /// waits for the switch to finish moving.
    private var keepHistory: Binding<Bool> {
        Binding(get: { settings.historyEnabled }, set: { on in
            settings.historyEnabled = on
            History.shared.refresh()
            if !on { Task { await HistoryClearing.historyTurnedOff() } }
        })
    }

    /// The recorder for an action, and for an optional one a button that removes its shortcut.
    private func shortcutControl(_ slot: ShortcutSlot, name: String) -> some View {
        let current = settings.shortcut(for: slot)
        return HStack(spacing: Design.Space.compact) {
            ShortcutRecorder(label: current?.label ?? tr("Not Set"), name: name) { code, mods, newLabel in
                record(slot, code: code, mods: mods, label: newLabel)
            }
            .frame(minWidth: 96)
            .fixedSize()
            if slot.isOptional, current != nil {
                Button {
                    HotKeyManager.shared.unregister(slot)
                    settings.setShortcut(nil, for: slot)
                } label: { Image(systemName: "xmark.circle.fill") }
                .buttonStyle(.borderless)
                .foregroundStyle(Design.Ink.secondary)
                .help(tr("Remove shortcut"))
                .accessibilityLabel(tr("Remove shortcut"))
            }
        }
    }

    /// Registers a recorded shortcut and, only if the system accepts it, saves it. Returns whether it was accepted.
    private func record(_ slot: ShortcutSlot, code: Int, mods: Int, label: String) -> Bool {
        let new = Shortcut(code: code, mods: mods)
        let others = ShortcutSlot.allCases.filter { $0 != slot }.compactMap { settings.shortcut(for: $0)?.shortcut }
        let outcome = ShortcutBinding.apply(new: new, current: settings.shortcut(for: slot)?.shortcut, others: others) {
            HotKeyManager.shared.register(slot, code: $0.code, mods: $0.mods)
        }
        guard outcome == .accepted else { return false }
        settings.setShortcut(new, label: label, for: slot)
        return true
    }
}
