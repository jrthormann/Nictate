// Nictate: a macOS menu bar app that copies text from anywhere on your screen.
// Copyright (c) 2026 jrthormann. MIT License, see LICENSE.

import AppKit
import ScreenCaptureKit

/// One display as it looked when the selection started.
struct DisplayStill: Sendable {
    /// The display in global screen points, as NSScreen.frame has it.
    let frame: CGRect
    /// Pixels per point.
    let scale: CGFloat
    let image: CGImage
}

extension NSScreen {
    /// The CoreGraphics display this screen shows, which ScreenCaptureKit also uses.
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber).map { CGDirectDisplayID($0.uint32Value) }
    }
}

/// Stills of every display, taken with ScreenCaptureKit before the selection opens. The capture reads the
/// frame into memory: nothing is written to disk. Needs Screen Recording access.
enum ScreenStill {
    /// Nil when no display can be read, most often because Screen Recording is not granted. A screen that
    /// ScreenCaptureKit does not list (a mirror, for example) gets no overlay; the others still work.
    @MainActor
    static func captureAll() async -> [DisplayStill]? {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true) else {
            Log.capture.error("Screen content unavailable")
            return nil
        }
        // Every stream starts before any frame is awaited, so the waits overlap instead of adding up.
        var running: [(screen: NSScreen, grabber: FrameGrabber, stream: SCStream)] = []
        for screen in NSScreen.screens {
            guard let id = screen.displayID, let display = content.displays.first(where: { $0.displayID == id }) else {
                Log.capture.notice("A screen is not in the capture list and gets no overlay")
                continue
            }
            let pixels = CGSize(width: screen.frame.width * screen.backingScaleFactor,
                                height: screen.frame.height * screen.backingScaleFactor)
            guard let started = await start(display, pixels: pixels) else {
                await stop(running)
                return nil
            }
            running.append((screen, started.grabber, started.stream))
        }
        guard !running.isEmpty else { return nil }
        var images: [CGImage?] = []
        for item in running { images.append(await item.grabber.firstFrame(timeout: 3)) }
        await stop(running)
        var stills: [DisplayStill] = []
        for (item, image) in zip(running, images) {
            guard let image else { return nil }
            // The scale comes from the pixels actually captured: the stream may round the requested size.
            let scale = CGFloat(image.width) / item.screen.frame.width
            stills.append(DisplayStill(frame: item.screen.frame, scale: scale, image: image))
        }
        return stills
    }

    /// Starts a stream for one display; its first complete frame is awaited separately.
    @MainActor
    private static func start(_ display: SCDisplay, pixels: CGSize) async -> (grabber: FrameGrabber, stream: SCStream)? {
        let configuration = SCStreamConfiguration()
        configuration.width = Int(pixels.width)
        configuration.height = Int(pixels.height)
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.showsCursor = false
        let grabber = FrameGrabber()
        let stream = SCStream(filter: SCContentFilter(display: display, excludingWindows: []),
                              configuration: configuration, delegate: nil)
        do {
            try stream.addStreamOutput(grabber, type: .screen, sampleHandlerQueue: grabber.queue)
            try await stream.startCapture()
        } catch {
            Log.capture.error("Stream: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        return (grabber, stream)
    }

    @MainActor
    private static func stop(_ running: [(screen: NSScreen, grabber: FrameGrabber, stream: SCStream)]) async {
        for item in running { try? await item.stream.stopCapture() }
    }
}

/// Receives the frames of one stream on its own queue and hands over the first complete one.
private final class FrameGrabber: NSObject, SCStreamOutput, @unchecked Sendable {
    let queue = DispatchQueue(label: "app.nictate.still")
    private let context = CIContext()
    private let lock = NSLock()
    private var finished = false
    private var result: CGImage?
    private var waiter: CheckedContinuation<CGImage?, Never>?

    /// The first frame, or nil after `timeout` seconds without one.
    func firstFrame(timeout: TimeInterval) async -> CGImage? {
        await withCheckedContinuation { continuation in
            lock.lock()
            if finished {
                let image = result
                lock.unlock()
                continuation.resume(returning: image)
                return
            }
            waiter = continuation
            lock.unlock()
            queue.asyncAfter(deadline: .now() + timeout) { self.finish(nil) }
        }
    }

    /// Only the first call counts: a later frame or a timeout changes nothing.
    private func finish(_ image: CGImage?) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true
        result = image
        let waiting = waiter
        waiter = nil
        lock.unlock()
        waiting?.resume(returning: image)
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        // Only complete frames carry pixels; the others announce idle, blank or suspended screens.
        guard type == .screen, sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let status = attachments.first?[.status] as? Int, status == SCFrameStatus.complete.rawValue,
              let pixels = sampleBuffer.imageBuffer else { return }
        let image = CIImage(cvPixelBuffer: pixels)
        finish(context.createCGImage(image, from: image.extent))
    }
}
