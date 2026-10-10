// Nictate: a macOS menu bar app that copies text from anywhere on your screen.
// Copyright (c) 2026 jrthormann. MIT License, see LICENSE.

/// The names that keep a build's data apart from the production app's. The production values are below.
/// `scripts/build-app.sh` with NICTATE_VARIANT=test compiles `scripts/variants/BuildIdentity.test.swift` in its
/// place, with its own bundle identifier, Keychain service, history folder and fixtures. Nothing else differs.
enum BuildIdentity {
    static let isTestVariant = false
    /// True only in the test variant: its history lives in memory, so the QA app never touches the Keychain.
    static let usesMemoryHistory = false
    /// The Keychain service of the history key. Its account is `HistoryKeychain`'s own.
    static let keychainService = "app.nictate.history"
    /// The folder under Application Support that holds `history.sealed`.
    static let historyFolderName = "Nictate"
    /// Captures added on the first launch of a test build, so the History screen can be checked. Empty here.
    static let historyFixtures: [String] = []
}
