// Nictate: a macOS menu bar app that copies text from anywhere on your screen.
// Copyright (c) 2026 jrthormann. MIT License, see LICENSE.

import CoreGraphics

/// What a capture shows while its read runs: nothing for StatusFlash.workingDelay, then the scan line and "Reading…"
/// together. One per capture. It holds the selection's rectangles and never its pixels, so the timer keeps no image.
@MainActor
final class ReadingPresentation {
    private let line: ScanLine
    private let rect: CGRect, screen: CGRect   // Global points.
    private var timer: Task<Void, Never>?

    init(rect: CGRect, screen: CGRect) {
        self.line = ScanLine(rect: rect)
        self.rect = rect
        self.screen = screen
    }

    /// Starts the threshold timer. Once only: a second call does nothing, and so does a call after `end`.
    func start() {
        guard timer == nil, !line.isClosed else { return }
        timer = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(StatusFlash.workingDelay))
            // A read that has ended, or a line already closed, reveals nothing (see ScanLine.mayReveal).
            guard let self, ScanLine.mayReveal(readRunning: !Task.isCancelled, lineClosed: self.line.isClosed) else { return }
            self.line.show()
            ResultPill.shared.show(.reading, near: self.rect, screen: self.screen)
        }
    }

    /// Ends the read: cancels the timer and closes the line at once. Idempotent. The "Reading…" pill stays up until the
    /// result replaces it.
    func end() {
        timer?.cancel()
        line.close()
    }
}
