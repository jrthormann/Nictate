// Nictate: a macOS menu bar app that copies text from anywhere on your screen.
// Copyright (c) 2026 jrthormann. MIT License, see LICENSE.

import SwiftUI

struct OutputTab: View {
    @ObservedObject private var settings = Settings.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        SettingsPage {
            SettingsSection("Clipboard") {
                SettingToggle("Append to Clipboard", isOn: $settings.appendMode.animated(reduceMotion: reduceMotion))
                SettingRow("Separator") {
                    Picker("Separator", selection: $settings.appendSeparator) {
                        Text(tr("New Line")).tag("newline")
                        Text(tr("Space")).tag("space")
                        Text(tr("Tab")).tag("tab")
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                .disclosed(by: settings.appendMode)
                SettingCaption("Add new captures to the text already copied.")

                SettingToggle("Private Clipboard", isOn: $settings.hideFromClipboardManagers)
                SettingCaption("Limit clipboard sharing and history when supported by macOS.")
            }

            SettingsSection("Smart Detection") {
                SettingToggle("Detect Links, Contacts & Colors", isOn: $settings.detectContent)
                SettingCaption("Recognize links, email addresses, phone numbers, and colors.")
                SettingRow("QR & Barcode Results") {
                    Picker("QR & Barcode Results", selection: $settings.barcodeAction) {
                        Text(tr("Copy Text Only")).tag("copy")
                        Text(tr("Ask Before Opening")).tag("ask")
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }
        }
    }
}
