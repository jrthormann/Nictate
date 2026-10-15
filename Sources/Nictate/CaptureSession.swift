// Nictate: a macOS menu bar app that copies text from anywhere on your screen.
// Copyright (c) 2026 jrthormann. MIT License, see LICENSE.

/// One capture from the shortcut to the selection, and what an Esc means at each point of it. The key panel reports an Esc
/// here, and the capture's task asks here what to do when its stills come back, so these rules are tested without a window.
/// The task keeps its own session: whatever ends the capture or starts another one never clears a cancel the task has yet
/// to see.
@MainActor
final class CaptureSession {
    enum Phase: Equatable {
        /// The shortcut was pressed and the stills are being taken. The key panel holds the keyboard.
        case preparing
        /// The selection is on screen and takes the keys itself.
        case selecting
        /// Over: cancelled, failed or finished.
        case ended
    }

    /// What the capture's task does once its stills are back.
    enum Next: Equatable {
        case selectArea
        /// The screen could not be read, and nobody cancelled.
        case reportFailure
        /// Nothing more: the capture was cancelled, or this session has already been told.
        case stop
    }

    private(set) var phase = Phase.preparing
    private(set) var isCancelled = false

    /// An Esc taken by the key panel. True when it cancelled the capture: while the stills are taken, or while the selection opens
    /// (the panel comes down in the turn that opens it, so only a panel still up can report an Esc then). An Esc in a finished
    /// capture is nobody's business.
    func escape() -> Bool {
        guard phase != .ended else { return false }
        isCancelled = true
        phase = .ended
        return true
    }

    /// The stills are back, or could not be taken. A cancelled capture gets neither a selection nor a failure message,
    /// whatever the stills are: recognition, the clipboard, the history and every cue come after one of those two.
    /// Asked once per capture.
    func stillsReturned(available: Bool) -> Next {
        guard phase == .preparing else { return .stop }
        guard available else {
            phase = .ended
            return .reportFailure
        }
        phase = .selecting
        return .selectArea
    }

    /// The capture is over, whatever its outcome. A cancel stays recorded.
    func end() {
        phase = .ended
    }
}
