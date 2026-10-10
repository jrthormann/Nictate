// Nictate: a macOS menu bar app that copies text from anywhere on your screen.
// Copyright (c) 2026 jrthormann. MIT License, see LICENSE.

import AppKit

// Draws the background of the Nictate disk image window: a soft light wash with an indigo glow, a fine
// grain, an eyelid-shaped arrow from the app to the Applications folder, and one line that makes people smile.
// Usage: make_dmg_background <out.png> [scale]   (run from the repository root, for the flag in docs/images)
// The window is 540x360 points; scripts/build-dmg.sh places Nictate at x 140 and Applications at x 400, both at
// y 180 from the top, and joins the 1x and 2x images into one TIFF.

let out = CommandLine.arguments.dropFirst().first ?? "background.png"
let scale = CGFloat(Double(CommandLine.arguments.dropFirst(2).first ?? "1") ?? 1)
let W: CGFloat = 540, H: CGFloat = 360

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
}

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W * scale), pixelsHigh: Int(H * scale),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: W, height: H)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSGraphicsContext.current?.imageInterpolation = .high
let canvas = NSRect(x: 0, y: 0, width: W, height: H)

// Base: a light wash that stays calm enough for Finder's labels.
NSGradient(colors: [rgb(246, 245, 255), rgb(238, 240, 255), rgb(232, 244, 255)],
           atLocations: [0, 0.5, 1], colorSpace: .sRGB)!.draw(in: canvas, angle: -28)

// Glow behind the arrow, the one place the accent is strongest.
let accent = rgb(84, 92, 250)
let iconY = H - 180
NSGradient(colors: [accent.withAlphaComponent(0.16), accent.withAlphaComponent(0)])!
    .draw(fromCenter: NSPoint(x: W / 2, y: iconY), radius: 0, toCenter: NSPoint(x: W / 2, y: iconY), radius: 200,
          options: [])

// Grain: deterministic dots, so every build looks the same.
var seed: UInt64 = 0x9E3779B97F4A7C15
func next() -> CGFloat {
    seed = seed &* 6364136223846793005 &+ 1442695040888963407
    return CGFloat(seed >> 33) / CGFloat(1 << 31)
}
for _ in 0..<Int(W * H / 14 * scale * scale) {
    let x = next() * W * scale / scale, y = next() * H
    let shade: CGFloat = next() < 0.5 ? 0 : 255
    NSColor(srgbRed: shade / 255, green: shade / 255, blue: shade / 255, alpha: 0.025)
        .setFill()
    NSRect(x: x, y: y, width: 1 / scale + 0.5, height: 1 / scale + 0.5).fill()
}

// The arrow is an eyelid: a lens between the two icons, thick in the middle, sharp at both ends. It reads as
// the membrane sweeping from the app to the folder.
let from = NSPoint(x: 140 + 74, y: iconY), to = NSPoint(x: 400 - 78, y: iconY)
let lid = NSBezierPath()
lid.move(to: from)
lid.curve(to: to, controlPoint1: NSPoint(x: from.x + 60, y: iconY + 30), controlPoint2: NSPoint(x: to.x - 60, y: iconY + 30))
lid.curve(to: from, controlPoint1: NSPoint(x: to.x - 60, y: iconY + 12), controlPoint2: NSPoint(x: from.x + 60, y: iconY + 12))
lid.close()
NSGradient(colors: [rgb(124, 92, 255, 0.9), rgb(20, 150, 255, 0.9)])!.draw(in: lid, angle: 0)

// Chevron tip at the Applications end.
let tip = NSBezierPath()
tip.move(to: NSPoint(x: to.x - 12, y: to.y + 10))
tip.line(to: NSPoint(x: to.x + 2, y: to.y + 1))
tip.line(to: NSPoint(x: to.x - 12, y: to.y - 8))
tip.lineWidth = 3
tip.lineCapStyle = .round
tip.lineJoinStyle = .round
rgb(20, 150, 255, 0.9).setStroke()
tip.stroke()

// The line that makes people smile, under the icons and their labels.
let caption = NSAttributedString(string: "Drag me to Applications. I promise not to blink.", attributes: [
    .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
    .foregroundColor: rgb(44, 46, 70),
])
caption.draw(at: NSPoint(x: (W - caption.size().width) / 2, y: iconY - 110))

// Footer: the flag and where it was made, in the same quiet grey as the plate.
let madeIn = NSAttributedString(string: "Made in the Dominican Republic, fueled by Coke Zero and pizza", attributes: [
    .font: NSFont.systemFont(ofSize: 10.5, weight: .regular),
    .foregroundColor: rgb(44, 46, 70, 0.7),
])
let flagSide: CGFloat = 13
let footerWidth = flagSide + 7 + madeIn.size().width
let footerX = (W - footerWidth) / 2
if let flag = NSImage(contentsOfFile: "docs/images/flag-do.svg") {
    flag.draw(in: NSRect(x: footerX, y: 12, width: flagSide, height: flagSide))
}
madeIn.draw(at: NSPoint(x: footerX + flagSide + 7, y: 11.5))

// Small details, like a printed plate: name and version top left, the promise top right, a hairline above the footer.
let plate: [NSAttributedString.Key: Any] = [
    .font: NSFont.monospacedSystemFont(ofSize: 9, weight: .medium),
    .foregroundColor: rgb(44, 46, 70, 0.55),
    .kern: 1.4,
]
NSAttributedString(string: "NICTATE  1.0", attributes: plate).draw(at: NSPoint(x: 22, y: H - 28))
// The flag of the Dominican Republic, drawn in its four quarters and white cross (the coat of arms is left out
// for a clean mark). It sits right after "MADE IN".
func flag(at origin: NSPoint, width w: CGFloat, height h: CGFloat) {
    let blue = rgb(0, 45, 98), red = rgb(206, 17, 38)
    let r = NSRect(x: origin.x, y: origin.y, width: w, height: h)
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(roundedRect: r, xRadius: 2, yRadius: 2).addClip()
    blue.setFill(); r.fill()
    red.setFill()
    NSRect(x: r.midX, y: r.minY, width: w / 2, height: h / 2).fill()
    NSRect(x: r.minX, y: r.midY, width: w / 2, height: h / 2).fill()
    NSColor.white.setFill()
    NSRect(x: r.midX - w * 0.09, y: r.minY, width: w * 0.18, height: h).fill()
    NSRect(x: r.minX, y: r.midY - h * 0.14, width: w, height: h * 0.28).fill()
    NSGraphicsContext.restoreGraphicsState()
}

let made = NSAttributedString(string: "MADE IN", attributes: plate)
let madeX = W - 22 - 18 - 8 - made.size().width
made.draw(at: NSPoint(x: madeX, y: H - 28))
flag(at: NSPoint(x: W - 22 - 18, y: H - 30), width: 18, height: 12)

// Footer: a hairline and one small, friendly line.
rgb(44, 46, 70, 0.10).setFill()
NSRect(x: 22, y: 34, width: W - 44, height: 0.5).fill()
let footer = NSAttributedString(string: "HECHO CON CAFECITO EN RD", attributes: plate)
footer.draw(at: NSPoint(x: (W - footer.size().width) / 2, y: 12))

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
