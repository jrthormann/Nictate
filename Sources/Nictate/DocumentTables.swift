// Nictate: a macOS menu bar app that copies text from anywhere on your screen.
// Copyright (c) 2026 jrthormann. MIT License, see LICENSE.

import Foundation
import CoreGraphics
import Vision
import os

/// Apple's document reader (macOS 26 and later) as a second opinion on tables. Nictate's own layout runs
/// first; this is consulted only when that found no table, and its table is used only when it holds
/// nearly all of the text, so a page with a table among paragraphs keeps Nictate's reading.
enum DocumentTables {
    static func tsv(_ rows: [[String]]) -> String {
        rows.filter { !$0.isEmpty }.map { $0.joined(separator: "\t") }.joined(separator: "\n")
    }

    /// The table must hold at least 90% of the recognized characters.
    static func prefersTable(tableCharacters: Int, textCharacters: Int) -> Bool {
        textCharacters > 0 && Double(tableCharacters) >= 0.9 * Double(textCharacters)
    }

    /// Apple's reader runs its own text recognition, which can read a cell differently. Its table supplies
    /// structure only: it is used if every cell also appears in Nictate's own reading.
    static func cellsAgree(_ rows: [[String]], with text: String) -> Bool {
        let flat = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return rows.joined().allSatisfy { cell in
            let normalized = cell.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            return normalized.isEmpty || flat.contains(normalized)
        }
    }

    /// How long a capture waits for the reader. It usually answers in about 0.1 s, but its first run on a
    /// new install took 13.7 s once (measured), and a capture blocks every shortcut while it waits.
    static let captureTimeout: TimeInterval = 1.5

    /// Rows of the first table Apple finds, or nil (also before macOS 26, on an error, and when the reader
    /// takes longer than `timeout`, so the capture keeps Nictate's own layout). Blocking: call off the main thread.
    static func rows(in image: CGImage, timeout: TimeInterval = captureTimeout) -> [[String]]? {
        guard #available(macOS 26.0, *) else { return nil }
        let done = DispatchSemaphore(value: 0)
        // A reader that runs past the timeout can still finish later, so the result is handed over under a lock.
        let found = OSAllocatedUnfairLock<[[String]]?>(initialState: nil)
        let task = Task.detached {
            defer { done.signal() }
            do {
                let observations = try await RecognizeDocumentsRequest().perform(on: image, orientation: nil)
                guard let table = observations.first?.document.tables.first else { return }
                let rows = table.rows.map { row in row.map { $0.content.text.transcript.trimmingCharacters(in: .whitespacesAndNewlines) } }
                found.withLock { $0 = rows }
            } catch where !Task.isCancelled {
                Log.recognition.error("Document reader: \(error.localizedDescription, privacy: .public)")
            }
        }
        guard done.wait(timeout: .now() + timeout) == .success else {
            task.cancel()
            Log.recognition.notice("Document reader still busy after \(timeout) s; keeping Nictate's own layout")
            return nil
        }
        return found.withLock { $0 }
    }
}
