// Nictate: a macOS menu bar app that copies text from anywhere on your screen.
// Copyright (c) 2026 jrthormann. MIT License, see LICENSE.

import CoreGraphics
import Foundation

/// One recognized line/word with its Vision bounding box (normalized, origin bottom-left).
struct TextFragment: Equatable {
    let text: String
    let box: CGRect
    /// Set by the layout when the fragment is a cell of a detected table: the index of its column.
    var tableColumn: Int? = nil
}

private extension CGRect {
    /// Vision never returns a NaN or infinite box, but one would trap in the integer conversions below.
    var isFiniteRect: Bool { [origin.x, origin.y, size.width, size.height].allSatisfy(\.isFinite) }
}

enum TextLayout {
    /// Heuristic thresholds, in one place so tuning does not mean hunting for literals.
    private enum Tuning {
        /// A column gutter is at least this many characters wide...
        static let gutterChars: CGFloat = 6
        /// ...and at least this fraction of the image width.
        static let gutterFraction: CGFloat = 0.06
        /// Every column needs this many fragments, otherwise it is just ragged text.
        static let minColumnFragments = 3
        /// Neighbouring columns whose rows line up this often are a table...
        static let tablePairingRatio = 0.6
        /// ...provided their cells are short; long lines side by side are text columns.
        static let tableCellMaxLength = 20.0
        /// A fragment wider than this fraction of the image spans the page (a title across two columns).
        static let fullWidthFraction: CGFloat = 0.55
        /// A line jump larger than this multiple of the normal line pitch is a paragraph gap.
        static let paragraphGapRatio: CGFloat = 1.6
        static let maxBlankLines = 2
    }

    /// Rebuilds the on-screen layout from fragments:
    /// - reading order top-to-bottom, text columns one after another (tables stay row-wise);
    /// - blank lines where the screen has paragraph gaps;
    /// - with `preserveIndentation`, leading and inner gaps become spaces (median character width).
    static func compose(_ fragments: [TextFragment], imageSize: CGSize,
                        keepLineBreaks: Bool, preserveIndentation: Bool,
                        detectColumns: Bool = true, tablesAsTabs: Bool = false) -> String {
        guard imageSize.width.isFinite, imageSize.height.isFinite, imageSize.width > 0, imageSize.height > 0 else { return "" }
        let frags = fragments.filter { !$0.text.isEmpty && $0.box.isFiniteRect }
        guard !frags.isEmpty else { return "" }

        let charWidth = max(median(frags.map { $0.box.width * imageSize.width / CGFloat($0.text.count) }), 1)
        let tolerance = median(frags.map { $0.box.height * imageSize.height }) * 0.5
        // Tabs go between the cells of a detected table. Not in faithful mode, which keeps the screen's own
        // spacing, and not when lines are joined into one, where rows would run together.
        let tabs = tablesAsTabs && keepLineBreaks && !preserveIndentation
        let blocks = readingBlocks(frags, imageSize: imageSize, charWidth: charWidth, tolerance: tolerance,
                                   detectColumns: detectColumns).map {
            composeColumn($0, imageSize: imageSize, charWidth: charWidth, tolerance: tolerance,
                          keepLineBreaks: keepLineBreaks, preserve: preserveIndentation && keepLineBreaks, tabs: tabs)
        }
        return blocks.joined(separator: keepLineBreaks ? "\n\n" : " ")
    }

