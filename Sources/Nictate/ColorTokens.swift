// Nictate: a macOS menu bar app that copies text from anywhere on your screen.
// Copyright (c) 2026 jrthormann. MIT License, see LICENSE.

import AppKit
import SwiftUI

/// The design system's colours, one per token. Tokens with a light and a dark value resolve through
/// the system, so they follow the appearance (Light, Dark, and their high-contrast variants).
enum ColorTokens {
    private static func dynamic(light: (CGFloat, CGFloat, CGFloat, CGFloat),
                                dark: (CGFloat, CGFloat, CGFloat, CGFloat)) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let name = appearance.bestMatch(from: [.aqua, .darkAqua, .accessibilityHighContrastAqua,
                                                    .accessibilityHighContrastDarkAqua])
            let isDark = name == .darkAqua || name == .accessibilityHighContrastDarkAqua
            let c = isDark ? dark : light
            return NSColor(srgbRed: c.0, green: c.1, blue: c.2, alpha: c.3)
        })
    }

    /// Preview text only. In the app use NSColor.labelColor, which adapts to light, dark and Increase Contrast.
    static let ink = dynamic(light: (0.0431, 0.0431, 0.0706, 1.0000), dark: (0.9608, 0.9608, 0.9686, 1.0000))

    /// PROVISIONAL, awaiting design approval. Secondary text with AA contrast: at least 4.5:1 on the grounds of each appearance (Light 5.07:1 on #ececec, Dark 4.93:1 on #2b2b2b). Replaces the native secondary label, which measures 3.95:1 in Light.
    static let inkSecondaryAa = dynamic(light: (0.3882, 0.3882, 0.4000, 1.0000), dark: (0.5961, 0.5961, 0.6157, 1.0000))

    /// Preview only. In the app use NSColor.separatorColor.
    static let hairline = dynamic(light: (0.0000, 0.0000, 0.0000, 0.1200), dark: (1.0000, 1.0000, 1.0000, 0.1200))

    /// Brand color for the mark, icon and marketing. Controls do not use it: they follow the user's accent (NSColor.controlAccentColor). Text on it: use the system's selectedContentBackground pairing.
    static let accent = dynamic(light: (0.3294, 0.3608, 0.9804, 1.0000), dark: (0.4824, 0.5020, 1.0000, 1.0000))

    /// Text colour for 'Copied'. 4.97:1 on light paper, 9.7:1 on dark. Always with the check icon and words. Icons use success-icon.
    static let success = dynamic(light: (0.1137, 0.4784, 0.2000, 1.0000), dark: (0.1882, 0.8196, 0.3451, 1.0000))

    /// Text colour for 'No text found'. 4.61:1 on light paper, 9.54:1 on dark. Always with the question-mark icon and words. Icons use warning-icon.
    static let warning = dynamic(light: (0.7020, 0.3294, 0.0000, 1.0000), dark: (1.0000, 0.6235, 0.0392, 1.0000))

    /// Failed capture: the menu bar icon blinks it twice, and red text or glyphs on paper. Light is #d70015, the accessible red (4.94:1 on paper); dark is system red (5.76:1). Always with an icon and words.
    static let danger = dynamic(light: (0.8431, 0.0000, 0.0824, 1.0000), dark: (1.0000, 0.2706, 0.2275, 1.0000))

    /// Preview only. Keyboard focus ring in the app is NSColor.keyboardFocusIndicatorColor, drawn by the system. Never draw a custom ring on a standard control.
    static let focus = dynamic(light: (0.3294, 0.3608, 0.9804, 1.0000), dark: (0.4824, 0.5020, 1.0000, 1.0000))

    /// Question-mark glyph. 3.48:1 on light paper (3:1 required for functional icons).
    static let warningIcon = dynamic(light: (0.7882, 0.4157, 0.0000, 1.0000), dark: (1.0000, 0.6235, 0.0392, 1.0000))

    /// Increase Contrast text. 6.23:1 light, 13.36:1 dark. Replaces success when Increase Contrast is on.
    static let successIc = dynamic(light: (0.0941, 0.4118, 0.1725, 1.0000), dark: (0.3686, 0.9412, 0.5412, 1.0000))

    /// Increase Contrast text. 7.02:1 light, 12.05:1 dark. Replaces warning when Increase Contrast is on.
    static let warningIc = dynamic(light: (0.5412, 0.2392, 0.0000, 1.0000), dark: (1.0000, 0.7529, 0.3020, 1.0000))

    /// Increase Contrast secondary text, solid. 10.42:1 light, 12.89:1 dark. Replaces ink-secondary.
    static let inkSecondaryIc = dynamic(light: (0.2275, 0.2275, 0.2353, 1.0000), dark: (0.8196, 0.8196, 0.8392, 1.0000))

    /// Increase Contrast border, 2 pt. 4.66:1 light, 6.01:1 dark on paper (3:1 required for borders that define a control). Replaces hairline.
    static let hairlineIc = dynamic(light: (0.4314, 0.4314, 0.4510, 1.0000), dark: (0.5569, 0.5569, 0.5765, 1.0000))

    /// Off track of a switch. Non-text boundary: 3.26:1 on white card, 5.19:1 on dark card (3:1 required). Replaces the translucent track.
    static let switchOff = dynamic(light: (0.5569, 0.5569, 0.5765, 1.0000), dark: (0.5569, 0.5569, 0.5765, 1.0000))

    /// Border of a text field (search). Non-text boundary: 3.26:1 on white card, 5.19:1 on dark card. The hairline is decorative only and does not identify a field.
    static let fieldBorder = dynamic(light: (0.5569, 0.5569, 0.5765, 1.0000), dark: (0.5569, 0.5569, 0.5765, 1.0000))
}
