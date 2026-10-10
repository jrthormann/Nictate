// Nictate: a macOS menu bar app that copies text from anywhere on your screen.
// Copyright (c) 2026 jrthormann. MIT License, see LICENSE.

import AppKit
import Carbon.HIToolbox
import SwiftUI

/// A key cap that records a new global shortcut. A click, Space, Return or a VoiceOver press arms it; the next
/// combination with ⌘ or ⌃ is the new shortcut; Esc, a click elsewhere or leaving the window cancels.
/// While it is armed the app's own hotkeys are released, so pressing the current combination records it
/// instead of starting a capture.
final class RecorderButton: NSButton {
    /// Returns whether the shortcut was accepted; a refused one flashes a message on the button.
    var onRecord: ((Int, Int, String) -> Bool)?
    private(set) var isRecording = false {
        didSet {
            guard isRecording != oldValue else { return }
            if isRecording {
                messageToken += 1
                HotKeyManager.shared.suspend()
                title = tr("Press the shortcut…")
            } else {
                HotKeyManager.shared.resume()
                title = idleTitle
            }
            NSAccessibility.post(element: self, notification: .valueChanged)
        }
    }
    private var idleTitle = ""
    private var messageToken = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        target = self
        action = #selector(startRecording)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        target = self
        action = #selector(startRecording)
    }

    override var acceptsFirstResponder: Bool { true }

    func setIdleTitle(_ t: String) {
        let shown = KeyGlyph.display(t)
        guard shown != idleTitle else { return }
        idleTitle = shown
        if !isRecording { title = shown }
        NSAccessibility.post(element: self, notification: .valueChanged)
    }

    /// Arms the recorder, only in the key window and only once it has the focus: without them no key press
    /// would reach it and nothing would disarm it, so the hotkeys would stay released.
    @objc func startRecording() {
        guard !isRecording, let window, window.isKeyWindow, window.makeFirstResponder(self) else { return }
        isRecording = true
    }

    /// Disarms the recorder and keeps the focus on it, so a keyboard user can try again with Space.
    func cancelRecording() { isRecording = false }

    /// VoiceOver reads the shortcut in force as the value, after the action's name.
    override func accessibilityValue() -> Any? { isRecording ? tr("Press the shortcut…") : idleTitle }

    override func accessibilityPerformPress() -> Bool {
        startRecording()
        return true
    }

    override func mouseDown(with event: NSEvent) { startRecording() }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        return super.resignFirstResponder()
    }

    /// What disarms the recorder besides a key: its window losing key status or closing, and the app going
    /// to the background. None of them may leave the hotkeys released.
    private static let disarmingWindowNotifications = [NSWindow.didResignKeyNotification, NSWindow.willCloseNotification]

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { isRecording = false }
        let center = NotificationCenter.default
        if let old = window {
            for name in Self.disarmingWindowNotifications { center.removeObserver(self, name: name, object: old) }
        }
        if let newWindow {
            for name in Self.disarmingWindowNotifications {
                center.addObserver(self, selector: #selector(disarm(_:)), name: name, object: newWindow)
            }
        }
        super.viewWillMove(toWindow: newWindow)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        let center = NotificationCenter.default
        center.removeObserver(self, name: NSApplication.didResignActiveNotification, object: nil)
        if window != nil {
            center.addObserver(self, selector: #selector(disarm(_:)), name: NSApplication.didResignActiveNotification, object: nil)
        }
    }

    @objc private func disarm(_ note: Notification) { isRecording = false }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording else { return false }
        keyDown(with: event)
        return true
    }

    override func keyDown(with event: NSEvent) {
        let code = Int(event.keyCode)
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard isRecording else {
            // Space, Return and Enter arm it, so the shortcut can be changed without a mouse.
            if flags.isDisjoint(with: [.command, .control, .option]),
               [kVK_Space, kVK_Return, kVK_ANSI_KeypadEnter].contains(code) {
                return startRecording()
            }
            return super.keyDown(with: event)
        }
        if code == kVK_Escape { return cancelRecording() }
        var mods = 0, label = ""
        if flags.contains(.control) { mods |= controlKey; label += "⌃" }
        if flags.contains(.option) { mods |= optionKey; label += "⌥" }
        if flags.contains(.shift) { mods |= shiftKey; label += "⇧" }
        if flags.contains(.command) { mods |= cmdKey; label += "⌘" }
        guard mods & (controlKey | optionKey | cmdKey) != 0 else {
            // Tab and ⇧Tab still move the focus, so the keyboard is never trapped on the button.
            guard code == kVK_Tab else { return NSSound.beep() }
            cancelRecording()
            if flags.contains(.shift) { window?.selectKeyView(preceding: self) } else { window?.selectKeyView(following: self) }
            return
        }
        guard ShortcutRule.isAcceptableForRecording(mods: mods) else {
            cancelRecording()
            return flash(tr("Include ⌘ or ⌃: ⌥ with a letter types a character in every app."))
        }

        label += KeyGlyph.keyLabel(forKeyCode: code, characters: event.charactersIgnoringModifiers)
        // The hotkeys come back first, so registering the new one gets the system's real answer and a
        // refused one leaves the old shortcut in force.
        cancelRecording()
        let accepted = onRecord?(code, mods, label) ?? false
        if !accepted { flash(tr("Shortcut unavailable")) }
    }

    /// Shows why a shortcut was refused for a moment, then the shortcut that is still in force.
    private func flash(_ message: String) {
        NSSound.beep()
        messageToken += 1
        let token = messageToken
        title = message
        NSAccessibility.post(element: self, notification: .announcementRequested,
                             userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.high.rawValue])
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
            guard let self, self.messageToken == token, !self.isRecording else { return }
            self.title = self.idleTitle
        }
    }
}

struct ShortcutRecorder: NSViewRepresentable {
    let label: String
    /// What the shortcut does, spoken by VoiceOver ("Capture Text"); the shortcut itself is the value.
    let name: String
    let onRecord: (_ keyCode: Int, _ modifiers: Int, _ label: String) -> Bool

    func makeNSView(context: Context) -> RecorderButton {
        let button = RecorderButton()
        button.bezelStyle = .rounded
        // A key cap: as wide as its glyphs, in a monospaced face so ⌥⇧⌘ line up between rows.
        button.font = .monospacedSystemFont(ofSize: 13, weight: .medium)
        button.onRecord = onRecord
        button.setAccessibilityLabel(name)
        button.setAccessibilityHelp(tr("Press to record a new shortcut, then type the combination. Esc cancels."))
        return button
    }

    func updateNSView(_ button: RecorderButton, context: Context) {
        button.onRecord = onRecord
        button.setIdleTitle(label)
    }
}
