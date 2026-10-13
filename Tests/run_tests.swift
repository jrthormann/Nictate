// Nictate: a macOS menu bar app that copies text from anywhere on your screen.
// Copyright (c) 2026 jrthormann. MIT License, see LICENSE.

import AppKit
import Combine
import CryptoKit
import SwiftUI
import Carbon.HIToolbox
import Foundation

// Minimal dependency-free test runner (no Xcode needed). Run: Tests/run_tests.sh
// Arguments filter the checks: `build/run_tests history shortcut` reports only the checks whose name
// contains one of the words, ignoring case. The code of every test still runs; only the reports are filtered.
let nameFilters = CommandLine.arguments.dropFirst().map { $0.lowercased() }
var passes = 0
var failedChecks: [String] = []
@MainActor
func check(_ ok: Bool, _ name: String, _ detail: @autoclosure () -> String = "", file: StaticString = #fileID, line: UInt = #line) {
    guard nameFilters.isEmpty || nameFilters.contains(where: name.lowercased().contains) else { return }
    if ok { passes += 1; print("PASS  \(name)"); return }
    // run_tests.sh compiles a verbatim copy named main.swift, so its line numbers are this file's.
    let fileName = ("\(file)" as NSString).lastPathComponent
    let location = "\(fileName == "main.swift" ? "Tests/run_tests.swift" : fileName):\(line)"
    failedChecks.append("\(location)  \(name)")
    print("FAIL  \(location)  \(name) \(detail())")
}

/// The repository root, found from where the runner lives (`build/run_tests`) rather than from the working
/// directory, so the runner works when started from anywhere. `#filePath` is only a fallback: run_tests.sh
/// passes a relative path to swiftc, and a runner built on one machine can run on another (CI does).
let repoRoot: URL? = {
    let isRoot = { (url: URL) in FileManager.default.fileExists(atPath: url.appendingPathComponent("Sources/Nictate/Resources/en.lproj").path)
                                 && FileManager.default.fileExists(atPath: url.appendingPathComponent("Tests/run_tests.swift").path) }
    var starts: [URL] = []
    if let executable = Bundle.main.executableURL { starts.append(executable.resolvingSymlinksInPath().deletingLastPathComponent()) }
    let source = "\(#filePath)"
    if source.hasPrefix("/") { starts.append(URL(fileURLWithPath: source).deletingLastPathComponent()) }
    for start in starts {
        var url = start.standardizedFileURL
        while url.path != "/" {
            if isRoot(url) { return url }
            url.deleteLastPathComponent()
        }
    }
    return nil
}()

/// A preferences suite of its own for one test, named uniquely so that runs in parallel never share
/// values and the user's own preferences are never read or written. A suite named by an absolute path is
/// stored at that path, so every suite of a run lives in one temporary folder, deleted at the end: suites
/// in ~/Library/Preferences would leave an empty plist behind even after being emptied.
let testPreferences = FileManager.default.temporaryDirectory.appendingPathComponent("nictate-tests-\(UUID().uuidString)")
try? FileManager.default.createDirectory(at: testPreferences, withIntermediateDirectories: true)
struct TestSuite {
    let name: String
    let defaults: UserDefaults
    /// Empties the suite, for a test that needs to start over within its block.
    func wipe() { defaults.removePersistentDomain(forName: name) }
}
var testSuites: [TestSuite] = []
/// Runs an async History call to completion from the test's main thread.
@MainActor func settle(_ work: @escaping @MainActor () async -> Void) {
    var finished = false
    Task { await work(); finished = true }
    while !finished { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01)) }
}

/// Lets work already handed to the main actor run, by spinning the main run loop a few times.
@MainActor func drainMain() {
    for _ in 0..<5 { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01)) }
}

/// A store whose answers the test scripts: each load returns the next scripted result, and saves are counted.
/// Only the test's main thread changes it, and only after the I/O queue has been flushed.
final class ScriptedStore: HistoryStore, @unchecked Sendable {
    var answers: [HistoryLoad]
    var saved: HistorySnapshot?
    var loads = 0
    var saves = 0
    /// False makes every write fail, as a full disk would.
    var writesSucceed = true
    /// What a failing write reports. `.unconfirmed` stands for a write that landed but did not read back, so it is kept.
    var failure: HistoryPersistOutcome = .notWritten
    init(answers: [HistoryLoad], saved: HistorySnapshot? = nil) {
        self.answers = answers
        self.saved = saved
    }
    func load() -> HistoryLoad {
        loads += 1
        guard answers.count > 1 else { return answers.first ?? .unavailable }
        return answers.removeFirst()
    }
    func save(_ snapshot: HistorySnapshot) -> HistoryPersistOutcome {
        saves += 1
        guard writesSucceed else {
            if failure == .unconfirmed { saved = snapshot }
            return failure
        }
        saved = snapshot
        return .confirmed
    }
}

/// Saving is on for the history these tests build; the setting itself is not read.
let alwaysSaving: @Sendable () -> Bool = { true }

/// A history file of its own under the test folder. Each call is a new file, so tests never share one.
func sealedStore(_ tag: String) -> JSONHistoryStore {
    JSONHistoryStore(fileURL: testPreferences.appendingPathComponent("\(tag)-\(UUID().uuidString).json"))
}
@MainActor
func freshSuite(_ tag: String) -> TestSuite {
    let name = testPreferences.appendingPathComponent("nictate.test.\(tag).\(UUID().uuidString)").path
    let suite = TestSuite(name: name, defaults: UserDefaults(suiteName: name)!)
    suite.wipe()
    testSuites.append(suite)
    return suite
}
func frag(_ t: String, x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat = 0.05) -> TextFragment {
    TextFragment(text: t, box: CGRect(x: x, y: y, width: w, height: h))
}
let size = CGSize(width: 1000, height: 1000)

// TextLayout: reading order top-to-bottom, indentation from x offsets (char width = 0.01 * 1000 / 1 = 10px).
let code = [
    frag("func a() {", x: 0.10, y: 0.90, w: 0.10),            // 10 chars -> 10 px/char
    frag("let x = 1", x: 0.14, y: 0.80, w: 0.09),             // +4 chars indent
    frag("if x {", x: 0.14, y: 0.70, w: 0.06),
    frag("go()", x: 0.18, y: 0.60, w: 0.04),                  // +8 chars indent
    frag("}", x: 0.14, y: 0.50, w: 0.01),
    frag("}", x: 0.10, y: 0.40, w: 0.01),
].shuffled()
let composed = TextLayout.compose(code, imageSize: size, keepLineBreaks: true, preserveIndentation: true)
check(composed == "func a() {\n    let x = 1\n    if x {\n        go()\n    }\n}", "layout keeps order and indentation", composed)
check(TextLayout.compose(code, imageSize: size, keepLineBreaks: true, preserveIndentation: false)
      == "func a() {\nlet x = 1\nif x {\ngo()\n}\n}", "layout without indentation")
check(TextLayout.compose(code, imageSize: size, keepLineBreaks: false, preserveIndentation: true)
      == "func a() { let x = 1 if x { go() } }", "layout joined into one line")
check(TextLayout.compose([], imageSize: size, keepLineBreaks: true, preserveIndentation: true) == "", "layout empty")
let sameLine = [frag("a", x: 0.10, y: 0.5, w: 0.01), frag("b", x: 0.30, y: 0.505, w: 0.01)]
check(TextLayout.compose(sameLine, imageSize: size, keepLineBreaks: true, preserveIndentation: false) == "a b", "same-line fragments merge")

// Vertical gaps: a paragraph gap on screen becomes a blank line.
let gaps = [frag("a", x: 0.1, y: 0.90, w: 0.01), frag("b", x: 0.1, y: 0.80, w: 0.01), frag("c", x: 0.1, y: 0.60, w: 0.01)]
check(TextLayout.compose(gaps, imageSize: size, keepLineBreaks: true, preserveIndentation: false) == "a\nb\n\nc", "layout keeps paragraph gap")
check(TextLayout.compose(gaps, imageSize: size, keepLineBreaks: false, preserveIndentation: false) == "a b c", "single-line mode ignores gaps")

// Columns: long-line text in two baseline-aligned columns reads column by column.
func longLine(_ tag: String) -> String { tag + String(repeating: "x", count: 28) }
var twoCols: [TextFragment] = []
for i in 0..<4 {
    let y = 0.9 - CGFloat(i) * 0.1
    twoCols.append(frag(longLine("L\(i)"), x: 0.05, y: y, w: 0.30))
    twoCols.append(frag(longLine("R\(i)"), x: 0.60, y: y, w: 0.30))
}
let colsExpected = (0..<4).map { longLine("L\($0)") }.joined(separator: "\n") + "\n\n" + (0..<4).map { longLine("R\($0)") }.joined(separator: "\n")
check(TextLayout.compose(twoCols.shuffled(), imageSize: size, keepLineBreaks: true, preserveIndentation: false) == colsExpected, "two text columns read one after the other")
check(TextLayout.compose(twoCols, imageSize: size, keepLineBreaks: true, preserveIndentation: false, detectColumns: false)
      .hasPrefix(longLine("L0") + " "), "columns detection can be disabled")

// Tables: short aligned cells stay row-wise with their padding.
let rows = [("name", "age"), ("ann", "31"), ("bob", "42")]
var table: [TextFragment] = []
for (i, row) in rows.enumerated() {
    let y = 0.9 - CGFloat(i) * 0.1
    table.append(frag(row.0, x: 0.1, y: y, w: CGFloat(row.0.count) * 0.01))
    table.append(frag(row.1, x: 0.6, y: y, w: CGFloat(row.1.count) * 0.01))
}
let tableExpected = rows.map { r in r.0 + String(repeating: " ", count: Int((600 - (100 + CGFloat(r.0.count) * 10)) / 10)) + r.1 }.joined(separator: "\n")
check(TextLayout.compose(table, imageSize: size, keepLineBreaks: true, preserveIndentation: true) == tableExpected, "table keeps rows and padding")

// TextCleaner
check(TextCleaner.finalize("  hola \n", preserveIndentation: false, dehyphenate: false, collapseSpaces: false) == "hola", "trim plain")
check(TextCleaner.finalize("\n    if x {\n        y()  \n    }\n\n", preserveIndentation: true, dehyphenate: false, collapseSpaces: false)
      == "    if x {\n        y()\n    }", "code keeps first-line indent")
check(TextCleaner.finalize("inter-\nnacional", preserveIndentation: false, dehyphenate: true, collapseSpaces: false) == "internacional", "dehyphenate")
check(TextCleaner.finalize("a-\nB", preserveIndentation: false, dehyphenate: true, collapseSpaces: false) == "a-\nB", "dehyphenate skips capitals")
check(TextCleaner.finalize("a   b  c", preserveIndentation: false, dehyphenate: false, collapseSpaces: true) == "a b c", "collapse spaces")
check(TextCleaner.finalize("a   b", preserveIndentation: true, dehyphenate: true, collapseSpaces: true) == "a   b", "code mode never collapses")
let symbols = "{ } [ ] ( ) < > + - * / = == != === && || ! % & ^ | ~ ? : ; . , ` ' \" \\ _ # $ @"
check(TextCleaner.finalize(symbols, preserveIndentation: false, dehyphenate: true, collapseSpaces: false) == symbols, "symbols untouched")
check(TextCleaner.appended(existing: nil, new: "b", delimiter: "\n") == "b", "append to empty")
check(TextCleaner.appended(existing: "", new: "b", delimiter: "\n") == "b", "append to blank")
check(TextCleaner.appended(existing: "a", new: "b", delimiter: " ") == "a b", "append with delimiter")

// Code-Clean
let allOn = CodeCleanOptions()
func clean(_ t: String, _ o: CodeCleanOptions = allOn) -> String { CodeClean.apply(t, o) }
check(clean("$ ls -la\n$ cd src") == "ls -la\ncd src", "prompt: dollar")
check(clean(">>> x = 1\n... y = 2\n>>> print(x)") == "x = 1\ny = 2\nprint(x)", "prompt: python repl and continuation")
check(clean("jose@mac:~/dev$ git status") == "git status", "prompt: user@host:path$")
check(clean("root@srv:/# apt update") == "apt update", "prompt: root #")
check(clean("me@mac ~ % ls") == "ls", "prompt: zsh style")
check(clean("PS C:\\Users\\me> Get-Date") == "Get-Date", "prompt: powershell")
check(clean("C:\\Users\\me> dir") == "dir", "prompt: cmd")
check(clean("  $ ls") == "  ls", "prompt keeps indentation")
check(clean("$") == "", "prompt: lone dollar")
check(clean("$x = 5\n# comment\n... and then") == "$x = 5\n# comment\n... and then", "prompt: no false positives")
check(clean("1  let x = 5\n2  let y = 6\n3  print(x)") == "let x = 5\nlet y = 6\nprint(x)", "line numbers: whitespace gutter")
check(clean("1  def f():\n2      return 1\n3  f()") == "def f():\n    return 1\nf()", "line numbers keep indentation")
check(clean("1 | a\n2 | b\n3 | c") == "a\nb\nc", "line numbers: pipe gutter")
check(clean("1  a\n2\n3  b") == "a\n\nb", "line numbers: blank numbered line")
check(clean("1. Install\n2. Run\n3. Done") == "1. Install\n2. Run\n3. Done", "line numbers: leaves numbered lists")
check(clean("1  a\n2  b") == "1  a\n2  b", "line numbers: needs three lines")
check(clean("5  a\n9  b\n2  c") == "5  a\n9  b\n2  c", "line numbers: needs consecutive numbers")
check(clean(" 9  a\n10  b\n11  c") == "a\nb\nc", "line numbers: right-aligned numbers")
check(clean("37  x\n38  y\n39  z") == "x\ny\nz", "line numbers: selection starting mid-file")
check(clean("1  a\n2  b\n3  3 + x") == "a\nb\n3 + x", "line numbers: code lines starting with a digit survive")
check(clean("    def f():\n2       a = 1\n3       return a\n4   f()") == "def f():\n    a = 1\n    return a\nf()", "line numbers: tolerates numbers the OCR missed")
check(clean("1  a\n   wrapped\n2  b\n3  c") == "a\nwrapped\nb\nc", "line numbers: unnumbered lines lose the gutter")
check(clean("\u{201C}hi\u{201D} \u{2018}x\u{2019} don\u{2019}t") == "\"hi\" 'x' don't", "typographic quotes straightened")
check(clean("1  $ ls\n2  $ pwd\n3  echo \u{201C}hi\u{201D}") == "ls\npwd\necho \"hi\"", "all three together")
check(clean("$ ls \u{201C}a\u{201D}", CodeCleanOptions(stripPrompts: false, stripLineNumbers: true, straightenQuotes: false)) == "$ ls \u{201C}a\u{201D}", "options can be switched off")

// Column safety: parallel blocks on a 1000x1000 canvas, 10 px per character, Vision-style boxes
// (leading spaces are not part of a box). Faithful mode, so indentation is checked too.
func colBlock(_ lines: [String], x: CGFloat, top: CGFloat, pitch: CGFloat = 40) -> [TextFragment] {
    lines.enumerated().compactMap { i, line in
        let text = line.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        let indent = CGFloat(line.prefix { $0 == " " }.count)
        return TextFragment(text: text, box: CGRect(x: (x + indent * 10) / 1000, y: (1000 - top - CGFloat(i) * pitch - 30) / 1000,
                                                    width: CGFloat(text.count) * 10 / 1000, height: 30 / 1000))
    }
}
func faithful(_ f: [TextFragment]) -> String {
    TextLayout.compose(f.shuffled(), imageSize: CGSize(width: 1000, height: 1000), keepLineBreaks: true, preserveIndentation: true)
}
let swiftBlock = ["func load() {", "    let a = 1", "    if a > 0 {", "        run(a)", "    }", "}"]
let structBlock = ["struct Box {", "    var w = 2", "}"]

check(faithful(colBlock(swiftBlock, x: 40, top: 100) + colBlock(structBlock, x: 560, top: 100))
      == swiftBlock.joined(separator: "\n") + "\n\n" + structBlock.joined(separator: "\n"), "columns: side-by-side code blocks keep their indentation")

let banner = "Release notes for version two plus a long subtitle that crosses both columns"
check(faithful(colBlock([banner], x: 40, top: 40) + colBlock(swiftBlock, x: 40, top: 120) + colBlock(structBlock, x: 560, top: 120))
      == banner + "\n\n" + swiftBlock.joined(separator: "\n") + "\n\n" + structBlock.joined(separator: "\n"), "columns: a heading across both columns stays above them")

let people = ["name", "ann", "bob", "eve"], amounts = ["amount", "5", "120", "7"]
let tableFragments = colBlock(people, x: 40, top: 100) + zip(amounts.indices, amounts).map { i, text in
    TextFragment(text: text, box: CGRect(x: (700 - CGFloat(text.count) * 10) / 1000, y: (1000 - 100 - CGFloat(i) * 40 - 30) / 1000,
                                         width: CGFloat(text.count) * 10 / 1000, height: 30 / 1000)) }
let tableExpectedRows = zip(people, amounts).map { name, amount in
    name + String(repeating: " ", count: Int((700 - CGFloat(amount.count) * 10 - (40 + CGFloat(name.count) * 10)) / 10)) + amount }
check(faithful(tableFragments) == tableExpectedRows.joined(separator: "\n"), "columns: a table (left- and right-aligned cells) stays row by row")

let prose = ["Some prose that explains the", "code on the left side of this", "page in a few short lines", "of plain English text"]
check(faithful(colBlock(swiftBlock, x: 40, top: 100) + colBlock(prose, x: 560, top: 110, pitch: 33))
      == swiftBlock.joined(separator: "\n") + "\n\n" + prose.joined(separator: "\n"), "columns: code beside prose reads as two blocks")

let wide = (1...3).map { "alpha line number \($0) ok" }, mid = (1...3).map { "beta line number \($0) ok" }, last = (1...3).map { "gamma line number \($0) ok" }
check(faithful(colBlock(wide, x: 20, top: 100) + colBlock(mid, x: 350, top: 100) + colBlock(last, x: 680, top: 100))
      == [wide, mid, last].map { $0.joined(separator: "\n") }.joined(separator: "\n\n"), "columns: three columns of long lines read one after another")

let gappy = ["if ready {", "    start()        // begin", "    wait()         // idle", "}"]
check(faithful(colBlock(gappy, x: 40, top: 100)) == gappy.joined(separator: "\n"), "columns: one code block with a wide inner gap is not split")

// KNOWN LIMIT (also listed in docs/ARCHITECTURE.md and the 1.2.1 changelog): columns whose lines are
// all very short look exactly like a table, so they are read row by row. Nothing in the geometry tells
// them apart; a table is the safer reading, because splitting a real table would scramble its cells.
// These tests pin the behavior and its exact boundary (an average line length of 20 characters, the
// table cell limit in TextLayout) so that any change to the heuristic is deliberate.
func plain(_ f: [TextFragment]) -> String {
    TextLayout.compose(f.shuffled(), imageSize: CGSize(width: 1000, height: 1000), keepLineBreaks: true, preserveIndentation: false)
}
func sized(_ tag: String, _ length: Int) -> String { tag + String(repeating: "x", count: length - tag.count) }

let words = (["red", "green", "blue"], ["one", "two", "six"], ["cat", "dog", "fox"])
check(plain(colBlock(words.0, x: 40, top: 100) + colBlock(words.1, x: 350, top: 100) + colBlock(words.2, x: 660, top: 100))
      == "red one cat\ngreen two dog\nblue six fox", "known limit: three columns of single words read as table rows")

let belowLimitL = (1...3).map { sized("L\($0)", 19) }, belowLimitR = (1...3).map { sized("R\($0)", 19) }
check(plain(colBlock(belowLimitL, x: 40, top: 100) + colBlock(belowLimitR, x: 500, top: 100))
      == zip(belowLimitL, belowLimitR).map { $0 + " " + $1 }.joined(separator: "\n"), "known limit: 19-character lines read as a table")

let atLimitL = (1...3).map { sized("L\($0)", 20) }, atLimitR = (1...3).map { sized("R\($0)", 20) }
check(plain(colBlock(atLimitL, x: 40, top: 100) + colBlock(atLimitR, x: 500, top: 100))
      == atLimitL.joined(separator: "\n") + "\n\n" + atLimitR.joined(separator: "\n"), "known limit: 20-character lines read as two columns")

// The same short columns stop being a table as soon as one edge is ragged (indentation), which is
// what separates code from a table.
let raggedCode = ["if a {", "    b()", "}"], raggedMore = ["for x {", "    y()", "}"]
check(plain(colBlock(raggedCode, x: 40, top: 100) + colBlock(raggedMore, x: 500, top: 100))
      == "if a {\nb()\n}\n\nfor x {\ny()\n}", "known limit: short columns with a ragged edge (code) are still columns")

// Content detector: colors
func firstColor(_ text: String) -> RGBAColor? { ContentDetector.detect(in: text).colors.first?.color }
let coral = firstColor("background: #FF5733;")
check(coral?.hex == "#FF5733", "color: hex 6 digits", coral?.hex ?? "nil")
check(firstColor("#f53")?.hex == "#FF5533", "color: hex 3 digits expand")
check(firstColor("#00FF2280")?.hex == "#00FF2280", "color: hex with alpha")
check(firstColor("#00FF2280")?.rgb == "rgba(0, 255, 34, 0.5)", "color: alpha in rgba")
check(firstColor("color: rgb(255, 12, 0)")?.hex == "#FF0C00", "color: rgb()")
check(firstColor("rgba(0, 0, 0, 0.5)")?.hex == "#00000080", "color: rgba()")
check(firstColor("rgb(100%, 0%, 0%)")?.hex == "#FF0000", "color: rgb percent")
check(firstColor("rgb(255 128 0 / 50%)")?.hex == "#FF800080", "color: rgb space syntax")
check(firstColor("hsl(120, 100%, 50%)")?.hex == "#00FF00", "color: hsl()")
check(firstColor("hsl(0 0% 100%)")?.hex == "#FFFFFF", "color: hsl space syntax")
check(firstColor("hsl(-120, 100%, 50%)")?.hex == "#0000FF", "color: hsl negative hue wraps")
check(firstColor("UIColor(red: 1, green: 0, blue: 0, alpha: 1)")?.hex == "#FF0000", "color: UIColor reference")
check(firstColor("Color(red: 0.2, green: 0.4, blue: 0.6)")?.hex == "#336699", "color: SwiftUI Color reference")
check(coral?.hsl == "hsl(11, 100%, 60%)", "color: hsl output", coral?.hsl ?? "nil")
check(coral?.rgb == "rgb(255, 87, 51)", "color: rgb output")
check(coral?.swiftUI == "Color(red: 1.0, green: 0.341, blue: 0.2)", "color: SwiftUI output", coral?.swiftUI ?? "nil")
check(coral?.appKit == "NSColor(srgbRed: 1.0, green: 0.341, blue: 0.2, alpha: 1.0)", "color: NSColor output", coral?.appKit ?? "nil")
check(coral?.uiKit == "UIColor(red: 1.0, green: 0.341, blue: 0.2, alpha: 1.0)", "color: UIColor output")
check(coral?.formats.map(\.name) == ["HEX", "RGB", "HSL", "SwiftUI Color", "NSColor", "UIColor"], "color: all formats listed")
check(ContentDetector.detect(in: "#GGGGGG #12345 rgb(300, 0, 0) hsl(10, 150%, 50%) a#fff #include").colors.isEmpty, "color: rejects invalid values")
check(ContentDetector.detect(in: "#fff then #FFF and #fff").colors.count == 1, "color: duplicates collapse")
let palette = ContentDetector.detect(in: "a #112233 b rgb(1, 2, 3) c hsl(0, 0%, 0%)").colors.map(\.source)
check(palette == ["#112233", "rgb(1, 2, 3)", "hsl(0, 0%, 0%)"], "color: reading order", "\(palette)")

// Content detector: links and emails
let linkText = ContentDetector.detect(in: "visit https://example.com/a?b=1, then mail jose@example.com. See www.apple.com and main.swift or file.py")
check(linkText.links.map(\.absoluteString).first == "https://example.com/a?b=1", "link: trailing comma excluded", "\(linkText.links)")
check(linkText.links.contains { $0.host == "www.apple.com" }, "link: www prefix")
check(linkText.links.count == 2, "link: file names are not links", "\(linkText.links)")
check(linkText.emails == ["jose@example.com"], "email: address without trailing dot", "\(linkText.emails)")
check(ContentDetector.detect(in: "nothing to see here").isEmpty, "detector: plain text finds nothing")
check(ContentDetector.detect(in: "SEE HTTPS://EXAMPLE.COM/PATH NOW").links.count == 1, "link: upper-case scheme still detected")
check(ContentDetector.detect(in: "WWW.apple.com").links.first?.host?.lowercased() == "www.apple.com", "link: upper-case www at the very start")
check(ContentDetector.detect(in: "http://a.com").links.count == 1, "link: marker in the first four bytes")
check(ContentDetector.detect(in: "ADMIN@EXAMPLE.COM").emails == ["ADMIN@EXAMPLE.COM"], "email: upper-case address")
check(ContentDetector.detect(in: "visit example dot com or htt p://x www").links.isEmpty, "link: near-miss markers find nothing")
check(ContentDetector.detect(in: "https://a.com https://a.com").links.count == 1, "link: duplicates collapse")

