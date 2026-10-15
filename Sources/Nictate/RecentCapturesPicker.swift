// Nictate: a macOS menu bar app that copies text from anywhere on your screen.
// Copyright (c) 2026 jrthormann. MIT License, see LICENSE.

import AppKit

/// The Recent Captures panel. It takes keyboard focus, so the arrow keys and Escape reach the list, and it closes when the
/// user clicks elsewhere, as the popover does. An alert of the app's own, such as Clear History, does not close it.
final class FloatingPanel: NSPanel, NSWindowDelegate {
    /// Called when the panel stops being key, after it has left the screen.
    var onResignKey: (() -> Void)?
    /// The visible part of the screen that holds the menu bar icon. The panel stays inside it, whatever size its list has.
    var visibleScreenFrame: NSRect?

    override var canBecomeKey: Bool { true }

    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
        delegate = self
    }

    override func resignKey() {
        super.resignKey()
        // Clear History and Discard Unreadable History ask in an alert that becomes key and gives key status back when answered.
        guard RecentCapturesPicker.closesOnResignKey(appModalShown: NSApp.modalWindow != nil) else { return }
        orderOut(nil)
        onResignKey?()
    }

    /// Follows the content: the panel is as tall as its list, and the saved captures can arrive after it has opened.
    func fit(to size: NSSize) {
        guard let frame = RecentCapturesPicker.resizedFrame(self.frame, to: size) else { return }
        setFrame(frame, display: true)
        invalidateShadow()
    }

    /// The panel hangs from the icon and grows downward, so a longer list can reach past the bottom of the screen, and a wider one
    /// past its side: whatever resizes the panel, it is moved back inside.
    func windowDidResize(_ notification: Notification) {
        guard let visible = visibleScreenFrame else { return }
        let inside = RecentCapturesPicker.clamped(frame, within: visible)
        if inside != frame { setFrame(inside, display: true) }
    }
}

/// What the Recent Captures picker does around the menu bar popover and the capture shortcuts, apart from AppKit so it can be tested.
enum RecentCapturesPicker {
    enum Opening: Equatable { case ignore, openNow, closePopoverFirst }

    /// What the Recent Captures shortcut does. With the popover open it closes it first and opens the picker once it is gone.
    /// While the picker is open, or the popover is already closing for another choice, there is nothing to do.
    static func opening(popoverShown: Bool, closePending: Bool, pickerShown: Bool) -> Opening {
        if pickerShown || closePending { return .ignore }
        return popoverShown ? .closePopoverFirst : .openNow
    }

    /// A capture's stills would include the picker, so while it is on screen the capture shortcuts do nothing.
    static func ignores(_ slot: ShortcutSlot, pickerShown: Bool) -> Bool {
        pickerShown && slot != .rotateHistory
    }

    /// Whether the icon's popover remembers the app to return to. Not when it replaces the picker: that already did.
    static func remembersOrigin(replacingPicker: Bool) -> Bool {
        !replacingPicker
    }

    /// The picker's frame once its content wants `size`: the left and top edges stay where they are, since the panel hangs below
    /// the icon. Nil when there is nothing to change.
    static func resizedFrame(_ frame: NSRect, to size: NSSize) -> NSRect? {
        guard size.width > 0, size.height > 0, size != frame.size else { return nil }
        return NSRect(x: frame.minX, y: frame.maxY - size.height, width: size.width, height: size.height)
    }

    /// Whether losing key status closes the picker. Not while the app's own alert is up, which takes key status and returns it.
    /// Any other loss, such as a click outside, closes it.
    static func closesOnResignKey(appModalShown: Bool) -> Bool {
        !appModalShown
    }

    /// Whether the picker counts as shown: its panel is on screen, or the popover is closing for it. The popover reports itself
    /// closed while its fade-out is still drawn, so a capture started in that interval would have it in its stills.
    static func isShown(panelVisible: Bool, opening: Bool) -> Bool {
        panelVisible || opening
    }

    /// `frame` moved the least that puts it inside `visible`, the screen without the menu bar and the Dock. A frame larger than
    /// `visible` keeps its left edge and its top. Nothing moves when it is inside already.
    static func clamped(_ frame: NSRect, within visible: NSRect) -> NSRect {
        let x = max(min(frame.minX, visible.maxX - frame.width), visible.minX)
        let top = min(max(frame.maxY, visible.minY + frame.height), visible.maxY)
        guard x != frame.minX || top != frame.maxY else { return frame }
        return NSRect(x: x, y: top - frame.height, width: frame.width, height: frame.height)
    }

    /// The top left corner of a panel of `size` hanging below `icon`, centred on it, or at the top middle of `visible` when the
    /// icon cannot be seen. Either way the whole panel is inside `visible`.
    static func topLeft(for size: NSSize, below icon: NSRect?, within visible: NSRect) -> NSPoint {
        let anchor = icon ?? NSRect(x: visible.midX, y: visible.maxY, width: 0, height: 0)
        let hanging = NSRect(x: anchor.midX - size.width / 2, y: anchor.minY - size.height, width: size.width, height: size.height)
        let placed = clamped(hanging, within: visible)
        return NSPoint(x: placed.minX, y: placed.maxY)
    }

    /// Where the picker goes for the menu bar icon `button`, and the visible part of the screen that holds the icon, which the panel
    /// stays inside. Without an icon on screen, the main screen's.
    @MainActor
    static func placement(for size: NSSize, below button: NSView) -> (topLeft: NSPoint, visible: NSRect?) {
        var icon: NSRect?
        var screen = NSScreen.main ?? NSScreen.screens.first
        if let window = button.window, window.isVisible {
            icon = window.convertToScreen(button.convert(button.bounds, to: nil))
            screen = window.screen ?? screen
        }
        guard let visible = screen?.visibleFrame else { return (.zero, nil) }
        return (topLeft(for: size, below: icon, within: visible), visible)
    }
}
