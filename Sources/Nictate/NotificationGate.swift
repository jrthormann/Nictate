// Nictate: a macOS menu bar app that copies text from anywhere on your screen.
// Copyright (c) 2026 jrthormann. MIT License, see LICENSE.

import Foundation

/// Decides when to ask for notification permission: once, the first time a notification is actually
/// sent, so a new user meets that prompt in context rather than at launch beside the Screen Recording one.
struct NotificationGate {
    private var asked = false

    mutating func shouldRequest() -> Bool {
        defer { asked = true }
        return !asked
    }
}