    /// Fragment groups in reading order. A full-width line (a title across the page) divides the page
    /// into bands, and each band is split into columns on its own. A page with no columns stays one block.
    private static func readingBlocks(_ frags: [TextFragment], imageSize: CGSize, charWidth: CGFloat,
                                      tolerance: CGFloat, detectColumns: Bool) -> [[TextFragment]] {
        guard detectColumns else { return [frags] }

        var bands: [(fragments: [TextFragment], isFullWidth: Bool)] = []
        for frag in frags.sorted(by: { $0.box.midY > $1.box.midY }) {
            let isFullWidth = frag.box.width > Tuning.fullWidthFraction
            if let last = bands.indices.last, bands[last].isFullWidth == isFullWidth {
                bands[last].fragments.append(frag)
            } else {
                bands.append(([frag], isFullWidth))
            }
        }

        var blocks: [[TextFragment]] = []
        var everything: [TextFragment] = []   // the same fragments, with table cells marked
        var foundColumns = false
        for band in bands {
            if band.isFullWidth {
                blocks.append(band.fragments)
                everything += band.fragments
                continue
            }
            switch splitColumns(band.fragments, imageSize: imageSize, charWidth: charWidth, tolerance: tolerance) {
            case .single(let fragments), .table(let fragments):
                blocks.append(fragments)
                everything += fragments
            case .columns(let groups):
                foundColumns = foundColumns || groups.count > 1
                blocks += groups
                everything += groups.flatMap { $0 }
            }
        }
        return foundColumns ? blocks : [everything]
    }

    private static func composeColumn(_ frags: [TextFragment], imageSize: CGSize, charWidth: CGFloat,
                                      tolerance: CGFloat, keepLineBreaks: Bool, preserve: Bool, tabs: Bool) -> String {
        var lines: [[TextFragment]] = []
        var lineY: [CGFloat] = []
        for frag in frags.sorted(by: { $0.box.midY > $1.box.midY }) {
            let y = frag.box.midY * imageSize.height
            if let last = lineY.indices.last, abs(lineY[last] - y) <= tolerance {
                lines[last].append(frag)
            } else {
                lines.append([frag])
                lineY.append(y)
            }
        }

        // Normal distance between lines; a clearly larger jump is a paragraph gap.
        let steps = zip(lineY, lineY.dropFirst()).map { $0 - $1 }.filter { $0 > 0 }.sorted()
        let pitch = steps.isEmpty ? 0 : steps[(steps.count - 1) / 2]

        let originX = frags.map { $0.box.minX * imageSize.width }.min() ?? 0
        var out = ""
        for (index, line) in lines.enumerated() {
            if index > 0 {
                if keepLineBreaks {
                    out += "\n"
                    let step = lineY[index - 1] - lineY[index]
                    if pitch > 0, step > Tuning.paragraphGapRatio * pitch {
                        out += String(repeating: "\n", count: min(max(Int((step / pitch).rounded()) - 1, 1), Tuning.maxBlankLines))
                    }
                } else {
                    out += " "
                }
            }
            var cursor = originX
            let ordered = line.sorted(by: { $0.box.minX < $1.box.minX })
            for (i, frag) in ordered.enumerated() {
                let x = frag.box.minX * imageSize.width
                if preserve {
                    let gap = Int(((x - cursor) / charWidth).rounded())
                    out += String(repeating: " ", count: min(i == 0 ? max(gap, 0) : max(gap, 1), 200))
                } else if i > 0 {
                    // One tab per column step between two table cells, so a missing cell leaves an empty field.
                    if tabs, let from = ordered[i - 1].tableColumn, let to = frag.tableColumn, to > from {
                        out += String(repeating: "\t", count: to - from)
                    } else {
                        out += " "
                    }
                } else if tabs, let column = frag.tableColumn {
                    out += String(repeating: "\t", count: column)   // empty cells before the first one
                }
                out += frag.text
                cursor = frag.box.maxX * imageSize.width
            }
        }
        return out
    }

    /// What a band of fragments turned out to be.
    private enum Split {
        case single([TextFragment])
        case columns([[TextFragment]])
        /// Aligned rows of short cells; each fragment carries its column index.
        case table([TextFragment])
    }

