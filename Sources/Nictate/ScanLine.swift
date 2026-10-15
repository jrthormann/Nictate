// Nictate: a macOS menu bar app that copies text from anywhere on your screen.
// Copyright (c) 2026 jrthormann. MIT License, see LICENSE.

import AppKit
import QuartzCore

/// The line that sweeps over the selected area while its text is read. It lives in its own window, because the
/// selection overlay has closed by then, and it holds no image: the text is read from the still captured before it
/// existed. The window is borderless, never key and mouse-transparent. `close` is idempotent, and it blocks a `show`
/// that is still on its way.
@MainActor
final class ScanLine {
    static let minimumHeight: CGFloat = 16
    static let lineHeight: CGFloat = 2
    static let sweepSeconds: CFTimeInterval = 1.2
    /// The share of each sweep spent fading in at the top and out at the bottom.
    static let rampShare: Double = 0.15

    /// Whether a selection of `height` points gets a line: never under Reduce Motion, and never under one line of text.
    static func isShown(height: CGFloat, reduceMotion: Bool) -> Bool {
        !reduceMotion && height >= minimumHeight
    }

    /// Whether the threshold timer may reveal the line and the Reading pill. Only a read still running at the threshold
    /// does: the end of a read cancels the timer and closes the line, so a late firing finds neither. A capture starts
    /// its timer only after its selection is chosen, so a drag never reaches it. A pure rule, so the tests cover it.
    static func mayReveal(readRunning: Bool, lineClosed: Bool) -> Bool {
        readRunning && !lineClosed
    }

    private let rect: CGRect   // Global points. No image, no still.
    private var panel: NSPanel?
    /// Set by `close`. A closed line is never shown again.
    private(set) var isClosed = false

    init(rect: CGRect) { self.rect = rect }

    /// Whether a window is on screen for the line. Tests read it; the coordinator does not.
    var isShowing: Bool { panel != nil }

    func show() {
        guard !isClosed, panel == nil, Self.isShown(height: rect.height,
              reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion) else { return }
        let panel = NSPanel(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.level = .statusBar                      // Same level and behaviour as the result pill.
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true               // Clicks and scrolls reach the app underneath.
        // Set, but a probe did not see AppKit hide such a panel when its app deactivated, so that effect is unverified.
        // The line is closed explicitly when the read ends, whichever way it ends.
        panel.hidesOnDeactivate = true
        panel.animationBehavior = .none
        let contrast: ContrastVariant = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast ? .increased : .standard
        panel.contentView = ScanLineView(size: rect.size, contrast: contrast)
        panel.orderFrontRegardless()                  // Never made key, and never activates Nictate.
        self.panel = panel
        Log.capture.debug("Scan line shown")
    }

    /// Removes the line at once, without a fade, so the result pill appears in the same frame as its removal.
    func close() {
        isClosed = true
        guard let panel else { return }
        self.panel = nil
        panel.contentView?.layer?.sublayers?.forEach { $0.removeAllAnimations() }
        panel.orderOut(nil)
        panel.close()
        Log.capture.debug("Scan line closed")
    }
}

/// A layer-hosting view with no `draw(_:)`: the line is two solid layers that Core Animation moves and fades, so the
/// window never holds a bitmap the size of the selection and no per-frame work runs on the main thread.
@MainActor
private final class ScanLineView: NSView {
    init(size: CGSize, contrast: ContrastVariant) {
        super.init(frame: CGRect(origin: .zero, size: size))
        // A layer assigned before wantsLayer makes a layer-hosting view, so AppKit never redraws or replaces this tree.
        let root = CALayer()
        root.frame = CGRect(origin: .zero, size: size)
        layer = root
        wantsLayer = true
        setAccessibilityElement(false)

        let height = ScanLine.lineHeight, half = ScanLine.lineHeight / 2
        let peak: Float = contrast == .increased ? 0.9 : 0.6
        // The container starts invisible: the animation supplies its opacity, so removing the animation hides the line.
        let container = CALayer()
        container.frame = CGRect(x: 0, y: size.height - height, width: size.width, height: height)
        container.opacity = 0
        let white = CALayer()
        white.frame = CGRect(x: 0, y: half, width: size.width, height: half)
        white.backgroundColor = NSColor.white.cgColor
        let black = CALayer()
        black.frame = CGRect(x: 0, y: 0, width: size.width, height: half)
        black.backgroundColor = NSColor.black.withAlphaComponent(SelectionOutline.style(contrast).outerAlpha).cgColor
        container.addSublayer(white)
        container.addSublayer(black)
        root.addSublayer(container)

        let travel = Double(size.height - height)
        let sweep = CABasicAnimation(keyPath: "transform.translation.y")
        sweep.fromValue = 0.0
        sweep.toValue = -travel
        sweep.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        sweep.duration = ScanLine.sweepSeconds
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [0, peak, peak, 0].map { NSNumber(value: $0) }
        let ramp = ScanLine.rampShare
        fade.keyTimes = [0, ramp, 1 - ramp, 1].map { NSNumber(value: $0) }
        fade.duration = ScanLine.sweepSeconds
        let group = CAAnimationGroup()
        group.animations = [sweep, fade]
        group.duration = ScanLine.sweepSeconds
        group.repeatCount = .infinity
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        container.add(group, forKey: "sweep")
        CATransaction.commit()
    }

    required init?(coder: NSCoder) { nil }
}
