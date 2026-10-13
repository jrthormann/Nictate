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

    /// The length of a corner arm: `preferred` points, at most a third of the shorter side, rounded down to a whole
    /// device pixel so that the end of the arm lands on the pixel grid.
    static func cornerLength(for rect: CGRect, scale: CGFloat, preferred: CGFloat = 12) -> CGFloat {
        let limited = min(preferred, min(rect.width, rect.height) / 3)
        guard scale > 0 else { return limited }
        return floor(limited * scale) / scale
    }

    /// The four strips that make one edge of `width` points: top and bottom across the full length, left and right
    /// between them. They lie just inside `rect`, or just outside it, and never overlap.
    static func band(around rect: CGRect, width: CGFloat, outside: Bool) -> [CGRect] {
        if outside {
            return [
                CGRect(x: rect.minX, y: rect.maxY, width: rect.width, height: width),
                CGRect(x: rect.minX, y: rect.minY - width, width: rect.width, height: width),
                CGRect(x: rect.minX - width, y: rect.minY, width: width, height: rect.height),
                CGRect(x: rect.maxX, y: rect.minY, width: width, height: rect.height),
            ]
        }
        let between = max(0, rect.height - 2 * width)
        return [
            CGRect(x: rect.minX, y: rect.maxY - width, width: rect.width, height: width),
            CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: width),
            CGRect(x: rect.minX, y: rect.minY + width, width: width, height: between),
            CGRect(x: rect.maxX - width, y: rect.minY + width, width: width, height: between),
        ]
    }

    /// Two arms per corner, eight rectangles, each `length` long and `thickness` wide. Inside, the arms run from the
    /// corner along the edges. Outside, they start at the outer corner, so together they cover the corner square
    /// beyond the rectangle.
    static func cornerMarks(of rect: CGRect, length: CGFloat, thickness: CGFloat, outside: Bool) -> [CGRect] {
        // Each corner, with the direction (+1 or -1) that points into the rectangle along x and along y.
        let corners: [(x: CGFloat, y: CGFloat, dx: CGFloat, dy: CGFloat)] = [
            (rect.minX, rect.minY, 1, 1), (rect.maxX, rect.minY, -1, 1),
            (rect.minX, rect.maxY, 1, -1), (rect.maxX, rect.maxY, -1, -1),
        ]
        return corners.flatMap { corner -> [CGRect] in
            if outside {
                return [spanned(corner.x - corner.dx * thickness, corner.x + corner.dx * length,
                                corner.y, corner.y - corner.dy * thickness),
                        spanned(corner.x, corner.x - corner.dx * thickness,
                                corner.y - corner.dy * thickness, corner.y + corner.dy * length)]
            }
            return [spanned(corner.x, corner.x + corner.dx * length, corner.y, corner.y + corner.dy * thickness),
                    spanned(corner.x, corner.x + corner.dx * thickness, corner.y, corner.y + corner.dy * length)]
        }
    }

    /// The rectangle with opposite corners (x0, y0) and (x1, y1), in either order.
    private static func spanned(_ x0: CGFloat, _ x1: CGFloat, _ y0: CGFloat, _ y1: CGFloat) -> CGRect {
        CGRect(x: min(x0, x1), y: min(y0, y1), width: abs(x1 - x0), height: abs(y1 - y0))
    }
}

/// The selection's edge: a light band just inside it and a dark band just outside, so that it shows on dark content
/// and on white pages alike. Each band is one point wide, or two under Increase Contrast.
enum SelectionOutline {
    struct Style: Equatable {
        /// The light band just inside the edge: its width in points and its white alpha.
        let innerWidth: CGFloat
        let innerAlpha: CGFloat
        /// The dark band just outside the edge: its width in points and its black alpha.
        let outerWidth: CGFloat
        let outerAlpha: CGFloat
    }

    /// The corner marks are each band plus this many points, so they read as part of the outline.
    static let cornerExtra: CGFloat = 1

    static func style(_ variant: ContrastVariant) -> Style {
        switch variant {
        case .standard:
            return Style(innerWidth: 1, innerAlpha: 0.9, outerWidth: 1, outerAlpha: 0.35)
        case .increased:
            return Style(innerWidth: Design.Stroke.contrast, innerAlpha: 1, outerWidth: 1, outerAlpha: 0.8)
        }
    }

    /// The black dim over the still outside the selection: 28 % in Light, 45 % in Dark. The overlay draws it with this
    /// value, and the tests read it from here, so they follow any change.
    static func dim(dark: Bool) -> CGFloat {
        dark ? 0.45 : 0.28
    }
}
