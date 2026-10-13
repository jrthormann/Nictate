// Nictate: a macOS menu bar app that copies text from anywhere on your screen.
// Copyright (c) 2026 jrthormann. MIT License, see LICENSE.

// Offscreen renders of the selection overlay, for review by eye, with four self-checks. Run: Tests/run_render.sh,
// with NICTATE_RENDER_DIR set to a folder outside the repository. Each case writes a PNG and an 8x corner crop.
// The renders are sRGB bitmaps: they show geometry and relative contrast, not how a display shows colour.

import AppKit

// MARK: Cases

/// The display every render shows, in points. Its still is drawn at each scale.
let renderBounds = CGRect(x: 0, y: 0, width: 480, height: 320)

/// A selection, made by a drag. The reversed drag is a case of its own, so the self-check can compare the two.
enum RenderShape: CaseIterable {
    case full, reversed, small, medium, edge

    var name: String {
        switch self {
        case .full: "240x120"
        case .reversed: "240x120-reversed"
        case .small: "30x10"
        case .medium: "36x12"
        case .edge: "edge"
        }
    }

    /// The start and end of the drag, in points.
    var drag: (start: CGPoint, end: CGPoint) {
        switch self {
        case .full: (CGPoint(x: 120, y: 100), CGPoint(x: 360, y: 220))
        case .reversed: (CGPoint(x: 360, y: 220), CGPoint(x: 120, y: 100))
        case .small: (CGPoint(x: 225, y: 150), CGPoint(x: 255, y: 160))
        case .medium: (CGPoint(x: 222, y: 150), CGPoint(x: 258, y: 162))
        // Flush with the top of the display, and across the split, so both halves show beside its corners.
        case .edge: (CGPoint(x: 150, y: 200), CGPoint(x: 390, y: 320))
        }
    }

    /// The selection the drag makes, as SelectionView makes it.
    var rect: CGRect {
        SelectionGeometry.rect(from: drag.start, to: drag.end, within: renderBounds)
    }
}

/// What the selection sits on. The split crosses the selection, so both halves show beside its edge.
enum RenderBackdrop: CaseIterable {
    case white, dark, gradient, split

    var name: String {
        switch self {
        case .white: "white"
        case .dark: "dark"
        case .gradient: "gradient"
        case .split: "split"
        }
    }

    /// The colour of pixel (x, y), counted from the top left, in a still of `width` x `height` pixels.
    func colour(x: Int, y: Int, width: Int, height: Int) -> (red: UInt8, green: UInt8, blue: UInt8) {
        switch self {
        case .white: return (255, 255, 255)
        case .dark: return (30, 30, 30) // #1E1E1E
        case .split: return x < width / 2 ? (255, 255, 255) : (30, 30, 30)
        case .gradient:
            // #2E6FD8 to #F2A541 along the diagonal, with a 4 px checker of plus or minus 10 % standing in for a photo.
            let t = Double(x + y) / Double(width + height)
            let shade = ((x / 4) + (y / 4)) % 2 == 0 ? 1.1 : 0.9
            func channel(_ from: Double, _ to: Double) -> UInt8 {
                UInt8(min(255, ((from + (to - from) * t) * shade).rounded()))
            }
            return (channel(0x2E, 0xF2), channel(0x6F, 0xA5), channel(0xD8, 0x41))
        }
    }
}

// MARK: Pixels

/// Pixels, four bytes each, rows from the top, as a CGImage lays them out.
struct RenderBitmap: Equatable {
    let width: Int
    let height: Int
    let bytes: [UInt8]

    /// One pixel packed into a number for comparison. (x, y) are counted from the top left.
    func pixel(_ x: Int, _ y: Int) -> UInt32 {
        let i = (y * width + x) * 4
        return UInt32(bytes[i]) << 24 | UInt32(bytes[i + 1]) << 16 | UInt32(bytes[i + 2]) << 8 | UInt32(bytes[i + 3])
    }
}

/// A block of device pixels, [minX, maxX) by [minY, maxY), counted from the top left.
struct RenderBox {
    let minX: Int
    let minY: Int
    let maxX: Int
    let maxY: Int

    /// The pixels of `rect` (points) in a render at `scale` pixels per point.
    static func of(_ rect: CGRect, scale: CGFloat) -> RenderBox {
        let pixels = SelectionGeometry.pixelRect(for: rect, within: renderBounds, scale: scale)
        return RenderBox(minX: Int(pixels.minX), minY: Int(pixels.minY), maxX: Int(pixels.maxX), maxY: Int(pixels.maxY))
    }

    func inset(by n: Int) -> RenderBox {
        RenderBox(minX: minX + n, minY: minY + n, maxX: maxX - n, maxY: maxY - n)
    }

    func outset(by n: Int) -> RenderBox {
        inset(by: -n)
    }

    func contains(_ x: Int, _ y: Int) -> Bool {
        x >= minX && x < maxX && y >= minY && y < maxY
    }
}

