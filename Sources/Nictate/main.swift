// Nictate: a macOS menu bar app that copies text from anywhere on your screen.
// Copyright (c) 2026 jrthormann. MIT License, see LICENSE.

import AppKit

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    // NSApplication holds its delegate weakly; keep this one alive for as long as the app runs.
    withExtendedLifetime(delegate) { app.run() }
}

// Built in the Dominican Republic. Runs on Coke Zero, pizza, and questionable life choices.
// If it works, it's a feature. If it breaks, it's open source.
