// Nictate: a macOS menu bar app that copies text from anywhere on your screen.
// Copyright (c) 2026 jrthormann. MIT License, see LICENSE.

import SwiftUI

struct OutputTab: View {
    @ObservedObject private var settings = Settings.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        SettingsPage {
            SettingsSection("Clipboard") {
                SettingToggle("Append mode (add to the clipboard)", isOn: $settings.appendMode.animated(reduceMotion: reduceMotion))

                SettingRow("Separator") {
                    Picker("Separator", selection: $settings.appendSeparator) {
                        Text("New line").tag("newline")
                        Text("Space").tag("space")
                        Text("Tab").tag("tab")
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                .disclosed(by: settings.appendMode)

                SettingToggle("Keep captures private (no clipboard history or Handoff)", isOn: $settings.hideFromClipboardManagers)
            }

            SettingsSection("After capture") {
                SettingToggle("Detect colors, links, emails and phone numbers", isOn: $settings.detectContent)

                SettingRow("Scan QR codes and barcodes") {
                    Picker("Scan QR codes and barcodes", selection: $settings.barcodeAction) {
                        Text("Copy text only").tag("copy")
                        Text("Ask before opening").tag("ask")
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }
        }
    }
}
