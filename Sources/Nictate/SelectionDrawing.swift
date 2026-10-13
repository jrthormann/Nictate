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

    /// The edge, in four steps: the dark ring just outside the selection; each bracket's black keyline; the light band
    /// just inside the selection; each bracket's white stroke. Each band is one fill, so an overlap never doubles its
    /// alpha. The keyline runs on the white stroke's path, a point wider and farther out, so it shows only outside it.
    private static func drawOutline(_ rect: CGRect, style: SelectionOutline.Style, scale: CGFloat, in context: CGContext) {
        let reach = SelectionBracket.reach(for: rect, scale: scale)
        context.setFillColor(NSColor.black.withAlphaComponent(style.outerAlpha).cgColor)
        context.addRects(SelectionGeometry.band(around: rect, width: style.outerWidth, outside: true))
        context.fillPath()
        if let reach {
            let keyline = style.outerWidth
            stroke(SelectionBracket.path(around: rect, reach: reach, offset: SelectionBracket.offset + keyline / 2,
                                         radius: SelectionBracket.radius + keyline / 2),
                   width: SelectionBracket.stroke + keyline, color: NSColor.black.withAlphaComponent(style.outerAlpha).cgColor,
                   in: context)
        }
        context.setFillColor(NSColor.white.withAlphaComponent(style.innerAlpha).cgColor)
        context.addRects(SelectionGeometry.band(around: rect, width: style.innerWidth, outside: false))
        context.fillPath()
        if let reach {
            stroke(SelectionBracket.path(around: rect, reach: reach, offset: SelectionBracket.offset,
                                         radius: SelectionBracket.radius),
                   width: SelectionBracket.stroke, color: NSColor.white.withAlphaComponent(style.innerAlpha).cgColor,
                   in: context)
        }
    }

    /// Strokes a bracket path with round caps. Its colour and width are set inside a saved graphics state.
    private static func stroke(_ path: CGPath, width: CGFloat, color: CGColor, in context: CGContext) {
        context.saveGState()
        context.setStrokeColor(color)
        context.setLineWidth(width)
        context.setLineCap(.round)
        context.addPath(path)
        context.strokePath()
        context.restoreGState()
    }
}
