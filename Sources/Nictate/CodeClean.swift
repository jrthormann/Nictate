// Nictate: a macOS menu bar app that copies text from anywhere on your screen.
// Copyright (c) 2026 jrthormann. MIT License, see LICENSE.

import Foundation

struct CodeCleanOptions: Equatable {
    var stripPrompts = true
    var stripLineNumbers = true
    var straightenQuotes = true
}

/// Removes the noise OCR picks up when capturing code: terminal prompts, a line-number gutter and
/// typographic quotes. Indentation is always preserved.
enum CodeClean {
    static func apply(_ text: String, _ options: CodeCleanOptions) -> String {
        var lines = text.components(separatedBy: "\n")
        if options.stripLineNumbers { lines = removingLineNumbers(lines) }   // before prompts: "1  $ ls"
        if options.stripPrompts { lines = removingPrompts(lines) }
        let joined = lines.joined(separator: "\n")
        return options.straightenQuotes ? straightenedQuotes(joined) : joined
    }

    // MARK: Prompts

    /// Each pattern captures leading whitespace in group 1 so indentation survives.
    private static let promptPatterns: [NSRegularExpression] = [
        #"^(\s*)\$(?: |$)"#,                                      // "$ ls"
        #"^(\s*)[\w.\-]+@[\w.\-]+(?::\S*|\s+\S+)?\s*[$#%>] "#,    // "me@mac:~$ ", "root@srv:/# ", "me@mac ~ % "
        #"^(\s*)PS [^>\n]*> "#,                                    // PowerShell
        #"^(\s*)[A-Za-z]:\\[^>\n]*> "#,                            // cmd.exe
        #"^(\s*)>>> "#,                                            // Python REPL
    ].map { try! NSRegularExpression(pattern: $0) }

    /// "... " only counts as a prompt inside a Python REPL session (one that has ">>> " lines).
    private static let replContinuation = try! NSRegularExpression(pattern: #"^(\s*)\.\.\. ?"#)

    private static func removingPrompts(_ lines: [String]) -> [String] {
        let isRepl = lines.contains { $0.trimmingCharacters(in: .whitespaces).hasPrefix(">>> ") }
        let patterns = isRepl ? promptPatterns + [replContinuation] : promptPatterns
        return lines.map { line in
            let range = NSRange(line.startIndex..., in: line)
            for pattern in patterns where pattern.firstMatch(in: line, range: range) != nil {
                return pattern.stringByReplacingMatches(in: line, range: range, withTemplate: "$1")
            }
            return line
        }
    }

    // MARK: Line numbers

    private static let numberedLine = try! NSRegularExpression(
        pattern: #"^([ \t]*)(\d{1,5})(?:[ \t]*([|:])[ \t]?|([ \t]+))(.*)$"#)
    private static let bareNumber = try! NSRegularExpression(pattern: #"^[ \t]*(\d{1,5})[ \t]*$"#)

    private struct NumberedLine {
        let number: Int
        /// Column where the code starts, for whitespace gutters ("12   code"); nil for "|", ":" or a bare number.
        let contentColumn: Int?
        let content: String
    }

    private static func parseNumbered(_ line: String) -> NumberedLine? {
        let ns = line as NSString
        let full = NSRange(location: 0, length: ns.length)
        if let m = bareNumber.firstMatch(in: line, range: full) {
            return NumberedLine(number: Int(ns.substring(with: m.range(at: 1))) ?? 0, contentColumn: nil, content: "")
        }
        guard let m = numberedLine.firstMatch(in: line, range: full) else { return nil }
        let digits = ns.substring(with: m.range(at: 2))
        let gutter = m.range(at: 4)
        let column = gutter.location == NSNotFound ? nil : m.range(at: 1).length + digits.count + gutter.length
        return NumberedLine(number: Int(digits) ?? 0, contentColumn: column, content: ns.substring(with: m.range(at: 5)))
    }

    /// Strips a line-number gutter. Numbers count only if they form an increasing chain in which each
    /// jump is no larger than the number of lines between them. That tolerates numbers the OCR missed
    /// and wrapped lines, and ignores code lines that merely start with a digit. At least three must
    /// line up and cover half the text. "1." and "1)" are never touched: those are list markers.
    private static func removingLineNumbers(_ lines: [String]) -> [String] {
        let parsed = lines.map(parseNumbered)
        let gutterLines = longestNumberChain(parsed)
        let nonEmptyCount = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count
        guard gutterLines.count >= 3, gutterLines.count * 2 >= nonEmptyCount else { return lines }

        // Code starts at the narrowest content column; anything further right is the code's own indentation.
        let gutterWidth = gutterLines
            .compactMap { index in parsed[index].flatMap { $0.content.isEmpty ? nil : $0.contentColumn } }
            .min()

        return lines.indices.map { index in
            let line = lines[index]
            if gutterLines.contains(index), let entry = parsed[index] {
                let indent = entry.contentColumn.map { $0 - (gutterWidth ?? $0) } ?? 0
                return String(repeating: " ", count: max(indent, 0)) + entry.content
            }
            // A line without a number (wrapped or missed by OCR) still carries the gutter as leading space.
            if let gutterWidth, line.count >= gutterWidth, line.prefix(gutterWidth).allSatisfy({ $0 == " " }) {
                return String(line.dropFirst(gutterWidth))
            }
            return line
        }
    }

    /// Indices of the longest run of numbered lines that is plausibly one gutter.
    private static func longestNumberChain(_ parsed: [NumberedLine?]) -> Set<Int> {
        let numbered = parsed.enumerated().compactMap { index, entry in entry.map { (index: index, number: $0.number) } }
        var length = [Int](repeating: 1, count: numbered.count)
        var previous = [Int?](repeating: nil, count: numbered.count)
        for i in numbered.indices {
            for j in 0..<i {
                let step = numbered[i].number - numbered[j].number
                if step > 0, step <= numbered[i].index - numbered[j].index, length[j] + 1 > length[i] {
                    length[i] = length[j] + 1
                    previous[i] = j
                }
            }
        }
        guard let end = length.indices.max(by: { length[$0] < length[$1] }) else { return [] }
        var chain: Set<Int> = []
        var cursor: Int? = end
        while let i = cursor {
            chain.insert(numbered[i].index)
            cursor = previous[i]
        }
        return chain
    }

    // MARK: Quotes

    private static let quoteMap: [Character: Character] = [
        "\u{201C}": "\"", "\u{201D}": "\"", "\u{2018}": "'", "\u{2019}": "'",
    ]

    private static func straightenedQuotes(_ text: String) -> String {
        String(text.map { quoteMap[$0] ?? $0 })
    }
}
