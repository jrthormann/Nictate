// Nictate: a macOS menu bar app that copies text from anywhere on your screen.
// Copyright (c) 2026 jrthormann. MIT License, see LICENSE.

import SwiftUI

struct RecognitionTab: View {
    @ObservedObject private var settings = Settings.shared

    /// Languages shown as checkboxes by default; others appear once added.
    private static let featured = ["en-US", "es-ES", "fr-FR", "it-IT", "de-DE"]
    private let supported = Set(Recognizer.supportedLanguages)

    /// Faithful mode ignores correction, line-break and column rules, so those controls fade out.
    private var faithful: Bool { settings.codeMode }

    private var shownLanguages: [String] {
        let featured = Self.featured.filter(supported.contains)
        return featured + settings.languages.filter { !featured.contains($0) }
    }

    private var addableLanguages: [String] {
        Recognizer.supportedLanguages.filter { !shownLanguages.contains($0) }
    }

    var body: some View {
        SettingsPage {
            SettingsSection("Text mode") {
                SettingToggle("Faithful mode (code and structure)", isOn: $settings.codeMode)
                SettingCaption("Faithful mode copies text exactly as it appears: it keeps indentation, spacing between columns and blank lines, and turns off correction and text clean-up.")
            }

            SettingsSection("Languages") {
                SettingToggle("Language correction", isOn: $settings.languageCorrection)
                    .dimmed(when: faithful)
                if settings.languages.isEmpty {
                    SettingCaption("With nothing selected, the language is detected automatically.")
                }
                ForEach(shownLanguages, id: \.self) { code in
                    Toggle(languageName(code), isOn: languageBinding(code)).toggleStyle(.checkbox)
                }
                if !addableLanguages.isEmpty {
                    Menu("+ Add Language…") {
                        ForEach(addableLanguages, id: \.self) { code in
                            Button(languageName(code)) { settings.languages.append(code) }
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
            }

            SettingsSection("Layout") {
                SettingToggle("Keep line breaks", isOn: $settings.keepLineBreaks)
                SettingToggle("Detect text columns", isOn: $settings.detectColumns)
                SettingToggle("Separate table cells with tabs", isOn: $settings.tablesAsTabs)
                if faithful {
                    SettingCaption("Faithful mode ignores these settings.")
                }
            }
            .dimmed(when: faithful)

            SettingsSection("Text clean-up") {
                SettingToggle("Join split words and collapse spaces", isOn: $settings.cleanText)
            }
            .dimmed(when: faithful)

            SettingsSection("Code clean-up") {
                SettingToggle("Clean code when capturing", isOn: $settings.codeClean)
                SettingCaption("Removes terminal prompts, line numbers (only when at least three in a row) and typographic quotes. Works together with faithful mode and keeps indentation.")
            }
        }
    }

    private func languageBinding(_ code: String) -> Binding<Bool> {
        Binding(
            get: { settings.languages.contains(code) },
            set: { on in
                if on { settings.languages.append(code) }
                else { settings.languages.removeAll { $0 == code } }
            })
    }
}
