// Nictate: a macOS menu bar app that copies text from anywhere on your screen.
// Copyright (c) 2026 jrthormann. MIT License, see LICENSE.

import CoreGraphics

/// The arithmetic of a region selection, kept free of AppKit so that every rule is unit tested.
/// Points use the overlay's own coordinates (origin at the bottom left, as NSView has them). Pixels
/// use the still image's (origin at the top left, as CGImage has them).
enum SelectionGeometry {
    /// A drag shorter than this in either direction is a click, not a region.
    static let minimumSide: CGFloat = 4
    /// An arrow key moves the pointer this many pixels; Shift with an arrow moves it `coarseStep` pixels, as the
    /// system screenshot tool does.
    static let fineStep: CGFloat = 1
    static let coarseStep: CGFloat = 10

    /// The point nearest to `point` on the pixel grid of a display with `scale` pixels per point. Selections
    /// snap to it, so every edge lands on a whole pixel.
    static func snapped(_ point: CGPoint, scale: CGFloat) -> CGPoint {
        guard scale > 0 else { return point }
        return CGPoint(x: (point.x * scale).rounded() / scale, y: (point.y * scale).rounded() / scale)
    }
    /// The rectangle spanned by two points, kept inside `bounds`. Empty when the points lie outside it.
    static func rect(from start: CGPoint, to end: CGPoint, within bounds: CGRect) -> CGRect {
        let spanned = CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
                             width: abs(end.x - start.x), height: abs(end.y - start.y))
        let inside = spanned.intersection(bounds)
        return inside.isNull ? .zero : inside
    }

    /// `point` moved by a key step, kept inside `bounds`.
    static func moved(_ point: CGPoint, dx: CGFloat, dy: CGFloat, within bounds: CGRect) -> CGPoint {
        CGPoint(x: min(max(point.x + dx, bounds.minX), bounds.maxX),
                y: min(max(point.y + dy, bounds.minY), bounds.maxY))
    }

    static func isRegion(_ rect: CGRect) -> Bool {
        rect.width >= minimumSide && rect.height >= minimumSide
    }

    /// The pixels of `rect` (points) in a still that covers `bounds` at `scale` pixels per point.
    static func pixelRect(for rect: CGRect, within bounds: CGRect, scale: CGFloat) -> CGRect {
        CGRect(x: (rect.minX - bounds.minX) * scale,
               y: (bounds.maxY - rect.maxY) * scale,
               width: rect.width * scale,
               height: rect.height * scale).integral
    }

    /// Where a size pill of `size` sits: below `rect`, or above it when there is no room below. Centred on
    /// the selection and kept `inset` points from the edges of `bounds`.
    static func pillOrigin(size: CGSize, below rect: CGRect, within bounds: CGRect,
                           gap: CGFloat = 8, inset: CGFloat = 8) -> CGPoint {
        var y = rect.minY - gap - size.height
        if y < bounds.minY + inset { y = rect.maxY + gap }
        let x = min(max(rect.midX - size.width / 2, bounds.minX + inset), bounds.maxX - size.width - inset)
        return CGPoint(x: x, y: min(max(y, bounds.minY + inset), bounds.maxY - size.height - inset))
    }
}
