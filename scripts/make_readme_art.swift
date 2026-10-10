// Nictate: a macOS menu bar app that copies text from anywhere on your screen.
// Copyright (c) 2026 jrthormann. MIT License, see LICENSE.


import AppKit

// Renders the README images, in light and dark. Usage: make_readme_art [language] [outDir]
// English goes to docs/images, any other language to docs/images/<language>.
//   hero-*.png   the name, the promise, and a capture: a window, the aperture over a paragraph,
//                the "Text copied" notification and the menu with what was found
//   bento-*.png  four things Nictate does, as tiles with SF Symbols
//   icon.png     the app icon at 256 px, copied from Sources/Nictate/Resources/preview.png
// The art is authored in points at 2x, y-up.

let language = CommandLine.arguments.dropFirst().first ?? "en"
let outDir = CommandLine.arguments.dropFirst(2).first ?? (language == "en" ? "docs/images" : "docs/images/\(language)")
try! FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

// MARK: Words

// The words drawn into the images, keyed by the English text. Menu and notification words match
// the app's own strings in Sources/Nictate/Resources/<language>.lproj.
let translations: [String: [String: String]] = [
    "es": [
        "Copy the text you can see.": "Copia el texto que ves.",
        "Meeting notes, 9 October": "Notas de la reuni\u{F3}n, 9 de octubre",
        "Ship the new icon.": "Publicar el icono nuevo.",
        "Invoice #4471 is due on Friday.": "La factura #4471 vence el viernes.",
        "Brand color: #5B5CF6": "Color de marca: #5B5CF6",
        "Docs: https://github.com/jrthormann/Nictate": "Docs: https://github.com/jrthormann/Nictate",
        "Ask Ana about the table export.": "Preguntar a Ana por la exportaci\u{F3}n de tablas.",
        "Found in the last capture": "Detectado en la \u{FA}ltima captura",
        "Capture Text": "Capturar texto",
        "Text copied": "Texto copiado",
        "now": "ahora",
        "Select. It\u{2019}s copied.": "Seleccionas. Copiado.",
        "Any app, image, video or PDF on screen.": "Cualquier app, imagen, v\u{ED}deo o PDF en pantalla.",
        "Pixel by pixel.": "P\u{ED}xel a p\u{ED}xel.",
        "Arrow keys adjust the selection one pixel at a time.": "Las flechas ajustan la selecci\u{F3}n un p\u{ED}xel cada vez.",
        "Colors, links, codes.": "Colores, enlaces, c\u{F3}digos.",
        "Copy a HEX, open a link, read a QR.": "Copia un HEX, abre un enlace, lee un QR.",
        "Never leaves your Mac.": "Nunca sale de tu Mac.",
        "No account. No analytics.": "Sin cuenta. Sin anal\u{ED}ticas.",
    ],
]

func T(_ english: String) -> String {
    if language == "en" || english.isEmpty { return english }
    guard let words = translations[language] else { fatalError("No words for \(language)") }
    guard let word = words[english] else { fatalError("No \(language) for \"\(english)\"") }
    return word
}

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
}

struct Theme {
    let name: String
    let page, ink, secondaryInk: NSColor
    let wallpaper: [NSColor]
    let menuBar, menuInk: NSColor
    let window, windowBar, text, mutedText: NSColor
    let shade: NSColor           // dims the screen outside the selection
    let glass, glassEdge, shadow: NSColor
    let tile, accent: NSColor
}

let light = Theme(
    name: "light",
    page: rgb(255, 255, 255), ink: rgb(29, 29, 31), secondaryInk: rgb(110, 110, 115),
    wallpaper: [rgb(214, 222, 255), rgb(229, 220, 255), rgb(206, 236, 255)],
    menuBar: rgb(255, 255, 255, 0.72), menuInk: rgb(60, 60, 67, 0.75),
    window: rgb(255, 255, 255), windowBar: rgb(246, 246, 248), text: rgb(29, 29, 31), mutedText: rgb(150, 150, 160),
    shade: rgb(20, 20, 40, 0.18),
    glass: rgb(255, 255, 255, 0.82), glassEdge: rgb(255, 255, 255, 0.95), shadow: rgb(30, 30, 80, 0.22),
    tile: rgb(244, 244, 247), accent: rgb(84, 92, 250))

