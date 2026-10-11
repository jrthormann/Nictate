// Nictate: a macOS menu bar app that copies text from anywhere on your screen.
// Copyright (c) 2026 jrthormann. MIT License, see LICENSE.

// Replaces Sources/Nictate/BuildIdentity.swift in the test variant (scripts/build-app.sh, NICTATE_VARIANT=test).
// The bundle identifier and names are set by the script to match: com.jrthormann.nictate.test, "Nictate Test".
// This build never touches the production history file.
enum BuildIdentity {
    static let isTestVariant = true
    /// The QA build never reads the production Keychain key, so it offers no import of the old history.
    static let supportsLegacyImport = false
    static let historyFolderName = "Nictate Test"
    /// Empty on purpose: the QA build starts with no synthetic captures and never seeds them. A test that needs
    /// captures passes its own to History.seedFixtures.
    static let historyFixtures: [String] = []
}