// Clipboard output: with Append mode off, an earlier capture can never reach a new one.
check(TextCleaner.clipboardText(new: "second", existing: "first", appendMode: false, delimiter: "\n") == "second",
      "append off: the previous clipboard is never included")
check(TextCleaner.clipboardText(new: "second", existing: "first", appendMode: true, delimiter: "\n") == "first\nsecond",
      "append on: joins with the delimiter")
check(TextCleaner.clipboardText(new: "second", existing: nil, appendMode: true, delimiter: "\n") == "second",
      "append on, nothing on the clipboard: just the new text")
check(TextCleaner.clipboardText(new: "second", existing: "", appendMode: true, delimiter: ", ") == "second",
      "append on, empty clipboard: just the new text")
check(TextCleaner.clipboardText(new: "second", existing: "first", appendMode: false, delimiter: "|") == "second",
      "append off ignores the delimiter")

// History rotation
let trio = ["c", "b", "a"]   // newest first
check(HistoryRotation.nextIndex(items: [], clipboard: "x") == nil, "rotation: empty history")
check(HistoryRotation.nextIndex(items: trio, clipboard: nil) == 0, "rotation: empty clipboard gets the newest")
check(HistoryRotation.nextIndex(items: trio, clipboard: "overwritten") == 0, "rotation: overwritten clipboard gets the newest")
check(HistoryRotation.nextIndex(items: trio, clipboard: "c") == 1, "rotation: newest -> second")
check(HistoryRotation.nextIndex(items: trio, clipboard: "b") == 2, "rotation: second -> third")
check(HistoryRotation.nextIndex(items: trio, clipboard: "a") == 0, "rotation: wraps after the oldest")
check(HistoryRotation.nextIndex(items: ["only"], clipboard: "only") == 0, "rotation: single item")

// Append separator: three choices; any other stored value reads as a new line.
do {
    let prefs = Settings(defaults: freshSuite("separator").defaults)
    prefs.appendSeparator = "space"
    check(prefs.appendDelimiter == " ", "space separator")
    prefs.appendSeparator = "tab"
    check(prefs.appendDelimiter == "\t", "tab separator")
    prefs.appendSeparator = "newline"
    check(prefs.appendDelimiter == "\n", "newline separator")
    prefs.appendSeparator = "custom"
    check(prefs.appendSeparator == "newline" && prefs.appendDelimiter == "\n", "retired custom separator reads as a new line")
}

// QR/barcode action: "open" (retired) must never open a link without asking.
do {
    let suite = freshSuite("barcode")
    let prefs = Settings(defaults: suite.defaults)
    for (stored, expected) in [("copy", "copy"), ("ask", "ask"), ("open", "ask"), ("junk", "copy")] {
        suite.defaults.set(stored, forKey: "barcodeAction")
        check(prefs.barcodeAction == expected, "barcode action: \(stored) reads as \(expected)", prefs.barcodeAction)
    }
}

// Storage compatibility: values saved under the plain property names must still load, and
// what Settings writes must land under those same names.
do {
    let stored = freshSuite("storage").defaults
    let prefs = Settings(defaults: stored)
    stored.set(true, forKey: "codeMode"); stored.set("tab", forKey: "appendSeparator")
    stored.set(["es-ES"], forKey: "languages")
    check(prefs.codeMode && prefs.appendSeparator == "tab"
          && prefs.languages == ["es-ES"], "storage: values saved under the old key names still load")
    prefs.cleanText = true; prefs.hotKeyLabel = "⌥⌘K"
    check(stored.object(forKey: "dehyphenate") as? Bool == true && stored.string(forKey: "hotKeyLabel") == "⌥⌘K", "storage: writes land under the old key names")
}
do {
    let keys = Set(StorageKeys.settings)
    check(keys.count == StorageKeys.settings.count, "storage: no settings key is listed twice")
    check(!keys.contains(StorageKeys.didOnboard),
          "storage: settings keys are separate from the history and app-state keys")
}
check(StorageKeys.didOnboard == "didOnboard", "storage: non-settings keys unchanged")

// Defaults: what a new user gets, read over an empty suite. The registered defaults are process-wide
// (UserDefaults keeps one registration domain), so they apply to the suite as they do to the app.
do {
    let prefs = Settings(defaults: freshSuite("defaults").defaults)
    let table: [(String, Bool)] = [
        ("capture shortcut is ⇧⌘2", prefs.hotKeyCode == kVK_ANSI_2 && prefs.hotKeyMods == cmdKey | shiftKey && prefs.hotKeyLabel == "⇧⌘2"),
        ("rotation shortcut is ⌥⇧⌘2", prefs.rotateHotKeyCode == kVK_ANSI_2 && prefs.rotateHotKeyMods == optionKey | shiftKey | cmdKey
            && prefs.rotateHotKeyLabel == "⌥⇧⌘2"),
        ("the optional shortcut is unset", prefs.shortcut(for: .captureCode) == nil),
        ("the visual cue is on", prefs.visualCue),
        ("the notification is the notice only", prefs.notificationStyle == .generic),
        ("languages are detected automatically", prefs.languages.isEmpty),
        ("language correction is on", prefs.languageCorrection),
        ("faithful mode is off", !prefs.codeMode),
        ("line breaks are kept", prefs.keepLineBreaks),
        ("columns are detected", prefs.detectColumns),
        ("table cells are separated by tabs", prefs.tablesAsTabs),
        ("text clean-up is off", !prefs.cleanText),
        ("code clean-up is off", !prefs.codeClean),
        ("append mode ships off", !prefs.appendMode),
        ("the append separator is a new line", prefs.appendSeparator == "newline" && prefs.appendDelimiter == "\n"),
        ("a link in a code is copied", prefs.barcodeAction == "copy"),
        ("content detection is on", prefs.detectContent),
        ("captures are offered to clipboard managers", !prefs.hideFromClipboardManagers),
        ("history is off for a new install", !prefs.historyEnabled),
        ("history is kept on quit", !prefs.clearHistoryOnQuit),
    ]
    for (name, ok) in table { check(ok, "default: \(name)") }
}

// StorageKeys round trip: changing every setting writes exactly the keys in StorageKeys.settings (which
// a new Settings over the same store reads every value back.
do {
    let suite = freshSuite("roundtrip")
    let prefs = Settings(defaults: suite.defaults)
    prefs.setShortcut(Shortcut(code: 1, mods: cmdKey), label: "⌘S", for: .capture)
    prefs.setShortcut(Shortcut(code: 3, mods: optionKey), label: "⌥F", for: .rotateHistory)
    prefs.setShortcut(Shortcut(code: 8, mods: cmdKey | controlKey), label: "⌃⌘C", for: .captureCode)
    prefs.visualCue = false; prefs.notificationStyle = .text
    prefs.languages = ["es-ES"]; prefs.languageCorrection = false; prefs.codeMode = true; prefs.keepLineBreaks = false
    prefs.detectColumns = false; prefs.tablesAsTabs = false; prefs.cleanText = true; prefs.codeClean = true
    prefs.appendMode = true; prefs.appendSeparator = "tab"; prefs.barcodeAction = "ask"
    prefs.detectContent = false; prefs.hideFromClipboardManagers = true
    prefs.historyEnabled = false; prefs.clearHistoryOnQuit = true
    let written = Set(suite.defaults.persistentDomain(forName: suite.name)?.keys.map { $0 } ?? [])
    check(written.subtracting([StorageKeys.historyDefaultApplied]) == Set(StorageKeys.settings), "storage: every setting is written under a listed key, and every listed key belongs to a setting",
          "\(written.symmetricDifference(StorageKeys.settings).sorted())")
    let back = Settings(defaults: suite.defaults)
    check(back.shortcut(for: .capture)! == (Shortcut(code: 1, mods: cmdKey), "⌘S")
          && back.shortcut(for: .rotateHistory)! == (Shortcut(code: 3, mods: optionKey), "⌥F")
          && back.shortcut(for: .captureCode)! == (Shortcut(code: 8, mods: cmdKey | controlKey), "⌃⌘C"),
          "storage: every shortcut reads back with its label")
    check(!back.visualCue && back.notificationStyle == .text
          && back.languages == ["es-ES"] && !back.languageCorrection && back.codeMode && !back.keepLineBreaks
          && !back.detectColumns && !back.tablesAsTabs && back.cleanText && back.codeClean
          && back.appendMode && back.appendSeparator == "tab" && back.barcodeAction == "ask"
          && !back.detectContent && back.hideFromClipboardManagers
          && !back.historyEnabled && back.clearHistoryOnQuit,
          "storage: every other setting reads back")
}

// Shortcut settings: saving a shortcut is one change for observers (the menu bar icon, the panel), not one per stored field.
do {
    let prefs = Settings(defaults: freshSuite("shortcut-change").defaults)
    var changes = 0
    let watching = prefs.objectWillChange.sink { changes += 1 }
    prefs.setShortcut(Shortcut(code: 1, mods: cmdKey), label: "⌘S", for: .capture)
    check(changes == 1, "settings: saving the capture shortcut is one change", "\(changes)")
    changes = 0
    prefs.setShortcut(Shortcut(code: 3, mods: optionKey | cmdKey), label: "⌥⌘F", for: .rotateHistory)
    check(changes == 1, "settings: saving the Cycle History shortcut is one change", "\(changes)")
    changes = 0
    prefs.setShortcut(Shortcut(code: 8, mods: cmdKey | controlKey), label: "⌃⌘C", for: .captureCode)
    prefs.setShortcut(nil, for: .captureCode)
    check(changes == 2, "settings: setting and removing the code shortcut are one change each", "\(changes)")
    changes = 0
    prefs.setShortcut(nil, for: .capture)
    check(changes == 0, "settings: the capture shortcut cannot be removed, and nothing changes", "\(changes)")
    watching.cancel()
}

// Shortcut labels are shown one way everywhere (review #31): a stored private-use character reads as its key's name,
// and what is stored never changes.
do {
    let prefs = Settings(defaults: freshSuite("shortcut-label").defaults)
    prefs.setShortcut(Shortcut(code: kVK_F5, mods: cmdKey), label: "⌘\u{F708}", for: .capture)
    check(prefs.shortcutLabel(for: .capture) == "⌘F5" && prefs.hotKeyLabel == "⌘\u{F708}",
          "shortcut label: a stored private-use label is shown by name and stored unchanged", prefs.shortcutLabel(for: .capture) ?? "nil")
    check(prefs.shortcutLabel(for: .rotateHistory) == prefs.rotateHotKeyLabel, "shortcut label: an ordinary label is shown exactly as stored")
    check(prefs.shortcutLabel(for: .captureCode) == nil, "shortcut label: an unset optional shortcut has no label")
}

// Notifications: permission is asked once, at the first notification actually sent.
do {
    var gate = NotificationGate()
    check(gate.shouldRequest(), "notifications: the first notification asks for permission")
    check(!gate.shouldRequest() && !gate.shouldRequest(), "notifications: later ones do not ask again")
}

/// A notification center the test answers by hand. It records what Notifier asks and holds each answer (the permission,
/// a banner added) until the test gives it, so a deletion can come before a late answer.
final class RecordingCenter: NoticeCenter, @unchecked Sendable {
    var permissionAnswers: [@Sendable (Bool) -> Void] = []
    var added: [(identifier: String, body: String)] = []
    var addAnswers: [@Sendable (Bool) -> Void] = []
    var removed: [String] = []
    var removedAll = 0
    func requestPermission(_ answer: @escaping @Sendable (Bool) -> Void) { permissionAnswers.append(answer) }
    func add(identifier: String, body: String, _ answer: @escaping @Sendable (Bool) -> Void) {
        added.append((identifier, body)); addAnswers.append(answer)
    }
    func remove(identifier: String) { removed.append(identifier) }
    func removeAll() { removedAll += 1 }
}

// Banners: the first waits for the permission answer, a refusal or "None" shows nothing, and later ones do not ask.
do {
    let center = RecordingCenter()
    let notifier = Notifier(settings: Settings(defaults: freshSuite("notices-first").defaults), center: center)
    notifier.notify(generic: "Text copied", text: "secret")
    let waited = center.added.isEmpty && center.permissionAnswers.count == 1
    center.permissionAnswers.first?(true)
    drainMain()
    check(waited && center.added.map(\.body) == ["Text copied"],
          "notifications: the first banner waits for the permission answer, then shows the notice without the text", "\(center.added.map(\.body))")
    notifier.notify(generic: "Text copied", text: "again")
    check(center.permissionAnswers.count == 1 && center.added.count == 2, "notifications: later banners are shown without asking again")
}
do {
    let center = RecordingCenter()
    let notifier = Notifier(settings: Settings(defaults: freshSuite("notices-refused").defaults), center: center)
    notifier.notify(generic: "Text copied", text: "secret")
    center.permissionAnswers.first?(false)
    drainMain()
    check(center.added.isEmpty, "notifications: a refused permission shows no banner")
}
do {
    let prefs = Settings(defaults: freshSuite("notices-none").defaults)
    prefs.notificationStyle = .none
    let center = RecordingCenter()
    Notifier(settings: prefs, center: center).notify(generic: "Text copied", text: "secret")
    check(center.permissionAnswers.isEmpty && center.added.isEmpty, "notifications: with Copy Feedback set to None, nothing is asked or shown")
}
// Deleting captures withdraws banners: those shown go, and those still on their way never appear.
do {
    let prefs = Settings(defaults: freshSuite("notices-late-answer").defaults)
    prefs.notificationStyle = .text
    let center = RecordingCenter()
    let notifier = Notifier(settings: prefs, center: center)
    notifier.notify(generic: "Text copied", text: "secret")
    Notifier.withdrawAll(from: center)
    center.permissionAnswers.first?(true)
    drainMain()
    check(center.added.isEmpty, "notifications: a banner still waiting for permission when captures are deleted is never shown", "\(center.added.map(\.body))")
    check(center.removedAll == 1, "notifications: deleting captures takes down the banners already shown", "\(center.removedAll)")
}
do {
    let center = RecordingCenter()
    let notifier = Notifier(settings: Settings(defaults: freshSuite("notices-added-late").defaults), center: center)
    notifier.notify(generic: "Text copied", text: "first")
    center.permissionAnswers.first?(true)
    drainMain()
    notifier.notify(generic: "Text copied", text: "second")
    let second = center.added.last?.identifier ?? ""
    Notifier.withdrawAll(from: center)
    center.addAnswers.last?(true)
    drainMain()
    check(!second.isEmpty && center.removed == [second], "notifications: a banner the system adds after captures are deleted is taken down at once", "\(center.removed)")
}
do {
    let prefs = Settings(defaults: freshSuite("notices-after").defaults)
    prefs.notificationStyle = .text
    let center = RecordingCenter()
    let notifier = Notifier(settings: prefs, center: center)
    Notifier.withdrawAll(from: center)
    notifier.notify(generic: "Text copied", text: "after")
    center.permissionAnswers.first?(true)
    drainMain()
    center.addAnswers.first?(true)
    drainMain()
    check(center.added.map(\.body) == ["after"] && center.removed.isEmpty, "notifications: a banner asked for after a deletion is shown and kept as usual", "\(center.added.map(\.body)) \(center.removed)")
}

// Welcome: the primary button restarts only when the permission still does not apply after a visit to Settings.
check(ScreenRecordingStep.state(granted: true, returnedFromSettings: false) == .granted, "welcome: granted -> granted")
check(ScreenRecordingStep.state(granted: true, returnedFromSettings: true) == .granted, "welcome: granted after a visit -> granted")
check(ScreenRecordingStep.state(granted: false, returnedFromSettings: false) == .pending, "welcome: not yet granted, never left -> pending")
check(ScreenRecordingStep.state(granted: false, returnedFromSettings: true) == .notActiveYet, "welcome: back from Settings without the permission applying -> Restart")

// History dates: each capture keeps its time beside its text.
do {
    let store = sealedStore("dates")
    let history = History(store: store, isEnabled: alwaysSaving)
    let t0 = Date(timeIntervalSince1970: 1_000)
    history.add("a", at: t0)
    History.flushWrites()
    history.add("b", at: t0 + 60)
    History.flushWrites()
    check(history.items == ["b", "a"] && history.dates == [t0 + 60, t0], "history dates: newest first, each beside its text")
    history.add("a", at: t0 + 120)
    History.flushWrites()
    check(history.items == ["a", "b"] && history.dates == [t0 + 120, t0 + 60], "history dates: a repeated capture moves to the front with a new time")
    history.remove("b")
    History.flushWrites()
    check(history.items == ["a"] && history.dates == [t0 + 120], "history dates: removing keeps them aligned")
    History.flushWrites()
    let reloaded = History(store: store, isEnabled: alwaysSaving)
    check(reloaded.items == ["a"] && reloaded.dates == [t0 + 120], "history dates: texts and times are saved and load back")
    history.clear()
    History.flushWrites()
    check(history.items.isEmpty && history.dates.isEmpty, "history dates: clear empties both")

    check(History.alignedDates(count: 2, stored: [5, 9]) == [Date(timeIntervalSince1970: 5), Date(timeIntervalSince1970: 9)], "history dates: stored times load as they are")
    let repaired = History.alignedDates(count: 3, stored: [5, 9])
    check(repaired.count == 3 && repaired.allSatisfy { $0 == .distantPast }, "history dates: a length mismatch is repaired as unknown, never misaligned")
    check(History.alignedDates(count: 2, stored: []).count == 2, "history dates: captures saved before dates existed load as unknown")

    let now = Date(timeIntervalSince1970: 100_000)
    check(History.ageLabel(for: .distantPast, now: now, locale: Locale(identifier: "en_US")) == nil, "history age: unknown time shows nothing")
    let label = History.ageLabel(for: now - 300, now: now, locale: Locale(identifier: "en_US"))
    check(label?.contains("5") == true, "history age: five minutes ago reads as five", label ?? "nil")
}

// Shortcut binding: a refused combination never leaves an action without a shortcut.
do {
    let a = Shortcut(code: 1, mods: 2), b = Shortcut(code: 3, mods: 4), c = Shortcut(code: 5, mods: 6), d = Shortcut(code: 7, mods: 8)
    var registered: [Shortcut] = []
    var outcome = ShortcutBinding.apply(new: c, current: a, others: [b]) { registered.append($0); return true }
    check(outcome == .accepted && registered == [c], "shortcut: a free combination is accepted and registered")
    registered = []
    outcome = ShortcutBinding.apply(new: b, current: a, others: [b]) { registered.append($0); return true }
    check(outcome == .conflictsWithOther && registered.isEmpty, "shortcut: the other action's combination is refused without touching the system")
    registered = []
    outcome = ShortcutBinding.apply(new: d, current: a, others: [b, c, d]) { registered.append($0); return true }
    check(outcome == .conflictsWithOther && registered.isEmpty, "shortcut: a combination used by any of the other actions is refused")
    registered = []
    outcome = ShortcutBinding.apply(new: c, current: a, others: [b]) { registered.append($0); return $0 != c }
    check(outcome == .unavailable && registered == [c, a], "shortcut: a combination another app owns is refused and the current one is registered again")
    registered = []
    outcome = ShortcutBinding.apply(new: c, current: nil, others: [b]) { registered.append($0); return false }
    check(outcome == .unavailable && registered == [c], "shortcut: refusing a first shortcut leaves the action without one and restores nothing")
    registered = []
    outcome = ShortcutBinding.apply(new: c, current: nil, others: []) { registered.append($0); return true }
    check(outcome == .accepted && registered == [c], "shortcut: an optional action can get its first shortcut")
    registered = []
    outcome = ShortcutBinding.apply(new: a, current: a, others: [b]) { registered.append($0); return true }
    check(outcome == .accepted && registered == [a], "shortcut: recording the same combination again is fine")
}

// Optional shortcut: the code capture has none until the user sets one.
do {
    let defaults = freshSuite("shortcuts").defaults
    let settings = Settings(defaults: defaults)
    check(settings.shortcut(for: .captureCode) == nil, "optional shortcuts: none by default")
    check(settings.shortcut(for: .capture) != nil && settings.shortcut(for: .rotateHistory) != nil, "optional shortcuts: the two main ones always have a value")
    check(ShortcutSlot.allCases.filter(\.isOptional) == [.captureCode], "optional shortcuts: the code capture is the only optional one")
    settings.setShortcut(Shortcut(code: 8, mods: 4352), label: "⌃⌘C", for: .captureCode)
    check(settings.shortcut(for: .captureCode)?.shortcut == Shortcut(code: 8, mods: 4352) && settings.shortcut(for: .captureCode)?.label == "⌃⌘C", "optional shortcuts: a saved one reads back with its label")
    settings.setShortcut(nil, for: .captureCode)
    check(settings.shortcut(for: .captureCode) == nil && defaults.object(forKey: StorageKeys.codeHotKey) == nil, "optional shortcuts: removing one clears it")
    defaults.set(["code": "junk"], forKey: StorageKeys.codeHotKey)
    check(settings.shortcut(for: .captureCode) == nil, "optional shortcuts: a damaged stored value reads as unset")
}

// Notification style: what the banner says about a capture.
do {
    check(NotificationStyle.none.body(generic: "Text copied", text: "secret") == nil, "notification: none shows no banner")
    check(NotificationStyle.generic.body(generic: "Text copied", text: "secret") == "Text copied", "notification: notice only never carries the text")
    check(NotificationStyle.text.body(generic: "Text copied", text: "secret") == "secret", "notification: with the text shows the text")

}

// Text pipeline: what a recognized capture becomes before it reaches the clipboard.
do {
    func run(_ text: String, barcode: Bool = false, codeClean: Bool = false, faithful: Bool = false, cleanText: Bool = false) -> String {
        TextPipeline.process(RecognitionResult(text: text, isBarcode: barcode), codeClean: codeClean, faithful: faithful, cleanText: cleanText)
    }
    check(run("  a   b ", barcode: true, codeClean: true, cleanText: true) == "  a   b ", "pipeline: a QR or barcode payload is never touched")
    check(run("  hola  \n") == "hola", "pipeline: plain text is trimmed")
    check(run("$ ls -la\nprint(\u{201C}hi\u{201D})", codeClean: true) == "ls -la\nprint(\"hi\")", "pipeline: code clean-up drops the prompt and straightens quotes")
    check(run("$ ls", codeClean: false) == "$ ls", "pipeline: without code clean-up the prompt stays")
    check(run("inter-\nnacional  texto", cleanText: true) == "internacional texto", "pipeline: the text-clean switch joins split words and collapses spaces")
    check(run("    x   y", faithful: true, cleanText: true) == "    x   y", "pipeline: faithful mode keeps indentation and spacing")
}

// Link policy: only a plain web address from a QR code is ever offered to open, and only after asking.
do {
    func url(_ text: String, _ action: String) -> String? { LinkPolicy.urlToConfirm(in: text, action: action)?.absoluteString }
    check(url("https://example.com/a", "ask") == "https://example.com/a", "link: an https address is offered when the choice is ask")
    check(url("https://example.com/a", "copy") == nil, "link: nothing is offered when the choice is copy only")
    check(url("HTTP://EXAMPLE.COM", "ask") != nil, "link: the scheme is matched ignoring case")
    check(url("javascript:alert(1)", "ask") == nil && url("file:///etc/passwd", "ask") == nil && url("mailto:a@b.c", "ask") == nil
          && url("tel:123", "ask") == nil && url("ftp://host/x", "ask") == nil, "link: other schemes are never offered")
    check(url("https://a.com\nhttps://b.com", "ask") == nil, "link: several lines are never offered")
    check(url("not a url", "ask") == nil && url("", "ask") == nil, "link: text that is not an address is never offered")
}

// Languages: every strings file parses, and the Spanish translation reaches the user instead of the English key.
do {
    // Anchor on the repository root and prove it first, so the absence checks cannot pass vacuously.
    let resources = repoRoot?.appendingPathComponent("Sources/Nictate/Resources").path ?? "(repository root not found)"
    check(FileManager.default.fileExists(atPath: resources + "/en.lproj"), "languages: the Resources folder is found from the runner's location", resources)
    let probes: [(lang: String, quit: String)] = [("en", "Quit Nictate"), ("es", "Salir de Nictate")]
    for probe in probes {
        let bundle = Bundle(path: resources + "/\(probe.lang).lproj")
        let quit = bundle?.localizedString(forKey: "Quit Nictate", value: nil, table: nil)
        check(quit == probe.quit, "languages: \(probe.lang) translates the quit item", quit ?? "no bundle")
        let position = bundle?.localizedString(forKey: "Capture %d of %d", value: nil, table: nil) ?? ""
        let formatted = String(format: position, 2, 5)
        check(formatted.contains("2") && formatted.contains("5") && !formatted.contains("%"), "languages: \(probe.lang) keeps both placeholders working", formatted)
    }
    for lang in ["fr", "de", "it"] {
        check(!FileManager.default.fileExists(atPath: resources + "/\(lang).lproj"), "languages: only en and es ship, not \(lang)")
    }
}

