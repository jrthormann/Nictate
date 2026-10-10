// Nictate: a macOS menu bar app that copies text from anywhere on your screen.
// Copyright (c) 2026 jrthormann. MIT License, see LICENSE.

import Foundation

/// How much a capture's banner says. Captured text can be a password or a one-time code, so by default
/// the banner only confirms the copy; showing the text is a choice.
enum NotificationStyle: String, CaseIterable {
    case none
    case generic
    case text

    /// The banner body, or nil when no banner should appear.
    func body(generic notice: String, text: String) -> String? {
        switch self {
        case .none: return nil
        case .generic: return notice
        case .text: return text
        }
    }
}
