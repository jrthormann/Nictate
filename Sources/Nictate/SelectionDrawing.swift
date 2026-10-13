// Nictate: a macOS menu bar app that copies text from anywhere on your screen.
// Copyright (c) 2026 jrthormann. MIT License, see LICENSE.

import AppKit

/// What the selection overlay paints over its still: the still, the dim, and the selection undimmed with its edge.
/// It works on a CGContext alone, so the offscreen render (Tests/render_capture.swift) draws exactly what the overlay draws.
enum SelectionDrawing {
    /// Draws `still` across `bounds`, dims it, and, when there is a `selection`, shows that area undimmed with its
    /// edge. `scale` is the still's pixels per point.
    static func draw(still: CGImage, in bounds: CGRect, selection: CGRect?, dark: Bool, style: SelectionOutline.Style,
                     scale: CGFloat, context: CGContext) {
        context.draw(still, in: bounds)
        // The dim is 28 % in Light and 45 % in Dark (SelectionOutline.dim).
        context.setFillColor(NSColor.black.withAlphaComponent(SelectionOutline.dim(dark: dark)).cgColor)
        context.fill(bounds)
        if let rect = selection {
            context.saveGState()
            context.clip(to: rect)
            context.draw(still, in: bounds)
            context.restoreGState()
            drawOutline(rect, style: style, scale: scale, in: context)
        }
    }

    /// The edge: a dark band just outside the selection, then a light band just inside it, each with four corner
    /// marks that thicken it by one point. Each set is one fill, so an overlap never doubles its alpha. The two sets
    /// do not touch, so their order does not change what shows.
    private static func drawOutline(_ rect: CGRect, style: SelectionOutline.Style, scale: CGFloat, in context: CGContext) {
        let length = SelectionGeometry.cornerLength(for: rect, scale: scale)
        context.setFillColor(NSColor.black.withAlphaComponent(style.outerAlpha).cgColor)
        context.addRects(SelectionGeometry.band(around: rect, width: style.outerWidth, outside: true)
            + SelectionGeometry.cornerMarks(of: rect, length: length,
                                            thickness: style.outerWidth + SelectionOutline.cornerExtra, outside: true))
        context.fillPath()
        context.setFillColor(NSColor.white.withAlphaComponent(style.innerAlpha).cgColor)
        context.addRects(SelectionGeometry.band(around: rect, width: style.innerWidth, outside: false)
            + SelectionGeometry.cornerMarks(of: rect, length: length,
                                            thickness: style.innerWidth + SelectionOutline.cornerExtra, outside: false))
        context.fillPath()
    }
}
