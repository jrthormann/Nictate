// Nictate: a macOS menu bar app that copies text from anywhere on your screen.
// Copyright (c) 2026 jrthormann. MIT License, see LICENSE.

import SwiftUI

/// The measurements every surface draws from, so the app keeps one rhythm. Spacing runs on a 4 pt
/// grid, and window and panel sizes are multiples of 8.
enum Design {
    enum Space {
        static let tight: CGFloat = 4
        static let compact: CGFloat = 8
        static let row: CGFloat = 12
        static let cardGap: CGFloat = 16
        static let inset: CGFloat = 20
        static let page: CGFloat = 24
        static let window: CGFloat = 32
    }

    enum Ink {
        /// Secondary text. Provisional until the design is final.
        static let secondary = ColorTokens.inkSecondaryAa
    }

    enum Stroke {
        /// The card edge in the standard appearance (stroke-hairline in the design system).
        static let hairline: CGFloat = 0.75
        /// The card edge under Increase Contrast (stroke-contrast).
        static let contrast: CGFloat = 2
    }

    enum Size {
        static let settingsWidth: CGFloat = 560
        /// A settings window never grows past this share of the visible screen height; the page scrolls beyond it.
        static let settingsMaxHeightShare: CGFloat = 0.8
        static let welcomeWidth: CGFloat = 480
        static let welcomeIcon: CGFloat = 64
        static let stepIcon: CGFloat = 32
        static let history = CGSize(width: 480, height: 400)
    }
}
