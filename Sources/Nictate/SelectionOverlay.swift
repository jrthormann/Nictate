// Nictate: a macOS menu bar app that copies text from anywhere on your screen.
// Copyright (c) 2026 jrthormann. MIT License, see LICENSE.

import AppKit

/// The area the user chose: its pixels, and where it sits on the screen in global points.
struct SelectedRegion: Sendable {
    let image: CGImage
    /// The selection in global screen points.
    let rect: CGRect
    /// The whole display it was drawn on, in global screen points.
    let screen: CGRect
}

/// The region selection on frozen stills: one borderless window per display, above full-screen apps and on
/// every Space. Drag to select (release to copy), or use the keyboard: Return starts a corner, arrows move the
/// other one (Shift for 10 points), Return copies. Esc cancels.
@MainActor
final class SelectionOverlay {
    /// Keeps the session alive while its windows are on screen.
    private static var active: SelectionOverlay?

    private var windows: [NSWindow] = []
    private var continuation: CheckedContinuation<SelectedRegion?, Never>?

    /// Shows the overlay on the stills and waits. Returns the chosen region, or nil when cancelled.
    static func select(_ stills: [DisplayStill]) async -> SelectedRegion? {
        let session = SelectionOverlay()
        active = session
        defer { active = nil }
        return await session.run(stills)
    }

    private func run(_ stills: [DisplayStill]) async -> SelectedRegion? {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            NSApp.activate(ignoringOtherApps: true)
            let mouse = NSEvent.mouseLocation
            for still in stills {
                let window = SelectionWindow(still: still, session: self)
                windows.append(window)
                window.orderFrontRegardless()
                if still.frame.contains(mouse) { window.makeKeyAndOrderFront(nil) }
            }
        }
    }

    /// Called once by a view: closes every window and hands the crop (or nil) back to the caller.
    fileprivate func finish(_ region: SelectedRegion?) {
        guard let continuation else { return }
        self.continuation = nil
        for window in windows { window.close() }
        windows.removeAll()
        continuation.resume(returning: region)
    }
}

