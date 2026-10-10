// Nictate: a macOS menu bar app that copies text from anywhere on your screen.
// Copyright (c) 2026 jrthormann. MIT License, see LICENSE.

import CryptoKit
import Foundation
import Security

/// The one-time migration from the encrypted `history.sealed` of earlier versions to `history.json`. Only this file
/// knows about the old cipher and the Keychain key. Normal operation never reads either. The migration never deletes
/// or changes the old file, never creates a key, and never replaces a History that is already valid.
enum LegacyHistoryMigration {
    enum Outcome: Equatable {
        case noLegacyFile
        case alreadyMigrated
        case migrated(count: Int)
        /// Nothing was written. `reason` is for the log, not for the user interface.
        case failed(reason: String)
    }

    /// Runs the migration. `key` returns the old key without creating one; it may throw when the Keychain refuses.
    static func run(legacy: URL, destination: JSONHistoryStore, key: () throws -> SymmetricKey) -> Outcome {
        guard FileManager.default.fileExists(atPath: legacy.path) else { return .noLegacyFile }
        if case .loaded = destination.load() { return .alreadyMigrated }
        guard let sealed = try? Data(contentsOf: legacy) else { return .failed(reason: "legacy file unreadable") }
        let symmetric: SymmetricKey
        do {
            symmetric = try key()
        } catch {
            return .failed(reason: "legacy key unavailable: \(error)")
        }
        guard let plain = try? LegacyHistoryCipher.open(sealed, key: symmetric),
              let old = try? JSONDecoder().decode(HistorySnapshot.self, from: plain),
              old.texts.count == old.dates.count else {
            return .failed(reason: "legacy file could not be decrypted and decoded")
        }
        let kept = sorted(old).capped()
        guard destination.save(kept) else { return .failed(reason: "new file could not be written") }
        // Read the new file back and confirm it holds what was expected before the migration counts as done.
        guard case .loaded(let check) = destination.load(), check == kept else {
            return .failed(reason: "new file did not read back as written")
        }
        return .migrated(count: kept.texts.count)
    }

    /// Newest first by capture time. Entries with unknown times keep their stored order, after the known ones.
    static func sorted(_ snapshot: HistorySnapshot) -> HistorySnapshot {
        let indexed = snapshot.texts.indices.map { ($0, snapshot.texts[$0], snapshot.dates[$0]) }
        let ordered = indexed.sorted { lhs, rhs in
            if lhs.2 != rhs.2 { return lhs.2 > rhs.2 }
            return lhs.0 < rhs.0
        }
        return HistorySnapshot(texts: ordered.map(\.1), dates: ordered.map(\.2))
    }
}

/// The old AES-GCM format. Kept only so the migration can read it, and so tests can make fixtures.
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