let dark = Theme(
    name: "dark",
    page: rgb(13, 17, 23), ink: rgb(240, 240, 245), secondaryInk: rgb(152, 152, 160),
    wallpaper: [rgb(36, 32, 92), rgb(46, 30, 88), rgb(18, 52, 98)],
    menuBar: rgb(30, 30, 40, 0.7), menuInk: rgb(235, 235, 245, 0.7),
    window: rgb(36, 36, 42), windowBar: rgb(46, 46, 54), text: rgb(236, 236, 242), mutedText: rgb(120, 120, 132),
    shade: rgb(0, 0, 0, 0.32),
    glass: rgb(48, 48, 60, 0.82), glassEdge: rgb(255, 255, 255, 0.16), shadow: rgb(0, 0, 0, 0.5),
    tile: rgb(24, 28, 36), accent: rgb(130, 140, 255))

// MARK: Drawing helpers

func render(width: CGFloat, height: CGFloat, scale: CGFloat = 2, _ draw: () -> Void) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width * scale), pixelsHigh: Int(height * scale),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let t = NSAffineTransform(); t.scale(by: scale); t.concat()
    draw()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

func rounded(_ r: NSRect, _ radius: CGFloat) -> NSBezierPath { NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius) }

func withShadow(_ color: NSColor, blur: CGFloat, y: CGFloat, _ draw: () -> Void) {
    NSGraphicsContext.saveGraphicsState()
    let s = NSShadow(); s.shadowColor = color; s.shadowBlurRadius = blur; s.shadowOffset = NSSize(width: 0, height: y); s.set()
    draw()
    NSGraphicsContext.restoreGraphicsState()
}

func text(_ string: String, size: CGFloat, weight: NSFont.Weight, color: NSColor, mono: Bool = false,
          tracking: CGFloat = 0) -> NSAttributedString {
    let font = mono ? NSFont.monospacedSystemFont(ofSize: size, weight: weight) : NSFont.systemFont(ofSize: size, weight: weight)
    return NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: color, .kern: tracking])
}

func drawCentered(_ s: NSAttributedString, centerX: CGFloat, baselineY: CGFloat) {
    s.draw(at: NSPoint(x: centerX - s.size().width / 2, y: baselineY))
}

func symbol(_ name: String, size: CGFloat, color: NSColor) -> NSImage {
    let config = NSImage.SymbolConfiguration(pointSize: size, weight: .regular)
        .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
    return NSImage(systemSymbolName: name, accessibilityDescription: nil)!.withSymbolConfiguration(config)!
}

/// Four rounded corner brackets around `rect`, the shape of the app icon.
func aperture(_ rect: NSRect, arm: CGFloat, radius: CGFloat, width: CGFloat) -> NSBezierPath {
    let path = NSBezierPath()
    for (sx, sy) in [(-1, 1), (1, 1), (1, -1), (-1, -1)] as [(CGFloat, CGFloat)] {
        let corner = NSPoint(x: sx < 0 ? rect.minX : rect.maxX, y: sy < 0 ? rect.minY : rect.maxY)
        let alongY = NSPoint(x: corner.x, y: corner.y - sy * arm)
        let alongX = NSPoint(x: corner.x - sx * arm, y: corner.y)
        path.move(to: alongY)
        path.appendArc(from: corner, to: alongX, radius: radius)
        path.line(to: alongX)
    }
    path.lineWidth = width
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    return path
}

// MARK: Hero

let paragraph = [
    "Meeting notes, 9 October",
    "",
    "Ship the new icon.",
    "Invoice #4471 is due on Friday.",
    "Brand color: #5B5CF6",
    "Docs: https://github.com/jrthormann/Nictate",
    "",
    "Ask Ana about the table export.",
]
let selected = 2...5

