// Nictate: a macOS menu bar app that copies text from anywhere on your screen.
// Copyright (c) 2026 jrthormann. MIT License, see LICENSE.

import os

/// The app's loggers, one per area. Interpolated values are private by default in os.Logger, and
/// captured text is never passed to a logger at all.
enum Log {
    private static let subsystem = "com.jrthormann.nictate"
    static let app = Logger(subsystem: subsystem, category: "app")
    static let hotKeys = Logger(subsystem: subsystem, category: "hotkeys")
    static let recognition = Logger(subsystem: subsystem, category: "recognition")
    static let capture = Logger(subsystem: subsystem, category: "capture")
}
