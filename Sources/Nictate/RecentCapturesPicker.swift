// Nictate: a macOS menu bar app that copies text from anywhere on your screen.
// Copyright (c) 2026 jrthormann. MIT License, see LICENSE.

import AppKit

/// The Recent Captures panel. It takes keyboard focus, so the arrow keys and Escape reach the list, and it closes when the
/// user clicks elsewhere, as the popover does.
final class FloatingPanel: NSPanel {
    /// Called when the panel stops being key, after it has left the screen.
    var onResignKey: (() -> Void)?

    override var canBecomeKey: Bool { true }

    override func resignKey() {
        super.resignKey()
        orderOut(nil)
        onResignKey?()
    }

    /// Follows the content: the panel is as tall as its list, and the saved captures can arrive after it has opened.
    func fit(to size: NSSize) {
        guard let frame = RecentCapturesPicker.resizedFrame(self.frame, to: size) else { return }
        setFrame(frame, display: true)
        invalidateShadow()
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
}
