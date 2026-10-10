// Nictate: a macOS menu bar app that copies text from anywhere on your screen.
// Copyright (c) 2026 jrthormann. MIT License, see LICENSE.

import Foundation

/// A color in sRGB with components in 0...1.
struct RGBAColor: Equatable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double = 1

    private var bytes: (r: Int, g: Int, b: Int, a: Int) {
        (Int((red * 255).rounded()), Int((green * 255).rounded()), Int((blue * 255).rounded()), Int((alpha * 255).rounded()))
    }

    var hex: String {
        let c = bytes
        return alpha < 1 ? String(format: "#%02X%02X%02X%02X", c.r, c.g, c.b, c.a)
                         : String(format: "#%02X%02X%02X", c.r, c.g, c.b)
    }

    var rgb: String {
        let c = bytes
        return alpha < 1 ? "rgba(\(c.r), \(c.g), \(c.b), \(Self.trimmed(alpha, 2)))" : "rgb(\(c.r), \(c.g), \(c.b))"
    }

    var hsl: String {
        let top = max(red, green, blue), bottom = min(red, green, blue)
        let lightness = (top + bottom) / 2
        let delta = top - bottom
        var hue = 0.0, saturation = 0.0
        if delta > 0 {
            saturation = delta / (1 - abs(2 * lightness - 1))
            switch top {
            case red: hue = ((green - blue) / delta).truncatingRemainder(dividingBy: 6)
            case green: hue = (blue - red) / delta + 2
            default: hue = (red - green) / delta + 4
            }
            hue *= 60
            if hue < 0 { hue += 360 }
        }
        let h = Int(hue.rounded()) % 360, s = Int((saturation * 100).rounded()), l = Int((lightness * 100).rounded())
        return alpha < 1 ? "hsla(\(h), \(s)%, \(l)%, \(Self.trimmed(alpha, 2)))" : "hsl(\(h), \(s)%, \(l)%)"
    }

    /// "red: 1.0, green: 0.341, blue: 0.2", with the first label varying by framework.
    private func channels(first label: String) -> String {
        "\(label): \(Self.trimmed(red, 3)), green: \(Self.trimmed(green, 3)), blue: \(Self.trimmed(blue, 3))"
    }

    var swiftUI: String {
        "Color(\(channels(first: "red"))\(alpha < 1 ? ", opacity: \(Self.trimmed(alpha, 3))" : ""))"
    }

    var appKit: String { "NSColor(\(channels(first: "srgbRed")), alpha: \(Self.trimmed(alpha, 3)))" }

    var uiKit: String { "UIColor(\(channels(first: "red")), alpha: \(Self.trimmed(alpha, 3)))" }

    /// Every format a developer might want, in menu order.
    var formats: [(name: String, value: String)] {
        [("HEX", hex), ("RGB", rgb), ("HSL", hsl), ("SwiftUI Color", swiftUI), ("NSColor", appKit), ("UIColor", uiKit)]
    }

    /// "0.341", "1.0", "0.2": at most `decimals` places, trailing zeros dropped but one decimal kept.
    private static func trimmed(_ value: Double, _ decimals: Int) -> String {
        var text = String(format: "%.\(decimals)f", value)
        while text.hasSuffix("0") && !text.hasSuffix(".0") { text.removeLast() }
        return text
    }
}

struct DetectedColor: Equatable {
    let source: String
    let color: RGBAColor
}

struct Detections: Equatable {
    var colors: [DetectedColor] = []
    var links: [URL] = []
    var emails: [String] = []
    var phones: [String] = []

    var isEmpty: Bool { colors.isEmpty && links.isEmpty && emails.isEmpty && phones.isEmpty }
}

/// Finds colors, web links, email addresses and phone numbers in recognized text. Pure and local; nothing is opened here.
enum ContentDetector {
    static func detect(in text: String, limit: Int = 8) -> Detections {
        var result = Detections()
        var seenColors = Set<String>()
        for found in colors(in: text) where seenColors.insert(found.source.lowercased()).inserted {
            if result.colors.count < limit { result.colors.append(found) }
        }
        for item in linksAndEmails(in: text) {
            switch item {
            case .link(let url) where !result.links.contains(url) && result.links.count < limit: result.links.append(url)
            case .email(let address) where !result.emails.contains(address) && result.emails.count < limit: result.emails.append(address)
            default: break
            }
        }
        result.phones = phoneNumbers(in: text, limit: limit)
        return result
    }

    // MARK: Colors

