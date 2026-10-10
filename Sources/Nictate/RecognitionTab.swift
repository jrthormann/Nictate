// Nictate: a macOS menu bar app that copies text from anywhere on your screen.
// Copyright (c) 2026 jrthormann. MIT License, see LICENSE.

import SwiftUI

struct RecognitionTab: View {
    @ObservedObject private var settings = Settings.shared
    /// Remembered between visits, so a user who opened Advanced finds it open again.
    @AppStorage(StorageKeys.advancedRecognitionExpanded) private var advancedExpanded = false

    /// Preserve Original Formatting ignores correction, line-break and column rules, so those controls fade out.
    private var faithful: Bool { settings.codeMode }

    var body: some View {
        SettingsPage {
            SettingsSection("Text Recognition") {
                SettingToggle("Preserve Original Formatting", isOn: $settings.codeMode)
                SettingCaption("Keep spacing, indentation, and line breaks as they appear.")
                SettingToggle("Improve Recognized Text", isOn: $settings.languageCorrection)
                    .dimmed(when: faithful)
                SettingCaption("Fix common recognition errors.")
            }

            SettingsSection("Languages") {
                SettingRow("Recognized Languages") { languageMenu }
                SettingCaption("Automatically detect languages, or choose the ones you use.")
            }

            DisclosureGroup("Advanced", isExpanded: $advancedExpanded) {
                VStack(alignment: .leading, spacing: Design.Space.row) {
                    // Preserve Original Formatting overrides these four; Code Cleanup still applies in that mode.
                    SettingToggle("Keep Line Breaks", isOn: $settings.keepLineBreaks)
                        .dimmed(when: faithful)
                    SettingToggle("Detect Text Columns", isOn: $settings.detectColumns)
                        .dimmed(when: faithful)
                    SettingToggle("Separate Table Cells with Tabs", isOn: $settings.tablesAsTabs)
                        .dimmed(when: faithful)
                    SettingToggle("Join Split Words", isOn: $settings.cleanText)
                        .dimmed(when: faithful)
                    SettingToggle("Code Cleanup", isOn: $settings.codeClean)
                    SettingCaption("Code Cleanup removes terminal prompts, line numbers (only when at least three in a row) and typographic quotes. It keeps indentation.")
                    if faithful {
                        SettingCaption("Preserve Original Formatting ignores these settings, except Code Cleanup.")
                    }
                }
                .padding(.top, Design.Space.row)
            }
        }
    }

    /// Automatic, or the chosen languages as one line. Several can be chosen; the menu keeps its checkmarks.
    private var languageMenu: some View {
        Menu {
            Button("Automatic") { settings.languages = [] }
            Divider()
            ForEach(Recognizer.supportedLanguages, id: \.self) { code in
                Toggle(languageName(code), isOn: languageBinding(code))
            }
        } label: {
            Text(languageSummary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var languageSummary: String {
        RecognitionTab.summary(of: settings.languages.map(languageName))
    }

    /// "Automatic" for none, the name for one, "English, Spanish" for two, and "English, Spanish +1" beyond that.
    static func summary(of names: [String]) -> String {
        switch names.count {
        case 0: return tr("Automatic")
        case 1, 2: return names.joined(separator: ", ")
        default: return tr("%@, %@ +%d", names[0], names[1], names.count - 2)
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
