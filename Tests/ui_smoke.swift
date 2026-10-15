// Nictate: a macOS menu bar app that copies text from anywhere on your screen.
// Copyright (c) 2026 jrthormann. MIT License, see LICENSE.


// UI smoke tests: the behavior of real AppKit objects (menu bar icon, the settings window,
// the shortcut button). They need a window server, so they run with Tests/run_ui_tests.sh
// (`make ui-test`) and not with the logic tests. Settings and history live in this test binary's own
// preferences domain, never in the app's.
import AppKit
import CryptoKit
import Carbon.HIToolbox
import SwiftUI

let application = NSApplication.shared
application.setActivationPolicy(.accessory)

var failures = 0
var skips = 0
var notes = 0
/// History files this run creates in the temporary folder. They are removed before the run exits, so repeated runs leave nothing behind.
var historyFiles: [URL] = []
@MainActor
func scratchHistoryFile(_ prefix: String) -> URL {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(prefix)\(UUID().uuidString).json")
    historyFiles.append(file)
    return file
}
@MainActor
func check(_ ok: Bool, _ name: String, _ detail: String = "") {
    print((ok ? "PASS  " : "FAIL  ") + name + (detail.isEmpty || ok ? "" : " " + detail))
    if !ok { failures += 1 }
}
/// Runs the run loop until `condition` holds or `timeout` passes, so a busy machine slows a test down
/// instead of failing it.
@discardableResult
func waitUntil(_ timeout: Double = 4, _ condition: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
    return condition()
}
/// Set by a block on the main queue, so a test can wait for it to have run.
final class Marker: @unchecked Sendable { var fired = false }
/// Set from inside the link question's modal alert: whether the alert was up, and whether a pill of the capture was on screen.
final class QuestionProbe: @unchecked Sendable { var asked = false; var pillUp = true }
/// Receives what a selection on a test still returns: the chosen region, or nil when it was cancelled, and whether it has ended.
final class OverlayProbe: @unchecked Sendable { var done = false; var region: SelectedRegion? }
/// What a selection's `whenOpen` hook saw: how many times it ran, and how many windows of the selection were on screen then.
final class HookProbe: @unchecked Sendable { var calls = 0; var windows = 0 }
/// Counts the times the app became active while a test watched.
final class ActivationCount: @unchecked Sendable { var count = 0 }
/// Holds a capture's stills back until the test lets them go, so the test decides what happens while the key panel is up.
@MainActor
final class StillsGate {
    private var waiting: CheckedContinuation<[DisplayStill]?, Never>?
    private var released: [DisplayStill]??
    func wait() async -> [DisplayStill]? {
        if let released { return released }
        return await withCheckedContinuation { waiting = $0 }
    }
    func release(_ stills: [DisplayStill]?) {
        released = .some(stills)
        waiting?.resume(returning: stills)
        waiting = nil
    }
}
/// Waits until a block queued on the main queue for `seconds` from now has run. Anything the code under test
/// queued there for an earlier moment has then run too, however busy the machine: the way to show that
/// something does NOT happen without guessing a margin.
@MainActor
func waitPast(_ seconds: Double) {
    let marker = Marker()
    DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { marker.fired = true }
    waitUntil(seconds + 10) { marker.fired }
}
/// With the display asleep or the screen locked no frames are drawn, so animations never advance and a
/// fade can neither start nor finish. The checks that depend on one are skipped, and say so, instead of failing;
/// in CI (CI=true) a skip fails the run, since there it means the suite did not test what it claims.
let displayAwake = CGDisplayIsAsleep(CGMainDisplayID()) == 0
@MainActor
func skip(_ name: String) {
    print("SKIP  " + name)
    skips += 1
}
/// A fact about where the suite runs that changes how a check is made, not what it covers: a process
/// started from a terminal, or a CI runner, cannot make its window key, so a stand-in is used. Counted on its
/// own and never fails a run, CI included; the deterministic checks next to it carry the coverage.
@MainActor
func note(_ text: String) {
    print("NOTE  " + text)
    notes += 1
}
/// A window that can report itself key when the system will not make it so; see the shortcut checks.
final class StandInKeyWindow: NSWindow {
    var pretendsKey = false
    override var isKeyWindow: Bool { (pretendsKey && isVisible) || super.isKeyWindow }
}
@MainActor
func descendants(of view: NSView) -> [NSView] { view.subviews + view.subviews.flatMap(descendants(of:)) }
/// The run's windows on screen, apart from the menu bar's: what a capture adds and must take away again.
@MainActor
func visibleWindows() -> [NSWindow] {
    NSApp.windows.filter { $0.isVisible && !String(describing: type(of: $0)).contains("StatusBar") }
}
@MainActor
func visibleWindowIDs() -> Set<ObjectIdentifier> { Set(visibleWindows().map(ObjectIdentifier.init)) }
/// How the run's windows on screen differ from `baseline`, for a failed check to print: "windows +1 -0" is one extra.
@MainActor
func windowDelta(_ baseline: Set<ObjectIdentifier>) -> String {
    let now = visibleWindowIDs()
    return "windows +\(now.subtracting(baseline).count) -\(baseline.subtracting(now).count)"
}
/// A scan line's state, for a failed check to print: whether it holds a window, and the windows against `baseline`.
@MainActor
func scanState(_ line: ScanLine, _ baseline: Set<ObjectIdentifier>) -> String {
    "showing \(line.isShowing), \(windowDelta(baseline))"
}
/// Whether a window a check watches is on screen, off it, or already released, for a failed check to print.
@MainActor
func windowState(_ window: NSWindow?) -> String { window.map { $0.isVisible ? "visible" : "hidden" } ?? "released" }
/// Whether the window server still draws `window`, however faintly. A popover's `isVisible` turns false the moment it starts
/// to close, while its fade-out is still on screen for a quarter of a second: the stills of a capture would include it.
@MainActor
func isDrawn(_ window: NSWindow?) -> Bool {
    guard let window,
          let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else { return false }
    return list.contains {
        ($0[kCGWindowNumber as String] as? Int) == window.windowNumber && (($0[kCGWindowAlpha as String] as? Double) ?? 1) > 0
    }
}
/// What a capture saw when its stills were requested: whether the status panel's window was still drawn, and whether the popover still counted as shown.
final class PanelAtStills: @unchecked Sendable {
    var window: NSWindow?
    var panel: StatusPanel?
    var requested = false
    var drawn = false
    var popoverShown = false
    var count = 0
}
/// Holds an object without keeping it alive, so a check can see that it was released.
final class WeakRef<Object: AnyObject> {
    weak var object: Object?
    init(_ object: Object?) { self.object = object }
}

