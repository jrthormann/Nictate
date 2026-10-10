// Nictate: a macOS menu bar app that copies text from anywhere on your screen.
// Copyright (c) 2026 jrthormann. MIT License, see LICENSE.

import Foundation

/// The product limit: History keeps at most this many captures, on disk and on screen.
enum HistoryPolicy {
    static let maximumHistoryEntries = 15
}

/// What History keeps: the texts, newest first, and their capture times in seconds since 1970.
struct HistorySnapshot: Codable, Equatable, Sendable {
    var texts: [String]
    var dates: [Double]

    static let empty = HistorySnapshot(texts: [], dates: [])

    /// The same snapshot, cut to the product limit. Every load and every write goes through this.
    func capped() -> HistorySnapshot {
        let limit = HistoryPolicy.maximumHistoryEntries
        return HistorySnapshot(texts: Array(texts.prefix(limit)), dates: Array(dates.prefix(limit)))
    }
}

/// What a store found. `corrupt` means the file is there but cannot be read as History. `unavailable` means it
/// could not be read at all. Neither is an empty history: nothing may be written over the file in either case.
enum HistoryLoad: Equatable {
    case empty
    case loaded(HistorySnapshot)
    case corrupt
    case unavailable
}

/// Where the history lives between launches. `save` returns false when nothing could be written.
protocol HistoryStore: Sendable {
    func load() -> HistoryLoad
    func save(_ snapshot: HistorySnapshot) -> Bool
}

/// The history as a JSON file in the app's Application Support folder, inside its sandbox container.
/// Writes are atomic, and each write is read back and compared before it is reported as saved.
struct JSONHistoryStore: HistoryStore, Sendable {
    let fileURL: URL

    /// `history.json` in Application Support, in the folder named by the build (production and QA differ).
    static var standardURL: URL {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return folder.appendingPathComponent(BuildIdentity.historyFolderName, isDirectory: true)
            .appendingPathComponent("history.json")
    }

    func load() -> HistoryLoad {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return .empty }
        guard let data = try? Data(contentsOf: fileURL) else { return .unavailable }
        guard let snapshot = try? JSONDecoder().decode(HistorySnapshot.self, from: data),
              snapshot.texts.count == snapshot.dates.count else { return .corrupt }
        return .loaded(snapshot.capped())
    }

    func save(_ snapshot: HistorySnapshot) -> Bool {
        do {
            let data = try JSONEncoder().encode(snapshot.capped())
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
            // Read back what was written before reporting success.
            return (try? Data(contentsOf: fileURL)) == data
        } catch {
            return false
        }
    }
}

/// The history store the app uses. The QA build uses the same JSON store in its own folder (BuildIdentity).
enum AppHistoryStore {
    static func make() -> any HistoryStore {
        JSONHistoryStore(fileURL: JSONHistoryStore.standardURL)
    }
}

/// Carries a store's answer from the I/O queue to the caller that waits for it. The caller reads it only after the
/// semaphore has been signalled, so the write and the read never overlap.
final class WriteOutcome: @unchecked Sendable {
    var saved = false
}
