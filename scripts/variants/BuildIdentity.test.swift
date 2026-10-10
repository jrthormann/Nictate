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
    /// Representative OCR captures: code with indentation, a table, links, contacts, accents, a long paragraph.
    static let historyFixtures: [String] = [
        "Selected text, the second line\n    indented by four spaces\n\tand a tab\nend",
        "let total = items.reduce(0) { $0 + $1.price }",
        "Name\tRole\tCity\nAna\tDesigner\tSanto Domingo\nLuis\tEngineer\tMadrid",
        "https://example.com/docs/capture?ref=test",
        "ana@example.com",
        "+1 (809) 555-0142",
        "Reunión mañana a las 10:30 en la oficina de Malecón, sala 4.",
        "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat.",
        "Color #FF8800 and rgb(0, 128, 255)",
        "Trailing spaces kept   ",
    ]
}