MainActor.assumeIsolated {
    let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    // CI pins the setting for each run (Tests/run_ui_tests.sh), so both modes are tested on every run. A mismatch
    // means the pin did not take effect, and the run fails instead of testing the wrong mode.
    if let pinned = ProcessInfo.processInfo.environment["NICTATE_UI_REDUCE_MOTION"] {
        check(reduceMotion == (pinned == "on"), "system Reduce Motion matches the pinned mode \(pinned)",
              "system reads \(reduceMotion)")
    }

    // MARK: Menu bar pulse while a capture is read
    do {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let flash = StatusFlash(button: item.button, idleImage: MenuBarIcon.image(appending: false))
        let started = Date()
        flash.beginWorking()
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        // Only meaningful if the run loop came back before the delay was up, which a stalled machine may not.
        check(!flash.isWorking || Date().timeIntervalSince(started) >= StatusFlash.workingDelay,
              "pulse: nothing shows before the delay")
        flash.endWorking(); waitPast(StatusFlash.workingDelay)
        check(!flash.isWorking, "pulse: a read shorter than the delay never shows it")
        flash.beginWorking(); waitUntil { flash.isWorking }
        check(flash.isWorking, "pulse: starts after the delay")
        check(reduceMotion ? item.button?.alphaValue == 0.5 : item.button?.layer?.animation(forKey: "working") != nil,
              reduceMotion ? "pulse: Reduce Motion rests the icon dimmed" : "pulse: the animation is on the icon")
        flash.endWorking()
        check(!flash.isWorking && item.button?.alphaValue == 1 && item.button?.layer?.animation(forKey: "working") == nil,
              "pulse: ending restores the icon")
        flash.beginWorking(); flash.beginWorking(); waitUntil { flash.isWorking }
        flash.endWorking(); waitPast(StatusFlash.workingDelay)
        check(!flash.isWorking, "pulse: repeated begin then end leaves nothing running")

        let idle = flash.idleImage
        item.button?.image = idle
        flash.show(.failure)
        check(item.button?.image !== idle && item.button?.image?.isTemplate == false,
              "blink: the icon turns to a colored frame at once")
        if !displayAwake {
            skip("blink: the blink runs, then the icon rests tinted (display asleep: animations cannot run)")
        } else if !reduceMotion {
            check(flash.isBlinking, "blink: the blink runs")
            waitUntil { !flash.isBlinking }
            check(!flash.isBlinking && item.button?.image !== idle, "blink: after the blinks the icon rests tinted")
        }
        waitUntil { !flash.isBlinking && item.button?.image === idle }
        check(!flash.isBlinking && item.button?.image === idle, "blink: the resting icon comes back after the blink")
        NSStatusBar.system.removeStatusItem(item)
    }

    // MARK: Settings window: toolbar tabs that resize the window
    do {
        let controller = PreferencesController()
        let window = NSWindow(contentViewController: controller)
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        waitUntil { window.toolbar?.items.count == 3 }
        check(window.toolbar?.items.count == 3, "settings: three tabs in the toolbar", "\(window.toolbar?.items.count ?? 0)")
        let cap = (window.screen?.visibleFrame.height ?? 800) * Design.Size.settingsMaxHeightShare
        var heights: [CGFloat] = []
        for index in controller.tabViewItems.indices {
            controller.selectedTabViewItemIndex = index
            // The window animates to its new size: wait until the height has stopped changing.
            var last: CGFloat = -1, steady = 0
            waitUntil(6) {
                let now = window.contentLayoutRect.height
                steady = now == last ? steady + 1 : 0
                last = now
                return steady >= 6
            }
            heights.append(window.contentLayoutRect.height)
            check(window.title == controller.tabViewItems[index].label, "settings: the window title is the tab name", window.title)
        }
        check(heights.allSatisfy { $0 <= cap + 1 }, "settings: no tab is taller than 80% of the screen", "\(heights) cap \(cap)")
        // The two tall tabs can both hit the cap on a short screen, so only the short one has to differ.
        if let output = controller.tabViewItems.firstIndex(where: { $0.label == tr("Output") }), heights.count == 3 {
            check(heights.indices.allSatisfy { $0 == output || heights[output] < heights[$0] },
                  "settings: the window resizes to each tab (Output is the shortest)", "\(heights)")
        } else {
            check(false, "settings: the Output tab is there", "\(controller.tabViewItems.map(\.label))")
        }
        window.close()
    }

    // MARK: Hotkeys: a combination the system refuses is reported as refused
    // ⌃⌥⇧⌘F17 is unlikely to belong to anyone. Registered twice in one process, Carbon refuses the second
    // (eventHotKeyExistsErr), the same answer as for a combination another app owns.
    let hotKeys = HotKeyManager.shared
    let hyper = controlKey | optionKey | shiftKey | cmdKey
    check(hotKeys.register(.capture, code: kVK_F17, mods: hyper), "hotkeys: a free combination registers")
    check(!hotKeys.register(.rotateHistory, code: kVK_F17, mods: hyper), "hotkeys: a combination already taken is refused")
    check(hotKeys.registeredCount == 1, "hotkeys: the refused slot holds nothing", "\(hotKeys.registeredCount)")
    // A relaunch and the recorder can both suspend: only the last resume registers again.
    hotKeys.suspend(); hotKeys.suspend(); hotKeys.resume()
    check(hotKeys.registeredCount == 0 && hotKeys.isSuspended, "hotkeys: nested suspends need a resume each")
    hotKeys.resume()
    check(hotKeys.registeredCount == 1 && !hotKeys.isSuspended, "hotkeys: the last resume registers them again")

    // MARK: Shortcut button
    do {
        let host = NSHostingView(rootView: ShortcutRecorder(label: "⇧⌘2", name: "Capture Text") { _, _, _ in false })
        let window = StandInKeyWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 80), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        // The recorder arms only in the key window. A process started from a terminal is not allowed to take the
        // focus from the frontmost app on macOS 14 and later, so when the window cannot really become key it
        // stands in as key: the checks still run and the run prints a NOTE, which never fails, CI included.
        application.activate()
        window.makeKeyAndOrderFront(nil)
        if !waitUntil(2, { window.isKeyWindow }) {
            note("shortcut: the test window could not become key (no focus for this process); it stands in as key")
            window.pretendsKey = true
        }
        waitUntil { descendants(of: host).contains { ($0 as? RecorderButton)?.title == "⇧⌘2" } }
        guard let button = descendants(of: host).compactMap({ $0 as? RecorderButton }).first else {
            check(false, "shortcut: the recorder button is in the view")
            return
        }
        check(button.accessibilityLabel() == "Capture Text", "shortcut: VoiceOver gets the name of the action", button.accessibilityLabel() ?? "nil")
        check(button.accessibilityValue() as? String == "⇧⌘2", "shortcut: VoiceOver gets the shortcut as the value",
              "\(button.accessibilityValue() ?? "nil")")

        @MainActor
        func key(_ code: Int, _ characters: String, _ flags: NSEvent.ModifierFlags = []) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                             windowNumber: window.windowNumber, context: nil, characters: characters,
                             charactersIgnoringModifiers: characters, isARepeat: false, keyCode: UInt16(code))!
        }
        @MainActor
        func press(_ button: RecorderButton) {
            let down = NSEvent.mouseEvent(with: .leftMouseDown, location: .zero, modifierFlags: [], timestamp: 0,
                                          windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
            button.mouseDown(with: down)
            button.keyDown(with: key(kVK_ANSI_2, "2", [.command, .shift]))
        }
        press(button)
        check(button.title == "Shortcut unavailable", "shortcut: a refused combination says so on the button", button.title)
        waitUntil(6) { button.title == "⇧⌘2" }
        check(button.title == "⇧⌘2", "shortcut: the button returns to the shortcut in force", button.title)

        var accepted = false
        button.onRecord = { _, _, _ in accepted = true; return true }
        press(button)
        check(accepted && button.title != "Shortcut unavailable", "shortcut: an accepted combination shows no error")

        // Keyboard and VoiceOver: no mouse needed, and the hotkeys are released only while it listens.
        check(button.accessibilityPerformPress() && button.isRecording, "shortcut: a VoiceOver press arms the recorder")
        check(hotKeys.registeredCount == 0 && hotKeys.isSuspended, "shortcut: no hotkey is registered while it listens",
              "\(hotKeys.registeredCount)")
        check(button.accessibilityValue() as? String == "Press the shortcut…", "shortcut: VoiceOver hears that it listens")
        button.keyDown(with: key(kVK_Escape, "\u{1b}"))
        check(!button.isRecording && button.title == "⇧⌘2", "shortcut: Esc cancels and shows the shortcut in force", button.title)
        check(hotKeys.registeredCount == 1 && !hotKeys.isSuspended, "shortcut: Esc gives the hotkeys back", "\(hotKeys.registeredCount)")
        check(window.firstResponder === button, "shortcut: the focus stays on the button after Esc")

        button.keyDown(with: key(kVK_Space, " "))
        check(button.isRecording, "shortcut: Space arms the recorder")
        button.keyDown(with: key(kVK_Tab, "\t"))
        check(!button.isRecording && hotKeys.registeredCount == 1, "shortcut: Tab leaves the recorder and gives the hotkeys back")

        var countWhenHandedOver = -1
        var recordedLabel = ""
        button.onRecord = { _, _, label in
            countWhenHandedOver = hotKeys.registeredCount
            recordedLabel = label
            return true
        }
        button.keyDown(with: key(kVK_Return, "\r"))
        check(button.isRecording, "shortcut: Return arms the recorder")
        button.keyDown(with: key(kVK_F5, "\u{F708}", [.command, .control]))
        check(!button.isRecording && countWhenHandedOver == 1, "shortcut: the hotkeys are back before a new one is handed over",
              "\(countWhenHandedOver)")
        check(recordedLabel == "⌃⌘F5", "shortcut: an F-key is labelled by name", recordedLabel)

        button.setIdleTitle("⌘\u{F708}")
        check(button.title == "⌘F5", "shortcut: a label saved with a private-use character shows the key's name", button.title)

        check(button.accessibilityPerformPress() && hotKeys.registeredCount == 0, "shortcut: armed again before the window closes")
        window.close()
        check(!button.isRecording && hotKeys.registeredCount == 1 && !hotKeys.isSuspended,
              "shortcut: closing the window while it listens gives the hotkeys back", "\(hotKeys.registeredCount)")
        _ = button.accessibilityPerformPress()
        check(!button.isRecording && hotKeys.registeredCount == 1, "shortcut: a recorder in a closed window does not arm")
    }
    hotKeys.unregister(.capture)
    check(hotKeys.registeredCount == 0, "hotkeys: unregistering frees the combination")

    // MARK: History deletion alerts: Cancel is the default, and every deleting choice needs its own click
    do {
        let off = HistoryClearing.switchOffAlert(savedCount: 3)
        check(off.messageText == "Delete the 3 saved captures too?" && off.buttons.map(\.title) == ["Cancel", "Keep Captures", "Delete Captures"],
              "history deletion: switching off offers Cancel, Keep Captures and Delete Captures", "\(off.buttons.map(\.title))")
        check(off.buttons[0].keyEquivalent == "\r", "history deletion: Cancel is the Return default")
        check(off.buttons[1].keyEquivalent == "" && off.buttons[2].keyEquivalent == "" && off.buttons[2].hasDestructiveAction,
              "history deletion: Keep Captures and Delete Captures have no key; Delete is destructive")
        let clear = HistoryClearing.clearAlert(savedCount: 1)
        check(clear.messageText == "Delete the saved capture?" && clear.buttons.map(\.title) == ["Cancel", "Clear History"],
              "history deletion: Clear History asks once, with Cancel first", "\(clear.messageText) \(clear.buttons.map(\.title))")
        check(clear.buttons[0].keyEquivalent == "\r" && clear.buttons[1].keyEquivalent == "" && clear.buttons[1].hasDestructiveAction,
              "history deletion: Clear History has no key, so Return cannot delete")
        // With nothing saved, neither path shows an alert (a modal here would hang the run until the timeout).
        let empty = History(store: JSONHistoryStore(fileURL: scratchHistoryFile("nictate-ui-")))
        HistoryClearing.confirmClear(empty)
        check(!HistoryDeletion.asksOnSwitchOff(savedCount: empty.items.count), "history deletion: an empty history asks nothing when saving is switched off")
    }

    // MARK: Scan line: the window a slow read shows is gone when the read ends, however it ends
    // A capture needs Screen Recording and a drag on the overlay, so CaptureCoordinator cannot run here. These checks
    // drive the real ScanLine on its own. The reading presentation after them is the capture's own timer, line and pill.
    do {
        let rect = CGRect(x: 200, y: 200, width: 200, height: 100)
        let baseline = visibleWindowIDs()
        if reduceMotion {
            let line = ScanLine(rect: rect)
            line.show()
            check(!line.isShowing && visibleWindowIDs() == baseline,
                  "scan line: under Reduce Motion it makes no window", scanState(line, baseline))
            // No window was made, so there is nothing to tear down: the teardown checks run in the normal-motion pass.
            line.close()
        } else {
            let shown = WeakRef<NSWindow>(nil), first = WeakRef<ScanLine>(nil)
            autoreleasepool {
                let line = ScanLine(rect: rect)
                first.object = line
                line.show()
                let added = visibleWindows().filter { !baseline.contains(ObjectIdentifier($0)) }
                check(added.count == 1 && line.isShowing, "scan line: showing it adds exactly one window", "\(added.count)")
                if let panel = added.first {
                    shown.object = panel
                    check(!panel.isKeyWindow && !panel.canBecomeKey, "scan line: its window is never key",
                          "key \(panel.isKeyWindow), can become key \(panel.canBecomeKey)")
                    check(panel.styleMask.contains(.nonactivatingPanel),
                          "scan line: its window never activates Nictate")
                    check(panel.contentView?.isAccessibilityElement() == false,
                          "scan line: its view is hidden from VoiceOver",
                          panel.contentView.map { "element \($0.isAccessibilityElement())" } ?? "no content view")
                    check(panel.ignoresMouseEvents, "scan line: its window lets clicks through to the app underneath")
                    check(panel.level == .statusBar, "scan line: its window sits at the status bar level", "\(panel.level.rawValue)")
                    check(panel.frame == rect, "scan line: its window covers the selection and nothing more", "\(panel.frame)")
                    // The sweep is one group, and each of its two animations must last the full sweep.
                    let sweepGroup = panel.contentView?.layer?.sublayers?.first?.animation(forKey: "sweep") as? CAAnimationGroup
                    let children = sweepGroup?.animations ?? []
                    check(children.count == 2 && children.allSatisfy { $0.duration == ScanLine.sweepSeconds },
                          "scan line: the sweep and the fade each last the full 1.2 s",
                          "children \(children.map(\.duration)), group \(sweepGroup?.duration ?? 0)")
                }
                line.close()
                check(shown.object?.isVisible == false && !line.isShowing && visibleWindowIDs() == baseline,
                      "scan line: closing it takes its window off the screen",
                      "window \(windowState(shown.object)), \(scanState(line, baseline))")
                line.close()
                line.show()
                check(!line.isShowing && visibleWindowIDs() == baseline, "scan line: a second close, and a show after close, add no window",
                      scanState(line, baseline))
            }
            check(waitUntil { shown.object == nil && first.object == nil }, "scan line: the closed line and its window are released",
                  "window \(windowState(shown.object)), line \(first.object == nil ? "released" : "kept")")

            // Twenty slow reads in a row: each adds one window and takes it away again, and none is kept.
            var mismatches = 0
            var windows: [WeakRef<NSWindow>] = []
            for _ in 1...20 {
                autoreleasepool {
                    let line = ScanLine(rect: rect)
                    line.show()
                    let added = visibleWindows().filter { !baseline.contains(ObjectIdentifier($0)) }
                    windows.append(WeakRef(added.first))
                    line.close()
                    if added.count != 1 || visibleWindowIDs() != baseline { mismatches += 1 }
                }
            }
            check(mismatches == 0, "scan line: 20 shows and closes in a row each add one window and take it away", "\(mismatches) off")
            check(waitUntil { windows.allSatisfy { $0.object == nil } }, "scan line: none of those 20 windows is kept",
                  "\(windows.filter { $0.object != nil }.count) of \(windows.count) kept")
        }
    }

    // MARK: Reading presentation: the capture's timer, scan line and "Reading…" pill, as the capture runs them
    // The capture starts a presentation when its read begins and ends it when the read ends, however the read ends.
    // Under Reduce Motion the line makes no window, so the pill is the only one.
    do {
        let rect = CGRect(x: 200, y: 200, width: 200, height: 100)
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        ResultPill.shared.hide(animated: false)
        let baseline = visibleWindowIDs()
        // Each presentation is held here only by a weak reference, so the release check can see it go.
        var presentations: [WeakRef<ReadingPresentation>] = []
        autoreleasepool {
            // A slow read: nothing for the working delay, then the line and the pill together.
            let slow = ReadingPresentation(rect: rect, screen: screen)
            presentations.append(WeakRef(slow))
            slow.start()
            waitPast(0.2)
            check(visibleWindowIDs() == baseline, "reading: nothing shows before the 300 ms working delay", windowDelta(baseline))
            let expected = reduceMotion ? 1 : 2
            check(waitUntil { visibleWindowIDs().count == baseline.count + expected },
                  "reading: at 300 ms the pill shows, with the scan line too unless Reduce Motion is on", windowDelta(baseline))
            let added = visibleWindows().filter { !baseline.contains(ObjectIdentifier($0)) }
            let linePanel = added.first { $0.frame == rect }
            let pillPanel = added.first { $0.frame != rect }
            let pillAtPlace = pillPanel.map {
                $0.frame.origin == SelectionGeometry.pillOrigin(size: $0.frame.size, below: rect, within: screen)
            } ?? false
            check(pillAtPlace, "reading: the pill sits where a result pill sits, below the selection",
                  pillPanel.map { "\($0.frame)" } ?? "no pill window")
            if reduceMotion {
                check(linePanel == nil, "reading: under Reduce Motion the scan line makes no window", windowDelta(baseline))
            } else {
                check(linePanel?.ignoresMouseEvents == true, "reading: the scan line covers the selection and lets clicks through",
                      "frames \(added.map(\.frame))")
            }
            slow.end()
            check(reduceMotion || linePanel?.isVisible == false,
                  "reading: ending the read takes the line's window off at once, before any run-loop turn",
                  linePanel.map { windowState($0) } ?? "no line window")
            check(pillPanel?.isVisible == true, "reading: ending the read leaves the pill up for the result", windowDelta(baseline))
            ResultPill.shared.hide(animated: false)
            check(visibleWindowIDs() == baseline, "reading: with the pill hidden, the windows equal the baseline", windowDelta(baseline))
        }
        autoreleasepool {
            // A fast read: it ends at 100 ms, and for half a second after that nothing shows.
            let fast = ReadingPresentation(rect: rect, screen: screen)
            presentations.append(WeakRef(fast))
            fast.start()
            waitPast(0.1)
            fast.end()
            waitPast(0.5)
            check(visibleWindowIDs() == baseline, "reading: a read ending at 100 ms shows nothing, not even after the working delay",
                  windowDelta(baseline))
        }
        autoreleasepool {
            // The timer falls due as the read ends. The main thread stays busy past the working delay, so the timer's
            // wake-up queues behind the end of the read, and the end cancels the timer before it can reveal anything.
            let busy = ReadingPresentation(rect: rect, screen: screen)
            presentations.append(WeakRef(busy))
            busy.start()
            waitPast(0.05) // The timer has begun its working delay.
            Thread.sleep(forTimeInterval: StatusFlash.workingDelay + 0.2)
            busy.end()
            waitPast(StatusFlash.workingDelay)
            check(visibleWindowIDs() == baseline, "reading: a timer due in the same turn as the end shows nothing", windowDelta(baseline))
        }
        autoreleasepool {
            // Ended twice, then started: nothing shows, and the presentation is released.
            let late = ReadingPresentation(rect: rect, screen: screen)
            presentations.append(WeakRef(late))
            late.end()
            late.end()
            late.start()
        }
        waitPast(StatusFlash.workingDelay)
        check(visibleWindowIDs() == baseline, "reading: ended twice, then started, shows nothing", windowDelta(baseline))
        check(waitUntil { presentations.allSatisfy { $0.object == nil } },
              "reading: each presentation is released once its read has ended",
              "\(presentations.filter { $0.object != nil }.count) of \(presentations.count) kept")
    }

    // MARK: Link question: no pill of a capture sits over "Open this link?" while it waits, and none is left after the answer
    do {
        let rect = CGRect(x: 200, y: 200, width: 200, height: 100)
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        ResultPill.shared.hide(animated: false)
        let baseline = visibleWindowIDs()
        ResultPill.shared.show(.reading, near: rect, screen: screen)
        let pillID = visibleWindows().first { !baseline.contains(ObjectIdentifier($0)) }.map(ObjectIdentifier.init)
        let saved = Settings.shared.barcodeAction
        defer { Settings.shared.barcodeAction = saved }
        Settings.shared.barcodeAction = "ask"
        let probe = QuestionProbe()
        // AppKit documents abortModal for a timer in the modal panel run loop mode; the abort counts as Cancel.
        let answer = Timer(timeInterval: 0.2, repeats: false) { _ in
            MainActor.assumeIsolated {
                probe.asked = NSApp.modalWindow != nil
                probe.pillUp = pillID.map { visibleWindowIDs().contains($0) } ?? true
                if NSApp.modalWindow != nil { NSApp.abortModal() }
            }
        }
        RunLoop.main.add(answer, forMode: .modalPanel)
        if Settings.shared.barcodeAction == "ask" {                       // never reach NSWorkspace.open in a test run
            CaptureCoordinator(status: StatusItemController(), windows: WindowCoordinator())
                .openLink(URL(string: "https://example.com/nictate-ui-question")!)
        }
        answer.invalidate()
        check(pillID != nil, "link question: the Reading pill was up before the question")
        check(probe.asked, "link question: Open this link? was asked")
        check(probe.asked && !probe.pillUp, "link question: no pill is on screen while the question waits")
        check(waitUntil { visibleWindowIDs() == baseline }, "link question: once answered, no window is left", windowDelta(baseline))
    }

    // MARK: Selection overlay: VoiceOver hears a layout area with keyboard help, and the keyboard alone selects, copies and cancels
    do {
        let context = CGContext(data: nil, width: 240, height: 120, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(gray: 0.5, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 240, height: 120))
        let still = DisplayStill(frame: CGRect(x: 120, y: 120, width: 240, height: 120), scale: 1, image: context.makeImage()!)
        let baseline = visibleWindowIDs()
        @MainActor
        func key(_ view: NSView, _ code: Int, _ characters: String, _ flags: NSEvent.ModifierFlags = []) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                             windowNumber: view.window?.windowNumber ?? 0, context: nil, characters: characters,
                             charactersIgnoringModifiers: characters, isARepeat: false, keyCode: UInt16(code))!
        }
        // Starts a selection on the still and returns the overlay's view once its window is on screen.
        @MainActor
        func openOverlay(_ probe: OverlayProbe) -> NSView? {
            Task { @MainActor in
                probe.region = await SelectionOverlay.select([still])
                probe.done = true
            }
            waitUntil { NSApp.windows.contains { $0.isVisible && $0.level == .screenSaver } }
            return NSApp.windows.first { $0.isVisible && $0.level == .screenSaver }?.contentView
        }

        let selecting = OverlayProbe()
        let view = openOverlay(selecting)
        check(view?.accessibilityRole() == .layoutArea, "overlay: VoiceOver hears a layout area, not an unknown element",
              "role \(String(describing: view?.accessibilityRole()))")
        check(view?.accessibilityLabel() == tr("Select the text to copy"), "overlay: VoiceOver still hears the label",
              "\(view?.accessibilityLabel() ?? "nil")")
        check(view?.accessibilityHelp() == tr("Press Return to start a corner, move the other with the arrow keys, then press Return to copy or Esc to cancel."),
              "overlay: VoiceOver's hint gives the keyboard path", "\(view?.accessibilityHelp() ?? "nil")")
        if let view {
            // Whatever the pointer's position, the start corner goes to the bottom left: the arrows stop at the edges.
            for _ in 0..<30 { view.keyDown(with: key(view, kVK_LeftArrow, "\u{F702}", .shift)) }
            for _ in 0..<30 { view.keyDown(with: key(view, kVK_DownArrow, "\u{F701}", .shift)) }
            view.keyDown(with: key(view, kVK_Return, "\r"))
            for _ in 0..<10 { view.keyDown(with: key(view, kVK_RightArrow, "\u{F703}", .shift)) }
            for _ in 0..<5 { view.keyDown(with: key(view, kVK_UpArrow, "\u{F700}", .shift)) }
            view.keyDown(with: key(view, kVK_Return, "\r"))
        }
        let selected = waitUntil { selecting.done }
        let region = selecting.region
        check(selected && region?.rect == CGRect(x: 120, y: 120, width: 100, height: 50) && region?.image.width == 100 && region?.image.height == 50,
              "overlay: the keyboard alone selects an area and confirms it", "region \(String(describing: region?.rect))")
        check(waitUntil { visibleWindowIDs() == baseline }, "overlay: confirming closes every overlay window", windowDelta(baseline))

        // The hook a capture uses to end its hold on the keyboard (the key panel): it runs once, with the windows already up,
        // so the keyboard is never without a window of Nictate.
        let hooked = OverlayProbe(), hook = HookProbe()
        Task { @MainActor in
            hooked.region = await SelectionOverlay.select([still], whenOpen: {
                hook.calls += 1
                hook.windows = visibleWindowIDs().subtracting(baseline).count
            })
            hooked.done = true
        }
        waitUntil { NSApp.windows.contains { $0.isVisible && $0.level == .screenSaver } }
        check(hook.calls == 1 && hook.windows >= 1, "overlay: whenOpen runs once, after the selection windows are on screen",
              "calls \(hook.calls), windows \(hook.windows)")
        if let opened = NSApp.windows.first(where: { $0.isVisible && $0.level == .screenSaver })?.contentView {
            opened.keyDown(with: key(opened, kVK_Escape, "\u{1b}"))
        }
        waitUntil { hooked.done }
        check(hook.calls == 1 && visibleWindowIDs() == baseline, "overlay: whenOpen is not run again when the selection ends", "calls \(hook.calls), \(windowDelta(baseline))")

        let cancelling = OverlayProbe()
        if let cancelled = openOverlay(cancelling) {
            cancelled.keyDown(with: key(cancelled, kVK_Escape, "\u{1b}"))
        }
        let cancelEnded = waitUntil { cancelling.done }
        check(cancelEnded && cancelling.region == nil && visibleWindowIDs() == baseline,
              "overlay: Esc cancels and closes every overlay window", "region \(cancelling.region != nil), \(windowDelta(baseline))")

        // Another app or a system dialog taking the keyboard leaves Esc no way in, so the selection ends by itself: when the
        // overlay window resigns key, and when the app resigns active. A process started from a terminal never has a key
        // overlay window, so the notification is a real loss here; where the system does make it key, the rule's own checks
        // in run_tests.swift cover the decision, and the overlay is closed with Esc.
        @MainActor
        func checkFocusLoss(_ name: String, _ leave: (NSView) -> Void) {
            let leaving = OverlayProbe()
            guard let overlay = openOverlay(leaving) else { return check(false, "overlay: opens for the focus-loss check (\(name))") }
            if overlay.window?.isKeyWindow == true {
                note("overlay: the window is key in this process, so \"\(name)\" is covered by the rule's checks only")
                overlay.keyDown(with: key(overlay, kVK_Escape, "\u{1b}"))
                waitUntil { leaving.done }
                return
            }
            leave(overlay)
            let ended = waitUntil { leaving.done }
            check(ended && leaving.region == nil && visibleWindowIDs() == baseline,
                  "overlay: focus leaving it cancels and closes every overlay window (\(name))",
                  "ended \(ended), region \(leaving.region != nil), \(windowDelta(baseline))")
            if !ended { overlay.keyDown(with: key(overlay, kVK_Escape, "\u{1b}")); waitUntil { leaving.done } }
        }
        checkFocusLoss("its window resigns key") { NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: $0.window) }
        checkFocusLoss("the app resigns active") { _ in NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: NSApp) }
    }

    // MARK: Key panel: from the shortcut until the selection opens, an Esc is Nictate's and cancels the capture
    // The stills take a fraction of a second, and until the selection opens the keys go to the app the user is in. A hidden,
    // non-activating panel takes the keyboard for that wait without activating Nictate.
    do {
        @MainActor
        func escapeEvent(_ flags: NSEvent.ModifierFlags = []) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil,
                             characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: UInt16(kVK_Escape))!
        }
        @MainActor
        func keyEvent(_ code: Int, _ characters: String, _ flags: NSEvent.ModifierFlags = []) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil,
                             characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: UInt16(code))!
        }
        /// The key panel a coordinator has on screen, if any.
        @MainActor
        func shownKeyPanel() -> EscapeKeyPanel? { NSApp.windows.compactMap { $0 as? EscapeKeyPanel }.first { $0.isVisible } }
        /// The selection's windows: on screen, above everything, and not the key panel.
        @MainActor
        func selectionWindows() -> [NSWindow] { NSApp.windows.filter { $0.isVisible && $0.level == .screenSaver && !($0 is EscapeKeyPanel) } }

        // The panel on its own. An activation an earlier check asked for may still be on its way: let it land before counting.
        waitPast(0.3)
        let baseline = visibleWindowIDs()
        let activations = ActivationCount()
        let observer = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: nil) { _ in
            activations.count += 1
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        let frontBefore = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let panel = EscapeKeyPanel()
        check(!panel.isVisible && visibleWindowIDs() == baseline, "key panel: made hidden, it is not on screen", windowDelta(baseline))
        check(panel.styleMask.contains(.nonactivatingPanel) && panel.canBecomeKey && !panel.canBecomeMain,
              "key panel: it can take the keyboard without making Nictate the active app")
        check(panel.level == .screenSaver && panel.ignoresMouseEvents && !panel.hidesOnDeactivate,
              "key panel: above everything, transparent to the mouse, and not hidden while the app is inactive",
              "level \(panel.level.rawValue), ignores mouse \(panel.ignoresMouseEvents), hides \(panel.hidesOnDeactivate)")
        check(panel.collectionBehavior.isSuperset(of: [.canJoinAllSpaces, .fullScreenAuxiliary]),
              "key panel: it can show over a full-screen app and on every Space")
        panel.present(near: CGPoint(x: 400, y: 300))
        check(panel.isVisible && panel.frame == CGRect(x: 380, y: 280, width: 40, height: 40),
              "key panel: shown as a small square under the pointer", "\(panel.frame)")
        waitPast(0.2)
        check(activations.count == 0 && NSWorkspace.shared.frontmostApplication?.processIdentifier == frontBefore,
              "key panel: showing it activates nothing and changes no frontmost app",
              "activations \(activations.count), front \(String(describing: NSWorkspace.shared.frontmostApplication?.processIdentifier)) was \(String(describing: frontBefore))")
        var escapes = 0
        panel.onEscape = { escapes += 1 }
        for (code, characters) in [(kVK_Return, "\r"), (kVK_Space, " "), (kVK_LeftArrow, "\u{F702}"), (kVK_ANSI_A, "a"), (kVK_Delete, "\u{7f}")] {
            panel.keyDown(with: keyEvent(code, characters))
        }
        check(escapes == 0, "key panel: other keys are swallowed and cancel nothing", "\(escapes)")
        panel.keyDown(with: escapeEvent())
        check(escapes == 1, "key panel: Esc is reported", "\(escapes)")
        panel.keyDown(with: escapeEvent([.shift, .command]))
        check(escapes == 2, "key panel: Esc counts with the shortcut's own modifiers still held", "\(escapes)")
        // AppKit offers a key to performKeyEquivalent before keyDown, and an Esc with the shortcut's Command still held arrives there.
        check(panel.performKeyEquivalent(with: escapeEvent([.shift, .command])) && escapes == 3,
              "key panel: Esc cancels as a key equivalent too, with the shortcut's Command held", "\(escapes)")
        check(panel.performKeyEquivalent(with: keyEvent(kVK_ANSI_Q, "q", .command)) && panel.performKeyEquivalent(with: keyEvent(kVK_ANSI_Comma, ",", .command)) && escapes == 3,
              "key panel: other Command keys are consumed without cancelling, so Quit and Settings cannot fire from an invisible window", "\(escapes)")
        check(!panel.performKeyEquivalent(with: keyEvent(kVK_ANSI_A, "a")) && escapes == 3, "key panel: a plain key is not a key equivalent", "\(escapes)")
        check(panel.dismiss(), "key panel: taking it down says it did")
        check(!panel.isVisible && !panel.isKeyWindow, "key panel: once down it is neither on screen nor key")
        check(!panel.dismiss(), "key panel: taking it down again does nothing")
        check(visibleWindowIDs() == baseline, "key panel: nothing is left on screen", windowDelta(baseline))

        // The capture task: stills held back by the test, a private clipboard, and the answers the system would give.
        let context = CGContext(data: nil, width: 240, height: 120, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(gray: 0.5, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 240, height: 120))
        let still = DisplayStill(frame: CGRect(x: 120, y: 120, width: 240, height: 120), scale: 1, image: context.makeImage()!)
        let sentinel = "EARLY-ESC-SENTINEL"
        @MainActor
        func makeCapture(otherAppInFront: Bool) -> (coordinator: CaptureCoordinator, gate: StillsGate, board: NSPasteboard) {
            let board = NSPasteboard(name: NSPasteboard.Name("nictate-ui-early-esc-\(UUID().uuidString)"))
            board.clearContents()
            board.setString(sentinel, forType: .string)
            let gate = StillsGate()
            var source = CaptureSource()
            source.permitted = { true }
            source.otherAppInFront = { otherAppInFront }
            source.stills = { await gate.wait() }
            let coordinator = CaptureCoordinator(status: StatusItemController(), windows: WindowCoordinator(),
                                                 clipboard: ClipboardWriter(pasteboard: board), source: source)
            return (coordinator, gate, board)
        }
        let before = visibleWindowIDs()

        // Esc before the stills are back: no selection opens, whenever the stills come, and the clipboard is untouched.
        do {
            let (coordinator, gate, board) = makeCapture(otherAppInFront: true)
            coordinator.capture(mode: .text)
            let up = shownKeyPanel()
            check(coordinator.isCapturing && up != nil, "early Esc: the key panel is up as soon as the shortcut is handled, before the stills are back")
            up?.keyDown(with: escapeEvent())
            check(shownKeyPanel() == nil, "early Esc: the Esc takes the panel down at once")
            check(!coordinator.isCapturing, "early Esc: the capture is over for the coordinator at once, so a new shortcut can start another")
            gate.release([still])
            waitPast(0.2) // The cancelled capture's task has run by now, whatever it did with the stills.
            check(selectionWindows().isEmpty && visibleWindowIDs() == before, "early Esc: no selection opens, however late the stills come", windowDelta(before))
            check(board.string(forType: .string) == sentinel, "early Esc: nothing is copied")
            board.releaseGlobally()
        }
        // Esc, then stills that could not be taken: a capture the user cancelled reports no failure and shows nothing.
        do {
            let (coordinator, gate, board) = makeCapture(otherAppInFront: true)
            coordinator.capture(mode: .text)
            shownKeyPanel()?.keyDown(with: escapeEvent())
            gate.release(nil)
            waitPast(0.2)
            check(!coordinator.isCapturing && shownKeyPanel() == nil && selectionWindows().isEmpty && visibleWindowIDs() == before,
                  "early Esc: unreadable stills after the Esc change nothing", windowDelta(before))
            board.releaseGlobally()
        }
        // After an Esc a new shortcut starts a capture at once, though the cancelled one still waits for its stills. When those
        // come they open nothing and leave the new capture's panel alone.
        do {
            let board = NSPasteboard(name: NSPasteboard.Name("nictate-ui-early-esc-\(UUID().uuidString)"))
            board.clearContents()
            board.setString(sentinel, forType: .string)
            let first = StillsGate(), second = StillsGate()
            var gates = [first, second]
            var source = CaptureSource()
            source.permitted = { true }
            source.otherAppInFront = { true }
            source.stills = { await gates.removeFirst().wait() }
            let coordinator = CaptureCoordinator(status: StatusItemController(), windows: WindowCoordinator(),
                                                 clipboard: ClipboardWriter(pasteboard: board), source: source)
            coordinator.capture(mode: .text)
            shownKeyPanel()?.keyDown(with: escapeEvent())
            coordinator.capture(mode: .text)
            check(coordinator.isCapturing && shownKeyPanel() != nil, "retry after an Esc: the new shortcut starts a capture with its own key panel")
            first.release([still])
            waitPast(0.2)
            check(shownKeyPanel() != nil && selectionWindows().isEmpty,
                  "retry after an Esc: the cancelled capture's stills open nothing and leave the new capture's panel up", windowDelta(before))
            shownKeyPanel()?.keyDown(with: escapeEvent())
            second.release([still])
            waitPast(0.2)
            check(!coordinator.isCapturing && shownKeyPanel() == nil && selectionWindows().isEmpty && visibleWindowIDs() == before,
                  "retry after an Esc: the new capture cancels the same way", windowDelta(before))
            board.releaseGlobally()
        }
        // No Esc: the panel is gone when the selection opens, and the selection's own Esc ends the capture as before.
        do {
            let (coordinator, gate, board) = makeCapture(otherAppInFront: true)
            coordinator.capture(mode: .text)
            check(shownKeyPanel() != nil, "no Esc: the key panel is up while the stills are taken")
            gate.release([still])
            check(waitUntil { !selectionWindows().isEmpty }, "no Esc: the selection opens when the stills are back")
            check(shownKeyPanel() == nil, "no Esc: the key panel is down once the selection is up")
            selectionWindows().first?.contentView?.keyDown(with: escapeEvent())
            check(waitUntil { !coordinator.isCapturing } && visibleWindowIDs() == before,
                  "no Esc: the selection's own Esc cancels as before and leaves nothing on screen", windowDelta(before))
            check(board.string(forType: .string) == sentinel, "no Esc: a cancelled selection copies nothing")
            board.releaseGlobally()
        }
        // A panel still up once the selection has opened (it comes down in the turn that opens it, so this is a guard): its Esc
        // cancels the selection as the selection's own Esc does.
        do {
            let (coordinator, gate, board) = makeCapture(otherAppInFront: true)
            coordinator.capture(mode: .text)
            let lingering = shownKeyPanel()
            gate.release([still])
            check(waitUntil { !selectionWindows().isEmpty }, "panel Esc in the selection: the selection opens")
            lingering?.present(near: CGPoint(x: 400, y: 300))
            lingering?.keyDown(with: escapeEvent())
            check(waitUntil { !coordinator.isCapturing } && selectionWindows().isEmpty && shownKeyPanel() == nil && visibleWindowIDs() == before,
                  "panel Esc in the selection: it cancels the selection and leaves nothing on screen", windowDelta(before))
            check(board.string(forType: .string) == sentinel, "panel Esc in the selection: nothing is copied")
            board.releaseGlobally()
        }
        // Unreadable stills with no Esc: the panel comes down before the failure is reported.
        do {
            let (coordinator, gate, board) = makeCapture(otherAppInFront: true)
            coordinator.capture(mode: .text)
            gate.release(nil)
            check(waitUntil { !coordinator.isCapturing } && shownKeyPanel() == nil && selectionWindows().isEmpty,
                  "failure: unreadable stills end the capture with no panel and no selection left on screen", windowDelta(before))
            board.releaseGlobally()
        }
        // A capture started inside Nictate (its menu bar panel, or Settings in front) has no key panel: Nictate is already the
        // active app, so no other app can receive the Esc.
        do {
            let (coordinator, gate, board) = makeCapture(otherAppInFront: false)
            coordinator.capture(mode: .text)
            check(coordinator.isCapturing && shownKeyPanel() == nil, "started inside Nictate: no key panel is shown")
            gate.release([still])
            check(waitUntil { !selectionWindows().isEmpty }, "started inside Nictate: the selection opens as before")
            selectionWindows().first?.contentView?.keyDown(with: escapeEvent())
            check(waitUntil { !coordinator.isCapturing } && visibleWindowIDs() == before, "started inside Nictate: Esc ends it as before", windowDelta(before))
            board.releaseGlobally()
        }
        // A shortcut while a capture is under way starts nothing: the first capture's panel is the only one.
        do {
            let (coordinator, gate, board) = makeCapture(otherAppInFront: true)
            coordinator.capture(mode: .text)
            coordinator.capture(mode: .text)
            check(NSApp.windows.compactMap { $0 as? EscapeKeyPanel }.filter(\.isVisible).count == 1, "second shortcut: still one key panel")
            shownKeyPanel()?.keyDown(with: escapeEvent())
            gate.release([still])
            check(waitUntil { !coordinator.isCapturing } && visibleWindowIDs() == before, "second shortcut: the first capture still cancels and leaves nothing", windowDelta(before))
            board.releaseGlobally()
        }
    }
}

