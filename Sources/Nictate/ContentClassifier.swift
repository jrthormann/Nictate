// Nictate: a macOS menu bar app that copies text from anywhere on your screen.
// Copyright (c) 2026 jrthormann. MIT License, see LICENSE.

import CoreGraphics
import Foundation

enum TextKind: Equatable, Sendable {
    case code, table, list, prose
}

struct Classification: Equatable, Sendable {
    let kind: TextKind
    /// 0...1. Below `ContentClassifier.threshold` the kind is a guess.
    let confidence: Double
}

/// Decides what a capture holds, from its text and its layout. Pure: no Vision, no AppKit.
enum ContentClassifier {
    static let threshold = 0.6

    static func classify(_ fragments: [TextFragment], text: String, imageSize: CGSize) -> Classification {
        let lines = text.split(separator: "\n").map(String.init).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard lines.count >= 2 else { return Classification(kind: .prose, confidence: 0) }

        let code = codeLikelihood(lines)
        if code >= threshold { return Classification(kind: .code, confidence: code) }
        let table = tableLikelihood(lines, fragments: fragments, imageSize: imageSize)
        let list = listLikelihood(lines)
        let best = table >= list ? (TextKind.table, table) : (TextKind.list, list)
        if best.1 >= threshold { return Classification(kind: best.0, confidence: best.1) }
        return Classification(kind: .prose, confidence: proseLikelihood(lines))
    }

    /// Only confident prose may lose its line breaks. Code, tables and lists always keep them, and so does
    /// any guess, which is never wrong, only less tidy.
    static func joinsParagraphs(_ classification: Classification) -> Bool {
        classification.kind == .prose && classification.confidence >= threshold
    }

    // MARK: Signals

    private static let symbols = CharacterSet(charactersIn: "{}();=<>[]")
    /// Keywords that start a line in code, shell-free SQL, or a quoted JSON key. Ordinary words such as "for"
    /// or "if" in prose do not count unless they open a call, like `if (`.
    private static let keyword = try! NSRegularExpression(
        pattern: #"^\s*(func|def|let|var|const|return|import|class|struct|fn|#include|SELECT|FROM|WHERE|ORDER BY|GROUP BY|JOIN)\b|\b(if|for|while)\s*\(|=>|->|^\s*"[^"]+"\s*:|^\s*[A-Za-z_][\w.]*\s*[-+*/]?=\s*\S|^\s*<\/?[A-Za-z]"#)
    /// Command-line tools at the start of a line: a pasted shell script, prompt or not.
    private static let command = try! NSRegularExpression(
        pattern: #"^\s*(pip3?|npm|yarn|git|sudo|brew|cargo|make|swift|python3?|cd|ls|curl|docker)\s"#)
    private static let prompt = try! NSRegularExpression(pattern: #"^\s*(\$|%|>>>|>|#)\s"#)
    private static let gutter = try! NSRegularExpression(pattern: #"^\s*\d{1,4}(\s{1,}|[|:.)]\s?)"#)
    private static let gap = try! NSRegularExpression(pattern: #"\S( {2,}|\t)\S"#)
    private static let bullet = try! NSRegularExpression(pattern: #"^\s*([-*•·▪●◦]|\d{1,3}[.)]|[a-zA-Z][.)])\s+\S"#)

    private static func share(_ lines: [String], where pattern: NSRegularExpression) -> Double {
        let hits = lines.filter { matches(pattern, $0) }.count
        return Double(hits) / Double(lines.count)
    }

    private static func matches(_ pattern: NSRegularExpression, _ line: String) -> Bool {
        pattern.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil
    }

    /// Symbols per visible character, keywords, lines that end a statement, indentation, shell prompts and
    /// line-number gutters. A terminal paste (prompts) or a numbered listing alone is not enough to decide.
    private static func codeLikelihood(_ lines: [String]) -> Double {
        let visible = lines.joined().filter { !$0.isWhitespace }
        let symbolCount = visible.unicodeScalars.filter { symbols.contains($0) }.count
        let symbolShare = visible.isEmpty ? 0 : Double(symbolCount) / Double(visible.count)
        let ends = lines.filter { $0.trimmingCharacters(in: .whitespaces).last.map { "{};)]>".contains($0) } ?? false }
        let indented = lines.filter { $0.hasPrefix("  ") || $0.hasPrefix("\t") }
        // Each signal is its own term: one long sum of mixed literals overruns the type checker on Swift 6.
        let symbolTerm: Double = 0.2 * min(1, symbolShare / 0.05)
        let keywordTerm: Double = 0.4 * min(1, share(lines, where: keyword) / 0.25)
        let commandTerm: Double = 0.3 * min(1, share(lines, where: command) / 0.5)
        let endTerm: Double = 0.15 * min(1, Double(ends.count) / Double(lines.count) / 0.25)
        let indentTerm: Double = 0.05 * min(1, Double(indented.count) / Double(lines.count) / 0.3)
        let promptTerm: Double = 0.6 * min(1, share(lines, where: prompt) / 0.5)
        let gutterTerm: Double = 0.25 * min(1, share(lines, where: gutter) / 0.5)
        let score: Double = symbolTerm + keywordTerm + commandTerm + endTerm + indentTerm + promptTerm + gutterTerm
        return min(1, score)
    }

    /// Lines with cells separated by two or more spaces or a tab. Layout rows found by the reader count too.
    private static func tableLikelihood(_ lines: [String], fragments: [TextFragment], imageSize: CGSize) -> Double {
        let rows = share(lines, where: gap)
        let layoutRows = fragments.isEmpty ? 0 : TextLayout.multiCellRows(fragments, imageSize: imageSize)
        if layoutRows >= 3 && rows >= 0.5 { return 1 }
        return min(1, rows / 0.8)
    }

    private static func listLikelihood(_ lines: [String]) -> Double {
        min(1, share(lines, where: bullet) / 0.7)
    }

    /// Long lines that end in punctuation read as prose. Short labels and headings do not.
    private static func proseLikelihood(_ lines: [String]) -> Double {
        let average = Double(lines.reduce(0) { $0 + $1.count }) / Double(lines.count)
        let ended = lines.filter { $0.last.map { ".!?:;".contains($0) } ?? false }.count
        let endShare = Double(ended) / Double(lines.count)
        return min(1, average / 50) * (0.5 + 0.5 * endShare)
    }
}