    /// Splits at wide empty vertical gutters. Aligned rows of short cells are a table and are not split.
    private static func splitColumns(_ frags: [TextFragment], imageSize: CGSize,
                                     charWidth: CGFloat, tolerance: CGFloat) -> Split {
        if let cells = rowTable(frags, imageSize: imageSize, charWidth: charWidth, tolerance: tolerance) { return .table(cells) }
        let width = imageSize.width
        let minGutter = max(Tuning.gutterChars * charWidth, Tuning.gutterFraction * width)
        let spans = frags.map { ($0.box.minX * width, $0.box.maxX * width) }.sorted { $0.0 < $1.0 }

        var cuts: [CGFloat] = []
        var reach = spans[0].1
        for (low, high) in spans.dropFirst() {
            if low - reach >= minGutter { cuts.append((low + reach) / 2) }
            reach = max(reach, high)
        }
        guard !cuts.isEmpty else { return .single(frags) }

        var groups = Array(repeating: [TextFragment](), count: cuts.count + 1)
        for frag in frags {
            let centerX = frag.box.midX * width
            groups[cuts.filter { $0 < centerX }.count].append(frag)
        }
        guard groups.allSatisfy({ $0.count >= Tuning.minColumnFragments }) else { return .single(frags) }

        for i in 0..<(groups.count - 1) {
            let paired = groups[i].filter { left in
                groups[i + 1].contains { abs($0.box.midY - left.box.midY) * imageSize.height <= tolerance }
            }.count
            if Double(paired) / Double(groups[i].count) >= Tuning.tablePairingRatio,
               isTableColumn(groups[i], width: width, charWidth: charWidth),
               isTableColumn(groups[i + 1], width: width, charWidth: charWidth) {
                let cells = frags.map { frag -> TextFragment in
                    var cell = frag
                    cell.tableColumn = cuts.filter { $0 < frag.box.midX * width }.count
                    return cell
                }
                return .table(cells)
            }
        }
        return .columns(groups)
    }

    /// How many lines hold two or more fragments: a cheap sign that a capture may be a table.
    static func multiCellRows(_ fragments: [TextFragment], imageSize: CGSize) -> Int {
        let tolerance = median(fragments.map { $0.box.height * imageSize.height }) * 0.5
        var rowY: [CGFloat] = [], counts: [Int] = []
        for frag in fragments.sorted(by: { $0.box.midY > $1.box.midY }) {
            let y = frag.box.midY * imageSize.height
            if let last = rowY.indices.last, abs(rowY[last] - y) <= tolerance { counts[last] += 1 } else { rowY.append(y); counts.append(1) }
        }
        return counts.filter { $0 >= 2 }.count
    }

    /// A table found by its rows rather than by gutters: three or more rows with the same number (two or
    /// more) of short cells whose columns line up. Gutters miss tables whose columns are close together or
    /// unevenly spaced (measured on a 13 px spreadsheet: the last column was split off and read after the rest).
    /// Every fragment is marked with the column whose edges it is nearest to.
    private static func rowTable(_ frags: [TextFragment], imageSize: CGSize, charWidth: CGFloat,
                                 tolerance: CGFloat) -> [TextFragment]? {
        var rows: [[TextFragment]] = []
        var rowY: [CGFloat] = []
        for frag in frags.sorted(by: { $0.box.midY > $1.box.midY }) {
            let y = frag.box.midY * imageSize.height
            if let last = rowY.indices.last, abs(rowY[last] - y) <= tolerance {
                rows[last].append(frag)
            } else {
                rows.append([frag])
                rowY.append(y)
            }
        }
        let counts = rows.map(\.count).filter { $0 >= 2 }
        guard let cellsPerRow = Dictionary(grouping: counts, by: { $0 }).max(by: { $0.value.count < $1.value.count })?.key
        else { return nil }
        let full = rows.filter { $0.count == cellsPerRow }.map { $0.sorted { $0.box.minX < $1.box.minX } }
        guard full.count >= Tuning.minColumnFragments,
              Double(full.count) >= Tuning.tablePairingRatio * Double(rows.count) else { return nil }

        let width = imageSize.width
        var anchors: [(left: CGFloat, right: CGFloat)] = []
        for column in 0..<cellsPerRow {
            let cells = full.map { $0[column] }
            guard isTableColumn(cells, width: width, charWidth: charWidth) else { return nil }
            anchors.append((median(cells.map { $0.box.minX * width }), median(cells.map { $0.box.maxX * width })))
        }
        guard zip(anchors, anchors.dropFirst()).allSatisfy({ $0.left < $1.left }) else { return nil }

        return frags.map { frag in
            let left = frag.box.minX * width, right = frag.box.maxX * width
            var cell = frag
            cell.tableColumn = anchors.indices.min { a, b in
                min(abs(anchors[a].left - left), abs(anchors[a].right - right)) < min(abs(anchors[b].left - left), abs(anchors[b].right - right))
            }
            return cell
        }
    }