/// A context of `width` x `height` pixels, in sRGB, premultiplied RGBA: the layout a CGImage needs.
func makeContext(width: Int, height: Int) -> CGContext {
    CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
              space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}

/// The pixels a context holds, copied out row by row, since a context may pad its rows.
func pixels(of context: CGContext) -> RenderBitmap {
    let rowBytes = context.width * 4
    var bytes: [UInt8] = []
    bytes.reserveCapacity(rowBytes * context.height)
    let data = context.data!.assumingMemoryBound(to: UInt8.self)
    for y in 0..<context.height {
        bytes.append(contentsOf: UnsafeBufferPointer(start: data + y * context.bytesPerRow, count: rowBytes))
    }
    return RenderBitmap(width: context.width, height: context.height, bytes: bytes)
}

/// The still of a backdrop at `scale`: the CGImage the overlay draws, and its pixels for the self-checks.
func makeStill(_ backdrop: RenderBackdrop, scale: CGFloat) -> (image: CGImage, pixels: RenderBitmap) {
    let width = Int(renderBounds.width * scale), height = Int(renderBounds.height * scale)
    let context = makeContext(width: width, height: height)
    let data = context.data!.assumingMemoryBound(to: UInt8.self)
    for y in 0..<height {
        for x in 0..<width {
            let (red, green, blue) = backdrop.colour(x: x, y: y, width: width, height: height)
            let i = y * context.bytesPerRow + x * 4
            data[i] = red
            data[i + 1] = green
            data[i + 2] = blue
            data[i + 3] = 255
        }
    }
    return (context.makeImage()!, pixels(of: context))
}

/// The overlay over a still, drawn by SelectionDrawing into a bitmap at `scale` pixels per point.
func renderOverlay(_ still: CGImage, selection: CGRect?, dark: Bool, style: SelectionOutline.Style,
                   scale: CGFloat) -> RenderBitmap {
    let context = makeContext(width: Int(renderBounds.width * scale), height: Int(renderBounds.height * scale))
    context.scaleBy(x: scale, y: scale)
    SelectionDrawing.draw(still: still, in: renderBounds, selection: selection, dark: dark, style: style,
                          scale: scale, context: context)
    return pixels(of: context)
}

/// The pixels within `radius` of (x, y), each enlarged to an 8 by 8 square by nearest neighbour.
func zoomedCorner(_ picture: RenderBitmap, x: Int, y: Int, radius: Int, zoom: Int = 8) -> RenderBitmap {
    let x0 = max(0, x - radius), y0 = max(0, y - radius)
    let x1 = min(picture.width, x + radius), y1 = min(picture.height, y + radius)
    let width = (x1 - x0) * zoom, height = (y1 - y0) * zoom
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    for oy in 0..<height {
        for ox in 0..<width {
            let source = ((y0 + oy / zoom) * picture.width + (x0 + ox / zoom)) * 4
            let target = (oy * width + ox) * 4
            bytes[target..<target + 4] = picture.bytes[source..<source + 4]
        }
    }
    return RenderBitmap(width: width, height: height, bytes: bytes)
}

/// Writes `picture` as a PNG. Returns false when the file cannot be written.
func writePNG(_ picture: RenderBitmap, to url: URL) -> Bool {
    guard let provider = CGDataProvider(data: Data(picture.bytes) as CFData),
          let image = CGImage(width: picture.width, height: picture.height, bitsPerComponent: 8, bitsPerPixel: 32,
                              bytesPerRow: picture.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                              bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                              provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent),
          let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)
    else { return false }
    CGImageDestinationAddImage(destination, image, nil)
    return CGImageDestinationFinalize(destination)
}

// MARK: Self-checks

/// Check 2: inside the selection, beyond the light band, the render is the still, undimmed. Returns the first
/// pixel that differs, or nil.
func firstDifference(_ picture: RenderBitmap, _ expected: RenderBitmap, in box: RenderBox) -> String? {
    for y in stride(from: box.minY, to: box.maxY, by: 1) {
        for x in stride(from: box.minX, to: box.maxX, by: 1) where picture.pixel(x, y) != expected.pixel(x, y) {
            return "pixel (\(x), \(y))"
        }
    }
    return nil
}

/// Check 3: the four corners are mirror images. The window around the top left corner must equal its reflections
/// in the selection's vertical and horizontal centre lines, which are the other three corners.
func cornerMismatch(_ picture: RenderBitmap, box: RenderBox, radius: Int) -> String? {
    // Pixel column x reflects to minX + maxX - 1 - x, and row y to minY + maxY - 1 - y.
    let sumX = box.minX + box.maxX - 1, sumY = box.minY + box.maxY - 1
    for y in stride(from: box.minY - radius, to: box.minY + radius, by: 1) {
        for x in stride(from: box.minX - radius, to: box.minX + radius, by: 1) {
            let value = picture.pixel(x, y)
            let mirrorX = sumX - x, mirrorY = sumY - y
            if picture.pixel(mirrorX, y) != value || picture.pixel(x, mirrorY) != value
                || picture.pixel(mirrorX, mirrorY) != value {
                return "pixel (\(x), \(y))"
            }
        }
    }
    return nil
}