if notes > 0 { print("\n\(notes) NOTE\(notes == 1 ? "" : "S") (environment, not failures)") }
if skips > 0 { print("\n\(skips) SKIPPED") }
let ciRun = ProcessInfo.processInfo.environment["CI"] == "true"
if ciRun && skips > 0 {
    print("FAIL  skipped checks in CI: the suite did not test everything it claims (see the SKIP lines)")
    failures += 1
}
// MARK: Status panel: the history is a screen of the same panel, and copying closes it
do {
    let status = StatusItemController()
    let history = History(store: JSONHistoryStore(fileURL: scratchHistoryFile("nictate-ui-main-")), isEnabled: { true })
    let model = StatusPanelModel(capture: CaptureCoordinator(status: status, windows: WindowCoordinator()),
                                 windows: WindowCoordinator(), history: history)
    model.reset()
    check(model.screen == .main && model.query.isEmpty, "panel: opens on the main screen with an empty search")
    model.screen = .history
    model.backToMain()
    check(model.screen == .main, "panel: Back returns to the main screen without closing the panel")
}

// MARK: Status panel anchoring: the panel opens below its button and does not rise over the menu bar
do {
    let status = StatusItemController()
    let history = History(store: JSONHistoryStore(fileURL: scratchHistoryFile("nictate-ui-anchor-")), isEnabled: { true })
    let model = StatusPanelModel(capture: CaptureCoordinator(status: status, windows: WindowCoordinator()),
                                 windows: WindowCoordinator(), history: history)
    let panel = StatusPanel(model: model)
    let screen = NSScreen.main ?? NSScreen.screens[0]
    // A stand-in for the status item, placed just under the top edge the way the menu bar's icon sits.
    let anchor = NSWindow(contentRect: NSRect(x: screen.frame.midX, y: screen.frame.maxY - 60, width: 40, height: 40),
                          styleMask: .borderless, backing: .buffered, defer: false)
    let button = NSButton(frame: NSRect(x: 0, y: 0, width: 22, height: 22))
    anchor.contentView?.addSubview(button)
    anchor.orderFrontRegardless()
    panel.toggle(relativeTo: button)
    _ = waitUntil { panel.isShown && panel.window != nil }
    waitPast(0.5)
    let buttonBottom = anchor.convertToScreen(button.convert(button.bounds, to: nil)).minY
    let frame = panel.window?.frame ?? .zero
    check(panel.isShown, "panel: opens from its status button")
    check(frame.maxY <= buttonBottom + 1 && frame.height > 200,
          "panel: opens below its button and stays clear of the menu bar",
          "panel top \(frame.maxY), button bottom \(buttonBottom), height \(frame.height)")
    panel.close()
    anchor.orderOut(nil)
}

