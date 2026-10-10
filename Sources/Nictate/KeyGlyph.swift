// Nictate: a macOS menu bar app that copies text from anywhere on your screen.
// Copyright (c) 2026 jrthormann. MIT License, see LICENSE.

import AppKit
import Carbon.HIToolbox

/// How a key that types no character is written in a shortcut label, and the menu key equivalent that
/// label stands for. AppKit reports F-keys, arrows, Home, End and the like as characters in the private-use
/// area (U+F700-U+F8FF), which no font draws, so a label built from them showed an empty box.
enum KeyGlyph {
    private struct Key {
        let code: Int
        let label: String
        /// What `NSMenuItem.keyEquivalent` expects for this key.
        let equivalent: String
    }

    private static func function(_ value: Int) -> String { String(UnicodeScalar(UInt32(value))!) }

    private static let functionCodes = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
                                        kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20]

    /// Every named key. Space is not here: its label is translated, so `label(forKeyCode:)` handles it.
    private static let keys: [Key] = functionCodes.enumerated().map { index, code in
        Key(code: code, label: "F\(index + 1)", equivalent: function(NSF1FunctionKey + index))
    } + [
        Key(code: kVK_LeftArrow, label: "←", equivalent: function(NSLeftArrowFunctionKey)),
        Key(code: kVK_RightArrow, label: "→", equivalent: function(NSRightArrowFunctionKey)),
        Key(code: kVK_UpArrow, label: "↑", equivalent: function(NSUpArrowFunctionKey)),
        Key(code: kVK_DownArrow, label: "↓", equivalent: function(NSDownArrowFunctionKey)),
        Key(code: kVK_Home, label: "↖", equivalent: function(NSHomeFunctionKey)),
        Key(code: kVK_End, label: "↘", equivalent: function(NSEndFunctionKey)),
        Key(code: kVK_PageUp, label: "⇞", equivalent: function(NSPageUpFunctionKey)),
        Key(code: kVK_PageDown, label: "⇟", equivalent: function(NSPageDownFunctionKey)),
        Key(code: kVK_ForwardDelete, label: "⌦", equivalent: function(NSDeleteFunctionKey)),
        Key(code: kVK_Help, label: "Help", equivalent: function(NSHelpFunctionKey)),
        Key(code: kVK_Delete, label: "⌫", equivalent: "\u{8}"),
        Key(code: kVK_Escape, label: "⎋", equivalent: "\u{1b}"),
        Key(code: kVK_Return, label: "↩", equivalent: "\r"),
        Key(code: kVK_ANSI_KeypadEnter, label: "⌤", equivalent: "\u{3}"),
        Key(code: kVK_Tab, label: "⇥", equivalent: "\t"),
        Key(code: kVK_ANSI_KeypadClear, label: "⌧", equivalent: function(NSClearLineFunctionKey)),
    ]

    /// The modifier glyphs a recorded label starts with, in the order the recorder writes them.
    private static let modifierGlyphs: Set<Character> = ["⌃", "⌥", "⇧", "⌘"]

    /// Every key code the table names, plus Space: what the unit tests sweep.
    static var namedKeyCodes: [Int] { keys.map(\.code) + [kVK_Space] }

    /// The label for a key with a name of its own, or nil for a key that types a character.
    static func label(forKeyCode code: Int) -> String? {
        if code == kVK_Space { return tr("Space") }
        return keys.first { $0.code == code }?.label
    }

    /// The key part of a shortcut label: the named key, else the character the key types, upper-cased.
    /// A private-use character with no name becomes "?" rather than an invisible box.
    static func keyLabel(forKeyCode code: Int, characters: String?) -> String {
        if let named = label(forKeyCode: code) { return named }
        return readable(characters?.uppercased() ?? "") ?? "?"
    }

    /// The label with any private-use character replaced by its name. Stored labels can still hold
    /// the raw character, so a saved "⌘" + U+F708 reads "⌘F5". Nil when a character has no known name.
    static func readable(_ label: String) -> String? {
        guard !label.isEmpty else { return nil }
        var result = ""
        for scalar in label.unicodeScalars {
            guard isPrivateUse(scalar) else { result.unicodeScalars.append(scalar); continue }
            guard let key = keys.first(where: { $0.equivalent.unicodeScalars.first == scalar }) else { return nil }
            result += key.label
        }
        return result
    }

    /// The label as it should be shown: names in place of private-use characters, unchanged otherwise.
    static func display(_ label: String) -> String { readable(label) ?? label }

    /// The menu key equivalent for a recorded label such as "⇧⌘2", "⌃⌘F5" or "⌥⌘Space".
    static func keyEquivalent(forLabel label: String) -> String {
        let key = String(label.drop { modifierGlyphs.contains($0) })
        // Labels recorded before English became the source language end in "Espacio".
        if key == "Space" || key == "Espacio" || key == tr("Space") { return " " }
        if let named = keys.first(where: { $0.label == key }) { return named.equivalent }
        // A stored label may still hold the private-use character itself, which is already
        // the right key equivalent.
        return label.last.map { String($0).lowercased() } ?? ""
    }

    static func isPrivateUse(_ scalar: Unicode.Scalar) -> Bool { (0xF700...0xF8FF).contains(scalar.value) }
}