/// A window that can become key, so that it receives the keyboard; the overlay windows are borderless.
private final class SelectionWindow: NSWindow {
    init(still: DisplayStill, session: SelectionOverlay) {
        super.init(contentRect: still.frame, styleMask: .borderless, backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = true
        hasShadow = false
        backgroundColor = .black
        acceptsMouseMovedEvents = true
        contentView = SelectionView(still: still, session: session)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Draws the still, the dimming, the selection with its edge and corner marks, and turns mouse and key input into a selection.
@MainActor
private final class SelectionView: NSView {
    private let still: DisplayStill
    private unowned let session: SelectionOverlay
    /// The edge's bands and thickness for this appearance. Read once: the overlay lives for one selection.
    private let outline: SelectionOutline.Style
    /// Where the selection started: the mouse-down point, or the corner Return set.
    private var anchor: CGPoint?
    /// The moving corner: the pointer, or the keyboard position.
    private var pointer: CGPoint = .zero

    private static let keyEscape: UInt16 = 53
    private static let keyReturn: [UInt16] = [36, 76]
    private static let keyLeft: UInt16 = 123, keyRight: UInt16 = 124, keyDown: UInt16 = 125, keyUp: UInt16 = 126

    init(still: DisplayStill, session: SelectionOverlay) {
        self.still = still
        self.session = session
        outline = SelectionOutline.style(NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast ? .increased : .standard)
        super.init(frame: CGRect(origin: .zero, size: still.frame.size))
        setAccessibilityElement(true)
        setAccessibilityLabel(tr("Select the text to copy"))
    }

    required init?(coder: NSCoder) { nil }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        window.makeFirstResponder(self)
        pointer = pixelPoint(window.mouseLocationOutsideOfEventStream)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
        needsDisplay = true
    }

    /// A point in view coordinates, snapped to this display's pixel grid.
    private func pixelPoint(_ windowPoint: NSPoint) -> CGPoint {
        SelectionGeometry.snapped(convert(windowPoint, from: nil), scale: still.scale)
    }

    /// The keyboard follows the pointer from display to display: the window it enters takes the keys.
    override func mouseEntered(with event: NSEvent) {
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(self)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    private var selection: CGRect {
        guard let anchor else { return .zero }
        return SelectionGeometry.rect(from: anchor, to: pointer, within: bounds)
    }

    // MARK: Input

    override func mouseMoved(with event: NSEvent) {
        // While the keyboard holds a corner, the mouse does not move the selection under it.
        guard anchor == nil else { return }
        pointer = pixelPoint(event.locationInWindow)
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        anchor = pixelPoint(event.locationInWindow)
        pointer = anchor ?? pointer
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        pointer = pixelPoint(event.locationInWindow)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        pointer = pixelPoint(event.locationInWindow)
        // A click without a real drag starts over instead of copying a speck.
        guard SelectionGeometry.isRegion(selection) else {
            anchor = nil
            needsDisplay = true
            return
        }
        confirm()
    }

    override func keyDown(with event: NSEvent) {
        // Steps are pixels, so one press moves the corner by exactly one screen pixel.
        let pixels = event.modifierFlags.contains(.shift) ? SelectionGeometry.coarseStep : SelectionGeometry.fineStep
        let step = pixels / still.scale
        switch event.keyCode {
        case Self.keyEscape:
            session.finish(nil)
        case _ where Self.keyReturn.contains(event.keyCode):
            if anchor == nil {
                anchor = pointer
                needsDisplay = true
            } else if SelectionGeometry.isRegion(selection) {
                confirm()
            }
        case Self.keyLeft: nudge(dx: -step, dy: 0)
        case Self.keyRight: nudge(dx: step, dy: 0)
        case Self.keyDown: nudge(dx: 0, dy: -step)
        case Self.keyUp: nudge(dx: 0, dy: step)
        default: super.keyDown(with: event)
        }
    }

    private func nudge(dx: CGFloat, dy: CGFloat) {
        pointer = SelectionGeometry.moved(pointer, dx: dx, dy: dy, within: bounds)
        needsDisplay = true
    }

    private func confirm() {
        let crop = SelectionGeometry.pixelRect(for: selection, within: bounds, scale: still.scale)
        let rect = selection.offsetBy(dx: still.frame.minX, dy: still.frame.minY)
        guard let image = still.image.cropping(to: crop) else { return session.finish(nil) }
        session.finish(SelectedRegion(image: image, rect: rect, screen: still.frame))
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let rect = selection
        let selected = anchor != nil && SelectionGeometry.isRegion(rect)

        context.draw(still.image, in: bounds)
        // The dim is 28 % in Light and 45 % in Dark (SelectionOutline.dim).
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        context.setFillColor(NSColor.black.withAlphaComponent(SelectionOutline.dim(dark: dark)).cgColor)
        context.fill(bounds)
        if selected {
            context.saveGState()
            context.clip(to: rect)
            context.draw(still.image, in: bounds)
            context.restoreGState()
            drawOutline(rect, in: context)
        }
    }

    /// The edge: a dark band just outside the selection, then a light band just inside it, each with four corner
    /// marks that thicken it by one point. Each set is one fill, so an overlap never doubles its alpha. The two sets
    /// do not touch, so their order does not change what shows.
    private func drawOutline(_ rect: CGRect, in context: CGContext) {
        let length = SelectionGeometry.cornerLength(for: rect, scale: still.scale)
        context.setFillColor(NSColor.black.withAlphaComponent(outline.outerAlpha).cgColor)
        context.addRects(SelectionGeometry.band(around: rect, width: outline.outerWidth, outside: true)
            + SelectionGeometry.cornerMarks(of: rect, length: length,
                                            thickness: outline.outerWidth + SelectionOutline.cornerExtra, outside: true))
        context.fillPath()
        context.setFillColor(NSColor.white.withAlphaComponent(outline.innerAlpha).cgColor)
        context.addRects(SelectionGeometry.band(around: rect, width: outline.innerWidth, outside: false)
            + SelectionGeometry.cornerMarks(of: rect, length: length,
                                            thickness: outline.innerWidth + SelectionOutline.cornerExtra, outside: false))
        context.fillPath()
    }
}