// MARK: Capture from the panel: the panel is off the screen before the stills are taken, or its fade-out is in the capture
/// Opens a real status panel on a stand-in for the menu bar button, with a capture that records what it saw when its stills were
/// requested, then hands it to `act`. The panel is closed and everything released afterwards.
@MainActor
func withOpenPanel(animates: Bool, shown: Bool = true,
                   _ act: (StatusPanelModel, StatusPanel, PanelAtStills, CaptureCoordinator) -> Void) {
    let probe = PanelAtStills()
    var source = CaptureSource()
    source.permitted = { true }
    source.otherAppInFront = { false } // Started from Nictate's own panel, so no key panel.
    source.stills = {
        probe.count += 1
        probe.requested = true
        probe.drawn = isDrawn(probe.window)
        probe.popoverShown = probe.panel?.isShown ?? false
        return nil // The unreadable-screen path ends the capture without a selection.
    }
    let board = NSPasteboard(name: NSPasteboard.Name("nictate-ui-panel-capture-\(UUID().uuidString)"))
    let history = History(store: JSONHistoryStore(fileURL: scratchHistoryFile("nictate-ui-panel-capture-")), isEnabled: { true })
    let coordinator = CaptureCoordinator(status: StatusItemController(), windows: WindowCoordinator(),
                                         clipboard: ClipboardWriter(pasteboard: board), source: source)
    let model = StatusPanelModel(capture: coordinator, windows: WindowCoordinator(), history: history)
    let panel = StatusPanel(model: model, animates: animates)
    probe.panel = panel
    let screen = NSScreen.main ?? NSScreen.screens[0]
    let anchor = NSWindow(contentRect: NSRect(x: screen.frame.midX, y: screen.frame.maxY - 60, width: 40, height: 40),
                          styleMask: .borderless, backing: .buffered, defer: false)
    let button = NSButton(frame: NSRect(x: 0, y: 0, width: 22, height: 22))
    anchor.contentView?.addSubview(button)
    anchor.orderFrontRegardless()
    let shownMarker = Marker()
    let observer = NotificationCenter.default.addObserver(forName: NSPopover.didShowNotification, object: nil, queue: .main) { _ in shownMarker.fired = true }
    if shown {
        panel.toggle(relativeTo: button)
        check(waitUntil(6) { shownMarker.fired && panel.isShown }, "panel capture (animates \(animates)): the panel is open and finished opening")
        // Kept before the capture: once the popover has closed, its content view may no longer reach the window.
        probe.window = panel.window
        check(waitUntil(6) { isDrawn(probe.window) }, "panel capture (animates \(animates)): the panel's window is drawn before the choice")
    }
    act(model, panel, probe, coordinator)
    waitUntil { !coordinator.isCapturing }
    if panel.isShown { panel.close() }
    waitUntil { !panel.isShown }
    check(!panel.isShown && !isDrawn(probe.window), "panel capture (animates \(animates)): the panel is closed afterwards",
          "shown \(panel.isShown), drawn \(isDrawn(probe.window))")
    NotificationCenter.default.removeObserver(observer)
    anchor.orderOut(nil)
    board.releaseGlobally()
}

