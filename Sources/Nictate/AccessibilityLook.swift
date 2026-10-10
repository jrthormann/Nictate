// Nictate: a macOS menu bar app that copies text from anywhere on your screen.
// Copyright (c) 2026 jrthormann. MIT License, see LICENSE.


import AppKit
import SwiftUI

/// Which colour variant a surface draws with: the standard tokens, or the Increase Contrast (`-ic`) ones.
enum ContrastVariant: Equatable {
    case standard
    case increased
}

/// The accessibility settings that change how a surface looks. Views read them from the environment
/// (`accessibilityReduceTransparency`, `colorSchemeContrast`), so a change in System Settings applies live.
struct AccessibilityLook: Equatable {
    var reduceTransparency: Bool
    var increaseContrast: Bool

    var contrast: ContrastVariant { increaseContrast ? .increased : .standard }
}

extension Design.Ink {
    /// Secondary text. Under Increase Contrast it is solid, not the translucent ink.
    static func text(_ variant: ContrastVariant) -> Color {
        variant == .increased ? ColorTokens.inkSecondaryIc : secondary
    }
}

extension Design.Stroke {
    /// The edge of a card: the system separator normally, the solid high-contrast token under Increase Contrast.
    static func color(_ variant: ContrastVariant) -> Color {
        variant == .increased ? ColorTokens.hairlineIc : Color(nsColor: .separatorColor)
    }

    static func width(_ variant: ContrastVariant) -> CGFloat {
        variant == .increased ? contrast : hairline
    }
}