    private static func regex(_ pattern: String) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }

    /// Pieces the color syntaxes have in common, so each pattern states only what makes it different.
    private enum Piece {
        static let number = #"[\d.]+%?"#
        /// Components are separated by a comma or by whitespace ("rgb(1, 2, 3)" or "rgb(1 2 3)").
        static let separator = #"\s*(?:,|\s)\s*"#
        /// Optional alpha: ", 0.5" or "/ 50%".
        static let alpha = #"(?:(?:,|/)\s*(\#(number))\s*)?"#
        /// A labelled component such as "green: 0.4".
        static func channel(_ label: String) -> String { #"\#(label):\s*([\d.]+)\s*"# }
    }

    private static let hexPattern = regex(#"(?<![\w#])#([0-9a-f]{3,4}|[0-9a-f]{6}|[0-9a-f]{8})(?!\w)"#)
    private static let rgbPattern = regex(#"\brgba?\(\s*(\#(Piece.number))\#(Piece.separator)(\#(Piece.number))\#(Piece.separator)(\#(Piece.number))\s*\#(Piece.alpha)\)"#)
    private static let hslPattern = regex(#"\bhsla?\(\s*(-?[\d.]+)(?:deg)?\#(Piece.separator)([\d.]+)%\#(Piece.separator)([\d.]+)%\s*\#(Piece.alpha)\)"#)
    private static let applePattern = regex(#"\b(?:UIColor|NSColor|Color)\(\s*(?:srgbRed|red):\s*([\d.]+)\s*,\s*\#(Piece.channel("green")),\s*\#(Piece.channel("blue"))(?:,\s*(?:alpha|opacity):\s*([\d.]+)\s*)?\)"#)

    private static func colors(in text: String) -> [DetectedColor] {
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        var found: [(location: Int, color: DetectedColor)] = []

        func collect(_ pattern: NSRegularExpression, _ build: (_ groups: [String], _ location: Int) -> RGBAColor?) {
            for match in pattern.matches(in: text, range: full) {
                let groups = (1..<match.numberOfRanges).map { index -> String in
                    let r = match.range(at: index)
                    return r.location == NSNotFound ? "" : ns.substring(with: r)
                }
                if let color = build(groups, match.range.location) {
                    found.append((match.range.location, DetectedColor(source: ns.substring(with: match.range), color: color)))
                }
            }
        }
        // Every color syntax needs a "#" or an opening parenthesis; most text has neither.
        if text.contains("#") {
            collect(hexPattern) { groups, location in isHexColor(groups[0], at: location, in: ns) ? hexColor(groups[0]) : nil }
        }
        if text.contains("(") {
            collect(rgbPattern) { groups, _ in rgbColor(groups) }
            collect(hslPattern) { groups, _ in hslColor(groups) }
            collect(applePattern) { groups, _ in appleColor(groups) }
        }
        return found.sorted { $0.location < $1.location }.map(\.color)
    }

    private static func hexColor(_ digits: String) -> RGBAColor? {
        var chars = Array(digits)
        if chars.count <= 4 { chars = chars.flatMap { [$0, $0] } }       // #RGB / #RGBA -> doubled digits
        let values = stride(from: 0, to: chars.count, by: 2).compactMap { UInt8(String(chars[$0...$0 + 1]), radix: 16) }
        guard values.count == chars.count / 2, values.count >= 3 else { return nil }
        return RGBAColor(red: Double(values[0]) / 255, green: Double(values[1]) / 255, blue: Double(values[2]) / 255,
                         alpha: values.count == 4 ? Double(values[3]) / 255 : 1)
    }

    /// "#123" and "#1234" are usually issue or pull request numbers, so a short hex made only of decimal
    /// digits counts as a color only in a color context: a ":" or "=" just before it, spaces aside, as in
    /// "color: #123" or fill="#123". Six and eight digit forms and any short form with a letter a-f always count.
    private static func isHexColor(_ digits: String, at location: Int, in text: NSString) -> Bool {
        guard digits.count <= 4, digits.allSatisfy({ ("0"..."9").contains($0) }) else { return true }
        var index = location - 1
        while index >= 0, [0x20, 0x09, 0x22, 0x27].contains(text.character(at: index)) { index -= 1 }   // space, tab, quotes
        guard index >= 0 else { return false }
        return [0x3A, 0x3D].contains(text.character(at: index))                                       // ":" or "="
    }

    /// A 0...1 value from "0.5", "50%" (percent) or, when `scale` is given, "128" out of `scale`.
    private static func unit(_ text: String, scale: Double? = nil) -> Double? {
        if text.hasSuffix("%") { return Double(text.dropLast()).map { $0 / 100 }.flatMap { (0...1).contains($0) ? $0 : nil } }
        guard let value = Double(text) else { return nil }
        let scaled = scale.map { value / $0 } ?? value
        return (0...1).contains(scaled) ? scaled : nil
    }

    private static func alpha(_ text: String) -> Double? { text.isEmpty ? 1 : unit(text) }

    private static func rgbColor(_ g: [String]) -> RGBAColor? {
        guard let r = unit(g[0], scale: 255), let gr = unit(g[1], scale: 255), let b = unit(g[2], scale: 255),
              let a = alpha(g[3]) else { return nil }
        return RGBAColor(red: r, green: gr, blue: b, alpha: a)
    }

    private static func hslColor(_ g: [String]) -> RGBAColor? {
        guard let hue = Double(g[0]), let s = Double(g[1]), let l = Double(g[2]), s <= 100, l <= 100,
              let a = alpha(g[3]) else { return nil }
        let (sat, light) = (s / 100, l / 100)
        let chroma = (1 - abs(2 * light - 1)) * sat
        let h = (hue.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) / 60
        let x = chroma * (1 - abs(h.truncatingRemainder(dividingBy: 2) - 1))
        let (r1, g1, b1): (Double, Double, Double)
        switch Int(h) {
        case 0: (r1, g1, b1) = (chroma, x, 0)
        case 1: (r1, g1, b1) = (x, chroma, 0)
        case 2: (r1, g1, b1) = (0, chroma, x)
        case 3: (r1, g1, b1) = (0, x, chroma)
        case 4: (r1, g1, b1) = (x, 0, chroma)
        default: (r1, g1, b1) = (chroma, 0, x)
        }
        let match = light - chroma / 2
        return RGBAColor(red: r1 + match, green: g1 + match, blue: b1 + match, alpha: a)
    }

    private static func appleColor(_ g: [String]) -> RGBAColor? {
        guard let r = unit(g[0]), let gr = unit(g[1]), let b = unit(g[2]), let a = alpha(g[3]) else { return nil }
        return RGBAColor(red: r, green: gr, blue: b, alpha: a)
    }

    // MARK: Phone numbers

    private static let phoneDetector = try! NSDataDetector(types: NSTextCheckingResult.CheckingType.phoneNumber.rawValue)
    /// How long one capture may spend looking for phone numbers.
    static let phoneBudget: Duration = .milliseconds(50)

    /// A phone number needs at least seven digits, so text without them skips the system detector.
    private static func hasSevenDigits(_ text: String) -> Bool {
        var count = 0
        for byte in text.utf8 where byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9") {
            count += 1
            if count == 7 { return true }
        }
        return false
    }

    /// Numbers as written on screen, in order, without repeats. The system detector scans its whole range
    /// before reporting (850 ms on 20,000 characters of digits, and stopping early saves nothing), so the
    /// text is read in chunks that end at whitespace, and reading stops at `limit` numbers or after `budget`.
    /// The budget is measured on ContinuousClock, so a wall clock change during a scan cannot stretch or cut it.
    static func phoneNumbers(in text: String, limit: Int, budget: Duration = phoneBudget) -> [String] {
        guard hasSevenDigits(text) else { return [] }
        let ns = text as NSString
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: budget)
        let chunk = 1_500
        var found: [String] = []
        var location = 0
        while location < ns.length, found.count < limit, clock.now < deadline {
            var end = min(location + chunk, ns.length)
            if end < ns.length {
                let space = ns.rangeOfCharacter(from: .whitespacesAndNewlines, options: .backwards,
                                                range: NSRange(location: location, length: end - location))
                if space.location != NSNotFound, space.location > location { end = space.location }
            }
            phoneDetector.enumerateMatches(in: text, options: [], range: NSRange(location: location, length: end - location)) { match, _, stop in
                guard let match, match.phoneNumber != nil else { return }
                let written = ns.substring(with: match.range).trimmingCharacters(in: .whitespaces)
                if !found.contains(written) { found.append(written) }
                if found.count >= limit { stop.pointee = true }
            }
            location = end
        }
        return found
    }

    // MARK: Links and emails

    private enum LinkItem { case link(URL), email(String) }

    private static let linkDetector = try! NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    /// One pass over the bytes for the markers a link or email needs ("@", "http", "www."), ignoring ASCII
    /// case. The system detector is the costliest step, and Foundation's case-insensitive search costs
    /// more than the detector it would save.
    private static func mayContainLink(_ text: String) -> Bool {
        var recent: UInt32 = 0
        for byte in text.utf8 {
            if byte == UInt8(ascii: "@") { return true }
            recent = (recent << 8) | UInt32(byte | 0x20)          // fold ASCII letters to lower case
            if recent == 0x6874_7470 || recent == 0x7777_772E { return true }   // "http", "www."
        }
        return false
    }

    /// Only explicit web links count ("http(s)://" or "www."), so file names such as "main.py" are ignored.
    private static func linksAndEmails(in text: String) -> [LinkItem] {
        guard mayContainLink(text) else { return [] }
        let ns = text as NSString
        return linkDetector.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap { match in
            guard let url = match.url else { return nil }
            let matched = ns.substring(with: match.range)
            switch url.scheme?.lowercased() {
            case "http", "https":
                let lower = matched.lowercased()
                return lower.hasPrefix("http://") || lower.hasPrefix("https://") || lower.hasPrefix("www.") ? .link(url) : nil
            case "mailto":
                // Only the address: a matched "mailto:" link may carry a query (bcc, body) that must not
                // reach the Write Email action or the copied address.
                guard let address = URLComponents(url: url, resolvingAgainstBaseURL: false)?.path,
                      address.contains("@") else { return nil }
                return .email(address)
            default:
                return nil
            }
        }
    }
}