// With and without the close animation: without it the popover can report its close from inside performClose. The window
// server drops a closed window a frame or two after the close is reported, so only the animated panel, whose fade-out is
// what the stills caught, is checked against what the server draws; both must have reported the close.
for animates in [true, false] {
    withOpenPanel(animates: animates) { model, _, probe, _ in
        model.captureText()
        check(waitUntil(6) { probe.requested }, "panel capture (animates \(animates)): Capture Text asks for the stills")
        check(probe.requested && !probe.popoverShown && !(animates && probe.drawn),
              "panel capture (animates \(animates)): the panel has closed when the stills are taken",
              "window drawn \(probe.drawn), popover shown \(probe.popoverShown), stills asked \(probe.count) time(s)")
    }
    withOpenPanel(animates: animates) { model, _, probe, _ in
        model.captureCode()
        check(waitUntil(6) { probe.requested }, "panel capture (animates \(animates)): Capture Code asks for the stills")
        check(probe.requested && !probe.popoverShown && !(animates && probe.drawn),
              "panel capture (animates \(animates)): the panel has closed for Capture Code too",
              "window drawn \(probe.drawn), popover shown \(probe.popoverShown), stills asked \(probe.count) time(s)")
    }
}
// With no panel open there is nothing to wait for: the capture starts at once.
withOpenPanel(animates: true, shown: false) { model, panel, probe, _ in
    model.captureText()
    check(waitUntil(6) { probe.requested } && !panel.isShown, "panel capture, panel not open: the capture starts without waiting")
}
// A panel closed with no choice made starts no capture.
withOpenPanel(animates: true) { _, panel, probe, _ in
    panel.close()
    waitUntil { !panel.isShown }
    waitPast(0.2)
    check(probe.count == 0, "panel capture: closing the panel without a choice captures nothing", "stills asked \(probe.count) time(s)")
}

