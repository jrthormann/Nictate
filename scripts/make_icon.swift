// Nictate: a macOS menu bar app that copies text from anywhere on your screen.
// Copyright (c) 2026 jrthormann. MIT License, see LICENSE.

import AppKit

// Draws the Nictate app icon. Usage: make_icon <outDir>
// An indigo-to-azure squircle with a soft top light, three lines of text, the white aperture
// (four rounded corner brackets) and a bright scan beam across the middle line: the blink.
// The menu bar glyph shares the aperture's proportions and is drawn in code by Sources/Nictate/MenuBarIcon.swift.
// The art is authored in a 1024x1024 y-up canvas.

func render(pixels: Int, canvas: CGFloat, _ draw: () -> Void) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    let t = NSAffineTransform(); t.scale(by: CGFloat(pixels) / canvas); t.concat()
    draw()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
}

let top = rgb(124, 92, 255)       // violet
let middle = rgb(72, 86, 246)     // indigo
let bottom = rgb(20, 150, 255)    // azure
let beam = rgb(120, 245, 255)     // cyan light

/// Four corner brackets of a square of half-width `half` around `center`.
func aperture(center: CGPoint, half: CGFloat, arm: CGFloat, radius: CGFloat, width: CGFloat = 56) -> NSBezierPath {
    let path = NSBezierPath()
    // Each corner, with the unit steps along its two edges.
    for (sx, sy) in [(-1, 1), (1, 1), (1, -1), (-1, -1)] as [(CGFloat, CGFloat)] {
        let corner = CGPoint(x: center.x + sx * half, y: center.y + sy * half)
        let alongY = CGPoint(x: corner.x, y: corner.y - sy * arm)
        let alongX = CGPoint(x: corner.x - sx * arm, y: corner.y)
        path.move(to: alongY)
        path.appendArc(from: corner, to: alongX, radius: radius)
        path.line(to: alongX)
    }
    path.lineWidth = width
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    return path
}

func bar(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: NSRect(x: x, y: y - height / 2, width: width, height: height),
                 xRadius: height / 2, yRadius: height / 2)
}

/// The squircle with its gradient, light and shadow, shared by both renditions.
func drawBody() {
    let body = NSRect(x: 100, y: 100, width: 824, height: 824)
    let squircle = NSBezierPath(roundedRect: body, xRadius: 185.4, yRadius: 185.4)

    // Drop shadow under the body, as on the macOS icon grid.
    NSGraphicsContext.saveGraphicsState()
    let drop = NSShadow()
    drop.shadowColor = NSColor(white: 0, alpha: 0.32)
    drop.shadowOffset = NSSize(width: 0, height: -14)
    drop.shadowBlurRadius = 28
    drop.set()
    middle.setFill()
    squircle.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    squircle.addClip()
    NSGradient(colors: [top, middle, bottom], atLocations: [0, 0.45, 1], colorSpace: .sRGB)!
        .draw(in: body, angle: -70)
    // Soft light from above and a darker floor, for depth.
    NSGradient(starting: NSColor(white: 1, alpha: 0.22), ending: NSColor(white: 1, alpha: 0))!
        .draw(in: NSRect(x: 100, y: 560, width: 824, height: 364), angle: 90 + 180)
    NSGradient(starting: NSColor(white: 1, alpha: 0), ending: NSColor(white: 0, alpha: 0.14))!
        .draw(in: NSRect(x: 100, y: 100, width: 824, height: 300), angle: 90 + 180)
    NSGraphicsContext.restoreGraphicsState()

    // Inner rim: a thin light edge along the top.
    NSGraphicsContext.saveGraphicsState()
    squircle.addClip()
    let rim = NSBezierPath(roundedRect: body.insetBy(dx: 3, dy: 3), xRadius: 182, yRadius: 182)
    rim.lineWidth = 6
    NSColor(white: 1, alpha: 0.18).setStroke()
    rim.stroke()
    NSGraphicsContext.restoreGraphicsState()

}

func drawIcon() {
    drawBody()
    let center = CGPoint(x: 512, y: 512)

    // Three lines of text inside the aperture; the middle one is being read.
    NSColor(white: 1, alpha: 0.42).setFill()
    bar(x: 382, y: 600, width: 236, height: 40).fill()
    bar(x: 382, y: 424, width: 180, height: 40).fill()
    NSColor(white: 1, alpha: 0.96).setFill()
    bar(x: 382, y: 512, width: 260, height: 40).fill()

    // The scan beam: a wide glow, then a crisp core that reaches past the brackets.
    NSGraphicsContext.saveGraphicsState()
    let glow = NSShadow()
    glow.shadowColor = beam.withAlphaComponent(0.95)
    glow.shadowOffset = .zero
    glow.shadowBlurRadius = 46
    glow.set()
    beam.withAlphaComponent(0.85).setFill()
    bar(x: 226, y: 512, width: 572, height: 14).fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(colors: [beam.withAlphaComponent(0), .white, .white, beam.withAlphaComponent(0)],
               atLocations: [0, 0.2, 0.8, 1], colorSpace: .sRGB)!
        .draw(in: bar(x: 226, y: 512, width: 572, height: 10), angle: 0)

    // The aperture, with a faint shadow so it lifts off the gradient.
    NSGraphicsContext.saveGraphicsState()
    let lift = NSShadow()
    lift.shadowColor = NSColor(calibratedRed: 0.05, green: 0.05, blue: 0.3, alpha: 0.35)
    lift.shadowOffset = NSSize(width: 0, height: -8)
    lift.shadowBlurRadius = 18
    lift.set()
    NSColor.white.setStroke()
    aperture(center: center, half: 212, arm: 130, radius: 64).stroke()
    NSGraphicsContext.restoreGraphicsState()
}

/// The 16 and 32 point rendition: at those sizes the lines and the glow blur into a smudge, so it keeps
/// only thicker brackets and one solid bar, as Apple suggests simplifying small icons.
func drawSmallIcon() {
    drawBody()
    NSColor.white.setFill()
    bar(x: 352, y: 512, width: 320, height: 76).fill()
    NSColor.white.setStroke()
    aperture(center: CGPoint(x: 512, y: 512), half: 236, arm: 150, radius: 70, width: 92).stroke()
}

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
let iconset = out.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let px = base * scale
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        try! render(pixels: px, canvas: 1024, base <= 32 ? drawSmallIcon : drawIcon).write(to: iconset.appendingPathComponent(name))
    }
}
try! render(pixels: 1024, canvas: 1024, drawIcon).write(to: out.appendingPathComponent("preview.png"))