    /// Short cells that share an edge: left-aligned text or right-aligned numbers. Code (ragged left edge from
    /// indentation) and prose (long lines) are not table columns, however well their rows happen to line up.
    private static func isTableColumn(_ group: [TextFragment], width: CGFloat, charWidth: CGFloat) -> Bool {
        let averageLength = Double(group.reduce(0) { $0 + $1.text.count }) / Double(group.count)
        guard averageLength < Tuning.tableCellMaxLength else { return false }
        let lefts = group.map { $0.box.minX * width }, rights = group.map { $0.box.maxX * width }
        return (lefts.max() ?? 0) - (lefts.min() ?? 0) <= charWidth || (rights.max() ?? 0) - (rights.min() ?? 0) <= charWidth
    }

    private static func median(_ values: [CGFloat]) -> CGFloat {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        return sorted[sorted.count / 2]
    }
}

enum TextCleaner {
    /// Surrounding whitespace to remove. Tabs stay: a table row can start or end with an empty cell.
    private static let trimmed = CharacterSet.whitespacesAndNewlines.subtracting(CharacterSet(charactersIn: "\t"))

    /// Final clean-up of recognized text. Symbols are never touched; in code mode the first line's
    /// indentation survives (only blank lines and trailing whitespace are removed).
    static func finalize(_ raw: String, preserveIndentation: Bool,
                         dehyphenate: Bool, collapseSpaces: Bool) -> String {
        if !preserveIndentation {
            var text = raw
            if dehyphenate {
                text = text.replacingOccurrences(of: #"(\p{L})-\n(\p{Ll})"#, with: "$1$2", options: .regularExpression)
            }
            if collapseSpaces {
                // Spaces only: the layout's own tabs separate table cells and must survive.
                text = text.replacingOccurrences(of: #" {2,}"#, with: " ", options: .regularExpression)
            }
            return text.trimmingCharacters(in: Self.trimmed)
        }

        var lines = raw.components(separatedBy: "\n")
        while let first = lines.first, first.trimmingCharacters(in: .whitespaces).isEmpty { lines.removeFirst() }
        while let last = lines.last, last.trimmingCharacters(in: .whitespaces).isEmpty { lines.removeLast() }
        return lines
            .map { $0.replacingOccurrences(of: #"[ \t]+$"#, with: "", options: .regularExpression) }
            .joined(separator: "\n")
    }

    /// Additive clipboard: `existing + delimiter + new`, or just `new` if the clipboard is empty.
    static func appended(existing: String?, new: String, delimiter: String) -> String {
        guard let existing, !existing.isEmpty else { return new }
        return existing + delimiter + new
    }

    /// What goes on the clipboard for a new capture. With `appendMode` off the existing clipboard is
    /// ignored entirely, so nothing from an earlier capture can reach this one.
    static func clipboardText(new: String, existing: String?, appendMode: Bool, delimiter: String) -> String {
        appendMode ? appended(existing: existing, new: new, delimiter: delimiter) : new
    }
}