// MARK: Keyboard selection: the text field reports its text on every key, so a repeated search must not reset the highlight
do {
    let store = JSONHistoryStore(fileURL: scratchHistoryFile("nictate-ui-"))
    let history = History(store: store, isEnabled: { true })
    history.add("first")
    history.add("second")
    history.add("third")
    History.flushWrites()
    let status = StatusItemController()
    let model = StatusPanelModel(capture: CaptureCoordinator(status: status, windows: WindowCoordinator()),
                                 windows: WindowCoordinator(), history: history)
    model.reset()
    model.screen = .history
    check(model.selection == 0, "keyboard: opening History highlights its first match")
    model.searchChanged("")
    model.moveSelection(by: 1)
    model.searchChanged("")
    check(model.selection == 1, "keyboard: the same search text again keeps the arrow-key highlight where it is")
    model.searchChanged("i")
    check(model.entries.map(\.text) == ["third", "first"] && model.selection == 0,
          "keyboard: a real search change starts again at its first match", "\(model.entries.map(\.text))")
    model.moveSelection(by: 5)
    check(model.selection == 1, "keyboard: arrows stop at the last match rather than wrapping")
    model.moveSelection(by: -9)
    check(model.selection == 0, "keyboard: arrows stop at the first match")
    model.backToMain()
    check(model.selection == nil, "keyboard: leaving History clears the highlight")
}