/// Check 4: outside `box`, the render is the dimmed still. Returns the first pixel that differs, or nil.
func differenceOutside(_ picture: RenderBitmap, _ dimmed: RenderBitmap, outside box: RenderBox) -> String? {
    for y in 0..<picture.height {
        for x in 0..<picture.width where !box.contains(x, y) && picture.pixel(x, y) != dimmed.pixel(x, y) {
            return "pixel (\(x), \(y))"
        }
    }
    return nil
}

/// One self-check: how many renders it applied to, and the failures.
struct RenderCheck {
    let name: String
    var applied = 0
    var failures: [String] = []
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(2)
}

// MARK: Run

guard let directoryPath = ProcessInfo.processInfo.environment["NICTATE_RENDER_DIR"], !directoryPath.isEmpty else {
    fail("NICTATE_RENDER_DIR is not set")
}
let directory = URL(fileURLWithPath: directoryPath, isDirectory: true)
do {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
} catch {
    fail("cannot create \(directory.path)")
}

var checks = [
    RenderCheck(name: "reversed drag is byte-identical to the normal one"),
    RenderCheck(name: "interior beyond the light band is the undimmed still"),
    RenderCheck(name: "four corners are mirror images on flat backgrounds"),
    RenderCheck(name: "30 x 10 has nothing beyond the outer band"),
]
var written: [String] = []
var normalPictures: [String: RenderBitmap] = [:]

for backdrop in RenderBackdrop.allCases {
    for scale in [CGFloat(1), 2] {
        let still = makeStill(backdrop, scale: scale)
        for dark in [false, true] {
            for increased in [false, true] {
                let style = SelectionOutline.style(increased ? .increased : .standard)
                let label = "\(backdrop.name)-\(dark ? "dark" : "light")-\(increased ? "increased" : "standard")-\(Int(scale))x"
                // The split backdrop carries the four extra shapes; every other backdrop carries the main selection only.
                for shape in RenderShape.allCases where backdrop == .split || shape == .full {
                    let rect = shape.rect
                    let box = RenderBox.of(rect, scale: scale)
                    let name = "\(label)-\(shape.name)"
                    let picture = renderOverlay(still.image, selection: rect, dark: dark, style: style, scale: scale)
                    let corner = zoomedCorner(picture, x: box.minX, y: box.minY, radius: Int(12 * scale))

                    // Check 1: the reversed drag must give the normal render, byte for byte.
                    if shape == .full { normalPictures[label] = picture }
                    if shape == .reversed {
                        checks[0].applied += 1
                        if picture != normalPictures[label] { checks[0].failures.append(name) }
                    }
                    // Check 2: the interior beyond the light band is the still itself.
                    checks[1].applied += 1
                    let innerPixels = Int((style.innerWidth * scale).rounded())
                    if let at = firstDifference(picture, still.pixels, in: box.inset(by: innerPixels)) {
                        checks[1].failures.append("\(name): first difference at \(at)")
                    }
                    // Check 3: on the flat backdrops, the four corners of the main selection mirror one another.
                    if (backdrop == .white || backdrop == .dark) && shape == .full {
                        checks[2].applied += 1
                        if let at = cornerMismatch(picture, box: box, radius: Int(12 * scale)) {
                            checks[2].failures.append("\(name): first difference at \(at)")
                        }
                    }
                    // Check 4: the 30 x 10 selection draws nothing beyond the outer band.
                    if shape == .small {
                        checks[3].applied += 1
                        let dimmed = renderOverlay(still.image, selection: nil, dark: dark, style: style, scale: scale)
                        let outerPixels = Int((style.outerWidth * scale).rounded())
                        if let at = differenceOutside(picture, dimmed, outside: box.outset(by: outerPixels)) {
                            checks[3].failures.append("\(name): first difference at \(at)")
                        }
                    }

                    for (file, bitmap) in [(name, picture), (name + "-corner", corner)] {
                        let url = directory.appendingPathComponent(file + ".png")
                        guard writePNG(bitmap, to: url) else { fail("cannot write \(url.path)") }
                        written.append(file + ".png")
                    }
                }
            }
        }
    }
}

print("\(written.count) PNG files in \(directory.path)")
for file in written { print("  \(file)") }
print("self-checks:")
var failedChecks = 0
for check in checks {
    let verdict = check.failures.isEmpty ? "PASS" : "FAIL"
    print("\(verdict)  \(check.name): \(check.failures.count) of \(check.applied) renders failed")
    for failure in check.failures { print("      \(failure)") }
    if !check.failures.isEmpty { failedChecks += 1 }
}
exit(failedChecks == 0 ? 0 : 1)
