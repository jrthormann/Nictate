// Nictate: a macOS menu bar app that copies text from anywhere on your screen.
// Copyright (c) 2026 jrthormann. MIT License, see LICENSE.

import AppKit
import QuartzCore


/// Visual cues on the menu bar icon: a soft pulse while a capture is being read, then a blink: the
/// aperture closes into a line and reopens, once in green on success, twice in red on failure.
@MainActor
final class StatusFlash {
    private weak var button: NSStatusBarButton?
    /// The resting icon. Replaced when a mode badge appears or disappears.
    var idleImage: NSImage?
    /// Whether the resting icon shows the Append mode "+", so the blink frames keep it.
    var appending = false
    private var blinkTimer: Timer?
    private(set) var isBlinking = false
    private var pendingReset: DispatchWorkItem?
    private var pendingWorking: DispatchWorkItem?
    private(set) var isWorking = false

    /// Reads that finish sooner than this show nothing, so a quick capture does not flicker.
    static let workingDelay: TimeInterval = 0.3

    init(button: NSStatusBarButton?, idleImage: NSImage?) {
        self.button = button
        self.idleImage = idleImage
    }

    /// Starts the "reading" pulse after `workingDelay`, until `endWorking`. With Reduce Motion the icon
    /// simply rests dimmed.
    func beginWorking() {
        pendingWorking?.cancel()
        let start = DispatchWorkItem { [weak self] in self?.showWorking() }
        pendingWorking = start
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.workingDelay, execute: start)
    }

    func endWorking() {
        pendingWorking?.cancel()
        pendingWorking = nil
        guard isWorking else { return }
        isWorking = false
        button?.layer?.removeAnimation(forKey: "working")
        button?.alphaValue = 1
    }

    private func showWorking() {
        guard let button else { return }
        isWorking = true
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            button.alphaValue = 0.5
            return
        }
        button.wantsLayer = true
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 1
        pulse.toValue = 0.35
        pulse.duration = 0.8
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        button.layer?.add(pulse, forKey: "working")
    }

    /// The blink, then the icon stays tinted until one second after the start. With Reduce Motion the
    /// icon is only tinted.
    func show(_ outcome: CaptureOutcome) {
        guard let button, idleImage != nil else { return }
        pendingReset?.cancel()
        blinkTimer?.invalidate()
        let color: NSColor = outcome == .success ? .systemGreen : .systemRed
        let resting = MenuBarIcon.blinkFrame(openness: 1, beam: 0, color: color, appending: appending)

        button.image = resting
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            isBlinking = true
            let blinks = EyelidTimeline.blinks(for: outcome)
            let start = CACurrentMediaTime()
            let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] timer in
                // The frame is drawn on the main actor; the timer itself stays out here, where it fires.
                let finished = MainActor.assumeIsolated { () -> Bool in
                    guard let self, let button = self.button else { return true }
                    guard let frame = EyelidTimeline.frame(at: CACurrentMediaTime() - start, blinks: blinks) else {
                        self.isBlinking = false
                        button.image = resting
                        return true
                    }
                    button.image = MenuBarIcon.blinkFrame(openness: frame.openness, beam: frame.beam,
                                                          color: color, appending: self.appending)
                    return false
                }
                if finished { timer.invalidate() }
            }
            RunLoop.main.add(timer, forMode: .common)
            blinkTimer = timer
        }

        let reset = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.blinkTimer?.invalidate()
            self.isBlinking = false
            self.button?.image = self.idleImage
        }
        pendingReset = reset
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: reset)
    }
}