func hero(_ t: Theme) -> Data {
    let w: CGFloat = 1200, h: CGFloat = 700
    return render(width: w, height: h) {
        t.page.setFill(); NSRect(x: 0, y: 0, width: w, height: h).fill()
        drawCentered(text("Nictate", size: 96, weight: .bold, color: t.ink, tracking: -2.5), centerX: w / 2, baselineY: 562)
        drawCentered(text(T("Copy the text you can see."), size: 34, weight: .regular, color: t.secondaryInk, tracking: -0.4),
                     centerX: w / 2, baselineY: 508)

        // The screen.
        let screen = NSRect(x: 50, y: 30, width: 1100, height: 440)
        withShadow(t.shadow, blur: 30, y: -10) { t.page.setFill(); rounded(screen, 28).fill() }
        NSGraphicsContext.saveGraphicsState()
        rounded(screen, 28).addClip()
        NSGradient(colors: t.wallpaper)!.draw(in: screen, angle: -20)

        // Menu bar with the Nictate glyph and its green "copied" cue.
        let bar = NSRect(x: screen.minX, y: screen.maxY - 30, width: screen.width, height: 30)
        t.menuBar.setFill(); bar.fill()
        t.menuInk.setFill()
        NSBezierPath(ovalIn: NSRect(x: bar.minX + 22, y: bar.midY - 6, width: 12, height: 12)).fill()
        for (x, wd) in [(56.0, 44.0), (112.0, 36.0), (160.0, 40.0), (212.0, 30.0)] as [(CGFloat, CGFloat)] {
            rounded(NSRect(x: bar.minX + x, y: bar.midY - 4, width: wd, height: 8), 4).fill()
        }
        for i in 0..<8 { rounded(NSRect(x: bar.maxX - 40 - CGFloat(i) * 34, y: bar.midY - 6, width: 20, height: 12), 3).fill() }
        let glyph = NSRect(x: bar.maxX - 336, y: bar.midY - 8, width: 16, height: 16)
        withShadow(rgb(52, 199, 89, 0.9), blur: 8, y: 0) {
            rgb(52, 199, 89).setStroke()
            aperture(glyph, arm: 4.5, radius: 2, width: 1.8).stroke()
        }

        // A window with a paragraph.
        let win = NSRect(x: 150, y: 70, width: 560, height: 320)
        withShadow(t.shadow, blur: 24, y: -8) { t.window.setFill(); rounded(win, 14).fill() }
        NSGraphicsContext.saveGraphicsState()
        rounded(win, 14).addClip()
        t.windowBar.setFill(); NSRect(x: win.minX, y: win.maxY - 34, width: win.width, height: 34).fill()
        NSGraphicsContext.restoreGraphicsState()
        for (i, c) in [rgb(255, 95, 87), rgb(254, 188, 46), rgb(40, 200, 64)].enumerated() {
            c.setFill(); NSBezierPath(ovalIn: NSRect(x: win.minX + 16 + CGFloat(i) * 20, y: win.maxY - 23, width: 12, height: 12)).fill()
        }
        var y = win.maxY - 74
        var lineRects: [NSRect] = []
        for (i, line) in paragraph.enumerated() {
            let s = text(T(line), size: i == 0 ? 20 : 18, weight: i == 0 ? .semibold : .regular,
                         color: selected.contains(i) || i == 0 ? t.text : t.mutedText)
            s.draw(at: NSPoint(x: win.minX + 30, y: y))
            lineRects.append(NSRect(x: win.minX + 30, y: y, width: s.size().width, height: s.size().height))
            y -= line.isEmpty ? 14 : 30
        }

        // The selection: the screen dims outside it, the aperture frames it.
        let first = lineRects[selected.lowerBound], last = lineRects[selected.upperBound]
        let sel = NSRect(x: win.minX + 16, y: last.minY - 10, width: 380, height: first.maxY - last.minY + 20)
        let dim = NSBezierPath(rect: screen); dim.append(rounded(sel, 6)); dim.windingRule = .evenOdd
        t.shade.setFill(); dim.fill()
        withShadow(rgb(0, 0, 60, 0.35), blur: 6, y: -1) {
            NSColor.white.setStroke(); aperture(sel.insetBy(dx: -6, dy: -6), arm: 26, radius: 10, width: 5).stroke()
        }

        // The menu under the glyph, offering what the capture contained.
        let menu = NSRect(x: glyph.minX - 12, y: bar.minY - 160, width: 330, height: 154)
        withShadow(t.shadow, blur: 24, y: -8) { t.glass.setFill(); rounded(menu, 12).fill() }
        t.glassEdge.setStroke(); let edge = rounded(menu.insetBy(dx: 0.5, dy: 0.5), 12); edge.lineWidth = 1; edge.stroke()
        text(T("Found in the last capture"), size: 13, weight: .semibold, color: t.secondaryInk)
            .draw(at: NSPoint(x: menu.minX + 16, y: menu.maxY - 30))
        let rowColor = NSRect(x: menu.minX + 6, y: menu.maxY - 70, width: menu.width - 12, height: 30)
        rgb(0, 122, 255).setFill(); rounded(rowColor, 6).fill()
        rgb(91, 92, 246).setFill(); NSBezierPath(ovalIn: NSRect(x: rowColor.minX + 10, y: rowColor.midY - 7, width: 14, height: 14)).fill()
        NSColor.white.setStroke(); let ring = NSBezierPath(ovalIn: NSRect(x: rowColor.minX + 10, y: rowColor.midY - 7, width: 14, height: 14)); ring.lineWidth = 1.5; ring.stroke()
        let colorLabel = text("#5B5CF6", size: 14, weight: .regular, color: .white)
        colorLabel.draw(at: NSPoint(x: rowColor.minX + 34, y: rowColor.midY - colorLabel.size().height / 2))
        let chevron = text("\u{203A}", size: 18, weight: .regular, color: .white)
        chevron.draw(at: NSPoint(x: rowColor.maxX - 18, y: rowColor.midY - chevron.size().height / 2))
        let rowLink = NSRect(x: menu.minX + 6, y: menu.maxY - 104, width: menu.width - 12, height: 30)
        symbol("link", size: 13, color: t.text).draw(in: NSRect(x: rowLink.minX + 10, y: rowLink.midY - 7, width: 15, height: 14))
        let linkLabel = text("https://github.com/jrthormann/Nictate", size: 14, weight: .regular, color: t.text)
        linkLabel.draw(at: NSPoint(x: rowLink.minX + 34, y: rowLink.midY - linkLabel.size().height / 2))
        let chevron2 = text("\u{203A}", size: 18, weight: .regular, color: t.secondaryInk)
        chevron2.draw(at: NSPoint(x: rowLink.maxX - 18, y: rowLink.midY - chevron2.size().height / 2))
        t.ink.withAlphaComponent(0.12).setFill(); NSRect(x: menu.minX + 14, y: menu.minY + 42, width: menu.width - 28, height: 1).fill()
        text(T("Capture Text"), size: 14, weight: .regular, color: t.text).draw(at: NSPoint(x: menu.minX + 16, y: menu.minY + 14))

        // The notification after the copy.
        let note = NSRect(x: 820, y: 60, width: 300, height: 76)
        withShadow(t.shadow, blur: 20, y: -6) { t.glass.setFill(); rounded(note, 18).fill() }
        t.glassEdge.setStroke(); let noteEdge = rounded(note.insetBy(dx: 0.5, dy: 0.5), 18); noteEdge.lineWidth = 1; noteEdge.stroke()
        if let icon = NSImage(contentsOfFile: "Sources/Nictate/Resources/preview.png") {
            icon.draw(in: NSRect(x: note.minX + 12, y: note.midY - 24, width: 48, height: 48))
        }
        text("Nictate", size: 15, weight: .semibold, color: t.text).draw(at: NSPoint(x: note.minX + 70, y: note.midY + 2))
        text(T("Text copied"), size: 15, weight: .regular, color: t.text).draw(at: NSPoint(x: note.minX + 70, y: note.midY - 20))
        let now = text(T("now"), size: 13, weight: .regular, color: t.secondaryInk)
        now.draw(at: NSPoint(x: note.maxX - 16 - now.size().width, y: note.midY + 4))
        NSGraphicsContext.restoreGraphicsState()
    }
}

