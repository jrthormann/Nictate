// Nictate: a macOS menu bar app that copies text from anywhere on your screen.
// Copyright (c) 2026 jrthormann. MIT License, see LICENSE.

import Foundation

/// Every key and name the app persists, in one place. The strings are part of what users already have
/// saved, so changing a value orphans their data: rename the Swift constant freely, never the string.
enum StorageKeys {
    // Shortcuts
    static let hotKeyCode = "hotKeyCode"
    static let hotKeyMods = "hotKeyMods"
    static let hotKeyLabel = "hotKeyLabel"
    static let rotateHotKeyCode = "rotateHotKeyCode"
    static let rotateHotKeyMods = "rotateHotKeyMods"
    static let rotateHotKeyLabel = "rotateHotKeyLabel"
    static let rotationDepth = "rotationDepth"
    /// The optional shortcut: a dictionary ["code": Int, "mods": Int, "label": String], absent when unset.
    static let codeHotKey = "codeHotKey"

    // Feedback
    static let visualCue = "visualCue"
    /// "none", "generic" (the default, never stored until chosen) or "text".
    static let notificationStyle = "notificationStyle"

    // Recognition
    static let languages = "languages"
    static let languageCorrection = "languageCorrection"
    static let codeMode = "codeMode"
    static let keepLineBreaks = "keepLineBreaks"
    static let detectColumns = "detectColumns"
    static let tablesAsTabs = "tablesAsTabs"
    /// Joins words split by hyphens and collapses repeated spaces. The stored key is "dehyphenate".
    static let cleanText = "dehyphenate"

    // Code clean-up
    static let codeClean = "codeClean"

    // Output
    static let appendMode = "appendMode"
    static let appendSeparator = "appendSeparator"
    static let barcodeAction = "barcodeAction"
    static let detectContent = "detectContent"
    static let hideFromClipboardManagers = "hideFromClipboardManagers"

    // History and system
    static let historyEnabled = "historyEnabled"
    static let clearHistoryOnQuit = "clearHistoryOnQuit"
    static let historyRetention = "historyRetention"

    // Stored outside Settings
    static let didOnboard = "didOnboard"

    /// Every key of `Settings`.
    static let settings = [
        hotKeyCode, hotKeyMods, hotKeyLabel, rotateHotKeyCode, rotateHotKeyMods, rotateHotKeyLabel, rotationDepth,
        codeHotKey,
        visualCue, notificationStyle,
        languages, languageCorrection, codeMode, keepLineBreaks, detectColumns, tablesAsTabs, cleanText,
        codeClean,
        appendMode, appendSeparator, barcodeAction, detectContent, hideFromClipboardManagers,
        historyEnabled, clearHistoryOnQuit, historyRetention,
    ]

    /// Window frame autosave names (AppKit stores each frame in UserDefaults under these).
    enum WindowFrame {
        static let history = "Nictate.History"
    }
}
