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

    /// The four strips that make one edge of `width` points: top and bottom across the full length, left and right
    /// between them. They lie just inside `rect`, or just outside it, and never share area. Outside, the top and bottom
    /// strips also run `width` past each end, so the four strips close a ring that covers the corner squares.
    static func band(around rect: CGRect, width: CGFloat, outside: Bool) -> [CGRect] {
        if outside {
            return [
                CGRect(x: rect.minX - width, y: rect.maxY, width: rect.width + 2 * width, height: width),
                CGRect(x: rect.minX - width, y: rect.minY - width, width: rect.width + 2 * width, height: width),
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
}

/// The corner brackets: a round-capped white stroke that bends around each corner of the selection, just outside it,
/// with a black keyline on its outer side. SelectionDrawing strokes both, from the same path.
enum SelectionBracket {
    /// The white stroke's width.
    static let stroke: CGFloat = 2
    /// The distance from the selection's edge to the stroke's centre line: the dark band, a gap of one point, the stroke.
    static let offset: CGFloat = 3
    /// The radius of each bend, on the centre line. The bend is centred on the selection's corner.
    static let radius: CGFloat = 3
    /// How far each arm runs past its corner, along the edge, on a long side. A shorter side gives less.
    static let preferredReach: CGFloat = 8

    /// How far each arm runs past its corner, in points: `preferredReach`, or a third of the shorter side where that is
    /// less, rounded down to a whole device pixel. Nil below `radius + stroke / 2`, where the arm would have no straight
    /// part past its bend, so no bracket is drawn.
    static func reach(for rect: CGRect, scale: CGFloat) -> CGFloat? {
        let limited = min(preferredReach, min(rect.width, rect.height) / 3)
        let distance = scale > 0 ? floor(limited * scale) / scale : limited
        return distance >= radius + stroke / 2 ? distance : nil
    }

    /// The centre line of the four brackets around `rect`. Each arm ends `reach` past its corner, counting the round
    /// cap, and runs along a line `offset` outside the edge, with its bend `radius` on the centre line. The top left
    /// corner is built once and mirrored into the other three, so the four are identical.
    static func path(around rect: CGRect, reach: CGFloat, offset: CGFloat, radius: CGFloat) -> CGPath {
        // The arm's end, before its round cap, which adds half the stroke: the visible tip is `reach`.
        let end = reach - stroke / 2
        // One corner in its own space: the origin is the selection's corner, and +x and +y point into the selection.
        let oneCorner = CGMutablePath()
        oneCorner.move(to: CGPoint(x: -offset, y: end))
        oneCorner.addLine(to: CGPoint(x: -offset, y: -offset + radius))
        oneCorner.addArc(tangent1End: CGPoint(x: -offset, y: -offset),
                         tangent2End: CGPoint(x: -offset + radius, y: -offset), radius: radius)
        oneCorner.addLine(to: CGPoint(x: end, y: -offset))
        // Each corner's position, and its direction (+1 or -1) into the rectangle along x and along y.
        let corners: [(x: CGFloat, y: CGFloat, dx: CGFloat, dy: CGFloat)] = [
            (rect.minX, rect.minY, 1, 1), (rect.maxX, rect.minY, -1, 1),
            (rect.minX, rect.maxY, 1, -1), (rect.maxX, rect.maxY, -1, -1),
        ]
        let brackets = CGMutablePath()
        for corner in corners {
            brackets.addPath(oneCorner, transform: CGAffineTransform(a: corner.dx, b: 0, c: 0, d: corner.dy,
                                                                     tx: corner.x, ty: corner.y))
        }
        return brackets
    }
}

/// The selection's edge: a light band just inside it and a dark band just outside, so that it shows on dark content
/// and on white pages alike. Each band is one point wide, or two under Increase Contrast. The dark band closes into a
/// ring around the corners; the brackets (SelectionBracket) sit beyond it.
enum SelectionOutline {
    struct Style: Equatable {
        /// The light band just inside the edge: its width in points and its white alpha.
        let innerWidth: CGFloat
        let innerAlpha: CGFloat
        /// The dark band just outside the edge: its width in points and its black alpha.
        let outerWidth: CGFloat
        let outerAlpha: CGFloat
    }

    static func style(_ variant: ContrastVariant) -> Style {
        switch variant {
        case .standard:
            return Style(innerWidth: 1, innerAlpha: 0.9, outerWidth: 1, outerAlpha: 0.6)
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
