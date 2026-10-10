// Nictate: a macOS menu bar app that copies text from anywhere on your screen.
// Copyright (c) 2026 jrthormann. MIT License, see LICENSE.

import Foundation

/// English is the development language: the English text is the key, `Sources/Nictate/Resources/en.lproj` maps it to
/// itself, and `Sources/Nictate/Resources/es.lproj/Localizable.strings` provides the Spanish translation.
func tr(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}

func tr(_ key: String, _ args: any CVarArg...) -> String {
    String(format: NSLocalizedString(key, comment: ""), arguments: args)
}

/// Localized display name of a recognition language code, e.g. "es-ES" -> "español (España)".
func languageName(_ code: String) -> String {
    Locale.current.localizedString(forIdentifier: code) ?? code
}
