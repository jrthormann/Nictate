// Nictate: a macOS menu bar app that copies text from anywhere on your screen.
// Copyright (c) 2026 jrthormann. MIT License, see LICENSE.

import AppKit
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
/// A sealed history file of its own under the test folder, with a fixed key.
func sealedStore(_ tag: String) -> EncryptedHistoryStore {
    EncryptedHistoryStore(fileURL: testPreferences.appendingPathComponent("\(tag)-\(UUID().uuidString).sealed"),
                          key: { _ in SymmetricKey(data: Data(repeating: 9, count: 32)) })
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
    stored.set(25, forKey: "rotationDepth"); stored.set(["es-ES"], forKey: "languages")
    check(prefs.codeMode && prefs.appendSeparator == "tab" && prefs.rotationDepth == 25
          && prefs.languages == ["es-ES"], "storage: values saved under the old key names still load")
    prefs.cleanText = true; prefs.hotKeyLabel = "⌥⌘K"
    check(stored.object(forKey: "dehyphenate") as? Bool == true && stored.string(forKey: "hotKeyLabel") == "⌥⌘K", "storage: writes land under the old key names")
}
do {
    let keys = Set(StorageKeys.settings)
    check(keys.count == StorageKeys.settings.count, "storage: no settings key is listed twice")
    check(keys.isDisjoint(with: [StorageKeys.didOnboard, StorageKeys.WindowFrame.history]),
          "storage: settings keys are separate from the history and app-state keys")
}
check(StorageKeys.didOnboard == "didOnboard"
      && StorageKeys.WindowFrame.history == "Nictate.History", "storage: non-settings keys unchanged")

