// Nictate: a macOS menu bar app that copies text from anywhere on your screen.
// Copyright (c) 2026 jrthormann. MIT License, see LICENSE.

import AppKit

/// The line beside a selection that says what the capture did: "Copied · 11 words", "No text found · try a
/// larger area", or "Reading…" while a large selection is recognized. It fades after 1.5 s, stays while the
/// pointer rests on it, and a click dismisses it.
@MainActor
final class ResultPill {
    enum Style: Equatable {
        case reading
        case success(String)
        case miss(String)
    }

    static let shared = ResultPill()
    private static let lingerSeconds: Double = 1.5
    private static let fadeSeconds: Double = 0.2

    private var panel: NSPanel?
    private var fadeTask: Task<Void, Never>?

    /// Shows the pill beside `rect` (global points) on `screen`, replacing any pill already up.
    func show(_ style: Style, near rect: CGRect, screen: CGRect) {
        cancelFade()
        let content = PillContent(style: style)
        content.onHover = { [weak self] hovering in
            if hovering { self?.cancelFade() } else { self?.scheduleFade() }
        }
        content.onClick = { [weak self] in self?.hide() }
        let panel = panel ?? makePanel()
        self.panel = panel
        panel.contentView = content
        content.layoutSubtreeIfNeeded()
        let size = content.fittingSize
        panel.setFrame(CGRect(origin: SelectionGeometry.pillOrigin(size: size, below: rect, within: screen), size: size),
                       display: false)
        panel.animator().alphaValue = 1
        panel.orderFrontRegardless()
        if style != .reading { scheduleFade() }
    }

    /// Fades the pill out, or removes it at once when `animated` is false or Reduce Motion is on.
    func hide(animated: Bool = true) {
        cancelFade()
        guard let panel, panel.isVisible else { return }
        let fade = animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        guard fade else {
            panel.orderOut(nil)
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = ResultPill.fadeSeconds
            panel.animator().alphaValue = 0
        }
        fadeTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(Int(ResultPill.fadeSeconds * 1000) + 20))
            guard !Task.isCancelled else { return }
            panel.orderOut(nil)
        }
    }

    private func scheduleFade() {
        cancelFade()
        fadeTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(ResultPill.lingerSeconds))
            guard !Task.isCancelled else { return }
            self.hide()
        }
    }

    private func cancelFade() {
        fadeTask?.cancel()
        fadeTask = nil
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        return panel
    }
}

/// The pill's content: a material background, a symbol or spinner, and the line of text.
@MainActor
private final class PillContent: NSVisualEffectView {
    var onHover: ((Bool) -> Void)?
    var onClick: (() -> Void)?

    init(style: ResultPill.Style) {
        super.init(frame: .zero)
        material = .hudWindow
        blendingMode = .behindWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 14

        let label = NSTextField(labelWithString: Self.text(for: style))
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .labelColor
        let mark = Self.mark(for: style)
        let stack = NSStackView(views: [mark, label])
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 14)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
        setAccessibilityLabel(Self.text(for: style))
    }

    required init?(coder: NSCoder) { nil }

    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }
    override func mouseDown(with event: NSEvent) { onClick?() }

    private static func text(for style: ResultPill.Style) -> String {
        switch style {
        case .reading: tr("Reading…")
        case .success(let text), .miss(let text): text
        }
    }

    private static func mark(for style: ResultPill.Style) -> NSView {
        let symbol: String
        let tint: NSColor
        switch style {
        case .reading:
            // A single dot that breathes while recognition runs; it stays still under Reduce Motion.
            let dot = NSView()
            dot.wantsLayer = true
            dot.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
            dot.layer?.cornerRadius = 4
            dot.translatesAutoresizingMaskIntoConstraints = false
            dot.widthAnchor.constraint(equalToConstant: 8).isActive = true
            dot.heightAnchor.constraint(equalToConstant: 8).isActive = true
            if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                let breathe = CABasicAnimation(keyPath: "opacity")
                breathe.fromValue = 1.0
                breathe.toValue = 0.25
                breathe.duration = 0.6
                breathe.autoreverses = true
                breathe.repeatCount = .infinity
                dot.layer?.add(breathe, forKey: "breathe")
            }
            return dot
        case .success:
            symbol = "checkmark.circle.fill"
            tint = .systemGreen
        case .miss:
            symbol = "questionmark.circle.fill"
            tint = .systemOrange
        }
        let view = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil) ?? NSImage())
        view.contentTintColor = tint
        view.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        return view
    }
}
