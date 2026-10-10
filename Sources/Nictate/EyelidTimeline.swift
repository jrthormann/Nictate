// Nictate: a macOS menu bar app that copies text from anywhere on your screen.
// Copyright (c) 2026 jrthormann. MIT License, see LICENSE.

import Foundation

enum CaptureOutcome { case success, failure }

/// The menu bar blink, as a pure function of time: the aperture closes like an eyelid into a thin
/// line (the scan beam) and reopens. Success blinks once, failure twice, so the cue never relies on
/// color alone. Closing eases in and opening eases out, which reads as a natural blink.
enum EyelidTimeline {
    struct Frame: Equatable {
        /// 1 is the resting aperture, 0 is closed into a line.
        let openness: Double
        /// Opacity of the line across the middle, strongest when closed.
        let beam: Double
    }

    static let closing: TimeInterval = 0.11
    static let opening: TimeInterval = 0.22

    static func blinks(for outcome: CaptureOutcome) -> Int { outcome == .success ? 1 : 2 }

    static func duration(blinks: Int) -> TimeInterval { Double(blinks) * (closing + opening) }

    /// The frame at `time` seconds after the start, or nil once the last blink has finished.
    static func frame(at time: TimeInterval, blinks: Int) -> Frame? {
        guard time > 0 else { return Frame(openness: 1, beam: 0) }
        guard time <= duration(blinks: blinks) else { return nil }
        let local = time.truncatingRemainder(dividingBy: closing + opening)
        // The remainder drifts by a few ulps, so the closed frame gets a little tolerance.
        if local <= closing + 1e-9 {
            let raw = local / closing
            let p = raw > 1 - 1e-9 ? 1 : raw
            return Frame(openness: 1 - p * p, beam: p)
        }
        let p = (local - closing) / opening
        let eased = 1 - (1 - p) * (1 - p)
        return Frame(openness: eased, beam: 1 - eased)
    }
}