// Defaults: what a new user gets, read over an empty suite. The registered defaults are process-wide
// (UserDefaults keeps one registration domain), so they apply to the suite as they do to the app.
do {
    let prefs = Settings(defaults: freshSuite("defaults").defaults)
    let table: [(String, Bool)] = [
        ("capture shortcut is ⇧⌘2", prefs.hotKeyCode == kVK_ANSI_2 && prefs.hotKeyMods == cmdKey | shiftKey && prefs.hotKeyLabel == "⇧⌘2"),
        ("rotation shortcut is ⌥⇧⌘2", prefs.rotateHotKeyCode == kVK_ANSI_2 && prefs.rotateHotKeyMods == optionKey | shiftKey | cmdKey
            && prefs.rotateHotKeyLabel == "⌥⇧⌘2"),
        ("the optional shortcut is unset", prefs.shortcut(for: .captureCode) == nil),
        ("rotation walks ten captures", prefs.rotationDepth == 10),
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
        ("history is on", prefs.historyEnabled),
        ("history is kept on quit", !prefs.clearHistoryOnQuit),
        ("a new install keeps captures for 7 days", prefs.historyRetention == .week),
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
    prefs.rotationDepth = 3; prefs.visualCue = false; prefs.notificationStyle = .text
    prefs.languages = ["es-ES"]; prefs.languageCorrection = false; prefs.codeMode = true; prefs.keepLineBreaks = false
    prefs.detectColumns = false; prefs.tablesAsTabs = false; prefs.cleanText = true; prefs.codeClean = true
    prefs.appendMode = true; prefs.appendSeparator = "tab"; prefs.barcodeAction = "ask"
    prefs.detectContent = false; prefs.hideFromClipboardManagers = true
    prefs.historyEnabled = false; prefs.clearHistoryOnQuit = true; prefs.historyRetention = .day
    let written = Set(suite.defaults.persistentDomain(forName: suite.name)?.keys.map { $0 } ?? [])
    check(written == Set(StorageKeys.settings), "storage: every setting is written under a listed key, and every listed key belongs to a setting",
          "\(written.symmetricDifference(StorageKeys.settings).sorted())")
    let back = Settings(defaults: suite.defaults)
    check(back.shortcut(for: .capture)! == (Shortcut(code: 1, mods: cmdKey), "⌘S")
          && back.shortcut(for: .rotateHistory)! == (Shortcut(code: 3, mods: optionKey), "⌥F")
          && back.shortcut(for: .captureCode)! == (Shortcut(code: 8, mods: cmdKey | controlKey), "⌃⌘C"),
          "storage: every shortcut reads back with its label")
    check(back.rotationDepth == 3 && !back.visualCue && back.notificationStyle == .text
          && back.languages == ["es-ES"] && !back.languageCorrection && back.codeMode && !back.keepLineBreaks
          && !back.detectColumns && !back.tablesAsTabs && back.cleanText && back.codeClean
          && back.appendMode && back.appendSeparator == "tab" && back.barcodeAction == "ask"
          && !back.detectContent && back.hideFromClipboardManagers
          && !back.historyEnabled && back.clearHistoryOnQuit && back.historyRetention == .day,
          "storage: every other setting reads back")
}

// Notifications: permission is asked once, at the first notification actually sent.
do {
    var gate = NotificationGate()
    check(gate.shouldRequest(), "notifications: the first notification asks for permission")
    check(!gate.shouldRequest() && !gate.shouldRequest(), "notifications: later ones do not ask again")
}

// Welcome: the primary button restarts only when the permission still does not apply after a visit to Settings.
check(ScreenRecordingStep.state(granted: true, returnedFromSettings: false) == .granted, "welcome: granted -> granted")
check(ScreenRecordingStep.state(granted: true, returnedFromSettings: true) == .granted, "welcome: granted after a visit -> granted")
check(ScreenRecordingStep.state(granted: false, returnedFromSettings: false) == .pending, "welcome: not yet granted, never left -> pending")
check(ScreenRecordingStep.state(granted: false, returnedFromSettings: true) == .notActiveYet, "welcome: back from Settings without the permission applying -> Restart")

// History dates: each capture keeps its time beside its text.
do {
    let store = sealedStore("dates")
    let history = History(store: store, retention: { .never })
    let t0 = Date(timeIntervalSince1970: 1_000)
    history.add("a", at: t0)
    history.add("b", at: t0 + 60)
    check(history.items == ["b", "a"] && history.dates == [t0 + 60, t0], "history dates: newest first, each beside its text")
    history.add("a", at: t0 + 120)
    check(history.items == ["a", "b"] && history.dates == [t0 + 120, t0 + 60], "history dates: a repeated capture moves to the front with a new time")
    history.remove("b")
    check(history.items == ["a"] && history.dates == [t0 + 120], "history dates: removing keeps them aligned")
    check(history.date(for: "a") == t0 + 120 && history.date(for: "nope") == nil, "history dates: lookup by text")
    History.flushWrites()
    let reloaded = History(store: store, retention: { .never })
    check(reloaded.items == ["a"] && reloaded.dates == [t0 + 120], "history dates: texts and times are saved and load back")
    history.clear()
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

// History retention: old captures expire, and ones with an unknown time are never guessed at.
do {
    check(HistoryRetention.never.seconds == nil && HistoryRetention.hour.seconds == 3_600
          && HistoryRetention.day.seconds == 86_400 && HistoryRetention.week.seconds == 604_800, "retention: choices and their lengths")
    let suite = freshSuite("retention")
    let settings = Settings(defaults: suite.defaults)
    let history = History(store: sealedStore("retention"), retention: { settings.historyRetention })
    let now = Date(timeIntervalSince1970: 1_000_000)
    history.add("old", at: now - 7_200)
    history.add("fresh", at: now - 600)
    history.add("unknown", at: .distantPast)
    history.prune(olderThan: nil, now: now)
    check(history.items.count == 3, "retention: never expires nothing")
    history.prune(olderThan: 3_600, now: now)
    check(history.items == ["unknown", "fresh"] && history.dates.count == 2, "retention: entries past the limit go, unknown-time entries stay, dates stay aligned")
    history.prune(olderThan: 60, now: now)
    check(history.items == ["unknown"], "retention: a shorter limit removes more")
    history.clear()
    settings.historyRetention = .hour
    history.add("a", at: Date().addingTimeInterval(-7_200))
    history.pruneExpired()
    check(history.items.isEmpty, "retention: pruneExpired uses the chosen setting")
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
    let history = History(store: sealedStore("robustness"), retention: { .never })
    history.add(String(repeating: "x", count: History.maxStoredLength + 1))
    check(history.items.isEmpty, "robustness: a capture too large for the history file is not stored")
    history.add("short")
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
    let count = writer.write("b", transient: false)
    check(count == board.changeCount && writer.lastWrite == ClipboardWrite(changeCount: count, text: "b"),
          "clipboard writer: the recorded count is the one the write produced")
    let trio = ["c", "b", "a"]
    check(HistoryRotation.nextIndex(items: trio, clipboard: writer.ownText) == 2,
          "clipboard writer: after a History window copy of the second, rotation moves on to the third")
    writer.write("b", transient: true)
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

// Sealed history: no readable capture on disk, a wrong key or a changed byte is rejected, a locked key never
// overwrites the file, and captures from the preferences move into it and the plain copy is removed.
do {
    let store = sealedStore("sealed")
    let history = History(store: store, retention: { .never })
    history.add("secret phrase quartz", at: Date(timeIntervalSince1970: 1_000))
    History.flushWrites()
    let bytes = (try? Data(contentsOf: store.fileURL)) ?? Data()
    check(!bytes.isEmpty && bytes.range(of: Data("secret phrase quartz".utf8)) == nil, "sealed: the file holds no readable capture")
    check(History(store: store, retention: { .never }).items == ["secret phrase quartz"], "sealed: captures open again with the same key")

    let locked = EncryptedHistoryStore(fileURL: store.fileURL, key: { _ in throw CocoaError(.fileReadNoPermission) })
    let blocked = History(store: locked, retention: { .never })
    blocked.add("not written")
    History.flushWrites()
    check(blocked.items == ["not written"] && History(store: store, retention: { .never }).items == ["secret phrase quartz"],
          "sealed: with the key locked, nothing is written and the file is kept")

    let wrong = EncryptedHistoryStore(fileURL: store.fileURL, key: { _ in SymmetricKey(data: Data(repeating: 1, count: 32)) })
    check(History(store: wrong, retention: { .never }).items.isEmpty, "sealed: a wrong key shows nothing")

    var tampered = bytes
    tampered[tampered.count / 2] ^= 0xFF
    try? tampered.write(to: store.fileURL)
    let rejected = History(store: store, retention: { .never })
    check(rejected.items.isEmpty, "sealed: a changed byte is rejected and the history starts empty")
    check(rejected.state == .unavailable, "sealed: a file that cannot be opened leaves the history unavailable")
    rejected.add("after tamper")
    History.flushWrites()
    check((try? Data(contentsOf: store.fileURL)) == tampered, "sealed: a file that cannot be opened is never overwritten")

}

/// Runs an async History call to completion from the test's main thread.
@MainActor func settle(_ work: @escaping @MainActor () async -> Void) {
    var finished = false
    Task { await work(); finished = true }
    while !finished { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01)) }
}

/// A store whose answers the test scripts: each load returns the next scripted result, and saves are counted.
/// Only the test's main thread changes it, and only after the I/O queue has been flushed.
final class ScriptedStore: HistoryStore, @unchecked Sendable {
    var answers: [HistoryLoad]
    var saved: HistorySnapshot?
    var loads = 0
    var saves = 0
    init(answers: [HistoryLoad], saved: HistorySnapshot? = nil) {
        self.answers = answers
        self.saved = saved
    }
    func load() -> HistoryLoad {
        loads += 1
        guard answers.count > 1 else { return answers.first ?? .unavailable }
        return answers.removeFirst()
    }
    func save(_ snapshot: HistorySnapshot) -> Bool {
        saves += 1
        saved = snapshot
        return true
    }
}

// Sealed history: authorization can be denied, delayed or restored, and none of those states writes over the
// file, shows an empty history by mistake, or blocks the caller. The one thing it may do is read the file again.
do {
    let stored = HistorySnapshot(texts: ["old"], dates: [1_000])

    // Denied: unavailable, captures stay in memory, the file is never written.
    let denied = ScriptedStore(answers: [.unavailable], saved: stored)
    let deniedHistory = History(store: denied, retention: { .never })
    deniedHistory.add("new", at: Date(timeIntervalSince1970: 2_000))
    History.flushWrites()
    check(deniedHistory.state == .unavailable && deniedHistory.items == ["new"],
          "authorization: denied shows unavailable, keeps new captures in memory")
    check(denied.saves == 0 && denied.saved == stored, "authorization: denied never writes the file")

    // Delayed, then granted: loading, then the stored history merged with what was captured meanwhile.
    let delayed = ScriptedStore(answers: [.unavailable, .loaded(stored)], saved: stored)
    let delayedHistory = History(store: delayed, retention: { .never })
    delayedHistory.add("while waiting", at: Date(timeIntervalSince1970: 2_000))
    settle { await delayedHistory.reload() }
    History.flushWrites()
    check(delayedHistory.state == .available && delayedHistory.items == ["while waiting", "old"],
          "authorization: granted later merges the stored history with the captures made meanwhile",
          "\(delayedHistory.items)")
    check(delayed.saved?.texts == ["while waiting", "old"], "authorization: the merged history is written once readable")

    // Recovery: after a denial the original history loads again, unchanged.
    let recovered = ScriptedStore(answers: [.unavailable, .loaded(stored)], saved: stored)
    let recoveredHistory = History(store: recovered, retention: { .never })
    settle { await recoveredHistory.reload() }
    check(recoveredHistory.items == ["old"] && recoveredHistory.state == .available && recovered.saves == 0,
          "authorization: recovery shows the original history and writes nothing new")

    // A removal made while unavailable is not undone by the older copy on disk.
    let removal = ScriptedStore(answers: [.unavailable, .loaded(stored)], saved: stored)
    let removalHistory = History(store: removal, retention: { .never })
    removalHistory.remove("old")
    settle { await removalHistory.reload() }
    History.flushWrites()
    check(removalHistory.items.isEmpty && removal.saved?.texts == [],
          "authorization: a removal made while unavailable is applied once the file can be read")

    // Corrupt: the file is kept as it is, and the history is unavailable rather than empty.
    let corrupt = ScriptedStore(answers: [.corrupt], saved: stored)
    let corruptHistory = History(store: corrupt, retention: { .never })
    corruptHistory.add("kept", at: Date(timeIntervalSince1970: 2_000))
    History.flushWrites()
    check(corruptHistory.state == .unavailable && corrupt.saves == 0 && corrupt.saved == stored,
          "authorization: a corrupt file is never overwritten")

    // Disabled: no load at all, so no Keychain access.
    let disabled = ScriptedStore(answers: [.loaded(stored)], saved: stored)
    let disabledHistory = History(store: disabled, retention: { .never }, isEnabled: { false }, loadsNow: false)
    disabledHistory.refresh()
    check(disabledHistory.state == .disabled && disabled.loads == 0,
          "authorization: a disabled history never reads the file or the key")

    // Loading from the app's path does not run the read on the main thread, and the caller gets control back.
    let slow = ScriptedStore(answers: [.loaded(stored)], saved: stored)
    let slowHistory = History(store: slow, retention: { .never }, loadsNow: false)
    check(slowHistory.state == .loading && slowHistory.items.isEmpty && slow.loads == 0,
          "authorization: the app's history starts loading without reading the file at launch")
    settle { await slowHistory.reload() }
    check(slowHistory.items == ["old"] && slowHistory.state == .available, "authorization: the background load shows the history")

    // Launch regression: a history that starts in `loading` must still start its read when the app asks.
    let launched = ScriptedStore(answers: [.loaded(stored)], saved: stored)
    let launchedHistory = History(store: launched, retention: { .never }, isEnabled: { true }, loadsNow: false)
    settle { await launchedHistory.refresh()?.value }
    check(launched.loads == 1 && launchedHistory.items == ["old"] && launchedHistory.state == .available,
          "authorization: refresh at launch starts the read, which had been skipped while the state was loading",
          "loads \(launched.loads), state \(launchedHistory.state)")
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
        check(UpdateCheck.outcome(current: "1.0.0", release: release) == .available(version: "1.1.0", page: release.htmlURL),
              "updates: a newer release is offered with its page and without the v")
        check(UpdateCheck.outcome(current: "1.1.0", release: release) == .upToDate, "updates: the current release is up to date")
    }
    let foreign = ReleaseInfo(tagName: "v9.0.0", htmlURL: URL(string: "https://example.com/release")!)
    check(UpdateCheck.outcome(current: "1.0.0", release: foreign) == .failed, "updates: a release page off github.com is never offered")
    check(UpdateCheck.endpoint.scheme == "https" && UpdateCheck.endpoint.host == "api.github.com", "updates: the only request goes to GitHub's API over https")
}

// Reset: stored settings go, retention is written as week so the next launch keeps it, onboarding stays.
do {
    let suite = freshSuite("reset")
    suite.defaults.set(false, forKey: StorageKeys.visualCue)
    suite.defaults.set(50, forKey: StorageKeys.rotationDepth)
    suite.defaults.set(HistoryRetention.hour.rawValue, forKey: StorageKeys.historyRetention)
    suite.defaults.set(true, forKey: StorageKeys.didOnboard)
    Settings.resetToDefaults(in: suite.defaults)
    let stored = suite.defaults.persistentDomain(forName: suite.name) ?? [:]
    check(stored[StorageKeys.visualCue] == nil && stored[StorageKeys.rotationDepth] == nil,
          "reset: stored settings are removed, so each one returns to its default")
    check(suite.defaults.string(forKey: StorageKeys.historyRetention) == HistoryRetention.week.rawValue,
          "reset: retention becomes a week, so the next launch does not settle it as never")
    check(suite.defaults.bool(forKey: StorageKeys.didOnboard), "reset: onboarding stays done, so the welcome window does not come back")
}

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
