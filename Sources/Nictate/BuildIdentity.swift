// Nictate: a macOS menu bar app that copies text from anywhere on your screen.
// Copyright (c) 2026 jrthormann. MIT License, see LICENSE.

/// The names that keep a build's data apart from the production app's. The production values are below.
/// `scripts/build-app.sh` with NICTATE_VARIANT=test compiles `scripts/variants/BuildIdentity.test.swift` in its
/// place, with its own bundle identifier, history folder and fixtures. Nothing else differs.
enum BuildIdentity {
    static let isTestVariant = false
    /// Whether this build may import the encrypted history of earlier versions (reads the old Keychain key).
    static let supportsLegacyImport = true
    /// The folder under Application Support that holds `history.json`.
    static let historyFolderName = "Nictate"
    /// Captures added on the first launch of a test build, so the History screen can be checked. Empty here.
    static let historyFixtures: [String] = []
}