// MARK: Bento

let tiles: [(String, String, String)] = [
    ("text.viewfinder", "Select. It\u{2019}s copied.", "Any app, image, video or PDF on screen."),
    ("square.dashed", "Pixel by pixel.", "Arrow keys adjust the selection one pixel at a time."),
    ("swatchpalette", "Colors, links, codes.", "Copy a HEX, open a link, read a QR."),
    ("lock.shield", "Never leaves your Mac.", "No account. No analytics."),
]

func bento(_ t: Theme) -> Data {
    let w: CGFloat = 1200, h: CGFloat = 640, gap: CGFloat = 20
    let tw = (w - gap * 3) / 2, th = (h - gap * 3) / 2
    return render(width: w, height: h) {
        t.page.setFill(); NSRect(x: 0, y: 0, width: w, height: h).fill()
        for (i, tile) in tiles.enumerated() {
            let col = CGFloat(i % 2), row = CGFloat(1 - i / 2)
            let r = NSRect(x: gap + col * (tw + gap), y: gap + row * (th + gap), width: tw, height: th)
            t.tile.setFill(); rounded(r, 28).fill()
            let icon = symbol(tile.0, size: 44, color: t.accent)
            let size = icon.size
            icon.draw(in: NSRect(x: r.minX + 44, y: r.maxY - 44 - size.height, width: size.width, height: size.height))
            text(T(tile.1), size: 34, weight: .bold, color: t.ink, tracking: -0.6).draw(at: NSPoint(x: r.minX + 44, y: r.minY + 76))
            text(T(tile.2), size: 20, weight: .regular, color: t.secondaryInk).draw(at: NSPoint(x: r.minX + 44, y: r.minY + 40))
        }
    }
}

for theme in [light, dark] {
    try! hero(theme).write(to: URL(fileURLWithPath: "\(outDir)/hero-\(theme.name).png"))
    try! bento(theme).write(to: URL(fileURLWithPath: "\(outDir)/bento-\(theme.name).png"))
}
