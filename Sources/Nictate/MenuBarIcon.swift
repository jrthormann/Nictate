// Nictate: a macOS menu bar app that copies text from anywhere on your screen.
// Copyright (c) 2026 jrthormann. MIT License, see LICENSE.

import AppKit

enum MenuBarIcon {
    private static let size = NSSize(width: 18, height: 18)
    /// Stroke centerlines sit on a 0.25 pt grid so they fall on whole pixels at 2x.
    private static let inset: CGFloat = 2.75
    private static let stroke: CGFloat = 1.5

    /// The menu bar glyph: four corner brackets around a selection, the shape of the app icon.
    /// It is a template image drawn as paths, so it stays sharp at any scale and macOS tints it for
    /// light and dark menu bars. With `appending` a "+" sits at the center of the frame.
    static func image(appending: Bool) -> NSImage {
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.black.setStroke()
            aperture(in: rect).stroke()
            if appending { plus(at: NSPoint(x: rect.midX, y: rect.midY)).stroke() }
            return true
        }
        image.isTemplate = true
        return image
    }

    /// One frame of the blink, in `color`: the aperture squeezed toward its middle by `openness`
    /// (1 at rest, 0 closed into a line) with the beam across the middle at `beam` opacity.
    static func blinkFrame(openness: CGFloat, beam: CGFloat, color: NSColor, appending: Bool) -> NSImage {
        let image = NSImage(size: size, flipped: false) { rect in
            color.setStroke()
            aperture(in: rect, openness: openness).stroke()
            if beam > 0 {
                let frame = rect.insetBy(dx: inset, dy: inset)
                let line = NSBezierPath()
                line.move(to: NSPoint(x: frame.minX, y: frame.midY))
                line.line(to: NSPoint(x: frame.maxX, y: frame.midY))
                line.lineWidth = stroke
                line.lineCapStyle = .round
                // Cubed, so the line shows only around the closed moment instead of as a dim bar.
                color.withAlphaComponent(color.alphaComponent * beam * beam * beam).setStroke()
                line.stroke()
            }
            if appending, openness > 0.5 {
                color.setStroke()
                plus(at: NSPoint(x: rect.midX, y: rect.midY)).stroke()
            }
            return true
        }
        image.isTemplate = false
        return image
    }

    private static func aperture(in rect: NSRect, openness: CGFloat = 1) -> NSBezierPath {
        let frame = rect.insetBy(dx: inset, dy: inset)
        let arm: CGFloat = 4.5
        // Closing moves the top and bottom brackets toward the middle and flattens them: their vertical
        // arms shrink faster than the gap, so they never touch, and at 0 they meet as one line.
        let open = max(0, min(1, openness))
        let half = frame.height / 2 * open
        let armY = arm * open * open
        let radius = min(2, armY)
        let path = NSBezierPath()
        for (sx, sy) in [(-1, 1), (1, 1), (1, -1), (-1, -1)] as [(CGFloat, CGFloat)] {
            let corner = NSPoint(x: sx < 0 ? frame.minX : frame.maxX, y: frame.midY + sy * half)
            let alongY = NSPoint(x: corner.x, y: corner.y - sy * armY)
            let alongX = NSPoint(x: corner.x - sx * arm, y: corner.y)
            path.move(to: alongY)
            if radius > 0.01 { path.appendArc(from: corner, to: alongX, radius: radius) } else { path.line(to: corner) }
            path.line(to: alongX)
        }
        path.lineWidth = stroke
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        return path
    }

    private static func plus(at center: NSPoint) -> NSBezierPath {
        let arm: CGFloat = 2.25
        let path = NSBezierPath()
        path.move(to: NSPoint(x: center.x - arm, y: center.y))
        path.line(to: NSPoint(x: center.x + arm, y: center.y))
        path.move(to: NSPoint(x: center.x, y: center.y - arm))
        path.line(to: NSPoint(x: center.x, y: center.y + arm))
        path.lineWidth = stroke
        path.lineCapStyle = .round
        return path
    }
}
