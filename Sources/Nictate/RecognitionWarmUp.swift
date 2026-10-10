// Nictate: a macOS menu bar app that copies text from anywhere on your screen.
// Copyright (c) 2026 jrthormann. MIT License, see LICENSE.

import CoreGraphics
import CoreText
import Foundation

/// The first accurate text request after the app is installed at a new path can stall for half a minute,
/// and so can the first one on a larger image and the first document read, while every later request
/// takes well under a second (measured on macOS 27). Running one of each at launch, in the background,
/// moves that wait away from the user's first capture.
enum RecognitionWarmUp {
    /// The two image sizes seen to stall separately: a small selection, and a laptop screen at 2x (kept
    /// under the size where recognition switches to the two-pass reading, which uses the same models).
    static let sizes = [CGSize(width: 400, height: 200), CGSize(width: 2880, height: 1800)]

    /// The document reader is only a second opinion during a capture, so it gets a short wait there; the
    /// warm-up waits long enough for its first run to finish and leave nothing for the user to pay.
    private static let documentTimeout: TimeInterval = 120

    /// Returns at once: the work runs on a utility queue, so it never delays launch or the main thread.
    static func start() {
        DispatchQueue.global(qos: .utility).async {
            let steps = run()
            Log.recognition.notice("Warm-up finished in \(steps.reduce(0, +)) ms (small \(steps[0]), large \(steps[1]), document \(steps[2]) ms)")
        }
    }

    /// Runs one recognition per size and one document read, and returns how long each took in
    /// milliseconds. Blocking: call off the main thread.
    @discardableResult
    static func run() -> [Int] {
        // A drawing that fails leaves its step at zero; the warm-up is only ever a head start.
        let images = sizes.map(textImage)
        var steps = images.map { image in
            milliseconds { if let image { _ = Recognizer.recognize(image, options: RecognitionOptions()) } }
        }
        steps.append(milliseconds { if let page = images[0] { _ = DocumentTables.rows(in: page, timeout: documentTimeout) } })
        return steps
    }

    /// Dark lines of ordinary words on white, so the text model has real work to do.
    static func textImage(_ size: CGSize) -> CGImage? {
        let width = Int(size.width), height = Int(size.height)
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let points = max(13, size.height / 60)
        let font = CTFontCreateUIFontForLanguage(.system, points, nil)
        let attributes = [kCTFontAttributeName: font as Any, kCTForegroundColorAttributeName: CGColor(gray: 0, alpha: 1)] as CFDictionary
        var baseline = size.height - points * 2
        var index = 0
        while baseline > points {
            let words = "Line \(index): the quick brown fox jumps over the lazy dog" as CFString
            guard let string = CFAttributedStringCreate(nil, words, attributes) else { return nil }
            context.textPosition = CGPoint(x: points, y: baseline)
            CTLineDraw(CTLineCreateWithAttributedString(string), context)
            baseline -= points * 1.6
            index += 1
        }
        return context.makeImage()
    }

    private static func milliseconds(_ work: () -> Void) -> Int {
        let start = DispatchTime.now().uptimeNanoseconds
        work()
        return Int((DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
    }
}