// Recent Captures: the shortcut opens the saved captures as a picker with the newest highlighted, and the next time the panel
// opens it starts again from the main screen, not as a picker.
do {
    let history = History(store: JSONHistoryStore(fileURL: scratchHistoryFile("nictate-ui-picker-")), isEnabled: { true })
    history.add("first")
    history.add("second")
    History.flushWrites()
    let status = StatusItemController()
    let model = StatusPanelModel(capture: CaptureCoordinator(status: status, windows: WindowCoordinator()),
                                 windows: WindowCoordinator(), history: history)
    model.reset()
    check(!model.isPicker, "picker: the panel opened from the icon is not a picker")
    model.openPicker()
    check(model.isPicker && model.screen == .history && model.selection == 0,
          "picker: the shortcut's list is the history with the newest capture highlighted", "\(model.screen) \(String(describing: model.selection))")
    model.moveSelection(by: 1)
    check(model.selection == 1, "picker: an arrow key moves the highlight to the next capture")
    model.reset()
    check(!model.isPicker && model.screen == .main && model.selection == nil,
          "picker: opening the panel again starts from the main screen, not as a picker")
}

// Regression: History's entries are read asynchronously. Captures that arrive after History opened still get a
// highlighted first match, so Return has a target.
do {
    let file = scratchHistoryFile("nictate-ui-late-")
    let seed = History(store: JSONHistoryStore(fileURL: file), isEnabled: { true })
    seed.add("arrived later")
    History.flushWrites()
    let history = History(store: JSONHistoryStore(fileURL: file), isEnabled: { true }, loadsNow: false)
    let status = StatusItemController()
    let model = StatusPanelModel(capture: CaptureCoordinator(status: status, windows: WindowCoordinator()),
                                 windows: WindowCoordinator(), history: history)
    model.reset()
    model.screen = .history
    check(model.selection == nil && model.entries.isEmpty, "late entries: History opens before its read has finished")
    let highlighted = waitUntil { model.selection == 0 && model.entries.map(\.text) == ["arrived later"] }
    check(highlighted, "late entries: the first match is highlighted once the read finishes", "\(model.entries.map(\.text))")
}