// Shortcut labels: the space key reads "Space", and a stored "Espacio" label still matches it.
check(Settings.keyEquivalent(forLabel: "⌘Space") == " ", "shortcut label: Space is the space key")
check(Settings.keyEquivalent(forLabel: "⌥⌘Espacio") == " ", "shortcut label: a saved Espacio label is still the space key")
check(Settings.keyEquivalent(forLabel: "⇧⌘E") == "e", "shortcut label: a plain E is not the space key")

// Tables: with the option on, the cells of a detected table are separated by tabs, so a paste fills columns.
do {
    func table(_ rows: [[String?]], top: CGFloat = 0.80) -> [TextFragment] {
        let colX: [CGFloat] = [0.05, 0.45, 0.75]
        var frags: [TextFragment] = []
        for (r, row) in rows.enumerated() {
            for (c, cell) in row.enumerated() {
                guard let cell else { continue }
                frags.append(TextFragment(text: cell, box: CGRect(x: colX[c], y: top - CGFloat(r) * 0.15, width: CGFloat(cell.count) * 0.012, height: 0.05)))
            }
        }
        return frags
    }
    let size = CGSize(width: 1000, height: 400)
    let full: [[String?]] = [["Name", "Qty", "Price"], ["Apples", "12", "3.40"], ["Pears", "7", "2.10"], ["Plums", "30", "9.99"]]
    func compose(_ frags: [TextFragment], tabs: Bool = true, keepLineBreaks: Bool = true, faithful: Bool = false) -> String {
        TextLayout.compose(frags, imageSize: size, keepLineBreaks: keepLineBreaks, preserveIndentation: faithful, detectColumns: true, tablesAsTabs: tabs)
    }
    check(compose(table(full)) == "Name\tQty\tPrice\nApples\t12\t3.40\nPears\t7\t2.10\nPlums\t30\t9.99", "tables: cells are separated by tabs")
    check(compose(table(full), tabs: false) == "Name Qty Price\nApples 12 3.40\nPears 7 2.10\nPlums 30 9.99", "tables: with the option off the output is as before")
    check(!compose(table(full), faithful: true).contains("\t"), "tables: faithful mode never inserts tabs")
    check(!compose(table(full), keepLineBreaks: false).contains("\t"), "tables: no tabs when line breaks are not kept")
    var gap = full; gap[2][1] = nil
    check(compose(table(gap)).contains("Pears\t\t2.10"), "tables: a missing cell keeps its column with an empty field", compose(table(gap)).debugDescription)
    var titled = table(full, top: 0.70)   // the title sits one row pitch above, so no paragraph gap
    titled.append(TextFragment(text: "Fruit prices for the week of March", box: CGRect(x: 0.05, y: 0.85, width: 0.8, height: 0.05)))
    let titledOut = compose(titled)
    check(titledOut.hasPrefix("Fruit prices for the week of March\nName\tQty\tPrice\n"), "tables: a title above the table stays plain", titledOut.debugDescription)
    var columns: [TextFragment] = []
    for r in 0..<6 {
        columns.append(TextFragment(text: "The first column keeps running prose line \(r)", box: CGRect(x: 0.05, y: 0.85 - CGFloat(r) * 0.12, width: 0.38, height: 0.05)))
        columns.append(TextFragment(text: "The second column also has long prose line \(r)", box: CGRect(x: 0.55, y: 0.85 - CGFloat(r) * 0.12, width: 0.38, height: 0.05)))
    }
    check(!compose(columns).contains("\t"), "tables: two columns of prose are not a table and get no tabs")
    check(TextCleaner.finalize("a\t\tb  c", preserveIndentation: false, dehyphenate: false, collapseSpaces: true) == "a\t\tb c", "tables: collapsing spaces keeps tabs")
    check(TextCleaner.finalize("\tx\t", preserveIndentation: false, dehyphenate: false, collapseSpaces: false) == "\tx\t", "tables: trimming keeps leading and trailing empty cells")
}

// Phone numbers: found like links and emails, never invented from prices, dates or versions.
do {
    func phones(_ text: String) -> [String] { ContentDetector.detect(in: text).phones }
    check(phones("Call +1 415 555 0132 or (212) 555-0100 today") == ["+1 415 555 0132", "(212) 555-0100"], "phones: international and local formats")
    check(phones("Llama al 912 345 678 o al +34 600 123 456") == ["912 345 678", "+34 600 123 456"], "phones: Spanish numbers")
    check(phones("Rufen Sie 030 123456 an") == ["030 123456"] && phones("Appelez le 01 23 45 67 89") == ["01 23 45 67 89"], "phones: German and French numbers")
    check(phones("Price 4,218.50 on 2024-01-01, invoice 20240101").isEmpty, "phones: prices and dates are not phone numbers")
    check(phones("Version 2.4.0 build 50, port 8080, ID 12345").isEmpty, "phones: versions, ports and short ids are not phone numbers")
    check(phones("Order 1234567890 shipped").isEmpty && phones("ISBN 978-3-16-148410-0").isEmpty, "phones: a long digit run or an ISBN is not a phone number")
    check(phones("Call 555 0100 or 555 0100 again") == ["555 0100"], "phones: the same number twice is listed once")
    check(!ContentDetector.detect(in: "Call (212) 555-0100").isEmpty && ContentDetector.detect(in: "no digits here at all").phones.isEmpty,
          "phones: a capture with only a phone number still counts as having detections")
    let digitHeavy = String(repeating: "12345 67890 ", count: 1700)
    let started = Date()
    let found = ContentDetector.detect(in: digitHeavy, limit: 3).phones
    let elapsed = Date().timeIntervalSince(started)
    // Loose on purpose: Rosetta and coverage builds run much slower, and 2.5 s still catches the quadratic
    // scan this guards against.
    check(found.count <= 3 && elapsed < 2.5, "phones: digit-heavy text stops at the limit and stays fast", "\(found.count) found in \(Int(elapsed * 1000)) ms")
    let prose = String(repeating: "lorem ipsum dolor sit amet ", count: 740)
    check(ContentDetector.detect(in: prose).phones.isEmpty, "phones: text without digits is skipped")
}

// Capture modes: the shortcut decides what a capture does, the settings decide the rest.
do {
    let text = RecognitionResult(text: "hello", isBarcode: false), code = RecognitionResult(text: "https://example.com", isBarcode: true)
    check(CaptureMode.text.accepts(text) && CaptureMode.text.accepts(code), "mode: a text capture takes any result")
    check(CaptureMode.code.accepts(code) && !CaptureMode.code.accepts(text), "mode: a code capture takes only a QR or barcode")
    check(CaptureMode.code.barcodesOnly && !CaptureMode.text.barcodesOnly, "mode: only the code capture skips text recognition")
}

// Tables found by row structure: tight or uneven gutters must not split or flatten a table.
do {
    let rows = [["Product", "Region", "Units", "Revenue"], ["Notebook", "North", "1,204", "$18,060"], ["Monitor", "South", "387", "$61,920"],
                ["Keyboard", "East", "2,950", "$44,250"], ["Webcam", "West", "612", "$30,600"], ["Dock", "North", "148", "$9,620"]]
    // Positions and widths measured from Vision on a 420 px wide, 13 px spreadsheet capture.
    func sheet(_ colX: [CGFloat], charW: CGFloat) -> [TextFragment] {
        var frags: [TextFragment] = []
        for (r, row) in rows.enumerated() {
            for (c, cell) in row.enumerated() {
                frags.append(TextFragment(text: cell, box: CGRect(x: colX[c], y: 0.85 - CGFloat(r) * 0.12, width: CGFloat(cell.count) * charW, height: 0.05)))
            }
        }
        return frags
    }
    let size = CGSize(width: 420, height: 380)
    let expected = rows.map { $0.joined(separator: "\t") }.joined(separator: "\n")
    let uneven = TextLayout.compose(sheet([0.043, 0.257, 0.471, 0.686], charW: 0.0185), imageSize: size, keepLineBreaks: true, preserveIndentation: false, tablesAsTabs: true)
    check(uneven == expected, "row tables: uneven gutters keep the table whole", uneven.debugDescription)
    let narrow = TextLayout.compose(sheet([0.054, 0.285, 0.477, 0.650], charW: 0.017), imageSize: CGSize(width: 520, height: 380), keepLineBreaks: true, preserveIndentation: false, tablesAsTabs: true)
    check(narrow == expected, "row tables: narrow gutters still give tabs", narrow.debugDescription)
    var missing = sheet([0.054, 0.285, 0.477, 0.650], charW: 0.017)
    missing.removeAll { $0.text == "387" }
    let gap = TextLayout.compose(missing, imageSize: CGSize(width: 520, height: 380), keepLineBreaks: true, preserveIndentation: false, tablesAsTabs: true)
    check(gap.contains("Monitor\tSouth\t\t$61,920"), "row tables: a missing cell keeps its column", gap.debugDescription)
    let off = TextLayout.compose(sheet([0.043, 0.257, 0.471, 0.686], charW: 0.0185), imageSize: size, keepLineBreaks: true, preserveIndentation: false, tablesAsTabs: false)
    check(off.components(separatedBy: "\n").first == "Product Region Units Revenue", "row tables: with tabs off the table still reads row by row", off.debugDescription)
}

// Tabs and code: with code clean-up on, a capture is code, and an aligned comment is not a table cell.
check(TextPipeline.tablesAsTabs(setting: true, codeClean: false) && !TextPipeline.tablesAsTabs(setting: true, codeClean: true)
      && !TextPipeline.tablesAsTabs(setting: false, codeClean: false), "tabs: off when code clean-up is on or the option is off")

// Apple's document reader as a second opinion for tables.
check(DocumentTables.tsv([["a", "b"], ["c", "d"]]) == "a\tb\nc\td", "document tables: rows become tab-separated lines")
check(DocumentTables.tsv([["a", "b"], [], ["c", "d"]]) == "a\tb\nc\td", "document tables: empty rows are dropped")
check(DocumentTables.cellsAgree([["Apples", "12"], ["Pears", "$1,204.00"]], with: "Apples 12\nPears $1,204.00")
      && !DocumentTables.cellsAgree([["Apples", "$1,204.0łąłś"]], with: "Apples $1,204.00"), "document tables: rejected when a cell's text differs from Nictate's own reading")
check(TextLayout.multiCellRows([TextFragment(text: "a", box: CGRect(x: 0.1, y: 0.8, width: 0.1, height: 0.05)), TextFragment(text: "b", box: CGRect(x: 0.5, y: 0.8, width: 0.1, height: 0.05)),
                                TextFragment(text: "c", box: CGRect(x: 0.1, y: 0.6, width: 0.1, height: 0.05))], imageSize: CGSize(width: 500, height: 300)) == 1,
      "document tables: rows holding several fragments are counted")
check(DocumentTables.prefersTable(tableCharacters: 95, textCharacters: 100) && !DocumentTables.prefersTable(tableCharacters: 60, textCharacters: 100)
      && !DocumentTables.prefersTable(tableCharacters: 0, textCharacters: 0), "document tables: used only when the table holds nearly all the text")

// Robustness: input a screen cannot produce must not crash the layout or fill the history file.
do {
    let odd = [TextFragment(text: "nan", box: CGRect(x: CGFloat.nan, y: 0, width: 0.1, height: 0.1)),
               TextFragment(text: "inf", box: CGRect(x: 0, y: 0, width: CGFloat.infinity, height: 0.1)),
               TextFragment(text: "ok", box: CGRect(x: 0.1, y: 0.1, width: 0.1, height: 0.02))]
    check(TextLayout.compose(odd, imageSize: CGSize(width: 100, height: 100), keepLineBreaks: true, preserveIndentation: false) == "ok",
          "robustness: boxes that are not finite are skipped")
    check(TextLayout.compose(odd, imageSize: CGSize(width: CGFloat.nan, height: 10), keepLineBreaks: true, preserveIndentation: false) == ""
          && TextLayout.compose(odd, imageSize: .zero, keepLineBreaks: true, preserveIndentation: false) == "",
          "robustness: an unusable image size gives no text instead of a crash")
    let history = History(store: sealedStore("robustness"), isEnabled: alwaysSaving)
    history.add(String(repeating: "x", count: History.maxStoredLength + 1))
    History.flushWrites()
    check(history.items.isEmpty, "robustness: a capture too large for the history file is not stored")
    history.add("short")
    History.flushWrites()
    check(history.items == ["short"], "robustness: normal captures are stored")
}

