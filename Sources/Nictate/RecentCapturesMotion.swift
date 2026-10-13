// Nictate: a macOS menu bar app that copies text from anywhere on your screen.
// Copyright (c) 2026 jrthormann. MIT License, see LICENSE.

import SwiftUI

/// The motion of the Recent Captures list. Changes are brief and animate opacity only, as DESIGN.md requires. Only how a
/// change is drawn is animated: the selection, the copy and the close happen at once, and Reduce Motion removes it all.
enum RecentCapturesMotion {
    enum Kind { case selection, press }

    /// Seconds a change takes to draw. Zero under Reduce Motion.
    static func duration(_ kind: Kind, reduceMotion: Bool) -> Double {
        if reduceMotion { return 0 }
        switch kind {
        case .selection: return 0.12
        case .press: return 0.08
        }
    }

    static func animation(_ kind: Kind, reduceMotion: Bool) -> Animation? {
        let seconds = duration(kind, reduceMotion: reduceMotion)
        return seconds > 0 ? .easeOut(duration: seconds) : nil
    }
}

/// A capture row's copy button. Pressing dims it for a moment, so the click has a visible answer.
struct RecentCapturesPressStyle: ButtonStyle {
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1)
            .animation(RecentCapturesMotion.animation(.press, reduceMotion: reduceMotion), value: configuration.isPressed)
    }
}