// Regression: deleting the highlighted last row moves the highlight to the new last row, so Return keeps a target.
do {
    let file = scratchHistoryFile("nictate-ui-delete-")
    let history = History(store: JSONHistoryStore(fileURL: file), isEnabled: { true })
    history.add("first")
    history.add("second")
    history.add("third")
    History.flushWrites()
    let status = StatusItemController()
    let model = StatusPanelModel(capture: CaptureCoordinator(status: status, windows: WindowCoordinator()),
                                 windows: WindowCoordinator(), history: history)
    model.reset()
    model.screen = .history
    model.moveSelection(by: 5)
    check(model.selection == 2, "delete: the highlight reaches the last row")
    model.deleteCapture("first")
    let moved = waitUntil { model.selection == 1 && model.entries.map(\.text) == ["third", "second"] }
    check(moved, "delete: the highlight moves to the new last row", "selection \(String(describing: model.selection))")
}

// Regression: a copy error from an earlier visit does not reappear when the panel opens again.
do {
    let history = History(store: JSONHistoryStore(fileURL: scratchHistoryFile("nictate-ui-err-")), isEnabled: { true })
    let status = StatusItemController()
    let model = StatusPanelModel(capture: CaptureCoordinator(status: status, windows: WindowCoordinator()),
                                 windows: WindowCoordinator(), history: history)
    model.copyError = "Couldn't copy text. Try again."
    model.reset()
    check(model.copyError == nil, "copy error: reopening the panel clears the error from an earlier copy")
}

// Regression: Command-F asks the History screen for its search field, once per press.
do {
    let history = History(store: JSONHistoryStore(fileURL: scratchHistoryFile("nictate-ui-find-")), isEnabled: { true })
    let status = StatusItemController()
    let model = StatusPanelModel(capture: CaptureCoordinator(status: status, windows: WindowCoordinator()),
                                 windows: WindowCoordinator(), history: history)
    let before = model.searchFocusRequests
    NotificationCenter.default.post(name: MainMenu.findRequested, object: nil)
    check(model.searchFocusRequests == before + 1, "find: Command-F asks the History search field for focus")
}

// Regression (finding #5): Save Captures changes the settings and history the panel was given, not the app's own.
do {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("nictate-ui-inject-\(UUID().uuidString)")
    let defaults = UserDefaults(suiteName: folder.path)!
    let settings = Settings(defaults: defaults)
    let history = History(store: JSONHistoryStore(fileURL: scratchHistoryFile("nictate-ui-inject-")), isEnabled: { settings.historyEnabled }, loadsNow: false)
    let status = StatusItemController()
    let model = StatusPanelModel(capture: CaptureCoordinator(status: status, windows: WindowCoordinator()),
                                 windows: WindowCoordinator(), history: history, settings: settings)
    model.setKeepHistory(true)
    let loaded = waitUntil { history.state == .available }
    check(settings.historyEnabled && model.historyEnabled && loaded,
          "inject: Save Captures turns on the panel's own settings and loads its own history", "\(history.state)")
    model.setKeepHistory(false)
    check(!settings.historyEnabled && history.state == .disabled,
          "inject: Save Captures off changes the panel's own settings; with nothing saved nothing is asked", "\(history.state)")
    defaults.removePersistentDomain(forName: folder.path)
    // A suite named by a path is stored at that path with .plist added; it goes with the history files at the end.
    historyFiles.append(folder.appendingPathExtension("plist"))
}

// Flush pending writes first, so a write cannot recreate a file after it is removed.
History.flushWrites()
for file in historyFiles { try? FileManager.default.removeItem(at: file) }
print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