// OCR depends on the host's Vision runtime; CI can opt out with SKIP_OCR=1.
if ProcessInfo.processInfo.environment["SKIP_OCR"] == nil {
    // OCR end to end on a rendered code snippet (Vision runs on-device).
    func render(_ text: String) -> CGImage {
        let font = NSFont.monospacedSystemFont(ofSize: 18, weight: .regular)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
        let str = NSAttributedString(string: text, attributes: attrs)
        let box = str.boundingRect(with: NSSize(width: 2000, height: 2000), options: [.usesLineFragmentOrigin])
        let w = Int(box.width) + 60, h = Int(box.height) + 60
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.white.setFill(); NSRect(x: 0, y: 0, width: w, height: h).fill()
        str.draw(at: NSPoint(x: 30, y: 30))
        NSGraphicsContext.restoreGraphicsState()
        return rep.cgImage!
    }
    let source = """
    func check(name: String) -> Bool {
        if name != "" && count >= 3 {
            return items[0] || flag
        }
        return false
    }
    """
    let result = Recognizer.recognize(render(source), options: RecognitionOptions(
        languages: [], keepLineBreaks: true, languageCorrection: false, preserveIndentation: true))
    print("--- OCR output ---\n\(result.text)\n------------------")
    let ocrLines = result.text.components(separatedBy: "\n")
    check(ocrLines.count == 6, "ocr line count", "\(ocrLines.count)")
    check(ocrLines.contains { $0.hasPrefix("    if") && !$0.hasPrefix("     ") }, "ocr indents level 1 by ~4 spaces")
    check(ocrLines.contains { $0.hasPrefix("        return") }, "ocr indents level 2 by ~8 spaces")
    check(result.text.contains("&&") && result.text.contains("!=") && result.text.contains(">="), "ocr keeps operators")
    check(!result.isBarcode, "ocr is not barcode")

    // A very large image with ordinary-sized text (a whole 5K screen): the accurate model alone returns nothing.
    func renderLarge() -> CGImage {
        let w = 5120, h = 1600
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.white.setFill(); NSRect(x: 0, y: 0, width: w, height: h).fill()
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 26), .foregroundColor: NSColor.black]
        for i in 0..<30 { ("Line \(i): the quick brown fox jumps over the lazy dog" as NSString).draw(at: NSPoint(x: 40, y: CGFloat(h - 60 - i * 39)), withAttributes: attrs) }
        NSGraphicsContext.restoreGraphicsState()
        return rep.cgImage!
    }
    // End to end: a table image read by Vision comes out tab-separated.
    func renderTable() -> CGImage {
        let w = 900, h = 300
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.white.setFill(); NSRect(x: 0, y: 0, width: w, height: h).fill()
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 30), .foregroundColor: NSColor.black]
        let rows = [["Name", "Qty", "Price"], ["Apples", "12", "3.40"], ["Pears", "7", "2.10"], ["Plums", "30", "9.99"]]
        for (r, row) in rows.enumerated() {
            for (c, cell) in row.enumerated() {
                (cell as NSString).draw(at: NSPoint(x: [40, 400, 700][c], y: CGFloat(h - 60 - r * 60)), withAttributes: attrs)
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        return rep.cgImage!
    }
    func renderSheet() -> CGImage {
        let w = 420, h = 380
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.white.setFill(); NSRect(x: 0, y: 0, width: w, height: h).fill()
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.black]
        let rows = [["Product", "Region", "Units", "Revenue"], ["Notebook", "North", "1,204", "$18,060"], ["Monitor", "South", "387", "$61,920"],
                    ["Keyboard", "East", "2,950", "$44,250"], ["Webcam", "West", "612", "$30,600"], ["Dock", "North", "148", "$9,620"]]
        for (r, row) in rows.enumerated() {
            for (c, cell) in row.enumerated() {
                (cell as NSString).draw(at: NSPoint(x: [20, 110, 200, 290][c], y: CGFloat(h) - 40 - CGFloat(r) * 24.7), withAttributes: attrs)
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        return rep.cgImage!
    }
    let sheetRead = Recognizer.recognize(renderSheet(), options: RecognitionOptions(
        languages: [], keepLineBreaks: true, languageCorrection: false, preserveIndentation: false, detectColumns: true, tablesAsTabs: true))
    let sheetLines = sheetRead.text.components(separatedBy: "\n")
    check(sheetLines.count == 6 && sheetLines.allSatisfy { $0.components(separatedBy: "\t").count == 4 },
          "ocr: a tight 13 px spreadsheet stays one table of six rows and four columns", sheetRead.text.debugDescription)
    let tableRead = Recognizer.recognize(renderTable(), options: RecognitionOptions(
        languages: [], keepLineBreaks: true, languageCorrection: false, preserveIndentation: false, detectColumns: true, tablesAsTabs: true))
    let tableLines = tableRead.text.components(separatedBy: "\n")
    check(tableLines.count == 4 && tableLines.allSatisfy { $0.components(separatedBy: "\t").count == 3 },
          "ocr: a table image comes out as four rows of three tab-separated cells", tableRead.text.debugDescription)
    // QR codes: read as before, and alone when the capture is code-only (no text recognition at all).
    func renderQR(_ payload: String) -> CGImage {
        let filter = CIFilter(name: "CIQRCodeGenerator")!
        filter.setValue(Data(payload.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        let code = filter.outputImage!.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        let side = Int(code.extent.width) + 160
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.white.setFill(); NSRect(x: 0, y: 0, width: side, height: side).fill()
        NSGraphicsContext.restoreGraphicsState()
        let background = CIImage(bitmapImageRep: rep)!
        let composed = code.transformed(by: CGAffineTransform(translationX: 80, y: 80)).composited(over: background)
        return CIContext().createCGImage(composed, from: background.extent)!
    }
    let payload = "https://example.com/page?x=1"
    let qrNormal = Recognizer.recognize(renderQR(payload), options: RecognitionOptions())
    check(qrNormal.isBarcode && qrNormal.text == payload, "ocr: a QR code is read as its payload", qrNormal.text)
    let qrOnly = Recognizer.recognize(renderQR(payload), options: RecognitionOptions(barcodesOnly: true))
    check(qrOnly.isBarcode && qrOnly.text == payload, "ocr: a code-only capture reads the QR code", qrOnly.text)
    let textOnlyImage = Recognizer.recognize(renderTable(), options: RecognitionOptions(barcodesOnly: true))
    check(!textOnlyImage.isBarcode && textOnlyImage.text.isEmpty, "ocr: a code-only capture of plain text returns nothing", textOnlyImage.text.debugDescription)
    let large = Recognizer.recognize(renderLarge(), options: RecognitionOptions())
    check(large.text.components(separatedBy: "\n").count >= 25 && large.text.contains("quick brown fox"),
          "ocr reads ordinary text on a 5120 px wide capture", "\(large.text.count) chars")

}

// EyelidTimeline: the menu bar icon closes like an eyelid into a line and reopens.
do {
    check(EyelidTimeline.blinks(for: .success) == 1 && EyelidTimeline.blinks(for: .failure) == 2,
          "blink: one blink on success, two on failure, so the cue is not color alone")
    let start = EyelidTimeline.frame(at: 0, blinks: 1)
    check(start == EyelidTimeline.Frame(openness: 1, beam: 0), "blink: starts open with no beam", "\(String(describing: start))")
    let shut = EyelidTimeline.frame(at: EyelidTimeline.closing, blinks: 1)
    check(shut == EyelidTimeline.Frame(openness: 0, beam: 1), "blink: fully closed into the beam at the end of closing", "\(String(describing: shut))")
    let half = EyelidTimeline.frame(at: EyelidTimeline.closing / 2, blinks: 1)!
    check(half.openness > 0.5 && half.openness < 1, "blink: closing eases in (slow start)", "\(half.openness)")
    let reopening = EyelidTimeline.frame(at: EyelidTimeline.closing + EyelidTimeline.opening / 2, blinks: 1)!
    check(reopening.openness > 0.5 && reopening.beam < 0.6, "blink: reopening eases out (fast start)", "\(reopening)")
    let one = EyelidTimeline.duration(blinks: 1)
    check(EyelidTimeline.frame(at: one - 0.0001, blinks: 1)!.openness > 0.99, "blink: ends open")
    check(EyelidTimeline.frame(at: one + 0.001, blinks: 1) == nil, "blink: nothing after the last blink")
    check(EyelidTimeline.frame(at: one + EyelidTimeline.closing, blinks: 2) == EyelidTimeline.Frame(openness: 0, beam: 1),
          "blink: the second blink closes like the first")
    check(EyelidTimeline.duration(blinks: 2) < 0.8, "blink: two blinks stay under 0.8 s", "\(EyelidTimeline.duration(blinks: 2))")
    check(EyelidTimeline.frame(at: -1, blinks: 1) == EyelidTimeline.Frame(openness: 1, beam: 0), "blink: a time before the start is open")
}

// NSPasteboard.replaceContents: private captures are marked transient and concealed; plain ones are not.
do {
    let board = NSPasteboard(name: NSPasteboard.Name("nictate.tests.\(UUID().uuidString)"))
    defer { board.releaseGlobally() }
    let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
    let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
    board.replaceContents(with: "public", transient: false)
    let plain = board.types ?? []
    check(board.string(forType: .string) == "public" && !plain.contains(transientType) && !plain.contains(concealedType),
          "pasteboard: with the setting off only the text is written", "\(plain)")
    board.replaceContents(with: "secret", transient: true)
    let hidden = board.types ?? []
    check(board.string(forType: .string) == "secret" && hidden.contains(transientType) && hidden.contains(concealedType),
          "pasteboard: with the setting on the text is marked transient and concealed", "\(hidden)")
    board.replaceContents(with: "public again", transient: false)
    let after = board.types ?? []
    check(board.string(forType: .string) == "public again" && !after.contains(transientType) && !after.contains(concealedType),
          "pasteboard: a later plain write drops the markers", "\(after)")
}

// ShortcutRule: a new global shortcut needs ⌘ or ⌃; ⌥ and ⇧ alone type characters in other apps.
do {
    // Carbon modifier masks, spelled out because this file does not import Carbon.
    let cmd = 256, shift = 512, option = 2048, control = 4096
    check(ShortcutRule.isAcceptableForRecording(mods: cmd), "shortcut rule: ⌘ is accepted")
    check(ShortcutRule.isAcceptableForRecording(mods: control), "shortcut rule: ⌃ is accepted")
    check(ShortcutRule.isAcceptableForRecording(mods: option | cmd), "shortcut rule: ⌥⌘ is accepted")
    check(ShortcutRule.isAcceptableForRecording(mods: control | option | shift), "shortcut rule: ⌃⌥⇧ is accepted")
    check(!ShortcutRule.isAcceptableForRecording(mods: option), "shortcut rule: ⌥ alone is rejected")
    check(!ShortcutRule.isAcceptableForRecording(mods: option | shift), "shortcut rule: ⇧⌥ is rejected")
    check(!ShortcutRule.isAcceptableForRecording(mods: shift), "shortcut rule: ⇧ alone is rejected")
    check(!ShortcutRule.isAcceptableForRecording(mods: 0), "shortcut rule: no modifier is rejected")
}

// Rotation depth: the clamp lives in HistoryRotation, so a stored depth below zero or history being off
// leaves nothing to cycle, and a depth past the history just takes all of it.
do {
    let five = ["e", "d", "c", "b", "a"]
    check(HistoryRotation.items(five, depth: -1, historyEnabled: true).isEmpty, "rotation depth: -1 cycles nothing")
    check(HistoryRotation.items(five, depth: 0, historyEnabled: true).isEmpty, "rotation depth: 0 cycles nothing")
    check(HistoryRotation.items(five, depth: 1, historyEnabled: true) == ["e"], "rotation depth: 1 keeps the newest")
    check(HistoryRotation.items(five, depth: 1000, historyEnabled: true) == five, "rotation depth: 1000 takes the whole history")
    check(HistoryRotation.items(five, depth: 10, historyEnabled: false).isEmpty, "rotation depth: history off cycles nothing")
}

// Cycle History never reads the clipboard: it remembers what Nictate last wrote and the pasteboard's change
// count after that write. Anything copied since (by any app) changes the count, so rotation restarts.
do {
    let write = ClipboardWrite(changeCount: 41, text: "c")
    check(HistoryRotation.ownClipboard(changeCount: 41, lastWrite: write) == "c", "rotation clipboard: our own write is known")
    check(HistoryRotation.ownClipboard(changeCount: 42, lastWrite: write) == nil, "rotation clipboard: a later copy is unknown")
    check(HistoryRotation.ownClipboard(changeCount: 0, lastWrite: nil) == nil, "rotation clipboard: nothing written yet")
    let trio = ["c", "b", "a"]
    check(HistoryRotation.nextIndex(items: trio, clipboard: HistoryRotation.ownClipboard(changeCount: 41, lastWrite: write)) == 1,
          "rotation clipboard: after our write of the newest, the second")
    check(HistoryRotation.nextIndex(items: trio, clipboard: HistoryRotation.ownClipboard(changeCount: 50, lastWrite: write)) == 0,
          "rotation clipboard: after someone else's copy, the newest")
}

// Opening a link: the sink itself only lets web and mail addresses through, whatever handed it the URL.
// An explicit click opens at once unless the user chose "ask first" (D16).
do {
    func decide(_ text: String, _ action: String) -> LinkPolicy.Opening? { URL(string: text).map { LinkPolicy.opening($0, action: action) } }
    check(decide("https://example.com", "copy") == .open, "open link: an explicit click on https opens without asking")
    check(decide("https://example.com", "ask") == .ask, "open link: ask first shows the address before opening")
    check(decide("HTTP://EXAMPLE.COM", "copy") == .open, "open link: the scheme is matched ignoring case")
    check(decide("mailto:a@b.com", "copy") == .open, "open link: a mail address opens")
    check(decide("file:///etc/passwd", "copy") == .refuse && decide("file:///etc/passwd", "ask") == .refuse,
          "open link: file is refused")
    check(decide("javascript:alert(1)", "copy") == .refuse, "open link: javascript is refused")
    check(decide("tel:123", "copy") == .refuse && decide("ftp://host/x", "copy") == .refuse
          && decide("x-apple-systempreferences:", "copy") == .refuse, "open link: every other scheme is refused")
}

// CapturePlan: everything a finished capture does, as a list of effects the coordinator carries out in order.
do {
    let plain = CapturePlan.Choices(appendMode: false, delimiter: "\n", historyEnabled: true, barcodeAction: "copy")
    let appending = CapturePlan.Choices(appendMode: true, delimiter: "\n", historyEnabled: true, barcodeAction: "copy")
    let found = Detections(colors: [], links: [URL(string: "https://example.com")!], emails: [], phones: [])
    func plan(_ text: String, mode: CaptureMode = .text, barcode: Bool = false, choices: CapturePlan.Choices = plain,
              existing: ExistingClipboard? = nil, detections: Detections = Detections()) -> [CaptureEffect] {
        CapturePlan.effects(mode: mode, result: RecognitionResult(text: text, isBarcode: barcode), text: text,
                            detections: detections, choices: choices, existing: existing)
    }
    func miss(_ message: String) -> [CaptureEffect] { [.cue(.failure), .announce(message), .notify(generic: message, text: message)] }
    func copied(_ effects: [CaptureEffect]) -> [String] { effects.compactMap { if case .copy(let text) = $0 { return text } else { return nil } } }

    check(plan("ABC", mode: .code) == miss(tr("No code found")), "plan: a code capture without a code is a miss")
    check(plan("") == miss(tr("No text found")), "plan: no text is a miss")
    check(plan("", mode: .code, barcode: true) == miss(tr("No text found")), "plan: an empty code is a miss")
    // A read that Vision could not run is a failure, not an empty capture.
    let failedRead = RecognitionResult(text: "", isBarcode: false, failed: true)
    for mode in [CaptureMode.text, .code] {
        let effects = CapturePlan.effects(mode: mode, result: failedRead, text: "", detections: Detections(), choices: plain, existing: nil)
        check(effects == miss(tr("Couldn't read this area. Try again.")),
              "plan: a failed read is reported as a failure in \(mode)")
    }
    check(plan("hello", detections: found) == [.remember(found), .copy("hello"), .cue(.success), .announce(tr("Text copied")),
                                               .addToHistory("hello"), .notify(generic: tr("Text copied"), text: "hello")],
          "plan: a text capture remembers, copies, cues, announces, saves and notifies, in that order")
    check(!plan("", detections: found).contains(.remember(found)), "plan: a miss keeps the earlier detections")
    check(copied(plan("new", existing: ExistingClipboard(text: "old", isPrivate: false))) == ["new"],
          "plan: replace mode ignores the clipboard")
    let added = plan("new", choices: appending, existing: ExistingClipboard(text: "old", isPrivate: false))
    check(copied(added) == ["old\nnew"] && added.contains(.announce(tr("Text added"))), "plan: append mode adds to the clipboard")
    check(copied(plan("new", choices: appending, existing: nil)) == ["new"], "plan: append mode with nothing to add to")
    check(copied(plan("new", choices: appending, existing: ExistingClipboard(text: "secret", isPrivate: true))) == ["new"],
          "plan: append mode starts fresh over a concealed or transient item")
    let noHistory = CapturePlan.Choices(appendMode: false, delimiter: "\n", historyEnabled: false, barcodeAction: "copy")
    check(plan("hello").contains(.addToHistory("hello")) && !plan("hello", choices: noHistory).contains { if case .addToHistory = $0 { return true } else { return false } },
          "plan: history only when it is on")
    let long = String(repeating: "x", count: 300)
    check(plan(long).contains(.notify(generic: tr("Text copied"), text: String(repeating: "x", count: 120))),
          "plan: the notification shows the first 120 characters")
    let asking = CapturePlan.Choices(appendMode: false, delimiter: "\n", historyEnabled: true, barcodeAction: "ask")
    check(plan("https://example.com/qr", mode: .code, barcode: true, choices: asking).last == .offerLink(URL(string: "https://example.com/qr")!),
          "plan: a barcode link is offered last when the choice is ask")
    check(!plan("https://example.com/qr", barcode: true).contains { if case .offerLink = $0 { return true } else { return false } },
          "plan: a barcode link is only copied when the choice is copy")
    check(!plan("https://example.com/qr", choices: asking).contains { if case .offerLink = $0 { return true } else { return false } },
          "plan: a link in recognized text is never offered on its own")

    // A refused copy is not a capture: the clipboard did not take the text, so nothing after the copy may claim it.
    let refusedMessage = tr("Couldn't copy text. Try again.")
    let refused = CapturePlan.settled(plan("hello", detections: found), copied: false)
    check(refused == [.remember(found), .copy("hello"), .cue(.failure), .announce(refusedMessage),
                      .notify(generic: refusedMessage, text: refusedMessage)],
          "plan: a refused copy ends as a failure that says the text was not copied", "\(refused)")
    check(!refused.contains { if case .addToHistory = $0 { return true } else { return false } },
          "plan: a refused copy is not kept in History")
    check(!refused.contains(.cue(.success)) && !refused.contains(.announce(tr("Text copied"))),
          "plan: a refused copy gives no success cue and no Text copied announcement")
    let refusedAppend = CapturePlan.settled(plan("new", choices: appending, existing: ExistingClipboard(text: "old", isPrivate: false)),
                                            copied: false)
    check(!refusedAppend.contains(.announce(tr("Text added"))) && !refusedAppend.contains(.notify(generic: tr("Text added"), text: "new")),
          "plan: a refused append does not say the text was added")
    check(!CapturePlan.settled(plan("https://example.com/qr", mode: .code, barcode: true, choices: asking), copied: false)
            .contains { if case .offerLink = $0 { return true } else { return false } },
          "plan: a refused barcode copy offers no link")
    let accepted = plan("hello", detections: found)
    check(CapturePlan.settled(accepted, copied: true) == accepted, "plan: an accepted copy carries out the whole plan")
    check(CapturePlan.settled(plan(""), copied: false) == miss(tr("No text found")), "plan: a miss stays a miss whatever the clipboard did")
    // As CaptureCoordinator.finish uses it, on a private pasteboard whose clipboard refuses the text (never the user's).
    let board = NSPasteboard(name: NSPasteboard.Name("nictate-tests-refused-\(UUID().uuidString)"))
    defer { board.releaseGlobally() }
    let refusing = ClipboardWriter(pasteboard: board, replace: { pasteboard, _, _ in pasteboard.clearContents(); return pasteboard.changeCount })
    let planned = plan("hello")
    let written = planned.compactMap(\.copiedText).first.map { refusing.writeVerified($0, transient: false) }
    check(written == false && refusing.lastWrite == nil && !CapturePlan.settled(planned, copied: written ?? false).contains(.addToHistory("hello")),
          "plan: a refused capture is not remembered as copied and never reaches History")
}

// Append mode reads the clipboard: an item another app marked concealed or transient (a password manager's
// copy) is never republished; Nictate's own writes stay appendable even when the private setting marks them.
do {
    let board = NSPasteboard(name: NSPasteboard.Name("nictate-test-\(UUID().uuidString)"))
    func mark(_ text: String, _ types: [String]) {
        board.clearContents()
        board.setString(text, forType: .string)
        for type in types { board.setData(Data(), forType: NSPasteboard.PasteboardType(type)) }
    }
    mark("hunter2", ["org.nspasteboard.ConcealedType"])
    check(ExistingClipboard.read(from: board, lastWrite: nil) == ExistingClipboard(text: nil, isPrivate: true),
          "append clipboard: a concealed item is private and its text is never read")
    mark("one-time code", ["org.nspasteboard.TransientType"])
    check(ExistingClipboard.read(from: board, lastWrite: nil) == ExistingClipboard(text: nil, isPrivate: true),
          "append clipboard: a transient item is private and its text is never read")
    mark("plain", [])
    check(ExistingClipboard.read(from: board, lastWrite: nil) == ExistingClipboard(text: "plain", isPrivate: false),
          "append clipboard: a plain item can be added to")
    board.replaceContents(with: "mine", transient: true)
    let mine = ClipboardWrite(changeCount: board.changeCount, text: "mine")
    check(ExistingClipboard.read(from: board, lastWrite: mine) == ExistingClipboard(text: "mine", isPrivate: false),
          "append clipboard: Nictate's own private write can still be added to")
    mark("hunter2", ["org.nspasteboard.ConcealedType"])
    check(ExistingClipboard.read(from: board, lastWrite: mine).isPrivate, "append clipboard: a later concealed copy is private again")
    board.releaseGlobally()
}

// Mail links: a detected email is just the address, and Write Email builds a bare mailto URL from it, so a
// recognized "mailto:" link can never smuggle extra recipients or a body into the mail draft.
do {
    let smuggled = ContentDetector.detect(in: "write to mailto:a@b.com?bcc=evil@x.com&body=hi today")
    check(smuggled.emails == ["a@b.com"], "mailto: a detected link keeps only the address", "\(smuggled.emails)")
    check(ContentDetector.detect(in: "MAILTO:Bob@Example.com").emails == ["Bob@Example.com"], "mailto: the scheme is dropped ignoring case")
    check(LinkPolicy.mailtoURL(for: "a@b.com")?.absoluteString == "mailto:a@b.com", "mailto: an address becomes a bare mail link")
    let rebuilt = LinkPolicy.mailtoURL(for: "mailto:a@b.com?bcc=evil@x.com&body=hi")
    check(rebuilt?.absoluteString == "mailto:a@b.com", "mailto: no doubled scheme and no query", rebuilt?.absoluteString ?? "nil")
    check(LinkPolicy.mailtoURL(for: "not an address") == nil && LinkPolicy.mailtoURL(for: "") == nil,
          "mailto: text without an address builds nothing")
}

// Short hex colors: "#123" is far more often an issue number than a color, so a three or four digit hex
// needs a letter a-f or a color context (a ":" or "=" right before it, as in CSS or an attribute).
do {
    func sources(_ text: String) -> [String] { ContentDetector.detect(in: text).colors.map(\.source) }
    check(sources("Fixes #123 and #1234").isEmpty, "short hex: issue numbers are not colors", "\(sources("Fixes #123 and #1234"))")
    check(sources("Merged (#123), see #4567").isEmpty, "short hex: an issue in parentheses is not a color")
    check(sources("color: #123") == ["#123"] && firstColor("color: #123")?.hex == "#112233", "short hex: after a colon it is a color")
    check(sources("fill=#1234") == ["#1234"] && sources("fill = #123") == ["#123"], "short hex: after an equals sign it is a color")
    check(sources("#abc and #1a2 and #9F0F") == ["#abc", "#1a2", "#9F0F"], "short hex: a letter a-f makes it a color")
    check(sources("#123456") == ["#123456"] && sources("#12345678") == ["#12345678"], "short hex: six and eight digits need no context")
}

// The phone scan's time budget runs on ContinuousClock, so a wall clock change cannot stretch or cut it.
do {
    check(ContentDetector.phoneBudget == .milliseconds(50), "phone budget: 50 ms on a monotonic clock")
    check(ContentDetector.phoneNumbers(in: "Call (212) 555-0100", limit: 8, budget: .zero).isEmpty,
          "phone budget: a spent budget reads nothing")
    check(ContentDetector.phoneNumbers(in: "Call (212) 555-0100", limit: 8) == ["(212) 555-0100"],
          "phone budget: the default budget reads the number")
}

// ClipboardWriter: every clipboard write Nictate makes (captures, Cycle History, the History window, the
// menu) goes through one writer, which records the change count the write itself produced.
do {
    let board = NSPasteboard(name: NSPasteboard.Name("nictate-test-\(UUID().uuidString)"))
    let writer = ClipboardWriter(pasteboard: board)
    check(writer.lastWrite == nil && writer.ownText == nil, "clipboard writer: nothing written yet")
    check(writer.writeVerified("b", transient: false) && writer.lastWrite == ClipboardWrite(changeCount: board.changeCount, text: "b"),
          "clipboard writer: the recorded count is the one the write produced")
    let trio = ["c", "b", "a"]
    check(HistoryRotation.nextIndex(items: trio, clipboard: writer.ownText) == 2,
          "clipboard writer: after a History window copy of the second, rotation moves on to the third")
    _ = writer.writeVerified("b", transient: true)
    check(writer.existingForAppend() == ExistingClipboard(text: "b", isPrivate: false),
          "clipboard writer: a History window copy with the private setting stays appendable")
    board.clearContents()
    board.setString("elsewhere", forType: .string)
    check(writer.ownText == nil && HistoryRotation.nextIndex(items: trio, clipboard: writer.ownText) == 0,
          "clipboard writer: a copy by another app restarts rotation")
    board.releaseGlobally()

    // Only ClipboardWriter writes the clipboard: no other source calls replaceContents directly.
    if let root = repoRoot {
        let sources = (try? FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("Sources/Nictate").path)) ?? []
        let writers = sources.filter { name in
            guard name.hasSuffix(".swift"), name != "Pasteboard.swift",
                  let code = try? String(contentsOf: root.appendingPathComponent("Sources/Nictate/\(name)"), encoding: .utf8) else { return false }
            return code.contains("replaceContents(")
        }
        check(writers == ["ClipboardWriter.swift"], "clipboard writer: the only caller of replaceContents", "\(writers.sorted())")
    } else {
        check(false, "clipboard writer: the only caller of replaceContents", "repository root not found")
    }
}

// Finding #5: a view or model that is given the history and settings never reaches for the app's own, and Save Captures has one writer.
// Checked in the source: the unit runner cannot build the panel or the Settings tab.
do {
    if let root = repoRoot {
        func codeLines(_ name: String) -> [String] {
            let text = (try? String(contentsOf: root.appendingPathComponent("Sources/Nictate/\(name)"), encoding: .utf8)) ?? ""
            return text.split(separator: "\n").map(String.init).filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
        }
        for name in ["StatusPanel.swift", "StatusPanelView.swift", "HistoryRecovery.swift", "GeneralTab.swift", "HistoryDeletion.swift"] {
            let lines = codeLines(name)
            let reached = lines.filter { $0.contains("History.shared") || $0.contains("Settings.shared") }
            check(!lines.isEmpty && reached.isEmpty, "injection: \(name) uses the history and settings it is given", "\(reached)")
        }
        let defaulted = codeLines("HistoryDeletion.swift").filter { $0.contains("= .shared") }
        check(defaulted.isEmpty, "injection: the clearing commands take the history and settings from their caller", "\(defaulted)")
        let sources = (try? FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("Sources/Nictate").path)) ?? []
        let writers = sources.filter { name in name.hasSuffix(".swift") && codeLines(name).contains { $0.contains(".historyEnabled = ") } }
        check(writers == ["HistoryDeletion.swift"], "save captures: HistoryClearing is the only code that turns it on or off", "\(writers.sorted())")
    } else {
        check(false, "injection: views and models use the history and settings they are given", "repository root not found")
    }
}

// Menu titles for links: a long address is shortened in the middle, so the host is always shown.
do {
    let long = URL(string: "https://example.com/" + String(repeating: "a", count: 80) + "/end")!
    let title = LinkPolicy.menuTitle(for: long)
    check(title.count <= 48 && title.hasPrefix("https://example.com/") && title.contains("…") && title.hasSuffix("/end"),
          "link title: a long link keeps its host and its end", title)
    check(LinkPolicy.menuTitle(for: URL(string: "https://a.com/x")!) == "https://a.com/x", "link title: a short link is shown whole")
    let longHost = URL(string: "https://" + String(repeating: "h", count: 60) + ".com/path")!
    check(LinkPolicy.menuTitle(for: longHost).hasPrefix("https://" + String(repeating: "h", count: 60) + ".com"),
          "link title: a host longer than the limit is never cut")
}

// RecognitionWarmUp and the document reader's bounded wait (both need the host's Vision runtime).
if ProcessInfo.processInfo.environment["SKIP_OCR"] == nil {
    let steps = RecognitionWarmUp.run()
    check(steps.count == 3 && steps.allSatisfy { $0 >= 0 }, "warm-up: one small and one large recognition, then one document read", "\(steps)")
    let warmImage = RecognitionWarmUp.textImage(RecognitionWarmUp.sizes[0])
    let warmRead = warmImage.map { Recognizer.recognize($0, options: RecognitionOptions()).text } ?? ""
    check(warmRead.contains("quick brown fox"), "warm-up: its image holds text the accurate model reads", warmRead.debugDescription)
    let warmLarge = RecognitionWarmUp.textImage(RecognitionWarmUp.sizes[1])
    check(warmLarge?.width == 2880 && warmLarge?.height == 1800,
          "warm-up: the large image is a laptop screen at 2x, under the two-pass size, so it warms the accurate model")
    if let warmImage {
        // A warm read takes about 70-90 ms here, so returning well before that means the wait was cut short.
        let started = DispatchTime.now().uptimeNanoseconds
        let rows = DocumentTables.rows(in: warmImage, timeout: 0)
        let waited = Double(DispatchTime.now().uptimeNanoseconds - started) / 1e9
        check(rows == nil && waited < 0.03, "document tables: a reader slower than the timeout is abandoned, keeping Nictate's own layout", "\(waited) s")
    }
    check(DocumentTables.captureTimeout > 0 && DocumentTables.captureTimeout <= 2, "document tables: a capture never waits more than 2 s for the reader")
}

// KeyGlyph: keys that type no character get a readable label and the matching menu key equivalent.
do {
    let privateUse = { (text: String) in text.unicodeScalars.contains(where: KeyGlyph.isPrivateUse) }
    // AppKit reports these keys as private-use characters (NSUpArrowFunctionKey through NSModeSwitchFunctionKey);
    // whatever character comes with whichever key code, the label must never show one.
    let functionCharacters = (NSUpArrowFunctionKey...NSModeSwitchFunctionKey).map { String(UnicodeScalar(UInt32($0))!) }
    let unnamed = (0..<128).filter { code in
        functionCharacters.contains { privateUse(KeyGlyph.keyLabel(forKeyCode: code, characters: $0)) }
    }
    check(unnamed.isEmpty, "key glyph: no key code labels with a private-use character", "\(unnamed)")
    let blank = KeyGlyph.namedKeyCodes.filter { KeyGlyph.label(forKeyCode: $0)?.isEmpty ?? true }
    check(blank.isEmpty, "key glyph: every named key has a label", "\(blank)")
    check(KeyGlyph.keyLabel(forKeyCode: kVK_F5, characters: "\u{F708}") == "F5", "key glyph: F5 is labelled F5")
    check(KeyGlyph.keyLabel(forKeyCode: kVK_ANSI_2, characters: "2") == "2", "key glyph: a character key keeps its character")
    check(KeyGlyph.keyLabel(forKeyCode: kVK_ANSI_K, characters: "k") == "K", "key glyph: a letter is shown upper-case")
    check(Settings.keyEquivalent(forLabel: "⌃⌘F5") == String(UnicodeScalar(UInt32(NSF5FunctionKey))!),
          "key glyph: the F5 label maps back to NSF5FunctionKey")
    check(Settings.keyEquivalent(forLabel: "⌘F") == "f", "key glyph: the letter F is not mistaken for an F-key")
    check(Settings.keyEquivalent(forLabel: "⌘F12") == String(UnicodeScalar(UInt32(NSF12FunctionKey))!),
          "key glyph: F12 maps to NSF12FunctionKey")
    check(Settings.keyEquivalent(forLabel: "⌥⌘←") == String(UnicodeScalar(UInt32(NSLeftArrowFunctionKey))!),
          "key glyph: the left arrow maps to its function key")
    check(Settings.keyEquivalent(forLabel: "⌘⌫") == "\u{8}", "key glyph: Delete maps to backspace")
    check(Settings.keyEquivalent(forLabel: "⇧⌘2") == "2", "key glyph: a digit label is unchanged")
    check(Settings.keyEquivalent(forLabel: "⌥⌘Space") == " " && Settings.keyEquivalent(forLabel: "⌥⌘Espacio") == " ",
          "key glyph: Space in either language maps to a space")
    check(Settings.keyEquivalent(forLabel: "⌘↩") == "\r" && Settings.keyEquivalent(forLabel: "⌘⇥") == "\t",
          "key glyph: Return and Tab keep their key equivalents")
    check(Settings.keyEquivalent(forLabel: "") == "", "key glyph: an empty label has no key equivalent")
    // Labels saved before KeyGlyph hold the raw character: shown by name, and still the right key equivalent.
    check(KeyGlyph.display("⌘\u{F708}") == "⌘F5", "key glyph: a stored private-use label is shown by name")
    check(Settings.keyEquivalent(forLabel: "⌘\u{F708}") == "\u{F708}", "key glyph: a stored private-use label keeps its key equivalent")
    check(KeyGlyph.display("⇧⌘2") == "⇧⌘2", "key glyph: an ordinary label is shown unchanged")
}

// History deletion (L42): turning history off asks about what is saved, Clear History asks once, and
// clear-on-quit also clears at launch, which covers a crash or a forced quit.
do {
    check(!HistoryDeletion.asksOnSwitchOff(savedCount: 0) && HistoryDeletion.asksOnSwitchOff(savedCount: 3),
          "history deletion: switching off asks only when captures are saved")
    check(HistoryDeletion.clearsOnSwitchOff(savedCount: 3, answer: .delete), "history deletion: Delete clears what is saved")
    check(!HistoryDeletion.clearsOnSwitchOff(savedCount: 3, answer: .keep), "history deletion: Keep leaves what is saved")
    check(!HistoryDeletion.clearsOnSwitchOff(savedCount: 0, answer: .delete), "history deletion: nothing saved, nothing to clear")
    check(!HistoryDeletion.clearsOnSwitchOff(savedCount: 3, answer: .cancel), "history deletion: Cancel deletes nothing")
    check(HistoryDeletion.Answer(response: .alertFirstButtonReturn) == .cancel && HistoryDeletion.Answer(response: .alertSecondButtonReturn) == .keep && HistoryDeletion.Answer(response: .alertThirdButtonReturn) == .delete,
          "history deletion: the buttons map to Cancel, Keep Captures and Delete Captures in order")
    check(HistoryDeletion.Answer(response: .abort) == .cancel && HistoryDeletion.Answer(response: .cancel) == .cancel,
          "history deletion: any dismissal other than Keep or Delete is a cancel")
    for answer in [HistoryDeletion.Answer.cancel, .keep] {
        check(!HistoryDeletion.clearsOnSwitchOff(savedCount: 5, answer: answer), "history deletion: \(answer) deletes nothing")
    }
    check(HistoryDeletion.showsClearControl(historyEnabled: true, savedCount: 0), "history deletion: Clear History shows while history is on")
    check(HistoryDeletion.showsClearControl(historyEnabled: false, savedCount: 2),
          "history deletion: captures kept after switching off keep Clear History visible")
    check(!HistoryDeletion.showsClearControl(historyEnabled: false, savedCount: 0), "history deletion: history off and empty hides Clear History")
    check(!HistoryDeletion.asksBeforeClear(savedCount: 0) && HistoryDeletion.asksBeforeClear(savedCount: 1),
          "history deletion: Clear History asks once, when there is something to delete")
    check(HistoryDeletion.clearsAtLaunch(clearOnQuit: true, savedCount: 4), "history deletion: clear-on-quit also clears at launch")
    check(!HistoryDeletion.clearsAtLaunch(clearOnQuit: false, savedCount: 4), "history deletion: without clear-on-quit, launch keeps history")
    check(!HistoryDeletion.clearsAtLaunch(clearOnQuit: true, savedCount: 0), "history deletion: nothing saved, nothing cleared at launch")
    check(HistoryDeletion.switchOffQuestion(savedCount: 1) == "Delete the saved capture too?"
          && HistoryDeletion.switchOffQuestion(savedCount: 5) == "Delete the 5 saved captures too?",
          "history deletion: the switch-off question names how many", HistoryDeletion.switchOffQuestion(savedCount: 5))
    check(HistoryDeletion.clearQuestion(savedCount: 1) == "Delete the saved capture?"
          && HistoryDeletion.clearQuestion(savedCount: 12) == "Delete all 12 saved captures?",
          "history deletion: the Clear History question names how many", HistoryDeletion.clearQuestion(savedCount: 12))
}

// The app joins the Dock only while one of its windows is open.
do {
    check(WindowCoordinator.activationPolicy(openWindows: 0) == .accessory, "dock: no window open keeps Nictate out of the Dock")
    check(WindowCoordinator.activationPolicy(openWindows: 1) == .regular && WindowCoordinator.activationPolicy(openWindows: 3) == .regular,
          "dock: any open window puts Nictate in the Dock and the menu bar")
}

// Main menu: the key equivalents text fields and windows rely on exist, each with an action.
do {
    let main = MainMenu(showSettings: {}, canFind: { false })
    func items(_ menu: NSMenu) -> [NSMenuItem] { menu.items + menu.items.compactMap(\.submenu).flatMap(items) }
    let all = items(main.menu)
    let plainCommand = all.filter { $0.keyEquivalentModifierMask == .command }
    let keys = Set(plainCommand.map(\.keyEquivalent))
    let wanted: Set<String> = ["x", "c", "v", "a", "z", "w", "q", ",", "f", "m", "h"]
    check(wanted.isSubset(of: keys), "main menu: ⌘X ⌘C ⌘V ⌘A ⌘Z ⌘W ⌘Q ⌘, ⌘F ⌘M ⌘H are there", "\(wanted.subtracting(keys).sorted())")
    check(all.contains { $0.keyEquivalent == "z" && $0.keyEquivalentModifierMask == [.command, .shift] }, "main menu: ⇧⌘Z redoes")
    let withKey = all.filter { !$0.keyEquivalent.isEmpty }
    check(withKey.allSatisfy { $0.action != nil }, "main menu: every key equivalent has an action")
    let shortcuts = withKey.map { "\($0.keyEquivalentModifierMask.rawValue)-\($0.keyEquivalent)" }
    check(Set(shortcuts).count == shortcuts.count, "main menu: no key equivalent is used twice", "\(shortcuts.sorted())")
    let byAction = { (selector: Selector) in all.first { $0.action == selector } }
    check(byAction(#selector(NSText.copy(_:)))?.keyEquivalent == "c" && byAction(#selector(NSText.paste(_:)))?.keyEquivalent == "v"
          && byAction(#selector(NSResponder.selectAll(_:)))?.keyEquivalent == "a" && byAction(#selector(NSWindow.performClose(_:)))?.keyEquivalent == "w",
          "main menu: copy, paste, select all and close go to the focused field or window")
    check([#selector(NSText.copy(_:)), #selector(NSText.paste(_:)), #selector(NSWindow.performClose(_:))].allSatisfy { byAction($0)?.target == nil },
          "main menu: edit and window items have no target, so the responder chain picks the receiver")
    check(main.menu.items.map(\.title) == ["Nictate", "Edit", "Window"] && main.windowMenu === main.menu.items.last?.submenu,
          "main menu: Nictate, Edit and Window menus", "\(main.menu.items.map(\.title))")
    let find = all.first { $0.keyEquivalent == "f" }
    check(find.map { !main.validateMenuItem($0) } ?? false, "main menu: Find is off unless History is the key window")
    let findable = MainMenu(showSettings: {}, canFind: { true })
    check(items(findable.menu).first { $0.keyEquivalent == "f" }.map(findable.validateMenuItem) ?? false, "main menu: Find is on in History")
    var opened = false
    let opener = MainMenu(showSettings: { opened = true }, canFind: { false })
    if let settingsItem = items(opener.menu).first(where: { $0.keyEquivalent == "," }), let action = settingsItem.action {
        _ = (settingsItem.target as? NSObject)?.perform(action, with: settingsItem)
    }
    check(opened, "main menu: ⌘, opens Settings")
}

// Accessibility looks: every combination of Reduce Transparency and Increase Contrast picks the right variant.
do {
    for (reduce, increase) in [(false, false), (true, false), (false, true), (true, true)] {
        let look = AccessibilityLook(reduceTransparency: reduce, increaseContrast: increase)
        check(look.contrast == (increase ? .increased : .standard),
              "look: Increase Contrast alone decides the variant (reduce \(reduce), increase \(increase))")
    }
    check(Design.Stroke.width(.standard) == Design.Stroke.hairline && Design.Stroke.width(.increased) == Design.Stroke.contrast,
          "look: the card edge is 0.75 pt, and 2 pt under Increase Contrast")
    check(Design.Stroke.width(.increased) > Design.Stroke.width(.standard), "look: the high-contrast edge is wider")
}

// Design system contrast: every text pair reaches 4.5:1 and every functional icon or border 3:1, measured
// with WCAG relative luminance on the token values in the design tokens.
do {
    func luminance(_ hex: String) -> Double {
        let digits = Array(hex.dropFirst())
        let channels = stride(from: 0, to: 6, by: 2).map { i -> Double in
            let v = Double(Int(String(digits[i...i + 1]), radix: 16) ?? 0) / 255
            return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2]
    }
    func ratio(_ a: String, _ b: String) -> Double {
        let (la, lb) = (luminance(a), luminance(b))
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }
    let paperLight = "#f5f5f7", paperDark = "#0b0b12"
    let pairs: [(name: String, foreground: String, background: String, minimum: Double)] = [
        ("success text, light", "#1d7a33", paperLight, 4.5),
        ("success text, dark", "#30d158", paperDark, 4.5),
        ("warning text, light", "#b35400", paperLight, 4.5),
        ("warning text, dark", "#ff9f0a", paperDark, 4.5),
        ("danger, light", "#d70015", paperLight, 4.5),
        ("danger, dark", "#ff453a", paperDark, 4.5),
        ("success-ic, light", "#18692c", paperLight, 4.5),
        ("success-ic, dark", "#5ef08a", paperDark, 4.5),
        ("warning-ic, light", "#8a3d00", paperLight, 4.5),
        ("warning-ic, dark", "#ffc04d", paperDark, 4.5),
        ("ink-secondary-ic, light", "#3a3a3c", paperLight, 4.5),
        ("ink-secondary-ic, dark", "#d1d1d6", paperDark, 4.5),
        ("on-accent, light, on the accent", "#ffffff", "#545cfa", 4.5),
        ("on-accent, dark, on the accent", "#0b0b12", "#7b80ff", 4.5),
        ("success icon, light", "#248a3d", paperLight, 3),
        ("warning icon, light", "#c96a00", paperLight, 3),
        ("hairline-ic, light, border", "#6e6e73", paperLight, 3),
        ("hairline-ic, dark, border", "#8e8e93", paperDark, 3),
        ("switch-off, light, on a white card", "#8e8e93", "#ffffff", 3),
    ]
    for pair in pairs {
        let measured = ratio(pair.foreground, pair.background)
        check(measured >= pair.minimum, "contrast: \(pair.name) reaches \(pair.minimum):1", String(format: "%.2f:1", measured))
    }
}

// Contrast of the system colours the app uses, resolved for each appearance (not the tokens' stand-ins).
// Known gaps are asserted at their measured value, so they stay visible and any change to them is caught.
do {
    func srgb(_ color: NSColor, _ appearance: NSAppearance.Name) -> (Double, Double, Double, Double) {
        var out = (0.0, 0.0, 0.0, 1.0)
        NSAppearance(named: appearance)!.performAsCurrentDrawingAppearance {
            let c = color.usingColorSpace(.sRGB)!
            out = (Double(c.redComponent), Double(c.greenComponent), Double(c.blueComponent), Double(c.alphaComponent))
        }
        return out
    }
    func lin(_ v: Double) -> Double { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
    func luminance(_ c: (Double, Double, Double, Double)) -> Double { 0.2126 * lin(c.0) + 0.7152 * lin(c.1) + 0.0722 * lin(c.2) }
    /// Contrast of `text` over an opaque `ground`, with the text's alpha applied first.
    func contrast(_ text: (Double, Double, Double, Double), over ground: (Double, Double, Double, Double)) -> Double {
        let a = text.3
        let mixed = (text.0 * a + ground.0 * (1 - a), text.1 * a + ground.1 * (1 - a), text.2 * a + ground.2 * (1 - a), 1.0)
        let (x, y) = (luminance(mixed), luminance(ground))
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }
    let light = NSAppearance.Name.aqua, dark = NSAppearance.Name.darkAqua
    let cardLight = srgb(.controlBackgroundColor, light), cardDark = srgb(.controlBackgroundColor, dark)
    let windowLight = srgb(.windowBackgroundColor, light), windowDark = srgb(.windowBackgroundColor, dark)

    for (name, text, ground) in [
        ("primary label, light, on the card", srgb(.labelColor, light), cardLight),
        ("primary label, dark, on the card", srgb(.labelColor, dark), cardDark),
        ("primary label, light, on the window", srgb(.labelColor, light), windowLight),
        ("primary label, dark, on the window", srgb(.labelColor, dark), windowDark),
    ] {
        check(contrast(text, over: ground) >= 4.5, "system contrast: \(name) reaches 4.5:1",
              String(format: "%.2f:1", contrast(text, over: ground)))
    }

    // Open difference: the system's secondary label is below 4.5:1 in Light. Asserted at the measured value.
    let secondaryLightOnCard = contrast(srgb(.secondaryLabelColor, light), over: cardLight)
    check(abs(secondaryLightOnCard - 3.95) < 0.05,
          "system contrast: secondary label in Light is the measured open difference (3.95:1, below 4.5:1)",
          String(format: "%.2f:1", secondaryLightOnCard))
    let secondaryDarkOnCard = contrast(srgb(.secondaryLabelColor, dark), over: cardDark)
    check(secondaryDarkOnCard >= 4.5, "system contrast: secondary label reaches 4.5:1 in Dark",
          String(format: "%.2f:1", secondaryDarkOnCard))

    // The user's accent is set in System Settings, so only the current one can be measured here. The label
    // colour the system picks is the better of white and black. Other accents need measuring on a Mac.
    let accentLight = srgb(.controlAccentColor, light)
    let best = max(contrast((1, 1, 1, 1), over: accentLight), contrast((0, 0, 0, 1), over: accentLight))
    print("NOTE  system accent (current, light): best label contrast \(String(format: "%.2f", best)):1; other accents need a Mac check")
}

// Colour tokens resolve to their design values in each appearance (light and dark).
do {
    func resolved(_ color: Color, _ appearance: NSAppearance.Name) -> (Double, Double, Double) {
        var out = (0.0, 0.0, 0.0)
        NSAppearance(named: appearance)!.performAsCurrentDrawingAppearance {
            let c = NSColor(color).usingColorSpace(.sRGB)!
            out = (Double(c.redComponent), Double(c.greenComponent), Double(c.blueComponent))
        }
        return out
    }
    func hex(_ value: String) -> (Double, Double, Double) {
        let digits = Array(value.dropFirst())
        func channel(_ i: Int) -> Double { Double(Int(String(digits[i...i + 1]), radix: 16) ?? 0) / 255 }
        return (channel(0), channel(2), channel(4))
    }
    let tokens: [(String, Color, String, String)] = [
        ("success", ColorTokens.success, "#1d7a33", "#30d158"),
        ("success-ic", ColorTokens.successIc, "#18692c", "#5ef08a"),
        ("warning", ColorTokens.warning, "#b35400", "#ff9f0a"),
        ("warning-ic", ColorTokens.warningIc, "#8a3d00", "#ffc04d"),
        ("danger", ColorTokens.danger, "#d70015", "#ff453a"),
        ("ink-secondary-ic", ColorTokens.inkSecondaryIc, "#3a3a3c", "#d1d1d6"),
        ("hairline-ic", ColorTokens.hairlineIc, "#6e6e73", "#8e8e93"),
        ("switch-off", ColorTokens.switchOff, "#8e8e93", "#8e8e93"),
        ("field-border", ColorTokens.fieldBorder, "#8e8e93", "#8e8e93"),
    ]
    for (name, color, light, dark) in tokens {
        let lightValue = resolved(color, .aqua), darkValue = resolved(color, .darkAqua)
        let expectedLight = hex(light), expectedDark = hex(dark)
        let lightOK = abs(lightValue.0 - expectedLight.0) < 0.01 && abs(lightValue.1 - expectedLight.1) < 0.01 && abs(lightValue.2 - expectedLight.2) < 0.01
        let darkOK = abs(darkValue.0 - expectedDark.0) < 0.01 && abs(darkValue.1 - expectedDark.1) < 0.01 && abs(darkValue.2 - expectedDark.2) < 0.01
        check(lightOK && darkOK, "tokens: \(name) resolves to its design token value in Light and Dark", "\(light) / \(dark)")
    }
}

// Secondary text, provisional AA token and the Increase Contrast token, on the grounds each appearance uses.
do {
    func resolvedRGB(_ color: Color, _ appearance: NSAppearance.Name) -> (Double, Double, Double, Double) {
        var out = (0.0, 0.0, 0.0, 1.0)
        NSAppearance(named: appearance)!.performAsCurrentDrawingAppearance {
            let c = NSColor(color).usingColorSpace(.sRGB)!
            out = (Double(c.redComponent), Double(c.greenComponent), Double(c.blueComponent), Double(c.alphaComponent))
        }
        return out
    }
    func luminance(_ c: (Double, Double, Double, Double)) -> Double {
        func lin(_ v: Double) -> Double { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(c.0) + 0.7152 * lin(c.1) + 0.0722 * lin(c.2)
    }
    func ratio(_ text: (Double, Double, Double, Double), _ ground: (Double, Double, Double, Double)) -> Double {
        let (x, y) = (luminance(text), luminance(ground))
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }
    func grey(_ v: Double) -> (Double, Double, Double, Double) { (v / 255, v / 255, v / 255, 1) }
    let lightGrounds = [grey(255), grey(236)], darkGrounds = [grey(30), grey(43)]
    for ground in lightGrounds {
        let measured = ratio(resolvedRGB(Design.Ink.secondary, .aqua), ground)
        check(measured >= 4.5, "secondary text (provisional AA): Light reaches 4.5:1 on \(Int(ground.0 * 255))", String(format: "%.2f:1", measured))
    }
    for ground in darkGrounds {
        let measured = ratio(resolvedRGB(Design.Ink.secondary, .darkAqua), ground)
        check(measured >= 4.5, "secondary text (provisional AA): Dark reaches 4.5:1 on \(Int(ground.0 * 255))", String(format: "%.2f:1", measured))
    }
    check(ratio(resolvedRGB(Design.Ink.text(.increased), .aqua), lightGrounds[1]) >= 7,
          "secondary text, Increase Contrast: Light is at least 7:1 on the window grey")
}

// Region selection: the rules of the drag, the keys, the pixel crop, and pill placement.
do {
    let bounds = CGRect(x: 0, y: 0, width: 800, height: 600)
    let dragged = SelectionGeometry.rect(from: CGPoint(x: 300, y: 200), to: CGPoint(x: 100, y: 50), within: bounds)
    check(dragged == CGRect(x: 100, y: 50, width: 200, height: 150), "selection: a drag in any direction spans the same rectangle", "\(dragged)")
    let cut = SelectionGeometry.rect(from: CGPoint(x: -50, y: 10), to: CGPoint(x: 100, y: 900), within: bounds)
    check(cut == CGRect(x: 0, y: 10, width: 100, height: 590), "selection: a drag past the edge is cut at the screen", "\(cut)")
    check(SelectionGeometry.rect(from: CGPoint(x: -20, y: -20), to: CGPoint(x: -5, y: -5), within: bounds) == .zero,
          "selection: a drag entirely off the screen is empty")
    check(SelectionGeometry.isRegion(CGRect(x: 0, y: 0, width: 4, height: 4)) && !SelectionGeometry.isRegion(CGRect(x: 0, y: 0, width: 3, height: 40)),
          "selection: four points is the smallest region, a thinner one is a click")
    let snapped = SelectionGeometry.snapped(CGPoint(x: 10.3, y: 20.7), scale: 2)
    check(snapped == CGPoint(x: 10.5, y: 20.5), "selection: a point snaps to the nearest pixel of a 2x display", "\(snapped)")
    let stepped = SelectionGeometry.moved(CGPoint(x: 799, y: 0.5), dx: 10, dy: -1, within: bounds)
    check(stepped == CGPoint(x: 800, y: 0), "selection: the pointer moves by a step and stops at the edge", "\(stepped)")
    let pixels = SelectionGeometry.pixelRect(for: CGRect(x: 10, y: 20, width: 30, height: 40), within: bounds, scale: 2)
    check(pixels == CGRect(x: 20, y: 1080, width: 60, height: 80),
          "selection: points become pixels, with y counted from the top of the still", "\(pixels)")
    let below = SelectionGeometry.pillOrigin(size: CGSize(width: 100, height: 24), below: CGRect(x: 300, y: 300, width: 200, height: 100), within: bounds)
    check(below == CGPoint(x: 350, y: 268), "pill: sits under the selection, centred", "\(below)")
    let above = SelectionGeometry.pillOrigin(size: CGSize(width: 100, height: 24), below: CGRect(x: 300, y: 0, width: 200, height: 100), within: bounds)
    check(above == CGPoint(x: 350, y: 108), "pill: moves above the selection when there is no room below", "\(above)")
    let edge = SelectionGeometry.pillOrigin(size: CGSize(width: 100, height: 24), below: CGRect(x: 0, y: 300, width: 40, height: 40), within: bounds)
    check(edge.x == 8, "pill: is kept on screen at the left edge", "\(edge)")
}

// Selection outline: a light band inside and a dark band outside each edge, with four corner marks, on whole device pixels.
do {
    func linear(_ v: Double) -> Double { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
    func overlaps(_ a: CGRect, _ b: CGRect) -> Bool {
        let shared = a.intersection(b)
        return !shared.isNull && shared.width * shared.height > 0
    }
    let standard = SelectionOutline.style(.standard), increased = SelectionOutline.style(.increased)
    check(standard == SelectionOutline.Style(innerWidth: 1, innerAlpha: 0.9, outerWidth: 1, outerAlpha: 0.35),
          "outline: the standard edge is 1 pt white at 90 % inside and 1 pt black at 35 % outside")
    check(increased == SelectionOutline.Style(innerWidth: 2, innerAlpha: 1, outerWidth: 1, outerAlpha: 0.8),
          "outline: Increase Contrast is 2 pt white at 100 % inside and 1 pt black at 80 % outside")
    check(SelectionOutline.cornerExtra == 1, "outline: each corner mark thickens its band by 1 pt")

    // Corner arms: 12 pt, at most a third of the shorter side, rounded down to whole pixels.
    let large = CGRect(x: 0, y: 0, width: 200, height: 100), small = CGRect(x: 0, y: 0, width: 30, height: 20)
    let tiny = CGRect(x: 0, y: 0, width: 4, height: 4)
    check(SelectionGeometry.cornerLength(for: large, scale: 2) == 12, "outline: corner arms are 12 pt on a large selection at 2x")
    check(SelectionGeometry.cornerLength(for: small, scale: 2) == 6.5,
          "outline: corner arms are a third of the shorter side, on a whole pixel, at 2x")
    check(SelectionGeometry.cornerLength(for: small, scale: 1) == 6, "outline: corner arms are whole points at 1x")
    check(SelectionGeometry.cornerLength(for: tiny, scale: 1) == 1 && SelectionGeometry.cornerLength(for: tiny, scale: 2) == 1,
          "outline: corner arms on a 4 pt selection are 1 pt")

    // Every edge of every band and corner mark lands on a device pixel, at 1x and 2x, in both styles.
    for scale in [CGFloat(1), 2] {
        let origin = SelectionGeometry.snapped(CGPoint(x: 10.3, y: 20.7), scale: scale)
        let far = SelectionGeometry.snapped(CGPoint(x: 70.9, y: 61.2), scale: scale)
        let selection = SelectionGeometry.rect(from: origin, to: far, within: CGRect(x: 0, y: 0, width: 200, height: 200))
        for (name, style) in [("standard", standard), ("increased", increased)] {
            var rects: [CGRect] = []
            for outside in [false, true] {
                let width = outside ? style.outerWidth : style.innerWidth
                rects += SelectionGeometry.band(around: selection, width: width, outside: outside)
                rects += SelectionGeometry.cornerMarks(of: selection, length: SelectionGeometry.cornerLength(for: selection, scale: scale),
                                                       thickness: width + SelectionOutline.cornerExtra, outside: outside)
            }
            let aligned = rects.allSatisfy { r in
                [r.minX, r.maxX, r.minY, r.maxY].allSatisfy { v in abs(v * scale - (v * scale).rounded()) < 1e-6 }
            }
            check(aligned, "outline: every band and corner mark has its edges on a device pixel (\(name), \(scale)x)")
        }
    }

    // The light band and its marks lie inside the selection; the dark band and its marks only touch it from outside;
    // the strips of one band never overlap.
    let frame = CGRect(x: 40, y: 30, width: 120, height: 80)
    for (name, style) in [("standard", standard), ("increased", increased)] {
        let length = SelectionGeometry.cornerLength(for: frame, scale: 2)
        let inner = SelectionGeometry.band(around: frame, width: style.innerWidth, outside: false)
        let outer = SelectionGeometry.band(around: frame, width: style.outerWidth, outside: true)
        let innerMarks = SelectionGeometry.cornerMarks(of: frame, length: length, thickness: style.innerWidth + SelectionOutline.cornerExtra, outside: false)
        let outerMarks = SelectionGeometry.cornerMarks(of: frame, length: length, thickness: style.outerWidth + SelectionOutline.cornerExtra, outside: true)
        check((inner + innerMarks).allSatisfy { frame.contains($0) }, "outline: the light band and its corner marks lie inside the selection (\(name))")
        check((outer + outerMarks).allSatisfy { r in
            let shared = frame.intersection(r)
            return shared.isNull || shared.width * shared.height == 0
        }, "outline: the dark band and its corner marks never enter the selection (\(name))")
        for strips in [inner, outer] {
            let pairs = strips.indices.flatMap { i in strips.indices.filter { $0 > i }.map { (i, $0) } }
            check(!pairs.contains { overlaps(strips[$0.0], strips[$0.1]) }, "outline: the strips of one band do not overlap (\(name))")
        }
        // The outer corner squares, beyond the selection's corners, are covered by the dark corner marks.
        let outerThickness = style.outerWidth + SelectionOutline.cornerExtra
        let outerCorners = [CGPoint(x: frame.minX, y: frame.minY), CGPoint(x: frame.maxX, y: frame.minY),
                            CGPoint(x: frame.minX, y: frame.maxY), CGPoint(x: frame.maxX, y: frame.maxY)]
        let squares = outerCorners.map { c in
            CGPoint(x: c.x + (c.x == frame.minX ? -outerThickness / 2 : outerThickness / 2),
                    y: c.y + (c.y == frame.minY ? -outerThickness / 2 : outerThickness / 2))
        }
        check(squares.allSatisfy { p in outerMarks.contains { $0.contains(p) } },
              "outline: the dark corner marks cover the four outer corner squares (\(name))")
    }

    // Contrast between the two bands on any content: the light band over black content is the least bright it gets,
    // and the dark band over white content that the overlay dims is the brightest it gets. Each dimming level, in both
    // styles, must keep them 3:1 apart (WCAG 1.4.11) or more.
    for (dimming, dim) in [("Light", 0.28), ("Dark", 0.45)] {
        for (name, style) in [("standard", standard), ("increased", increased)] {
            let lightest = style.innerAlpha
            let darkest = (1 - style.outerAlpha) * (1 - dim)
            let ratio = (linear(lightest) + 0.05) / (linear(darkest) + 0.05)
            check(ratio >= 3, "outline: the two bands are at least 3:1 apart on any content (\(dimming), \(name))",
                  String(format: "%.2f:1", ratio))
        }
    }
}

// History file: a readable JSON file in the test folder. A changed or truncated file is rejected, and it is never
// overwritten: the history stays unavailable until the file can be read again.
do {
    let store = sealedStore("file")
    let history = History(store: store, isEnabled: alwaysSaving)
    history.add("kept across restarts", at: Date(timeIntervalSince1970: 1_000))
    History.flushWrites()
    check(History(store: store, isEnabled: alwaysSaving).items == ["kept across restarts"], "file: captures are read back after a restart")

    var broken = (try? Data(contentsOf: store.fileURL)) ?? Data()
    broken.removeLast(5)
    try? broken.write(to: store.fileURL)
    let rejected = History(store: store, isEnabled: alwaysSaving)
    check(rejected.items.isEmpty && rejected.state == .unavailable, "file: a truncated file is not shown as an empty history")
    rejected.add("after damage")
    History.flushWrites()
    check((try? Data(contentsOf: store.fileURL)) == broken, "file: a damaged file is never overwritten")
}

// Sealed history: authorization can be denied, delayed or restored, and none of those states writes over the
// file, shows an empty history by mistake, or blocks the caller. The one thing it may do is read the file again.
do {
    let stored = HistorySnapshot(texts: ["old"], dates: [1_000])

    // Denied: unavailable, captures stay in memory, the file is never written.
    let denied = ScriptedStore(answers: [.unavailable], saved: stored)
    let deniedHistory = History(store: denied, isEnabled: alwaysSaving)
    deniedHistory.add("new", at: Date(timeIntervalSince1970: 2_000))
    History.flushWrites()
    check(deniedHistory.state == .unavailable && deniedHistory.items.isEmpty,
          "authorization: denied shows unavailable and keeps no capture, not even in memory")
    check(denied.saves == 0 && denied.saved == stored, "authorization: denied never writes the file")

    // Delayed, then granted: loading, then the stored history merged with what was captured meanwhile.
    let delayed = ScriptedStore(answers: [.unavailable, .loaded(stored)], saved: stored)
    let delayedHistory = History(store: delayed, isEnabled: alwaysSaving)
    delayedHistory.add("while waiting", at: Date(timeIntervalSince1970: 2_000))
    settle { await delayedHistory.reload() }
    History.flushWrites()
    check(delayedHistory.state == .available && delayedHistory.items == ["old"],
          "authorization: a capture made while locked is not kept, so granting later restores only the stored history",
          "\(delayedHistory.items)")
    check(delayed.saved == stored, "authorization: nothing is written for captures that were not kept")

    // Recovery: after a denial the original history loads again, unchanged.
    let recovered = ScriptedStore(answers: [.unavailable, .loaded(stored)], saved: stored)
    let recoveredHistory = History(store: recovered, isEnabled: alwaysSaving)
    settle { await recoveredHistory.reload() }
    check(recoveredHistory.items == ["old"] && recoveredHistory.state == .available && recovered.saves == 0,
          "authorization: recovery shows the original history and writes nothing new")

    // A removal made while unavailable is not undone by the older copy on disk.
    let removal = ScriptedStore(answers: [.unavailable, .loaded(stored)], saved: stored)
    let removalHistory = History(store: removal, isEnabled: alwaysSaving)
    removalHistory.remove("old")
    settle { await removalHistory.reload() }
    History.flushWrites()
    check(removalHistory.items.isEmpty && removal.saved?.texts == [],
          "authorization: a removal made while unavailable is applied once the file can be read")

    // Corrupt: the file is kept as it is, and the history is unavailable rather than empty.
    let corrupt = ScriptedStore(answers: [.corrupt], saved: stored)
    let corruptHistory = History(store: corrupt, isEnabled: alwaysSaving)
    corruptHistory.add("kept", at: Date(timeIntervalSince1970: 2_000))
    History.flushWrites()
    check(corruptHistory.state == .unavailable && corrupt.saves == 0 && corrupt.saved == stored,
          "authorization: a corrupt file is never overwritten")

    // Disabled: no load at all, so no Keychain access.
    let disabled = ScriptedStore(answers: [.loaded(stored)], saved: stored)
    let disabledHistory = History(store: disabled, isEnabled: { false }, loadsNow: false)
    disabledHistory.refresh()
    check(disabledHistory.state == .disabled && disabled.loads == 0,
          "authorization: a disabled history never reads the file or the key")

    // Loading from the app's path does not run the read on the main thread, and the caller gets control back.
    let slow = ScriptedStore(answers: [.loaded(stored)], saved: stored)
    let slowHistory = History(store: slow, isEnabled: alwaysSaving, loadsNow: false)
    check(slowHistory.state == .loading && slowHistory.items.isEmpty && slow.loads == 0,
          "authorization: the app's history starts loading without reading the file at launch")
    settle { await slowHistory.reload() }
    check(slowHistory.items == ["old"] && slowHistory.state == .available, "authorization: the background load shows the history")

    // Launch regression: a history that starts in `loading` must still start its read when the app asks.
    let launched = ScriptedStore(answers: [.loaded(stored)], saved: stored)
    let launchedHistory = History(store: launched, isEnabled: { true }, loadsNow: false)
    settle { await launchedHistory.refresh()?.value }
    check(launched.loads == 1 && launchedHistory.items == ["old"] && launchedHistory.state == .available,
          "authorization: refresh at launch starts the read, which had been skipped while the state was loading",
          "loads \(launched.loads), state \(launchedHistory.state)")
}

// Recognized languages: the compact summary shows the names, and says how many more there are.
do {
    check(RecognitionTab.summary(of: []) == tr("Automatic"), "languages: nothing chosen is Automatic")
    check(RecognitionTab.summary(of: ["English"]) == "English", "languages: one name is shown as it is")
    check(RecognitionTab.summary(of: ["English", "Spanish"]) == "English, Spanish", "languages: two names are both shown")
    check(RecognitionTab.summary(of: ["English", "Spanish", "French"]) == "English, Spanish +1", "languages: more than two shows the first two and +count")
}

// The limit: History keeps exactly 15 captures, on disk and on screen, newest first, and the oldest goes when a 16th arrives.
do {
    check(HistoryPolicy.maximumHistoryEntries == 15, "limit: the maximum is 15")
    for count in [0, 1, 14, 15, 16, 100] {
        let store = sealedStore("limit-\(count)")
        let history = History(store: store, isEnabled: alwaysSaving)
        for index in 0..<count { history.add("capture \(index)", at: Date(timeIntervalSince1970: Double(index))) }
        History.flushWrites()
        let expected = min(count, 15)
        let onDisk = History(store: store, isEnabled: alwaysSaving).items
        check(history.items.count == expected && onDisk.count == expected,
              "limit: \(count) captures leave \(expected) on screen and on disk", "\(history.items.count), \(onDisk.count)")
    }
    let newest = History(store: sealedStore("limit-order"), isEnabled: alwaysSaving)
    for index in 0..<16 { newest.add("capture \(index)", at: Date(timeIntervalSince1970: Double(index))) }
    History.flushWrites()
    check(newest.items.first == "capture 15" && newest.items.last == "capture 1" && !newest.items.contains("capture 0"),
          "limit: the 16th capture is first and the oldest one is gone", "\(newest.items.first ?? "-") … \(newest.items.last ?? "-")")

    let big = sealedStore("limit-load")
    let many = HistorySnapshot(texts: (0..<40).map { "stored \($0)" }, dates: (0..<40).map { Double(1_000 - $0) })
    _ = big.save(many)
    let loaded = History(store: big, isEnabled: alwaysSaving)
    check(loaded.items.count == 15 && loaded.items.first == "stored 0",
          "limit: a file with more than 15 entries loads only its newest 15", "\(loaded.items.count)")
    loaded.remove("stored 0")
    loaded.add("fresh")
    History.flushWrites()
    check(loaded.items.count == 15 && loaded.items.first == "fresh" && !loaded.items.contains("stored 0") && loaded.items.contains("stored 14"),
          "limit: deleting one and adding another keeps 15, with the newest first")
    check(History(store: big, isEnabled: alwaysSaving).items.count == 15, "limit: after a restart the file still holds 15")

    let duplicate = History(store: sealedStore("limit-duplicate"), isEnabled: alwaysSaving)
    duplicate.add("same", at: Date(timeIntervalSince1970: 1))
    duplicate.add("same", at: Date(timeIntervalSince1970: 2))
    History.flushWrites()
    check(duplicate.items == ["same"], "limit: a repeated capture moves to the front rather than duplicating")
}

// Import of the encrypted history.sealed of earlier versions: explicit, merged with what the new History holds,
// verified by reading back, and never destructive. Every file here is a disposable fixture.
do {
    let fixtureKey = SymmetricKey(data: Data(repeating: 7, count: 32))
    let legacyURL = testPreferences.appendingPathComponent("legacy-\(UUID().uuidString).sealed")
    func writeLegacy(_ snapshot: HistorySnapshot) {
        let plain = (try? JSONEncoder().encode(snapshot)) ?? Data()
        try? ((try? LegacyHistoryCipher.seal(plain, key: fixtureKey)) ?? Data()).write(to: legacyURL)
    }
    func destination() -> JSONHistoryStore { sealedStore("imported") }

    let absent = LegacyHistoryMigration.run(legacy: testPreferences.appendingPathComponent("absent.sealed"),
                                            destination: destination(), key: { fixtureKey })
    if case .failed = absent {} else { check(false, "import: a missing legacy file writes nothing") }

    let legacy = HistorySnapshot(texts: ["second", "first"], dates: [2_000, 1_000])
    writeLegacy(legacy)
    let legacyBytes = (try? Data(contentsOf: legacyURL)) ?? Data()
    let fresh = destination()
    check(LegacyHistoryMigration.run(legacy: legacyURL, destination: fresh, key: { fixtureKey }) == .imported(count: 2, dropped: 0),
          "import: a valid legacy file is imported")
    check(fresh.load() == .loaded(legacy), "import: the imported history reads back exactly, newest first")
    check((try? Data(contentsOf: legacyURL)) == legacyBytes, "import: the encrypted file is left byte for byte unchanged")
    check(LegacyHistoryMigration.run(legacy: legacyURL, destination: fresh, key: { fixtureKey }) == .imported(count: 2, dropped: 0)
          && fresh.load() == .loaded(legacy),
          "import: importing the same file again adds nothing and duplicates nothing")

    let current = destination()
    _ = current.save(HistorySnapshot(texts: ["now"], dates: [9_000]))
    check(LegacyHistoryMigration.run(legacy: legacyURL, destination: current, key: { fixtureKey }) == .imported(count: 3, dropped: 0)
          && current.load() == .loaded(HistorySnapshot(texts: ["now", "second", "first"], dates: [9_000, 2_000, 1_000])),
          "import: captures already in the new History are kept and merged, newest first")

    let big = (0..<20).map { "old \($0)" }
    writeLegacy(HistorySnapshot(texts: big, dates: (0..<20).map { Double(5_000 - $0) }))
    let capped = destination()
    check(LegacyHistoryMigration.run(legacy: legacyURL, destination: capped, key: { fixtureKey }) == .imported(count: 15, dropped: 5),
          "import: more than 15 legacy captures import only the newest 15")
    if case .loaded(let got) = capped.load() {
        check(got.texts == Array(big.prefix(15)), "import: the 15 kept are the newest, in order")
    }

    let missingKey = destination()
    let outcome = LegacyHistoryMigration.run(legacy: legacyURL, destination: missingKey, key: { throw LegacyHistoryKeychain.Failure.status(errSecItemNotFound) })
    check(outcome != .imported(count: 15, dropped: 5) && missingKey.load() == .empty,
          "import: a missing key writes nothing and the legacy file stays", "\(outcome)")
    let cancelled = destination()
    check(LegacyHistoryMigration.run(legacy: legacyURL, destination: cancelled, key: { throw LegacyHistoryKeychain.Failure.status(errSecUserCanceled) }) == .cancelled
          && cancelled.load() == .empty,
          "import: a cancelled authorization writes nothing and reports cancelled")
    let wrongKey = destination()
    let wrongOutcome = LegacyHistoryMigration.run(legacy: legacyURL, destination: wrongKey, key: { SymmetricKey(data: Data(repeating: 1, count: 32)) })
    check(wrongOutcome != .imported(count: 15, dropped: 5) && wrongKey.load() == .empty,
          "import: a decryption failure writes nothing", "\(wrongOutcome)")

    let unreadable = sealedStore("import-unreadable")
    try? "not json".data(using: .utf8)?.write(to: unreadable.fileURL)
    writeLegacy(legacy)
    check(LegacyHistoryMigration.run(legacy: legacyURL, destination: unreadable, key: { fixtureKey }) != .imported(count: 2, dropped: 0)
          && ((try? Data(contentsOf: unreadable.fileURL)) ?? Data()) == "not json".data(using: .utf8),
          "import: an unreadable new History is never replaced")

    let restarted = destination()
    _ = LegacyHistoryMigration.run(legacy: legacyURL, destination: restarted, key: { fixtureKey })
    let afterRestart = History(store: restarted, isEnabled: alwaysSaving)
    check(afterRestart.items == ["second", "first"] && afterRestart.state == .available,
          "import: after the import the history reads back from history.json on restart")
}

// Keep History: off for new installs, kept on for an install that already had the app set up, and no new capture
// is stored while it is off.
do {
    let fresh = UserDefaults(suiteName: "nictate-tests-fresh-\(UUID().uuidString)")!
    _ = Settings(defaults: fresh)
    check(fresh.bool(forKey: StorageKeys.historyEnabled) == false, "keep history: off for a new install")

    let existing = UserDefaults(suiteName: "nictate-tests-existing-\(UUID().uuidString)")!
    existing.set(true, forKey: StorageKeys.didOnboard)
    _ = Settings(defaults: existing)
    check(existing.bool(forKey: StorageKeys.historyEnabled) == true, "keep history: an existing install keeps it on",
          "value \(String(describing: existing.object(forKey: StorageKeys.historyEnabled))), applied \(existing.bool(forKey: StorageKeys.historyDefaultApplied)), onboarded \(existing.bool(forKey: StorageKeys.didOnboard))")

    let chosen = UserDefaults(suiteName: "nictate-tests-chosen-\(UUID().uuidString)")!
    chosen.set(true, forKey: StorageKeys.didOnboard)
    _ = Settings(defaults: chosen)
    let chosenSettings = Settings(defaults: chosen)
    chosenSettings.historyEnabled = false
    _ = Settings(defaults: chosen)
    check(chosen.bool(forKey: StorageKeys.historyEnabled) == false, "keep history: an explicit choice survives a restart")

    let off = ScriptedStore(answers: [.loaded(HistorySnapshot(texts: ["kept"], dates: [1]))], saved: nil)
    let offHistory = History(store: off, isEnabled: { false }, loadsNow: false)
    offHistory.refresh()
    offHistory.add("not recorded while off")
    History.flushWrites()
    check(offHistory.items == ["kept"] && off.saves == 0,
          "keep history: while off, the saved entries are shown, and no new capture is recorded or written")
}

// Rendered corpus: 16 captures (4 per kind) drawn as images, read through Vision, then classified. Written once,
// never used for tuning. Accepted at 80 % (13 of 16); no multi-line code, table or list may collapse into one line.
// A line Vision drops is an OCR miss, not a join, so it is not counted here.
if ProcessInfo.processInfo.environment["SKIP_OCR"] == nil {
    let rows = (try? String(contentsOfFile: "Tests/corpus/rendered.tsv", encoding: .utf8))?.split(separator: "\n") ?? []
    func drawn(_ text: String, monospaced: Bool) -> CGImage {
        let font = monospaced ? NSFont.monospacedSystemFont(ofSize: 18, weight: .regular) : NSFont.systemFont(ofSize: 18)
        let str = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: NSColor.black])
        let box = str.boundingRect(with: NSSize(width: 1400, height: 2000), options: [.usesLineFragmentOrigin])
        let w = Int(box.width) + 60, h = Int(box.height) + 60
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.white.setFill(); NSRect(x: 0, y: 0, width: w, height: h).fill()
        str.draw(at: NSPoint(x: 30, y: 30))
        NSGraphicsContext.restoreGraphicsState()
        return rep.cgImage!
    }
    var correct = 0
    var joined: [String] = []
    var misses: [String] = []
    for row in rows {
        let parts = row.split(separator: "\t", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { continue }
        let source = parts[1].replacingOccurrences(of: "\\n", with: "\n")
        let kind = parts[0]
        let image = drawn(source, monospaced: kind == "code" || kind == "table")
        let read = Recognizer.recognize(image, options: RecognitionOptions(
            languages: [], keepLineBreaks: false, languageCorrection: false, preserveIndentation: false, tablesAsTabs: true))
        let result = ContentClassifier.classify([], text: read.text, imageSize: .zero)
        if "\(result.kind)" == kind { correct += 1 } else { misses.append("\(kind) read as \(result.kind): \(source.prefix(30))") }
        let sourceLines = source.split(separator: "\n").count
        let readLines = read.text.split(separator: "\n").count
        if kind != "prose", sourceLines > 1, readLines < 2 { joined.append("\(kind) \(readLines)/\(sourceLines) lines: \(read.text.debugDescription.prefix(90))") }
    }
    check(rows.count == 16, "rendered corpus: 16 captures", "\(rows.count)")
    check(correct >= 13, "rendered corpus: at least 80 % read as their kind (\(correct)/\(rows.count))", "\n    " + misses.joined(separator: "\n    "))
    check(joined.isEmpty, "rendered corpus: no multi-line code, table or list collapses into one line", "\n    " + joined.joined(separator: "\n    "))
}

// Content classifier: 40 captures (10 per kind) as text, and the rules that must hold for every one.
do {
    let rows = (try? String(contentsOfFile: "Tests/corpus/captures.tsv", encoding: .utf8))?.split(separator: "\n") ?? []
    check(rows.count == 40, "classifier: the corpus holds 40 captures", "\(rows.count)")
    var correct = 0
    var joinedCode = 0
    var misses: [String] = []
    for row in rows {
        let parts = row.split(separator: "\t", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { continue }
        let text = parts[1].replacingOccurrences(of: "\\n", with: "\n").replacingOccurrences(of: "\\t", with: "\t")
        let result = ContentClassifier.classify([], text: text, imageSize: .zero)
        let expected = parts[0]
        let kind = "\(result.kind)"
        if kind == expected { correct += 1 } else { misses.append("\(expected) read as \(kind) at \(String(format: "%.2f", result.confidence)): \(text.prefix(40))") }
        if expected == "code", ContentClassifier.joinsParagraphs(result) { joinedCode += 1 }
    }
    check(Double(correct) / Double(max(rows.count, 1)) >= 0.9, "classifier: at least 90% of the corpus is read correctly (\(correct)/\(rows.count))", "\n    " + misses.joined(separator: "\n    "))
    check(joinedCode == 0, "classifier: no code capture is ever joined into paragraphs", "\(joinedCode)")
    let sentence = ContentClassifier.classify([], text: "The meeting moved to Thursday because the client could not come.\nPlease update your calendars.", imageSize: .zero)
    check(ContentClassifier.joinsParagraphs(sentence) == (sentence.confidence >= ContentClassifier.threshold), "classifier: prose joins only at confidence", "\(sentence)")
    check(!ContentClassifier.joinsParagraphs(Classification(kind: .prose, confidence: 0.59)), "classifier: a guess below the threshold keeps its line breaks")
    check(!ContentClassifier.joinsParagraphs(Classification(kind: .code, confidence: 1)), "classifier: code never joins")
}

// Captures written after the first weights. The weights were later changed after reading their misses, so this is
// a regression set, not a held-out measure. It is gated at 80 %.
do {
    let rows = (try? String(contentsOfFile: "Tests/corpus/held_out.tsv", encoding: .utf8))?.split(separator: "\n") ?? []
    var correct = 0
    var misses: [String] = []
    for row in rows {
        let parts = row.split(separator: "\t", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { continue }
        let text = parts[1].replacingOccurrences(of: "\\n", with: "\n").replacingOccurrences(of: "\\t", with: "\t")
        let result = ContentClassifier.classify([], text: text, imageSize: .zero)
        if "\(result.kind)" == parts[0] { correct += 1 } else { misses.append("\(parts[0]) read as \(result.kind): \(text.prefix(40))") }
    }
    check(correct * 10 >= rows.count * 8, "classifier: held-out captures read correctly (\(correct)/\(rows.count))", "\n    " + misses.joined(separator: "\n    "))
}

// Check for Updates: version order, which releases are accepted, and what the user is told. The request itself
// is checked by hand (it needs the network).
do {
    check(UpdateCheck.isNewer("1.0.1", than: "1.0.0") && UpdateCheck.isNewer("v1.1", than: "1.0.9") && UpdateCheck.isNewer("2", than: "1.9.9"),
          "updates: newer versions are recognised, with a leading v and short numbers")
    check(!UpdateCheck.isNewer("1.0", than: "1.0.0") && !UpdateCheck.isNewer("0.9", than: "1.0") && !UpdateCheck.isNewer("1.0.0-beta", than: "1.0.0"),
          "updates: equal or older versions are not offered")
    let json = Data(#"{"tag_name":"v1.1.0","html_url":"https://github.com/jrthormann/Nictate/releases/tag/v1.1.0","draft":false}"#.utf8)
    let release = try? JSONDecoder().decode(ReleaseInfo.self, from: json)
    check(release != nil, "updates: GitHub's release JSON decodes")
    if let release {
        check(UpdateCheck.outcome(current: "1.0.0", releases: [release]) == .available(version: "1.1.0", page: release.htmlURL),
              "updates: a newer release is offered with its page and without the v")
        check(UpdateCheck.outcome(current: "1.1.0", releases: [release]) == .upToDate, "updates: the current release is up to date")
    }
    let foreign = ReleaseInfo(tagName: "v9.0.0", htmlURL: URL(string: "https://example.com/release")!)
    check(UpdateCheck.outcome(current: "1.0.0", releases: [foreign]) == .failed, "updates: a release page off github.com is never offered")
    check(UpdateCheck.endpoint(for: "1.0.0").scheme == "https" && UpdateCheck.endpoint(for: "1.0.0-beta.1").host == "api.github.com", "updates: the only request goes to GitHub's API over https")
}

// Reset: stored settings and retired keys go, and each returns to its default. Onboarding stays done. A reset does
// not touch saved captures: nothing expires by age, so a capture from last month is still there after a relaunch.
do {
    let suite = freshSuite("reset")
    suite.defaults.set(false, forKey: StorageKeys.visualCue)
    suite.defaults.set(50, forKey: StorageKeys.rotationDepth)
    suite.defaults.set("hour", forKey: StorageKeys.historyRetention)
    suite.defaults.set(true, forKey: StorageKeys.didOnboard)
    Settings.resetToDefaults(in: suite.defaults)
    let stored = suite.defaults.persistentDomain(forName: suite.name) ?? [:]
    check(stored[StorageKeys.visualCue] == nil && stored[StorageKeys.rotationDepth] == nil && stored[StorageKeys.historyRetention] == nil,
          "reset: stored settings and retired keys are removed, so each returns to its default")
    check(suite.defaults.bool(forKey: StorageKeys.didOnboard), "reset: onboarding stays done, so the welcome window does not come back")
    let lastMonth = Date().addingTimeInterval(-30 * 86_400)
    let saved = HistorySnapshot(texts: ["saved last month"], dates: [lastMonth.timeIntervalSince1970])
    let relaunched = History(store: ScriptedStore(answers: [.loaded(saved)], saved: saved), isEnabled: alwaysSaving)
    check(relaunched.items == ["saved last month"], "reset: a capture from last month is still there after a reset and relaunch", "\(relaunched.items)")
}

// Unavailable history: the copy still works, nothing is kept in memory or queued, and the file is never replaced.
do {
    let stored = HistorySnapshot(texts: ["old"], dates: [1_000])
    let plain = CapturePlan.Choices(appendMode: false, delimiter: "\n", historyEnabled: true, barcodeAction: "copy")
    let broken = ScriptedStore(answers: [.unavailable], saved: stored)
    let brokenHistory = History(store: broken, isEnabled: alwaysSaving)
    let effects = CapturePlan.effects(mode: .text, result: RecognitionResult(text: "copy me", isBarcode: false), text: "copy me",
                                      detections: Detections(), choices: plain, existing: nil)
    let copiedTexts = effects.compactMap { (effect: CaptureEffect) -> String? in if case .copy(let text) = effect { return text } else { return nil } }
    check(copiedTexts == ["copy me"] && effects.contains(.addToHistory("copy me")),
          "unavailable: OCR still produces the copy while the history is unavailable")
    brokenHistory.add("lost to a fault")
    brokenHistory.add("second"); brokenHistory.add("third")
    History.flushWrites()
    check(brokenHistory.items.isEmpty && brokenHistory.state == .unavailable && broken.saves == 0,
          "unavailable: no capture is kept in memory or written, and the state is unavailable")

    let loading = ScriptedStore(answers: [.loaded(stored)], saved: stored)
    let loadingHistory = History(store: loading, isEnabled: alwaysSaving, loadsNow: false)
    loadingHistory.add("made while loading")
    check(loadingHistory.items.isEmpty, "loading: a capture made while loading is not queued")
    settle { await loadingHistory.reload() }
    History.flushWrites()
    check(loadingHistory.items == ["old"] && loading.saved == stored, "loading: once loaded, only the stored history is shown")

    let disabled = ScriptedStore(answers: [.loaded(stored)], saved: stored)
    let disabledHistory = History(store: disabled, isEnabled: { false }, loadsNow: false)
    disabledHistory.refresh()
    disabledHistory.add("not recorded")
    History.flushWrites()
    check(disabledHistory.state == .disabled && disabledHistory.items == ["old"] && disabled.saves == 0,
          "disabled: saved entries are shown, and no new capture is kept or written")
    disabledHistory.remove("old")
    History.flushWrites()
    check(disabled.saves == 1 && disabled.saved?.texts == [] && disabledHistory.items.isEmpty,
          "disabled: a deletion is written straight away, even while saving is off")

    let sealed = sealedStore("unavailable-available")
    let available = History(store: sealed, isEnabled: alwaysSaving)
    available.add("saved while available", at: Date(timeIntervalSince1970: 3_000))
    History.flushWrites()
    check(History(store: sealed, isEnabled: alwaysSaving).items == ["saved while available"], "available: a capture is saved and reads back")

    let before = (try? Data(contentsOf: sealed.fileURL)) ?? Data()
    try? "not json".data(using: .utf8)?.write(to: sealed.fileURL)
    let damaged = History(store: sealed, isEnabled: alwaysSaving)
    damaged.add("while damaged")
    History.flushWrites()
    check(damaged.state == .unavailable && damaged.items.isEmpty && before.count > 0,
          "unavailable: a damaged file leaves the history unavailable and keeps nothing new")

    let unlock = ScriptedStore(answers: [.unavailable, .loaded(stored)], saved: stored)
    let unlockHistory = History(store: unlock, isEnabled: alwaysSaving)
    unlockHistory.add("made while unavailable")
    settle { await unlockHistory.reload() }
    History.flushWrites()
    check(unlockHistory.items == ["old"], "recovery: captures made while unavailable do not come back on recovery")
}

// Persist first, publish after success: a capture is visible only once its write has succeeded.
do {
    // Not visible before the write completes, visible after it succeeds.
    let store = sealedStore("publish-after")
    let history = History(store: store, isEnabled: alwaysSaving)
    history.add("pending capture")
    check(!history.items.contains("pending capture"), "publish: a capture is not visible before its write completes")
    History.flushWrites()
    check(history.items == ["pending capture"] && History(store: store, isEnabled: alwaysSaving).items == ["pending capture"],
          "publish: a capture is visible once it is written, and it is in the file")

    // An interrupted write (the directory refuses the atomic replacement) never shows the capture and never
    // changes the file; the next start reads the previous history.
    let folder = testPreferences.appendingPathComponent("readonly-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let fixed = JSONHistoryStore(fileURL: folder.appendingPathComponent("history.json"))
    let base = History(store: fixed, isEnabled: alwaysSaving)
    base.add("kept before")
    History.flushWrites()
    let before = (try? Data(contentsOf: fixed.fileURL)) ?? Data()
    try? FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path)
    base.add("interrupted")
    History.flushWrites()
    try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path)
    check(!base.items.contains("interrupted") && base.items == ["kept before"],
          "publish: an interrupted write never shows the capture", "\(base.items)")
    check(((try? Data(contentsOf: fixed.fileURL)) ?? Data()) == before
          && History(store: fixed, isEnabled: alwaysSaving).items == ["kept before"],
          "publish: an interrupted write leaves the file byte for byte unchanged, and a restart reads the previous history")

    // Rapid captures: each is written in order, the newest is first, nothing duplicates, and the file matches the screen.
    let rapid = sealedStore("rapid")
    let fast = History(store: rapid, isEnabled: alwaysSaving)
    for index in 0..<60 { fast.add("capture \(index)", at: Date(timeIntervalSince1970: Double(index))) }
    History.flushWrites()
    let expected = (0..<60).reversed().prefix(HistoryPolicy.maximumHistoryEntries).map { "capture \($0)" }
    check(fast.items == Array(expected) && Set(fast.items).count == fast.items.count,
          "publish: rapid captures keep their order, nothing duplicates, and the newest is first", "\(fast.items.count)")
    check(History(store: rapid, isEnabled: alwaysSaving).items == Array(expected),
          "publish: after a restart the file holds exactly what was on screen")
}

// Concurrent captures and deletions: many threads hand their work to the main actor at once. History must still write
// each change once, one write at a time, in the order it was made, and show exactly what the file holds.
/// Counts the iterations of `runOnMainConcurrently` that have run on the main thread.
final class ArrivalCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func arrive() {
        lock.lock()
        count += 1
        lock.unlock()
    }
    var arrived: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
}

/// Runs `work` once for each index, as if from many threads at once: the iterations run concurrently on a background
/// queue, and each hops to the main thread, where History is used. Spins the run loop until every one has run, at most
/// ten seconds. True when all of them ran.
@MainActor
func runOnMainConcurrently(_ count: Int, _ work: @escaping @MainActor (Int) -> Void) -> Bool {
    let arrivals = ArrivalCounter()
    DispatchQueue.global().async {
        DispatchQueue.concurrentPerform(iterations: count) { index in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { work(index) }
                arrivals.arrive()
            }
        }
    }
    let deadline = Date().addingTimeInterval(10)
    while arrivals.arrived < count, Date() < deadline {
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.001))
    }
    return arrivals.arrived == count
}

/// Records each snapshot it is asked to save, and counts the saves that overlap. Saves run one at a time on the I/O
/// queue, so none may overlap; the short sleep gives an overlap the chance to show.
final class OverlapStore: HistoryStore, @unchecked Sendable {
    private let lock = NSLock()
    private var active = 0
    private(set) var overlaps = 0
    private(set) var snapshots: [HistorySnapshot] = []
    func load() -> HistoryLoad { .empty }
    func save(_ snapshot: HistorySnapshot) -> HistoryPersistOutcome {
        lock.lock()
        active += 1
        if active > 1 { overlaps += 1 }
        snapshots.append(snapshot)
        lock.unlock()
        Thread.sleep(forTimeInterval: 0.0002)
        lock.lock()
        active -= 1
        lock.unlock()
        return .confirmed
    }
}

do {
    let store = OverlapStore()
    let history = History(store: store, isEnabled: alwaysSaving)
    let ran = runOnMainConcurrently(200) { index in
        history.add("capture \(index)", at: Date(timeIntervalSince1970: Double(index)))
    }
    settle { await history.finishLoading() }
    History.flushWrites()
    let heads = store.snapshots.compactMap { $0.texts.first }
    check(ran && store.snapshots.count == 200 && Set(heads).count == 200 && store.overlaps == 0,
          "concurrent captures: each of 200 concurrent adds is written once, and no two writes overlap",
          "ran \(ran), writes \(store.snapshots.count), overlaps \(store.overlaps)")
    let chained = store.snapshots.indices.dropFirst().allSatisfy { index in
        Array(store.snapshots[index].texts.dropFirst())
            == Array(store.snapshots[index - 1].texts.prefix(HistoryPolicy.maximumHistoryEntries - 1))
    }
    check(chained, "concurrent captures: each write is the one before it plus its own capture, so none is lost or built from an older list")
    let last = store.snapshots.last?.texts ?? []
    check(history.items == last && last.count == HistoryPolicy.maximumHistoryEntries && Set(last).count == last.count,
          "concurrent captures: the list on screen is the last write, with 15 captures and none repeated", "\(history.items.count) shown")
    let ownTimes = history.dates.count == history.items.count && zip(history.items, history.dates).allSatisfy { pair in
        pair.1 == Date(timeIntervalSince1970: Double(pair.0.dropFirst("capture ".count)) ?? -1)
    }
    check(ownTimes, "concurrent captures: every capture keeps its own time", "\(history.dates)")
}
do {
    let store = sealedStore("concurrent")
    let history = History(store: store, isEnabled: alwaysSaving)
    let added = runOnMainConcurrently(100) { index in
        history.add("concurrent \(index)", at: Date(timeIntervalSince1970: Double(index)))
    }
    settle { await history.finishLoading() }
    History.flushWrites()
    let reread = History(store: store, isEnabled: alwaysSaving)
    check(added && history.items.count == HistoryPolicy.maximumHistoryEntries && reread.items == history.items,
          "concurrent captures: 100 concurrent adds leave the file equal to the list on screen, and a re-read matches",
          "shown \(history.items.count), file \(reread.items.count)")
    let shown = history.items
    let removed = runOnMainConcurrently(100) { index in
        history.remove(shown[index % shown.count])
    }
    settle { await history.finishLoading() }
    History.flushWrites()
    let afterRemoval = History(store: store, isEnabled: alwaysSaving)
    check(removed && history.items.isEmpty && afterRemoval.items.isEmpty,
          "concurrent captures: 100 concurrent removes of the shown captures all reach the file, and none comes back",
          "shown \(history.items.count), file \(afterRemoval.items.count)")
}

// A save reports what happened: a write that reads back is confirmed, and a refused write leaves the file as it was.
do {
    let first = HistorySnapshot(texts: ["first"], dates: [1_000])
    check(sealedStore("persist-ok").save(first) == .confirmed, "persist: a write that reads back is confirmed")
    let folder = testPreferences.appendingPathComponent("persist-readonly-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let locked = JSONHistoryStore(fileURL: folder.appendingPathComponent("history.json"))
    _ = locked.save(first)
    let before = (try? Data(contentsOf: locked.fileURL)) ?? Data()
    try? FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path)
    let refused = locked.save(HistorySnapshot(texts: ["second"], dates: [2_000]))
    try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path)
    check(refused == .notWritten && !before.isEmpty && ((try? Data(contentsOf: locked.fileURL)) ?? Data()) == before,
          "persist: a refused write is notWritten and the file is byte for byte as it was", "\(refused)")
}

// A failed encrypted write never reports the capture as saved: the file keeps its entries, the new capture is
// dropped, and the history is read again from the file.
do {
    let stored = HistorySnapshot(texts: ["old"], dates: [1_000])
    let failing = ScriptedStore(answers: [.loaded(stored), .loaded(stored)], saved: stored)
    let failingHistory = History(store: failing, isEnabled: alwaysSaving)
    failing.writesSucceed = false
    failingHistory.add("cannot be saved", at: Date(timeIntervalSince1970: 2_000))
    var settled = false
    for _ in 0..<400 where !settled {
        settled = failingHistory.items == ["old"] && failingHistory.state == .available
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
    }
    History.flushWrites()
    check(settled && failingHistory.items == ["old"] && failing.saved == stored,
          "available: a failed write drops the new capture, restores the saved entries, and leaves the file as it was",
          "items \(failingHistory.items), state \(failingHistory.state)")
}

// An unconfirmed write is not shown until the file is read again: then the file decides what is shown.
do {
    let old = HistorySnapshot(texts: ["old"], dates: [1_000])
    let grown = HistorySnapshot(texts: ["new", "old"], dates: [2_000, 1_000])
    let store = ScriptedStore(answers: [.loaded(old), .loaded(grown)], saved: old)
    store.writesSucceed = false
    store.failure = .unconfirmed
    let history = History(store: store, isEnabled: alwaysSaving)
    history.add("new", at: Date(timeIntervalSince1970: 2_000))
    var shown = false
    for _ in 0..<400 where !shown {
        shown = history.items == ["new", "old"] && history.state == .available
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
    }
    History.flushWrites()
    check(shown && store.loads == 2, "persist: an unconfirmed write is not shown until the file is read again, and then the file decides",
          "items \(history.items), loads \(store.loads)")
}

// Whitespace-only text is never kept in the history, but valid text keeps every space, tab and line break.
do {
    let store = sealedStore("blank")
    let history = History(store: store, isEnabled: alwaysSaving)
    for blank in ["", "   ", "\n", "\t", " \n \t "] {
        history.add(blank)
        History.flushWrites()
    }
    check(history.items.isEmpty, "blank captures: whitespace-only text is not stored")
    let indented = "    Hello World"
    history.add(indented)
    History.flushWrites()
    history.add("line one\n\tindented line two\n")
    History.flushWrites()
    check(history.items == ["line one\n\tindented line two\n", indented],
          "blank captures: valid text keeps its leading spaces, tabs and line breaks exactly", "\(history.items)")
    check(!"x".allSatisfy(\.isWhitespace) && "  x  ".allSatisfy(\.isWhitespace) == false,
          "blank captures: any visible character makes a capture")
}

// Clipboard reliability: a history copy is confirmed by reading the text back, and a refused write puts the
// previous clipboard contents back. A private pasteboard keeps the user's clipboard out of the tests.
do {
    let board = NSPasteboard(name: NSPasteboard.Name("nictate-tests-\(UUID().uuidString)"))
    defer { board.releaseGlobally() }
    let writer = ClipboardWriter(pasteboard: board)
    board.clearContents()
    board.setString("previous", forType: .string)

    check(writer.writeVerified("a full capture\nwith two lines", transient: false),
          "clipboard: a successful copy reports success")
    check(board.string(forType: .string) == "a full capture\nwith two lines",
          "clipboard: the complete text is what the clipboard holds")

    board.clearContents()
    board.setString("previous", forType: .string)
    let refusing = ClipboardWriter(pasteboard: board, replace: { pasteboard, _, _ in pasteboard.clearContents(); return pasteboard.changeCount })
    check(!refusing.writeVerified("never arrives", transient: false),
          "clipboard: a refused write reports failure instead of success")
    check(refusing.lastWrite == nil, "clipboard: a refused write is not remembered as ours")

    // Regression: the previous clipboard is never read, so a concealed entry from a password manager is neither
    // copied aside nor put back. The successful copy holds only the new text.
    board.clearContents()
    let concealed = NSPasteboardItem()
    concealed.setString("hunter2", forType: .string)
    concealed.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
    board.writeObjects([concealed])
    check(writer.writeVerified("after a password", transient: false) && board.string(forType: .string) == "after a password",
          "clipboard: a copy over a concealed entry holds only the new text")
    check((board.pasteboardItems ?? []).count == 1 && board.types?.contains(NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")) != true,
          "clipboard: the concealed entry is not restored or kept")
}

// Edge cases a history copy must get exactly right: multiline, accented and emoji text, long OCR output, and
// whitespace. Each is read back byte for byte.
do {
    let board = NSPasteboard(name: NSPasteboard.Name("nictate-tests-edge-\(UUID().uuidString)"))
    defer { board.releaseGlobally() }
    let writer = ClipboardWriter(pasteboard: board)
    let samples: [(String, String)] = [
        ("multiline", "first line\n\tindented\nlast line"),
        ("accents", "café naïve Ñandú résumé"),
        ("emoji and CJK", "🙂 漢字 한국어"),
        ("combining marks", "e\u{0301}\u{0303} vs é"),
        ("long capture", String(repeating: "Lorem ipsum dolor sit amet. ", count: 3_000)),
        ("whitespace only", "   \n\t  "),
    ]
    for (name, text) in samples {
        check(writer.writeVerified(text, transient: false) && board.string(forType: .string) == text,
              "clipboard edge: \(name) is copied exactly", "\(board.string(forType: .string)?.count ?? -1) of \(text.count)")
    }
    // An empty text is written as asked. The history never stores one (see History.add callers), so this is a clipboard check only.
    board.clearContents()
    board.setString("keep me", forType: .string)
    let emptyAccepted = writer.writeVerified("", transient: false)
    check(emptyAccepted && board.string(forType: .string) == "",
          "clipboard edge: an empty text is written as asked, and reads back as empty", "accepted \(emptyAccepted)")
}

// Several representations: a copy replaces them all with the text, and the previous rich representation is not read.
do {
    let board = NSPasteboard(name: NSPasteboard.Name("nictate-tests-reps-\(UUID().uuidString)"))
    defer { board.releaseGlobally() }
    board.clearContents()
    let item = NSPasteboardItem()
    item.setString("plain previous", forType: .string)
    item.setData(Data("{\\rtf1 rich previous}".utf8), forType: NSPasteboard.PasteboardType("public.rtf"))
    board.writeObjects([item])
    let writer = ClipboardWriter(pasteboard: board)
    check(writer.writeVerified("plain copy", transient: false), "clipboard reps: a copy over rich text reports success")
    let types = board.pasteboardItems?.first?.types ?? []
    check(board.string(forType: .string) == "plain copy" && !types.contains(NSPasteboard.PasteboardType("public.rtf")),
          "clipboard reps: the copy holds the text alone, with no previous rich representation", "\(types.map(\.rawValue))")
}

// Regression: Clear on Quit reaches the file even when the history was still loading at quit. The read is applied
// first, and only then is the clear written.
do {
    let stored = HistorySnapshot(texts: ["one", "two"], dates: [1_000, 2_000])
    let store = ScriptedStore(answers: [.loaded(stored)], saved: stored)
    let history = History(store: store, isEnabled: alwaysSaving, loadsNow: false)
    history.refresh()
    history.clear()
    history.waitForPendingWrites()
    History.flushWrites()
    check(history.items.isEmpty && store.saved?.texts.isEmpty == true,
          "quit: a clear requested while loading is written before quit", "file \(store.saved?.texts ?? [])")
}

// Regression: a read that was already in flight when an import began cannot end the import's hold, so a capture
// made during the import is not written over the merged file.
do {
    let stored = HistorySnapshot(texts: ["kept"], dates: [1_000])
    let merged = HistorySnapshot(texts: ["kept", "imported"], dates: [1_000, 500])
    let store = ScriptedStore(answers: [.loaded(stored), .loaded(merged)], saved: stored)
    let history = History(store: store, isEnabled: alwaysSaving, loadsNow: false)
    let stale = history.refresh()
    check(history.beginImport(), "import hold: an import is admitted while none runs")
    settle { await stale?.value }
    check(history.state == .loading, "import hold: a read that finishes during the import does not end the hold")
    history.add("during the import")
    History.flushWrites()
    check(store.saved?.texts == stored.texts, "import hold: a capture during the import is not written over the file")
    store.saved = merged
    history.endImport()
    settle { while history.state == .loading { try? await Task.sleep(nanoseconds: 1_000_000) } }
    check(history.items == ["kept", "imported"] && history.state == .available,
          "import hold: after the import the file's merged captures are shown", "\(history.items)")
}

// Import admission: one import at a time, and an end without an admitted import changes nothing.
do {
    let stored = HistorySnapshot(texts: ["kept"], dates: [1_000])
    let store = ScriptedStore(answers: [.loaded(stored)], saved: stored)
    let history = History(store: store, isEnabled: alwaysSaving)
    let first = history.beginImport()
    let second = history.beginImport()
    check(first && !second && history.importing && history.state == .loading,
          "import admission: a second import is refused while one holds the history", "first \(first), second \(second)")
    history.endImport()
    settle { await history.finishLoading() }
    check(history.beginImport(), "import admission: once the admitted import ends, another one can start")
    history.endImport()
    settle { await history.finishLoading() }
}
do {
    let stored = HistorySnapshot(texts: ["kept"], dates: [1_000])
    let store = ScriptedStore(answers: [.loaded(stored)], saved: stored)
    let history = History(store: store, isEnabled: alwaysSaving)
    let loads = store.loads
    history.endImport()
    let unchanged = history.state == .available
    History.flushWrites()
    check(unchanged && store.loads == loads && history.items == ["kept"],
          "import admission: an end without an admitted import changes nothing", "state \(history.state), loads \(store.loads - loads)")
}

// Clear on Quit: stores that stand in for a slow read, a hung disk and a failing disk.
final class SlowReadStore: HistoryStore, @unchecked Sendable {
    let stored: HistorySnapshot
    let readDelay: Double
    var saved: HistorySnapshot?
    init(stored: HistorySnapshot, readDelay: Double) {
        self.stored = stored
        self.readDelay = readDelay
    }
    func load() -> HistoryLoad {
        Thread.sleep(forTimeInterval: readDelay)
        return .loaded(stored)
    }
    func save(_ snapshot: HistorySnapshot) -> HistoryPersistOutcome {
        saved = snapshot
        return .confirmed
    }
}

final class HungWriteStore: HistoryStore, @unchecked Sendable {
    let stored: HistorySnapshot
    init(stored: HistorySnapshot) { self.stored = stored }
    func load() -> HistoryLoad { .loaded(stored) }
    func save(_ snapshot: HistorySnapshot) -> HistoryPersistOutcome {
        Thread.sleep(forTimeInterval: 1.0)
        return .confirmed
    }
}

// Regression: a slow read that finishes after Clear on Quit cannot bring the captures back.
do {
    let stored = HistorySnapshot(texts: ["one", "two"], dates: [1_000, 2_000])
    let store = SlowReadStore(stored: stored, readDelay: 0.6)
    let history = History(store: store, isEnabled: alwaysSaving, loadsNow: false)
    history.refresh()
    let confirmed = history.clearForQuit()
    History.flushWrites()
    check(confirmed && store.saved?.texts.isEmpty == true && history.items.isEmpty,
          "quit: a slow load during quit is cleared and the empty file is confirmed", "confirmed \(confirmed), file \(store.saved?.texts ?? [])")
}

// Regression: writes queued before Clear on Quit land before the empty write, and nothing is written after it.
do {
    let store = ScriptedStore(answers: [.empty])
    let history = History(store: store, isEnabled: alwaysSaving)
    history.add("pending one")
    history.add("pending two")
    let confirmed = history.clearForQuit()
    History.flushWrites()
    check(confirmed && store.saved?.texts.isEmpty == true && history.items.isEmpty,
          "quit: pending writes are followed by the empty write, which is what remains", "file \(store.saved?.texts ?? [])")
    history.add("after the clear")
    History.flushWrites()
    check(store.saved?.texts.isEmpty == true, "quit: a capture made after the clear is not written")
}

// Regression: a read already queued when Clear on Quit runs does not apply its captures afterwards.
do {
    let stored = HistorySnapshot(texts: ["restored?"], dates: [1_000])
    let store = ScriptedStore(answers: [.loaded(stored)], saved: stored)
    let history = History(store: store, isEnabled: alwaysSaving, loadsNow: false)
    history.refresh()
    let confirmed = history.clearForQuit()
    History.flushWrites()
    check(confirmed && store.saved?.texts.isEmpty == true && history.items.isEmpty,
          "quit: a late read does not restore the captures", "items \(history.items)")
}

// Corrupt and unreadable files are overwritten by Clear on Quit, which is approved for an explicit choice.
for (name, answer) in [("corrupt", HistoryLoad.corrupt), ("unreadable", HistoryLoad.unavailable)] {
    let store = ScriptedStore(answers: [answer])
    let history = History(store: store, isEnabled: alwaysSaving)
    let confirmed = history.clearForQuit()
    check(confirmed && store.saved?.texts.isEmpty == true,
          "quit: a \(name) file is overwritten with an empty history and the write is confirmed", "file \(store.saved?.texts ?? [])")
}

// A failed write is not claimed: the file and the list keep the captures, and the call reports false.
do {
    let stored = HistorySnapshot(texts: ["keep me"], dates: [1_000])
    let store = ScriptedStore(answers: [.loaded(stored)], saved: stored)
    store.writesSucceed = false
    let history = History(store: store, isEnabled: alwaysSaving)
    let confirmed = history.clearForQuit()
    History.flushWrites()
    check(!confirmed && history.items == ["keep me"] && store.saved?.texts == ["keep me"],
          "quit: a failed write is not reported as a deletion", "confirmed \(confirmed), items \(history.items)")
}

// A write that never finishes is abandoned after the timeout, and nothing is claimed.
do {
    let stored = HistorySnapshot(texts: ["stuck"], dates: [1_000])
    let history = History(store: HungWriteStore(stored: stored), isEnabled: alwaysSaving)
    let started = Date()
    let confirmed = history.clearForQuit(timeout: 0.2)
    let elapsed = Date().timeIntervalSince(started)
    check(!confirmed && history.items == ["stuck"] && elapsed < 0.9,
          "quit: a hung disk does not hold quit past its timeout, and nothing is claimed", "elapsed \(elapsed), confirmed \(confirmed)")
}

// Clear on Quit off: quitting writes what is pending and does not clear anything.
do {
    let store = ScriptedStore(answers: [.empty])
    let history = History(store: store, isEnabled: alwaysSaving)
    history.add("kept")
    history.waitForPendingWrites()
    check(store.saved?.texts == ["kept"], "quit without Clear on Quit: the pending capture is written before quit")
    history.add("still saving")
    History.flushWrites()
    check(history.items == ["still saving", "kept"] && store.saved?.texts == ["still saving", "kept"],
          "quit without Clear on Quit: the history keeps working afterwards")
}

// Regression: captures with unknown times keep their source order in an import; known times stay newest first.
do {
    let unknown = Date.distantPast.timeIntervalSince1970
    let current = HistorySnapshot(texts: ["zebra", "apple"], dates: [unknown, unknown])
    let imported = HistorySnapshot(texts: ["mango", "banana"], dates: [unknown, unknown])
    let merged = LegacyHistoryMigration.merge(current: current, imported: imported)
    check(merged.texts == ["zebra", "apple", "mango", "banana"], "import merge: captures with unknown times keep their source order", "\(merged.texts)")
    let dated = HistorySnapshot(texts: ["b"], dates: [2_000])
    let older = HistorySnapshot(texts: ["a", "c"], dates: [1_000, unknown])
    check(LegacyHistoryMigration.merge(current: dated, imported: older).texts == ["b", "a", "c"],
          "import merge: known times stay newest first, unknown times come last")
}

// Update check: a prerelease sits between the release before it and the release it leads to.
do {
    check(UpdateCheck.isNewer("1.0.0", than: "1.0.0-beta.1"), "update: the stable 1.0.0 is newer than 1.0.0-beta.1")
    check(UpdateCheck.isNewer("1.0.0-beta.2", than: "1.0.0-beta.1"), "update: beta 2 is newer than beta 1")
    check(UpdateCheck.isNewer("1.0.0-beta.10", than: "1.0.0-beta.9"), "update: beta 10 is newer than beta 9, as a number")
    check(!UpdateCheck.isNewer("1.0.0-beta.1", than: "1.0.0-beta.1"), "update: the same beta is not newer")
    check(!UpdateCheck.isNewer("1.0.0-beta.1", than: "1.0.0"), "update: a beta is not newer than its release")
    check(UpdateCheck.isNewer("1.0.1-beta.1", than: "1.0.0"), "update: a beta of a later version is newer")
}

// Update channels: a stable user is offered stable releases only. A beta user may be offered newer betas and the
// stable releases. A version that is not newer is never recommended.
do {
    func release(_ version: String) -> ReleaseInfo {
        ReleaseInfo(tagName: "v\(version)", htmlURL: URL(string: "https://github.com/jrthormann/Nictate/releases/tag/v\(version)")!)
    }
    let betas = [release("1.0.0-beta.1"), release("1.0.0-beta.2")]
    let withStable = betas + [release("1.0.0")]
    check(UpdateCheck.offersPrereleases(to: "1.0.0-beta.1") && !UpdateCheck.offersPrereleases(to: "1.0.0"),
          "channels: a beta is on the beta channel, a stable version is not")
    check(UpdateCheck.endpoint(for: "1.0.0-beta.1") != UpdateCheck.endpoint(for: "1.0.0"),
          "channels: each channel asks GitHub for its own releases")
    check(UpdateCheck.newest(in: betas, current: "1.0.0") == nil, "channels: a stable user is never offered a beta")
    check(UpdateCheck.newest(in: betas, current: "1.0.0-beta.1")?.tagName == "v1.0.0-beta.2", "channels: a beta user is offered the newer beta")
    check(UpdateCheck.newest(in: withStable, current: "1.0.0-beta.1")?.tagName == "v1.0.0", "channels: a beta user is offered the stable release")
    check(UpdateCheck.newest(in: withStable, current: "1.0.0-beta.2")?.tagName == "v1.0.0", "channels: beta 2 is offered the stable release, not beta 1")
    check(UpdateCheck.newest(in: [release("1.0.1")], current: "1.0.0")?.tagName == "v1.0.1", "channels: a stable user is offered a newer stable release")
    check(UpdateCheck.newest(in: [release("1.0.1-beta.1")], current: "1.0.0") == nil, "channels: a stable user is not offered a newer beta")
    check(UpdateCheck.newest(in: [release("1.0.0-beta.1")], current: "1.0.0-beta.2") == nil, "channels: an older beta is never recommended")
    check(UpdateCheck.newest(in: [], current: "1.0.0") == nil, "channels: no releases, nothing to offer")
    check(UpdateCheck.outcome(current: "1.0.0", releases: [release("1.0.0-beta.9")]) == .upToDate,
          "channels: a stable user who sees only a beta is up to date")
    check(UpdateCheck.outcome(current: "1.0.0-beta.1", releases: withStable) == .available(version: "1.0.0", page: release("1.0.0").htmlURL),
          "channels: the offer names the version and its page")
}

// Regression: deleting captures for a reset is confirmed by the store, and a refused deletion leaves the history saving.
do {
    let stored = HistorySnapshot(texts: ["a", "b"], dates: [1_000, 2_000])
    let store = ScriptedStore(answers: [.loaded(stored)], saved: stored)
    let history = History(store: store, isEnabled: alwaysSaving)
    check(history.clearForReset() == .confirmed && store.saved?.texts.isEmpty == true && history.items.isEmpty,
          "reset: deleting captures is confirmed by the store before the reset goes on")
}
do {
    let stored = HistorySnapshot(texts: ["keep"], dates: [1_000])
    let store = ScriptedStore(answers: [.loaded(stored)], saved: stored)
    store.writesSucceed = false
    let history = History(store: store, isEnabled: alwaysSaving)
    check(history.clearForReset() == .notWritten && history.items == ["keep"], "reset: a refused deletion is reported and nothing is claimed")
    store.writesSucceed = true
    history.add("after the refusal")
    History.flushWrites()
    check(store.saved?.texts == ["keep"] && history.isClosed, "reset: after a refused deletion the history stays closed and writes nothing", "\(store.saved?.texts ?? [])")
}

// A deletion the store does not confirm is reported as unconfirmed, and nothing is claimed.
do {
    let stored = HistorySnapshot(texts: ["keep"], dates: [1_000])
    let store = ScriptedStore(answers: [.loaded(stored)], saved: stored)
    store.writesSucceed = false
    store.failure = .unconfirmed
    let history = History(store: store, isEnabled: alwaysSaving)
    check(history.clearForReset() == .unconfirmed && history.isClosed && history.items == ["keep"],
          "reset: a deletion that did not read back is reported as unconfirmed, and nothing is claimed")
}

// A history that is cleared for quit or handed over for a restart offers no import; an open one does.
do {
    let stored = HistorySnapshot(texts: ["kept"], dates: [1_000])
    let open = History(store: ScriptedStore(answers: [.loaded(stored)], saved: stored), isEnabled: alwaysSaving)
    check(open.isOpenForImport, "import: an open history offers an import")
    let quitting = History(store: ScriptedStore(answers: [.loaded(stored)], saved: stored), isEnabled: alwaysSaving)
    _ = quitting.clearForQuit()
    check(!quitting.isOpenForImport, "import: a history cleared on quit offers no import")
    let handed = History(store: ScriptedStore(answers: [.loaded(stored)], saved: stored), isEnabled: alwaysSaving)
    settle { _ = await handed.handOff() }
    check(!handed.isOpenForImport, "import: a history handed over for a restart offers no import")
}
// Save Captures counts the history after its load: an unbounded wait counts a slow read, and a short bound gives up first.
do {
    let history = History(store: SlowReadStore(stored: HistorySnapshot(texts: ["slow"], dates: [1_000]), readDelay: 0.3), isEnabled: alwaysSaving, loadsNow: false)
    history.refresh()
    settle {
        let bounded = await history.finishLoading(timeout: 0.05)
        let unbounded = await history.finishLoading(timeout: .infinity)
        check(!bounded && unbounded && history.items == ["slow"],
              "load: a short wait gives up on a slow read, and an unbounded wait counts it", "bounded \(bounded), unbounded \(unbounded)")
    }
}

// Regression: a reset without deletion waits for the pending writes, and reports a write that never finishes.
do {
    let store = ScriptedStore(answers: [.empty])
    let history = History(store: store, isEnabled: alwaysSaving)
    history.add("pending")
    check(history.waitForPendingWrites() && store.saved?.texts == ["pending"], "reset: pending changes are on disk when the wait returns true")
}
do {
    let history = History(store: HungWriteStore(stored: HistorySnapshot(texts: ["x"], dates: [1_000])), isEnabled: alwaysSaving)
    history.add("y")
    let started = Date()
    let finished = history.waitForPendingWrites(timeout: 0.2)
    check(!finished && Date().timeIntervalSince(started) < 0.9, "reset: a write that never finishes is reported, not waited on forever")
}

// Regression: the Save Captures question waits for a load in flight, so it counts the saved captures.
do {
    let stored = HistorySnapshot(texts: ["one", "two"], dates: [1_000, 2_000])
    let history = History(store: SlowReadStore(stored: stored, readDelay: 0.3), isEnabled: alwaysSaving, loadsNow: false)
    history.refresh()
    settle { await history.finishLoading() }
    check(history.items == ["one", "two"], "save captures: the decision made during a load sees the saved captures", "\(history.items)")
}

// Regression: times that do not line up with the texts of an earlier history keep every capture, with unknown times.
do {
    let fixtureKey = SymmetricKey(data: Data(repeating: 9, count: 32))
    let legacyURL = testPreferences.appendingPathComponent("legacy-mismatch-\(UUID().uuidString).sealed")
    let mismatched = HistorySnapshot(texts: ["one", "two", "three"], dates: [1_000])
    let plain = (try? JSONEncoder().encode(mismatched)) ?? Data()
    try? ((try? LegacyHistoryCipher.seal(plain, key: fixtureKey)) ?? Data()).write(to: legacyURL)
    let destination = sealedStore("mismatch-import")
    let outcome = LegacyHistoryMigration.run(legacy: legacyURL, destination: destination, key: { fixtureKey })
    check(outcome == .imported(count: 3, dropped: 0), "import: times that do not line up keep every capture", "\(outcome)")
    if case .loaded(let file) = destination.load() {
        check(file.texts == ["one", "two", "three"] && file.dates.count == 3, "import: the captures keep their order, with unknown times")
    }
}

// Regression: the Save Captures question is dropped when saving is back on before it is asked.
check(!HistoryDeletion.shouldAskOnSwitchOff(savedCount: 3, stillOff: false), "switch-off: a decision made after saving is back on is dropped")
check(HistoryDeletion.shouldAskOnSwitchOff(savedCount: 3, stillOff: true), "switch-off: with saving off and captures kept, the question is asked")
check(!HistoryDeletion.shouldAskOnSwitchOff(savedCount: 0, stillOff: true), "switch-off: nothing saved, nothing to ask")

// A history whose deletion is not confirmed in time: a late write may still land, but nothing is written after it.
final class LateSaveStore: HistoryStore, @unchecked Sendable {
    let stored: HistorySnapshot
    var saved: HistorySnapshot?
    init(stored: HistorySnapshot) { self.stored = stored }
    func load() -> HistoryLoad { .loaded(stored) }
    func save(_ snapshot: HistorySnapshot) -> HistoryPersistOutcome {
        Thread.sleep(forTimeInterval: 0.4)
        saved = snapshot
        return .confirmed
    }
}

/// Records what happens while a restart is in progress. `restartReturned` is set once the restart call returns, so a change
/// that runs before that point ran while the restart was still waiting.
@MainActor final class RestartProbe {
    var restartReturned = false
    var addedWhileWaiting = false
}

/// A store whose writes wait until the test releases them, so the test decides when a write is still in flight.
/// `started` is signalled when a write begins. Each write waits for one release; `letWritesFinish` releases up to two.
final class GatedStore: HistoryStore, @unchecked Sendable {
    let started = DispatchSemaphore(value: 0)
    private let release = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var stored: HistorySnapshot?
    var saved: HistorySnapshot? {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }
    func load() -> HistoryLoad { .empty }
    func save(_ snapshot: HistorySnapshot) -> HistoryPersistOutcome {
        started.signal()
        release.wait()
        lock.lock()
        stored = snapshot
        lock.unlock()
        return .confirmed
    }
    func letWritesFinish() {
        release.signal()
        release.signal()
    }
}
do {
    let stored = HistorySnapshot(texts: ["keep"], dates: [1_000])
    let store = LateSaveStore(stored: stored)
    let history = History(store: store, isEnabled: alwaysSaving)
    check(history.clearForReset(timeout: 0.1) == .unconfirmed && history.isClosed && history.items == ["keep"],
          "reset: a deletion still running at the timeout is reported as unconfirmed, and the history stays closed")
    history.add("after the timeout")
    History.flushWrites()
    check(store.saved?.texts.isEmpty == true && history.items == ["keep"],
          "reset: a late deletion cannot be followed by a restored or new capture", "\(store.saved?.texts ?? [])")
}

// Restart handoff: a restart takes the history file over. Changes queued before it reach the file, nothing is written
// after it, and a restart that does not start gives the history back.
do {
    let store = LateSaveStore(stored: HistorySnapshot(texts: ["kept"], dates: [1_000]))
    let history = History(store: store, isEnabled: alwaysSaving)
    history.add("pending")
    settle {
        let handedOff = await history.handOff()
        check(handedOff && store.saved?.texts == ["pending", "kept"],
              "handoff: a change queued before a restart is on disk when the handoff completes", "\(store.saved?.texts ?? [])")
    }
    history.add("after the handoff")
    history.remove("kept")
    History.flushWrites()
    check(store.saved?.texts == ["pending", "kept"] && history.items == ["pending", "kept"],
          "handoff: a capture or deletion after the handoff never reaches the file the new instance reads", "\(store.saved?.texts ?? [])")
}
do {
    let store = ScriptedStore(answers: [.empty])
    let history = History(store: store, isEnabled: alwaysSaving)
    settle { _ = await history.handOff() }
    history.cancelHandOff()
    history.add("after a failed restart")
    History.flushWrites()
    check(!history.isHandedOff && store.saved?.texts == ["after a failed restart"],
          "handoff: when the new instance cannot start, this one keeps saving")
}
do {
    let stored = HistorySnapshot(texts: ["keep"], dates: [1_000])
    let store = ScriptedStore(answers: [.loaded(stored)], saved: stored)
    store.writesSucceed = false
    let history = History(store: store, isEnabled: alwaysSaving)
    _ = history.clearForReset()
    store.writesSucceed = true
    settle { _ = await history.handOff() }
    history.cancelHandOff()
    history.add("still closed")
    History.flushWrites()
    check(history.isClosed && store.saved?.texts == ["keep"],
          "handoff: a history closed by a refused deletion stays closed after a restart that did not start")
}
do {
    let stored = HistorySnapshot(texts: ["kept"], dates: [1_000])
    let store = ScriptedStore(answers: [.loaded(stored)], saved: stored)
    let history = History(store: store, isEnabled: alwaysSaving)
    settle { _ = await history.handOff() }
    store.saved = HistorySnapshot(texts: ["saved by the new instance"], dates: [2_000])
    let cleared = history.clearForQuit()
    History.flushWrites()
    check(!cleared && store.saved?.texts == ["saved by the new instance"],
          "handoff: Clear on Quit after a restart leaves the file to the new instance, which clears it at launch", "\(store.saved?.texts ?? [])")
    check(!history.beginImport(), "handoff: no import starts once the history is handed off")
}
do {
    let stored = HistorySnapshot(texts: ["kept"], dates: [1_000])
    let store = ScriptedStore(answers: [.loaded(stored)], saved: stored)
    let history = History(store: store, isEnabled: alwaysSaving)
    _ = history.beginImport()
    let started = Date()
    settle {
        let handedOff = await history.handOff()
        check(!handedOff && history.importing && Date().timeIntervalSince(started) < 2,
              "handoff: a restart during an import is refused at once, and the import keeps its hold")
    }
    history.endImport()
    settle { await history.finishLoading() }
}
do {   // last: its 1 s write occupies the shared I/O queue
    let history = History(store: HungWriteStore(stored: HistorySnapshot(texts: ["x"], dates: [1_000])), isEnabled: alwaysSaving)
    history.add("y")
    let started = Date()
    settle {
        let handedOff = await history.handOff(timeout: 0.2)
        check(!handedOff && !history.isHandedOff && Date().timeIntervalSince(started) < 0.9,
              "handoff: a write that never finishes stops the restart in time, and nothing is handed over")
    }
    History.flushWrites()
}
do {
    // The first write is held, so the restart is still waiting for it when the second change arrives. The gate opens only
    // after that change is in, so the restart cannot finish before it.
    let store = GatedStore()
    let history = History(store: store, isEnabled: alwaysSaving)
    history.add("first")
    let begun = store.started.wait(timeout: .now() + 5) == .success
    check(begun, "handoff: the first write is in flight before the restart starts")
    if begun {
        settle {
            let probe = RestartProbe()
            // Queued before the restart starts. Both run on the main actor, which the restart holds until it suspends. The
            // restart suspends only inside its wait for the held write, so this change runs while the restart is waiting.
            Task { @MainActor in
                probe.addedWhileWaiting = !probe.restartReturned
                history.add("second")
                store.letWritesFinish()
            }
            let handedOff = await history.handOff()
            probe.restartReturned = true
            check(probe.addedWhileWaiting, "handoff: the second change arrived while the restart was waiting for the first write")
            check(handedOff && store.saved?.texts == ["second", "first"],
                  "handoff: a change made while the restart waits is written before the handoff completes", "\(store.saved?.texts ?? [])")
        }
    }
    // Releases the held write on every path, including a failed readiness wait, so the flush below cannot block on it.
    store.letWritesFinish()
    History.flushWrites()
}

// An unreadable history file is never overwritten at startup or by a capture. Only an explicit discard replaces it.
do {
    let store = ScriptedStore(answers: [.corrupt])
    let history = History(store: store, isEnabled: alwaysSaving)
    history.add("not saved")
    History.flushWrites()
    check(history.fileIsUnreadable && history.state == .unavailable && store.saves == 0,
          "unreadable history: startup and a capture leave the file alone", "saves \(store.saves)")
}
do {
    let store = ScriptedStore(answers: [.corrupt, .empty])
    let history = History(store: store, isEnabled: alwaysSaving)
    settle {
        let discarded = await history.discardUnreadableFile()
        while history.state == .loading { try? await Task.sleep(nanoseconds: 1_000_000) }
        check(discarded == .confirmed && store.saved?.texts.isEmpty == true && history.state == .available && !history.fileIsUnreadable,
              "unreadable history: an explicit discard replaces the file and starts an empty history")
    }
}
do {
    let store = ScriptedStore(answers: [.corrupt])
    store.writesSucceed = false
    let history = History(store: store, isEnabled: alwaysSaving)
    settle {
        let discarded = await history.discardUnreadableFile()
        check(discarded == .notWritten && history.fileIsUnreadable && store.saved == nil,
              "unreadable history: a discard that fails leaves the file and the state as they were")
    }
}

// An unconfirmed discard is reported, and the file decides what is shown: read again, it holds an empty history.
do {
    let store = ScriptedStore(answers: [.corrupt, .empty])
    store.writesSucceed = false
    store.failure = .unconfirmed
    let history = History(store: store, isEnabled: alwaysSaving)
    settle {
        let outcome = await history.discardUnreadableFile()
        while history.state == .loading { try? await Task.sleep(nanoseconds: 1_000_000) }
        check(outcome == .unconfirmed && store.saved?.texts.isEmpty == true && !history.fileIsUnreadable && history.state == .available,
              "unreadable history: a discard that is not confirmed is reported, and the file decides what is shown",
              "outcome \(outcome), state \(history.state)")
    }
}

// Reset touches the stored settings only. App state outside them, such as the legacy import marker, is kept.
do {
    let suite = freshSuite("reset-app-state")
    suite.defaults.set(true, forKey: StorageKeys.legacyHistoryImported)
    Settings.resetToDefaults(in: suite.defaults)
    check(suite.defaults.bool(forKey: StorageKeys.legacyHistoryImported), "reset: app state outside the settings is kept")
}

// Turning saving back on needs no read of a file that is already known, so the next capture is kept at once.
do {
    let suite = freshSuite("reenable")
    let settings = Settings(defaults: suite.defaults)
    let stored = HistorySnapshot(texts: ["kept"], dates: [1_000])
    let store = ScriptedStore(answers: [.loaded(stored)], saved: stored)
    let history = History(store: store, isEnabled: { settings.historyEnabled })
    settings.historyEnabled = false
    history.refresh()
    settings.historyEnabled = true
    history.refresh()
    history.add("captured right after")
    History.flushWrites()
    check(history.state == .available && store.saved?.texts == ["captured right after", "kept"],
          "save captures: turning saving back on keeps the next capture at once", "\(store.saved?.texts ?? [])")
}

// Finding #5: Save Captures, from the panel or Settings, is one command on the history and settings it is given.
do {
    let settings = Settings(defaults: freshSuite("save-captures-command").defaults)
    let history = History(store: ScriptedStore(answers: [.empty]), isEnabled: { settings.historyEnabled }, loadsNow: false)
    HistoryClearing.setSaveCaptures(true, history: history, settings: settings)
    settle { await history.finishLoading() }
    check(settings.historyEnabled && history.state == .available,
          "save captures: on writes the given settings and loads the given history", "\(history.state)")
    HistoryClearing.setSaveCaptures(false, history: history, settings: settings)
    drainMain()
    check(!settings.historyEnabled && history.state == .disabled,
          "save captures: off writes the given settings and stops the given history; nothing saved, so nothing is asked", "\(history.state)")
}

// The switch-off decision waits for a queued write, so the capture being written is counted.
do {
    let stored = HistorySnapshot(texts: ["keep"], dates: [1_000])
    let store = LateSaveStore(stored: stored)
    let history = History(store: store, isEnabled: alwaysSaving)
    history.add("x")
    settle { await history.finishLoading() }
    check(history.items == ["x", "keep"] && store.saved?.texts == ["x", "keep"],
          "switch-off: the decision waits for a queued write, so it counts the capture", "\(history.items)")
}

// Focus: the app the user came from gets focus back only while Nictate is still the active app, and only if it runs.
check(FocusReturn.shouldReturn(nictateIsActive: true, hasTarget: true, targetRunning: true, targetIsNictate: false),
      "focus: returns to the app the user came from while Nictate is still active")
check(!FocusReturn.shouldReturn(nictateIsActive: false, hasTarget: true, targetRunning: true, targetIsNictate: false),
      "focus: never takes focus from an app the user has since selected")
check(!FocusReturn.shouldReturn(nictateIsActive: true, hasTarget: false, targetRunning: true, targetIsNictate: false),
      "focus: nothing remembered, nothing to return to")
check(!FocusReturn.shouldReturn(nictateIsActive: true, hasTarget: true, targetRunning: false, targetIsNictate: false),
      "focus: a terminated app is never activated")
check(!FocusReturn.shouldReturn(nictateIsActive: true, hasTarget: true, targetRunning: true, targetIsNictate: true),
      "focus: never returns to Nictate itself")

// Recovery: the History row stays when the file needs recovery, and is not shown when there is nothing to recover.
check(HistoryDeletion.showsHistoryRow(historyEnabled: false, savedCount: 0, unreadable: true),
      "recovery: an unreadable file keeps the History row, with saving off and nothing listed")
check(!HistoryDeletion.showsHistoryRow(historyEnabled: false, savedCount: 0, unreadable: false),
      "recovery: with nothing to recover and saving off, the History row is not shown")
check(HistoryDeletion.showsHistoryRow(historyEnabled: true, savedCount: 0, unreadable: false)
      && HistoryDeletion.showsHistoryRow(historyEnabled: false, savedCount: 2, unreadable: false),
      "recovery: the History row is shown while saving is on or captures are kept")
do {
    let flags = [ScriptedStore(answers: [.corrupt]), ScriptedStore(answers: [.empty]), ScriptedStore(answers: [.loaded(.empty)])]
        .map { History(store: $0, isEnabled: alwaysSaving).fileIsUnreadable }
    check(flags == [true, false, false], "recovery: the discard is offered only when the file was detected unreadable", "\(flags)")
}

// Defaults and reset: a fresh install starts with Save Captures and Clear on Quit off, and a reset returns them to those
// defaults without switching Save Captures back on at the next launch.
do {
    let suite = freshSuite("defaults-reset")
    let fresh = Settings(defaults: suite.defaults)
    check(!fresh.historyEnabled && !fresh.clearHistoryOnQuit, "defaults: Save Captures and Clear on Quit start off")
    check(fresh.notificationStyle == .generic, "defaults: Copy Feedback starts at Notice Only", "\(fresh.notificationStyle)")
    fresh.historyEnabled = true
    fresh.clearHistoryOnQuit = true
    fresh.notificationStyle = .none
    Settings.resetToDefaults(in: suite.defaults)
    let afterReset = Settings(defaults: suite.defaults)
    check(suite.defaults.object(forKey: StorageKeys.historyEnabled) == nil, "reset: the Save Captures choice is removed")
    check(!afterReset.historyEnabled, "reset: Save Captures is off, and is not switched on at the next launch")
    check(!afterReset.clearHistoryOnQuit && afterReset.notificationStyle == .generic,
          "reset: Clear on Quit and Copy Feedback return to their defaults")
}

// History rows: the keyboard selection is the only accented row, and a row under the pointer gets only a tint.
check(captureHighlight(selected: true, hovered: true) == .selected, "highlight: the keyboard selection wins over the pointer")
check(captureHighlight(selected: true, hovered: false) == .selected, "highlight: the keyboard selection is accented")
check(captureHighlight(selected: false, hovered: true) == .hovered, "highlight: a row under the pointer gets only a tint")
check(captureHighlight(selected: false, hovered: false) == .none, "highlight: other rows are plain")

for suite in testSuites { suite.wipe() }
try? FileManager.default.removeItem(at: testPreferences)
if nameFilters.isEmpty == false && passes + failedChecks.count == 0 {
    print("\nNo check matches \(nameFilters.joined(separator: " "))")
    exit(1)
}
if failedChecks.isEmpty {
    print("\n\(passes) passed\nALL PASSED")
    exit(0)
}
print("\n\(passes) passed, \(failedChecks.count) failed:")
for failure in failedChecks { print("  \(failure)") }
print("\(failedChecks.count) FAILED")
exit(1)
