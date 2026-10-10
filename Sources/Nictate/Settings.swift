// Nictate: a macOS menu bar app that copies text from anywhere on your screen.
// Copyright (c) 2026 jrthormann. MIT License, see LICENSE.

import AppKit
import Carbon.HIToolbox
import Combine
import Foundation

/// User preferences stored directly in UserDefaults under the keys in `StorageKeys`, so renaming a
/// property can never change what is persisted. Every change notifies SwiftUI through `objectWillChange`.
@MainActor
final class Settings: ObservableObject {
    static let shared = Settings()
    private let defaults: UserDefaults

    /// The app uses `shared`, over the standard defaults. Tests pass a suite of their own, so they never
    /// read or write the user's preferences and parallel runs cannot see each other's values.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            StorageKeys.hotKeyCode: kVK_ANSI_2, StorageKeys.hotKeyMods: cmdKey | shiftKey, StorageKeys.hotKeyLabel: "⇧⌘2",
            StorageKeys.rotateHotKeyCode: kVK_ANSI_2, StorageKeys.rotateHotKeyMods: optionKey | shiftKey | cmdKey, StorageKeys.rotateHotKeyLabel: "⌥⇧⌘2",
            StorageKeys.rotationDepth: 10,
            StorageKeys.codeClean: false,
            StorageKeys.visualCue: true,
            StorageKeys.languages: [String](), StorageKeys.languageCorrection: true, StorageKeys.codeMode: false,
            StorageKeys.keepLineBreaks: true, StorageKeys.detectColumns: true, StorageKeys.tablesAsTabs: true, StorageKeys.cleanText: false,
            StorageKeys.appendMode: false, StorageKeys.appendSeparator: "newline",
            StorageKeys.barcodeAction: "copy", StorageKeys.detectContent: true, StorageKeys.hideFromClipboardManagers: false,
            StorageKeys.historyEnabled: true, StorageKeys.clearHistoryOnQuit: false, StorageKeys.historyRetention: HistoryRetention.week.rawValue,
        ])
    }

    private func flag(_ key: String) -> Bool { defaults.bool(forKey: key) }
    private func number(_ key: String) -> Int { defaults.integer(forKey: key) }
    private func text(_ key: String) -> String { defaults.string(forKey: key) ?? "" }
    private func list(_ key: String) -> [String] { defaults.stringArray(forKey: key) ?? [] }
    private func store(_ value: Any, _ key: String) {
        objectWillChange.send()
        defaults.set(value, forKey: key)
    }

    // Shortcut
    var hotKeyCode: Int { get { number(StorageKeys.hotKeyCode) } set { store(newValue, StorageKeys.hotKeyCode) } }
    var hotKeyMods: Int { get { number(StorageKeys.hotKeyMods) } set { store(newValue, StorageKeys.hotKeyMods) } }
    var hotKeyLabel: String { get { text(StorageKeys.hotKeyLabel) } set { store(newValue, StorageKeys.hotKeyLabel) } }

    /// Second shortcut: cycles the clipboard through recent captures.
    var rotateHotKeyCode: Int { get { number(StorageKeys.rotateHotKeyCode) } set { store(newValue, StorageKeys.rotateHotKeyCode) } }
    var rotateHotKeyMods: Int { get { number(StorageKeys.rotateHotKeyMods) } set { store(newValue, StorageKeys.rotateHotKeyMods) } }
    var rotateHotKeyLabel: String { get { text(StorageKeys.rotateHotKeyLabel) } set { store(newValue, StorageKeys.rotateHotKeyLabel) } }
    /// The shortcut of an action and the label to show for it, or nil when an optional one is unset.
    func shortcut(for slot: ShortcutSlot) -> (shortcut: Shortcut, label: String)? {
        switch slot {
        case .capture: return (Shortcut(code: hotKeyCode, mods: hotKeyMods), hotKeyLabel)
        case .rotateHistory: return (Shortcut(code: rotateHotKeyCode, mods: rotateHotKeyMods), rotateHotKeyLabel)
        case .captureCode:
            guard let stored = defaults.dictionary(forKey: StorageKeys.codeHotKey),
                  let code = stored["code"] as? Int, let mods = stored["mods"] as? Int, let label = stored["label"] as? String
            else { return nil }
            return (Shortcut(code: code, mods: mods), label)
        }
    }

    /// Saves the shortcut of an action. Passing nil removes an optional one; the two main actions always keep theirs.
    func setShortcut(_ shortcut: Shortcut?, label: String = "", for slot: ShortcutSlot) {
        switch slot {
        case .capture:
            guard let shortcut else { return }
            hotKeyCode = shortcut.code; hotKeyMods = shortcut.mods; hotKeyLabel = label
        case .rotateHistory:
            guard let shortcut else { return }
            rotateHotKeyCode = shortcut.code; rotateHotKeyMods = shortcut.mods; rotateHotKeyLabel = label
        case .captureCode:
            objectWillChange.send()
            if let shortcut {
                defaults.set(["code": shortcut.code, "mods": shortcut.mods, "label": label], forKey: StorageKeys.codeHotKey)
            } else {
                defaults.removeObject(forKey: StorageKeys.codeHotKey)
            }
        }
    }

    /// How many recent captures the rotation walks through.
    var rotationDepth: Int { get { number(StorageKeys.rotationDepth) } set { store(newValue, StorageKeys.rotationDepth) } }

    // Feedback
    var visualCue: Bool { get { flag(StorageKeys.visualCue) } set { store(newValue, StorageKeys.visualCue) } }
    var notificationStyle: NotificationStyle {
        get { NotificationStyle(rawValue: text(StorageKeys.notificationStyle)) ?? .generic }
        set { store(newValue.rawValue, StorageKeys.notificationStyle) }
    }

    // Recognition
    /// Empty = automatic language detection.
    var languages: [String] { get { list(StorageKeys.languages) } set { store(newValue, StorageKeys.languages) } }
    var languageCorrection: Bool { get { flag(StorageKeys.languageCorrection) } set { store(newValue, StorageKeys.languageCorrection) } }
    /// Faithful mode: exact symbols, indentation and blank lines; no language correction, no cleanup.
    var codeMode: Bool { get { flag(StorageKeys.codeMode) } set { store(newValue, StorageKeys.codeMode) } }
    var keepLineBreaks: Bool { get { flag(StorageKeys.keepLineBreaks) } set { store(newValue, StorageKeys.keepLineBreaks) } }
    var detectColumns: Bool { get { flag(StorageKeys.detectColumns) } set { store(newValue, StorageKeys.detectColumns) } }
    /// Separates the cells of a detected table with tabs, so pasting into a spreadsheet fills columns.
    var tablesAsTabs: Bool { get { flag(StorageKeys.tablesAsTabs) } set { store(newValue, StorageKeys.tablesAsTabs) } }
    /// Joins words split by hyphens at a line break and collapses repeated spaces (never in faithful mode).
    var cleanText: Bool { get { flag(StorageKeys.cleanText) } set { store(newValue, StorageKeys.cleanText) } }

    // Code clean-up
    var codeClean: Bool { get { flag(StorageKeys.codeClean) } set { store(newValue, StorageKeys.codeClean) } }

    // Output
    var appendMode: Bool { get { flag(StorageKeys.appendMode) } set { store(newValue, StorageKeys.appendMode) } }
    /// One of "newline", "space", "tab". Any other stored value reads as "newline".
    var appendSeparator: String {
        get { ["space", "tab"].contains(text(StorageKeys.appendSeparator)) ? text(StorageKeys.appendSeparator) : "newline" }
        set { store(newValue, StorageKeys.appendSeparator) }
    }
    var appendDelimiter: String {
        switch appendSeparator {
        case "space": return " "
        case "tab": return "\t"
        default: return "\n"
        }
    }
    /// Look for colors, links and emails in each capture and offer actions for them.
    var detectContent: Bool { get { flag(StorageKeys.detectContent) } set { store(newValue, StorageKeys.detectContent) } }
    /// What to do with a link found in a QR code or barcode: "copy" or "ask". A link from a code is never
    /// opened without showing its address first.
    var barcodeAction: String {
        get { ["ask", "open"].contains(text(StorageKeys.barcodeAction)) ? "ask" : "copy" }
        set { store(newValue, StorageKeys.barcodeAction) }
    }
    var hideFromClipboardManagers: Bool { get { flag(StorageKeys.hideFromClipboardManagers) } set { store(newValue, StorageKeys.hideFromClipboardManagers) } }

    // History & system
    var historyEnabled: Bool { get { flag(StorageKeys.historyEnabled) } set { store(newValue, StorageKeys.historyEnabled) } }
    var clearHistoryOnQuit: Bool { get { flag(StorageKeys.clearHistoryOnQuit) } set { store(newValue, StorageKeys.clearHistoryOnQuit) } }
    /// A week by default (the registered default). A stored value that is not a choice reads as never, so a
    /// damaged preference can never delete captures.
    var historyRetention: HistoryRetention {
        get { HistoryRetention(rawValue: text(StorageKeys.historyRetention)) ?? .never }
        set { store(newValue.rawValue, StorageKeys.historyRetention) }
    }

    /// Reset Nictate: every stored setting goes, so each returns to its default. The retention is written as
    /// "week" (the default of a new install), so that the next launch does not settle it again as "never".
    static func resetToDefaults(in defaults: UserDefaults = .standard) {
        for key in StorageKeys.settings { defaults.removeObject(forKey: key) }
        defaults.set(HistoryRetention.week.rawValue, forKey: StorageKeys.historyRetention)
    }

    /// Key equivalent matching a recorded shortcut label, so menus render it natively (e.g. "⇧⌘2").
    static func keyEquivalent(forLabel label: String) -> String {
        // F-keys, arrows and the other named keys map to AppKit's function-key characters.
        KeyGlyph.keyEquivalent(forLabel: label)
    }

    static func modifierMask(for mods: Int) -> NSEvent.ModifierFlags {
        var mask: NSEvent.ModifierFlags = []
        if mods & controlKey != 0 { mask.insert(.control) }
        if mods & optionKey != 0 { mask.insert(.option) }
        if mods & shiftKey != 0 { mask.insert(.shift) }
        if mods & cmdKey != 0 { mask.insert(.command) }
        return mask
    }
}
