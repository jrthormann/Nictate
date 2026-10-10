// Nictate: a macOS menu bar app that copies text from anywhere on your screen.
// Copyright (c) 2026 jrthormann. MIT License, see LICENSE.

import AppKit

enum Permissions {
    private static let settingsURL = URL(string:
        "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!

    static var isGranted: Bool { CGPreflightScreenCaptureAccess() }

    /// Asks the system for Screen Recording access. This also lists the app in System Settings.
    static func request() { _ = CGRequestScreenCaptureAccess() }

    static func openSettings() { NSWorkspace.shared.open(settingsURL) }
}
