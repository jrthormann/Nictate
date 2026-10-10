// Nictate: a macOS menu bar app that copies text from anywhere on your screen.
// Copyright (c) 2026 jrthormann. MIT License, see LICENSE.

import AppKit
import CoreImage
import Vision

struct RecognitionOptions: Sendable {
    var languages: [String] = []
    var keepLineBreaks = true
    var languageCorrection = true
    var preserveIndentation = false
    var detectColumns = true
    var tablesAsTabs = false
    /// Look only for QR codes and barcodes; skip text recognition.
    var barcodesOnly = false
}

struct RecognitionResult: Sendable {
    let text: String
    /// QR/barcode payloads bypass text formatting and cleaning.
    let isBarcode: Bool
}

enum Recognizer {
    /// Empty if Vision cannot list them; the language menu then offers only Automatic.
    static let supportedLanguages: [String] = {
        do {
            return try VNRecognizeTextRequest().supportedRecognitionLanguages()
        } catch {
            Log.recognition.error("Supported languages: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }()

    private static let ciContext = CIContext()

    /// Runs barcode and text recognition on-device. Blocking: call off the main thread.
    static func recognize(_ source: CGImage, options: RecognitionOptions) -> RecognitionResult {
        let image = upscaledIfSmall(source)

        // Past this size the accurate model can come back empty, even for ordinary text (a whole 5K screen).
        // The fast model still finds every line, so large images are read in two passes: the fast model
        // locates the lines, then the accurate model re-reads each one on its own.
        let large = max(image.width, image.height) > largeImageSide
        let text = textRequest(options, level: large ? .fast : .accurate)
        let barcodes = VNDetectBarcodesRequest()

        do {
            // A code-only capture never runs the text model, which is the costly part.
            try VNImageRequestHandler(cgImage: image, options: [:]).perform(options.barcodesOnly ? [barcodes] : [text, barcodes])
        } catch {
            Log.recognition.error("Vision: \(error.localizedDescription, privacy: .public)")
            return RecognitionResult(text: "", isBarcode: false)
        }

        let codes = (barcodes.results ?? []).compactMap { $0.payloadStringValue }
        if !codes.isEmpty { return RecognitionResult(text: codes.joined(separator: "\n"), isBarcode: true) }
        if options.barcodesOnly { return RecognitionResult(text: "", isBarcode: false) }

        var fragments = (text.results ?? []).compactMap { obs -> TextFragment? in
            guard let candidate = obs.topCandidates(1).first else { return nil }
            return TextFragment(text: candidate.string, box: obs.boundingBox)
        }
        if large { fragments = refined(fragments, in: image, options: options) }
        let size = CGSize(width: image.width, height: image.height)
        // Line breaks are joined only in confidently recognized prose, so code, tables and lists keep theirs.
        let keptBreaks = TextLayout.compose(fragments, imageSize: size, keepLineBreaks: true,
                                            preserveIndentation: options.preserveIndentation,
                                            detectColumns: options.detectColumns, tablesAsTabs: options.tablesAsTabs)
        var composed = keptBreaks
        if !options.keepLineBreaks, ContentClassifier.joinsParagraphs(ContentClassifier.classify(fragments, text: keptBreaks, imageSize: size)) {
            composed = TextLayout.compose(fragments, imageSize: size, keepLineBreaks: false,
                                          preserveIndentation: options.preserveIndentation,
                                          detectColumns: options.detectColumns, tablesAsTabs: options.tablesAsTabs)
        }
        // No table found by Nictate's own layout: ask Apple's document reader, and use its table only if the
        // capture is essentially that table.
        // Only worth the extra pass (about 90 ms) when two or more lines hold several fragments.
        if options.tablesAsTabs, !options.preserveIndentation, !large, !composed.contains("\t"),
           TextLayout.multiCellRows(fragments, imageSize: CGSize(width: image.width, height: image.height)) >= 2,
           let rows = DocumentTables.rows(in: image), DocumentTables.cellsAgree(rows, with: composed) {
            let table = DocumentTables.tsv(rows)
            let count: (String) -> Int = { $0.filter { !$0.isWhitespace }.count }
            if DocumentTables.prefersTable(tableCharacters: count(table), textCharacters: count(composed)) {
                return RecognitionResult(text: table, isBarcode: false)
            }
        }
        return RecognitionResult(text: composed, isBarcode: false)
    }

    /// Above this long side (pixels) the accurate model cannot be trusted on the whole image.
    private static let largeImageSide = 3000

    private static func textRequest(_ options: RecognitionOptions, level: VNRequestTextRecognitionLevel) -> VNRecognizeTextRequest {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = level
        request.usesLanguageCorrection = options.languageCorrection
        if options.languages.isEmpty {
            request.automaticallyDetectsLanguage = true
        } else {
            request.automaticallyDetectsLanguage = false
            request.recognitionLanguages = options.languages
        }
        return request
    }

    /// Re-reads each located line with the accurate model, on a crop of just that line, so the text keeps
    /// the accurate model's quality and the layout keeps the positions found on the whole image. A line
    /// the accurate model cannot read keeps its fast reading.
    private static func refined(_ fragments: [TextFragment], in image: CGImage, options: RecognitionOptions) -> [TextFragment] {
        let width = CGFloat(image.width), height = CGFloat(image.height)
        var texts = [String?](repeating: nil, count: fragments.count)
        texts.withUnsafeMutableBufferPointer { buffer in
            // Each iteration writes only its own index, so concurrent writes never overlap.
            nonisolated(unsafe) let out = buffer
            DispatchQueue.concurrentPerform(iterations: fragments.count) { index in
                let box = fragments[index].box
                let lineHeight = box.height * height
                var rect = CGRect(x: box.minX * width - lineHeight * 0.5, y: (1 - box.maxY) * height - lineHeight * 0.3,
                                  width: box.width * width + lineHeight, height: lineHeight * 1.6)
                rect = rect.intersection(CGRect(x: 0, y: 0, width: width, height: height)).integral
                guard !rect.isEmpty, let crop = image.cropping(to: rect) else { return }

                let request = textRequest(options, level: .accurate)
                do {
                    try VNImageRequestHandler(cgImage: upscaledIfSmall(crop), options: [:]).perform([request])
                } catch {
                    Log.recognition.error("Line re-read: \(error.localizedDescription, privacy: .public)")
                    return
                }
                // A crop can include the edge of a neighbouring line: keep only what is centered in this one.
                let own = (request.results ?? []).filter { observation in
                    let center = CGPoint(x: (rect.minX + observation.boundingBox.midX * rect.width) / width,
                                         y: 1 - (rect.minY + (1 - observation.boundingBox.midY) * rect.height) / height)
                    return box.contains(center)
                }
                let read = own.sorted { $0.boundingBox.minX < $1.boundingBox.minX }
                    .compactMap { $0.topCandidates(1).first?.string }
                if !read.isEmpty { out[index] = read.joined(separator: " ") }
            }
        }
        return zip(fragments, texts).map { TextFragment(text: $1 ?? $0.text, box: $0.box) }
    }

    /// Small selections (a single line of code, say) read far better when enlarged first;
    /// measured on rendered code at 14-22 px, this recovered lines Vision otherwise dropped.
    static func upscaledIfSmall(_ image: CGImage) -> CGImage {
        let shortSide = CGFloat(min(image.width, image.height))
        guard shortSide < 500, let filter = CIFilter(name: "CILanczosScaleTransform") else { return image }
        filter.setValue(CIImage(cgImage: image), forKey: kCIInputImageKey)
        filter.setValue(min(3, 500 / shortSide), forKey: kCIInputScaleKey)
        filter.setValue(1.0, forKey: kCIInputAspectRatioKey)
        guard let output = filter.outputImage,
              let scaled = ciContext.createCGImage(output, from: output.extent) else { return image }
        return scaled
    }
}
