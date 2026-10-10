// Nictate: a macOS menu bar app that copies text from anywhere on your screen.
// Copyright (c) 2026 jrthormann. MIT License, see LICENSE.

import CryptoKit
import Foundation
import Security

/// The explicit, one-time import of the encrypted `history.sealed` written by earlier versions. Only this file knows
/// about the old cipher and the Keychain key, and only the user's "Import Previous History…" action runs it. It never
/// deletes or changes the old file, never creates a key, and never replaces captures it cannot read.
enum LegacyHistoryMigration {
    enum Outcome: Equatable {
        /// The captures were imported and read back. `dropped` counts captures removed to keep the 15-capture limit.
        case imported(count: Int, dropped: Int)
        /// The user (or macOS, for the Keychain prompt) cancelled. Nothing was written.
        case cancelled
        /// Nothing was written. `reason` is for the log, never for the interface.
        case failed(reason: String)
    }

    /// The old file, next to the new one in Application Support, in the folder this build uses.
    static var legacyURL: URL {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return folder.appendingPathComponent(BuildIdentity.historyFolderName, isDirectory: true)
            .appendingPathComponent("history.sealed")
    }

    /// Whether the import can be offered: an old file is present, and this build is allowed to read the old key.
    static var isOffered: Bool {
        BuildIdentity.supportsLegacyImport && FileManager.default.fileExists(atPath: legacyURL.path)
    }

    /// Imports the old captures into `destination`, merged with what it already holds. The result is the newest
    /// `HistoryPolicy.maximumHistoryEntries` captures of both, without duplicates. `key` returns the old key without
    /// creating one; it throws when the Keychain refuses or cancels.
    static func run(legacy: URL, destination: JSONHistoryStore, key: () throws -> SymmetricKey) -> Outcome {
        guard let sealed = try? Data(contentsOf: legacy) else { return .failed(reason: "legacy file unreadable") }
        let symmetric: SymmetricKey
        do {
            symmetric = try key()
        } catch LegacyHistoryKeychain.Failure.status(let status) where status == errSecUserCanceled {
            return .cancelled
        } catch {
            return .failed(reason: "legacy key unavailable: \(error)")
        }
        guard let plain = try? LegacyHistoryCipher.open(sealed, key: symmetric),
              let old = try? JSONDecoder().decode(HistorySnapshot.self, from: plain),
              old.texts.count == old.dates.count else {
            return .failed(reason: "legacy file could not be decrypted and decoded")
        }
        // Captures already in the new History are kept. A History that cannot be read is never replaced.
        let current: HistorySnapshot
        switch destination.load() {
        case .empty: current = .empty
        case .loaded(let snapshot): current = snapshot
        case .corrupt, .unavailable: return .failed(reason: "new history could not be read; it was left unchanged")
        }
        let merged = merge(current: current, imported: old)
        let kept = merged.capped()
        let dropped = merged.texts.count - kept.texts.count
        guard destination.save(kept) else { return .failed(reason: "new file could not be written") }
        // Read the new file back and confirm it holds exactly what was intended.
        guard case .loaded(let check) = destination.load(), check == kept else {
            return .failed(reason: "new file did not read back as written")
        }
        return .imported(count: kept.texts.count, dropped: dropped)
    }

    /// Both sets, newest first, each text once. For a text in both, the newer capture time is kept. Captures with the
    /// same time (unknown times, which are `.distantPast`) keep their source order, so the newest 15 are not chosen
    /// by alphabetical order.
    static func merge(current: HistorySnapshot, imported: HistorySnapshot) -> HistorySnapshot {
        var entries: [(text: String, date: Double)] = []
        var index: [String: Int] = [:]
        for (text, date) in zip(current.texts + imported.texts, current.dates + imported.dates) {
            if let existing = index[text] {
                entries[existing].date = max(entries[existing].date, date)
            } else {
                index[text] = entries.count
                entries.append((text: text, date: date))
            }
        }
        let ordered = entries.enumerated().sorted { lhs, rhs in
            (lhs.element.date, -lhs.offset) > (rhs.element.date, -rhs.offset)
        }.map(\.element)
        return HistorySnapshot(texts: ordered.map(\.text), dates: ordered.map(\.date))
    }
}

/// The old AES-GCM format. Kept only so the import can read it, and so tests can make fixtures.
enum LegacyHistoryCipher {
    static func seal(_ plain: Data, key: SymmetricKey) throws -> Data {
        guard let combined = try AES.GCM.seal(plain, using: key).combined else { throw CocoaError(.coderInvalidValue) }
        return combined
    }

    static func open(_ sealed: Data, key: SymmetricKey) throws -> Data {
        try AES.GCM.open(AES.GCM.SealedBox(combined: sealed), using: key)
    }
}

/// Reads the old key from the login Keychain. It only reads: a missing key is an error, never a new key.
enum LegacyHistoryKeychain {
    enum Failure: Error { case status(OSStatus), malformed }

    static let service = "app.nictate.history"
    static let account = "history-key"

    static func existingKey() throws -> SymmetricKey {
        let query: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: service,
                                      kSecAttrAccount: account, kSecReturnData: true, kSecMatchLimit: kSecMatchLimitOne]
        var found: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &found)
        guard status == errSecSuccess else { throw Failure.status(status) }
        guard let data = found as? Data, data.count == 32 else { throw Failure.malformed }
        return SymmetricKey(data: data)
    }
}
