// Nictate: a macOS menu bar app that copies text from anywhere on your screen.
// Copyright (c) 2026 jrthormann. MIT License, see LICENSE.

import CryptoKit
import Foundation
import Security

/// What the history keeps: the texts, newest first, and their capture times in seconds since 1970.
struct HistorySnapshot: Codable, Equatable, Sendable {
    var texts: [String]
    var dates: [Double]

    static let empty = HistorySnapshot(texts: [], dates: [])
}

/// What a store found. `corrupt` means the file is there but cannot be opened. `unavailable` means the key
/// could not be read (not authorized yet, denied, or another error). Neither may be written over: the file is
/// the user's history, and only a successful load says what it holds.
enum HistoryLoad: Equatable {
    case empty
    case loaded(HistorySnapshot)
    case corrupt
    /// The key needs the user's authorization and it was not given (cancelled, refused, or not yet asked).
    case locked
    /// The key or file could not be read for another reason.
    case unavailable
}

/// Where the history lives between launches. `save` returns false when nothing could be written.
protocol HistoryStore: Sendable {
    func load() -> HistoryLoad
    func save(_ snapshot: HistorySnapshot) -> Bool
}

/// The history as one AES-GCM sealed file in the app's container. The key comes from `key`: the Keychain in
/// the app, a fixed key in tests. No plaintext copy is written.
struct EncryptedHistoryStore: HistoryStore, Sendable {
    let fileURL: URL
    /// `mayCreate` is true only when there is no history file yet. An existing file never gets a new key.
    let key: @Sendable (_ mayCreate: Bool) throws -> SymmetricKey

    static let standard = EncryptedHistoryStore(fileURL: standardURL, key: { try HistoryKeychain.key(mayCreate: $0) })

    /// `history.sealed` in Application Support, which is inside the sandbox container.
    static var standardURL: URL {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return folder.appendingPathComponent(BuildIdentity.historyFolderName, isDirectory: true).appendingPathComponent("history.sealed")
    }

    func load() -> HistoryLoad {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return .empty }
        guard let sealed = try? Data(contentsOf: fileURL) else { return .unavailable }
        let symmetric: SymmetricKey
        do {
            symmetric = try key(false)
        } catch {
            Log.app.error("History key unavailable: \(error.localizedDescription, privacy: .public)")
            return HistoryKeychain.isAuthorizationRefusal(error) ? .locked : .unavailable
        }
        do {
            let plain = try HistoryCipher.open(sealed, key: symmetric)
            return .loaded(try JSONDecoder().decode(HistorySnapshot.self, from: plain))
        } catch {
            Log.app.error("History file could not be opened; it is kept unchanged")
            return .corrupt
        }
    }

    func save(_ snapshot: HistorySnapshot) -> Bool {
        do {
            let plain = try JSONEncoder().encode(snapshot)
            let sealed = try HistoryCipher.seal(plain, key: try key(!FileManager.default.fileExists(atPath: fileURL.path)))
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try sealed.write(to: fileURL, options: .atomic)
            return true
        } catch {
            Log.app.error("History not saved: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}

/// AES-GCM with the nonce and tag kept in the sealed bytes. Opening fails for any change to them or a wrong key.
enum HistoryCipher {
    static func seal(_ plain: Data, key: SymmetricKey) throws -> Data {
        guard let combined = try AES.GCM.seal(plain, using: key).combined else { throw CocoaError(.coderInvalidValue) }
        return combined
    }

    static func open(_ sealed: Data, key: SymmetricKey) throws -> Data {
        try AES.GCM.open(AES.GCM.SealedBox(combined: sealed), using: key)
    }
}

/// The 256-bit key in the login Keychain, created on first use. It is a file-based item: the data protection
/// Keychain needs a provisioning profile this app does not have.
enum HistoryKeychain {
    enum Failure: Error { case status(OSStatus), malformed }

    private static var service: String { BuildIdentity.keychainService }
    private static let account = "history-key"

    /// The stored key. Without `mayCreate` a missing key is an error, never a new key: a new key could not open
    /// the file that exists, and the next save would replace it.
    /// Cancelled or refused authorization, which the user can resolve by unlocking. Anything else is a fault.
    static func isAuthorizationRefusal(_ error: any Error) -> Bool {
        guard case Failure.status(let status) = error else { return false }
        return status == errSecUserCanceled || status == errSecAuthFailed || status == errSecInteractionNotAllowed
    }

    static func key(mayCreate: Bool) throws -> SymmetricKey {
        let query: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: service,
                                      kSecAttrAccount: account, kSecReturnData: true, kSecMatchLimit: kSecMatchLimitOne]
        var found: CFTypeRef?
        switch SecItemCopyMatching(query as CFDictionary, &found) {
        case errSecSuccess:
            guard let data = found as? Data, data.count == 32 else { throw Failure.malformed }
            return SymmetricKey(data: data)
        case errSecItemNotFound:
            guard mayCreate else { throw Failure.status(errSecItemNotFound) }
            let fresh = SymmetricKey(size: .bits256)
            let add: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: service,
                                        kSecAttrAccount: account, kSecValueData: fresh.withUnsafeBytes { Data($0) },
                                        kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
            let status = SecItemAdd(add as CFDictionary, nil)
            guard status == errSecSuccess else { throw Failure.status(status) }
            return fresh
        case let status:
            Log.app.error("History key: Security status \(status, privacy: .public)")
            throw Failure.status(status)
        }
    }
}
