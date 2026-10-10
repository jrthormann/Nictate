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

    var body: some View {
        SettingsPage {
            SettingsSection("Shortcut") {
                SettingRow("Capture Text") { shortcutControl(.capture, name: tr("Capture Text")) }
                SettingRow("Cycle History") { shortcutControl(.rotateHistory, name: tr("Cycle History")) }
                SettingRow("Capture QR Code or Barcode") { shortcutControl(.captureCode, name: tr("Capture QR Code or Barcode")) }
                SettingCaption("Click a shortcut, then press the new combination.")
            }

            SettingsSection("Feedback") {
                SettingRow("Notification on copy") {
                    Picker("Notification on copy", selection: $settings.notificationStyle) {
                        Text("None").tag(NotificationStyle.none)
                        Text("Notice only").tag(NotificationStyle.generic)
                        Text("With the text").tag(NotificationStyle.text)
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                SettingToggle("Visual cue in the menu bar", isOn: $settings.visualCue)
            }

            SettingsSection("History") {
                SettingToggle("Keep history", isOn: keepHistory.animated(reduceMotion: reduceMotion))
                VStack(spacing: Design.Space.row) {
                    SettingToggle("Clear history on quit", isOn: $settings.clearHistoryOnQuit)
                    SettingRow("Delete old captures") {
                        Picker("Delete old captures", selection: Binding(
                            get: { settings.historyRetention },
                            set: { settings.historyRetention = $0; History.shared.pruneExpired() })) {
                            Text("Never").tag(HistoryRetention.never)
                            Text("After 1 hour").tag(HistoryRetention.hour)
                            Text("After 24 hours").tag(HistoryRetention.day)
                            Text("After 7 days").tag(HistoryRetention.week)
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                    SettingRow("Captures in rotation") {
                        Picker("Captures in rotation", selection: $settings.rotationDepth) {
                            ForEach([5, 10, 20, 50], id: \.self) { Text(verbatim: String($0)).tag($0) }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                }
                .disclosed(by: settings.historyEnabled)
                if HistoryDeletion.showsClearControl(historyEnabled: settings.historyEnabled, savedCount: history.items.count) {
                    SettingRow("Saved captures") {
                        Button("Clear History…") { HistoryClearing.confirmClear() }
                            .disabled(history.items.isEmpty)
                    }
                }
            }

            SettingsSection("System") {
                SettingToggle("Open at login", isOn: Binding(
                    get: { login.enabled }, set: { login.set($0) }))
                SettingRow("Reset Nictate") {
                    Button("Reset Nictate…", role: .destructive) { ResetNictate.confirm() }
                }
            }
        }
    }

    /// "Keep history". Turning it off then asks whether the captures already saved go too; the question
    /// waits for the switch to finish moving.
    private var keepHistory: Binding<Bool> {
        Binding(get: { settings.historyEnabled }, set: { on in
            settings.historyEnabled = on
            if !on { DispatchQueue.main.async { HistoryClearing.historyTurnedOff() } }
        })
    }

    /// The recorder for an action, and for an optional one a button that removes its shortcut.
    private func shortcutControl(_ slot: ShortcutSlot, name: String) -> some View {
        let current = settings.shortcut(for: slot)
        return HStack(spacing: Design.Space.compact) {
            ShortcutRecorder(label: current?.label ?? tr("No shortcut"), name: name) { code, mods, newLabel in
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
