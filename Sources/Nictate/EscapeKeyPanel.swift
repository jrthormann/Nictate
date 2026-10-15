// Nictate: a macOS menu bar app that copies text from anywhere on your screen.
// Copyright (c) 2026 jrthormann. MIT License, see LICENSE.

import AppKit

/// A hidden panel that holds the keyboard while a capture takes its stills. From the shortcut until the selection opens, the
/// keys go to the app the user is in, so an Esc pressed in that gap would reach that app and the capture would go on. This
/// panel is key for the gap without making Nictate the active app, and an Esc in it cancels the capture.
///
/// Made once at launch and reused, because a panel made on the shortcut is key later (about 11 ms after the shortcut against
/// about 5 ms in a probe). Between captures it is not on screen. An Esc that reaches the window server before this panel is
/// key still goes to the app the user is in; that takes a few milliseconds from the shortcut (docs/ARCHITECTURE.md).
final class EscapeKeyPanel: NSPanel {
    private static let side: CGFloat = 40
    private static let keyEscape: UInt16 = 53

    /// Called for an Esc, with whatever modifiers are held: the shortcut's own can still be down.
    var onEscape: (@MainActor () -> Void)?

    init() {
        super.init(contentRect: CGRect(x: 0, y: 0, width: Self.side, height: Self.side),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        becomesKeyOnlyIfNeeded = false
        hidesOnDeactivate = false
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        // Clicks go to the window below, as if the panel were not there.
        ignoresMouseEvents = true
        hasShadow = false
        // One percent, so that it is a visible window to the window server while nothing can be seen.
        alphaValue = 0.01
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Puts the panel under `point` (global screen points) and makes it key. Nictate does not become the active app.
    func present(near point: CGPoint) {
        setFrame(CGRect(x: point.x - Self.side / 2, y: point.y - Self.side / 2, width: Self.side, height: Self.side), display: false)
        orderFrontRegardless()
        makeKey()
    }

    /// Takes the panel down, which ends its key status. True when it was up; a second call does nothing.
    @discardableResult
    func dismiss() -> Bool {
        guard isVisible else { return false }
        orderOut(nil)
        return true
    }

    // Every key is swallowed (no `super`, which would beep), and only Esc does anything.
    override func keyDown(with event: NSEvent) {
        _ = takeEscape(event)
    }

    /// AppKit offers a key to `performKeyEquivalent` first. An Esc with the shortcut's Command still held is a key equivalent
    /// and must still cancel. Any other Command key is consumed: the main menu would otherwise quit Nictate, hide it or open
    /// Settings from an invisible window.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        takeEscape(event) || event.modifierFlags.contains(.command)
    }

    private func takeEscape(_ event: NSEvent) -> Bool {
        guard event.keyCode == Self.keyEscape else { return false }
        onEscape?()
        return true
    }
}
