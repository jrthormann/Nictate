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

MainActor.assumeIsolated {
    let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

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

    // MARK: Main menu: ⌘A, ⌘C and ⌘V work in the History search, and ⌘W closes the window
    // ⌘C and ⌘V go through the general pasteboard, so what the user had there is put back afterwards.
    do {
        let board = NSPasteboard.general
        let saved: [NSPasteboardItem] = (board.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types { if let data = item.data(forType: type) { copy.setData(data, forType: type) } }
            return copy
        }
        let mainMenu = MainMenu(showSettings: {}, canFind: { false })
        mainMenu.install()
        // Deterministic, whatever has the focus: the menu is installed and each key goes to the action that
        // text fields and windows answer.
        check(application.mainMenu === mainMenu.menu && application.windowsMenu === mainMenu.windowMenu,
              "main menu: installed as the app's main menu, with its Window menu")
        func allItems(_ menu: NSMenu) -> [NSMenuItem] { menu.items + menu.items.compactMap(\.submenu).flatMap(allItems) }
        let expected: [(String, Selector)] = [("x", #selector(NSText.cut(_:))), ("c", #selector(NSText.copy(_:))),
                                              ("v", #selector(NSText.paste(_:))), ("a", #selector(NSResponder.selectAll(_:))),
                                              ("z", Selector(("undo:"))), ("w", #selector(NSWindow.performClose(_:))),
                                              ("m", #selector(NSWindow.performMiniaturize(_:)))]
        for (key, action) in expected {
            let item = allItems(mainMenu.menu).first { $0.keyEquivalent == key && $0.keyEquivalentModifierMask == .command }
            check(item?.action == action && item?.target == nil,
                  "main menu: ⌘\(key.uppercased()) sends \(NSStringFromSelector(action)) along the responder chain",
                  item.map { "\($0.action.map(NSStringFromSelector) ?? "nil")" } ?? "missing")
        }
        let windows = WindowCoordinator()
        windows.showHistory()
        let title = tr("Nictate History")
        waitUntil { application.windows.contains { $0.title == title && $0.isVisible } }
        guard let window = application.windows.first(where: { $0.title == title }),
              // .searchable lives in the window's toolbar, which is outside the content view.
              let field = (window.contentView?.superview.map(descendants(of:)) ?? []).compactMap({ $0 as? NSTextField }).first(where: \.isEditable) else {
            check(false, "main menu: the History window and its search field open")
            return
        }
        // A process started from a terminal may not take the focus (see the shortcut checks). Then the key
        // goes to the same menu item AppKit would pick, sent along the field's responder chain.
        check(application.activationPolicy() == .regular, "dock: an open History window puts Nictate in the Dock")
        let isKey = waitUntil(2) { window.isKeyWindow }
        if !isKey { note("main menu: the History window could not become key; each item's action goes along the field's responder chain directly") }
        @MainActor
        func press(_ key: String, _ name: String) {
            if isKey, let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
                                                   windowNumber: window.windowNumber, context: nil, characters: key,
                                                   charactersIgnoringModifiers: key, isARepeat: false, keyCode: 0) {
                check(application.mainMenu?.performKeyEquivalent(with: event) == true, "main menu: ⌘\(key.uppercased()) is handled (\(name))")
                return
            }
            func items(_ menu: NSMenu) -> [NSMenuItem] { menu.items + menu.items.compactMap(\.submenu).flatMap(items) }
            let item = application.mainMenu.map(items)?.first { $0.keyEquivalent == key && $0.keyEquivalentModifierMask == .command }
            check(item.flatMap { item in item.action.map { window.firstResponder?.tryToPerform($0, with: item) == true } } ?? false,
                  "main menu: ⌘\(key.uppercased()) reaches something that acts on it (\(name))")
        }
        window.makeFirstResponder(field)
        guard let editor = field.currentEditor() as? NSTextView else {
            check(false, "main menu: the search field takes the focus")
            return
        }
        editor.insertText("nictate", replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
        editor.setSelectedRange(NSRange(location: 0, length: 0))
        press("a", "select all")
        check(editor.selectedRange() == NSRange(location: 0, length: 7), "main menu: ⌘A selects the whole search", "\(editor.selectedRange())")
        board.clearContents()
        press("c", "copy")
        check(board.string(forType: .string) == "nictate", "main menu: ⌘C copies the search text", board.string(forType: .string) ?? "nil")
        editor.setSelectedRange(NSRange(location: 7, length: 0))
        press("v", "paste")
        check(editor.string == "nictatenictate", "main menu: ⌘V pastes into the search", editor.string)
        check(waitUntil { History.shared.query == "nictatenictate" }, "main menu: the pasted search filters History", History.shared.query)
        History.shared.query = ""
        press("w", "close")
        check(waitUntil { !window.isVisible }, "main menu: ⌘W closes the History window")
        check(application.activationPolicy() == .accessory, "dock: closing the last window takes Nictate out of the Dock")
        board.clearContents()
        board.writeObjects(saved)
    }

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
        let empty = History(store: EncryptedHistoryStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("nictate-ui-\(UUID().uuidString).sealed"),
                                                         key: { SymmetricKey(data: Data(repeating: 3, count: 32)) }),
                            retention: { .never })
        HistoryClearing.confirmClear(empty)
        HistoryClearing.historyTurnedOff(empty)
        check(empty.items.isEmpty, "history deletion: an empty history clears without asking")
    }

    // MARK: Dock: Nictate stays in the Dock until its last window closes, a minimized one included
    do {
        let windows = WindowCoordinator()
        windows.showPreferences()
        windows.showHistory()
        let own = { application.windows.filter { $0.isVisible && ($0.title == tr("Nictate History") || $0.contentViewController is PreferencesController) } }
        waitUntil { own().count == 2 }
        let history = own().first { $0.title == tr("Nictate History") }
        let settings = own().first { $0.contentViewController is PreferencesController }
        check(history != nil && settings != nil && application.activationPolicy() == .regular, "dock: Settings and History open, Nictate is in the Dock")
        history?.miniaturize(nil)
        if waitUntil(6, { history?.isMiniaturized == true }) {
            settings?.close()
            check(application.activationPolicy() == .regular, "dock: a minimized window keeps Nictate in the Dock, so it can come back")
        } else {
            skip("dock: the History window could not be minimized here")
            settings?.close()
        }
        history?.close()
        check(application.activationPolicy() == .accessory, "dock: closing the minimized window too leaves the Dock")
    }
}

if notes > 0 { print("\n\(notes) NOTE\(notes == 1 ? "" : "S") (environment, not failures)") }
if skips > 0 { print("\n\(skips) SKIPPED") }
let ciRun = ProcessInfo.processInfo.environment["CI"] == "true"
if ciRun && skips > 0 {
    print("FAIL  skipped checks in CI: the suite did not test everything it claims (see the SKIP lines)")
    failures += 1
}
// MARK: Status menu structure: separators, groups, symbols and key equivalents
do {
    let status = StatusItemController()
    let controller = MenuController(capture: CaptureCoordinator(status: status, windows: WindowCoordinator()), windows: WindowCoordinator())
    controller.menuNeedsUpdate(controller.menu)
    let items = controller.menu.items
    let titles = items.map { $0.isSeparatorItem ? "—" : $0.title }
    check(items.first?.isSeparatorItem == false && items.last?.isSeparatorItem == false,
          "menu: no separator at the start or the end", titles.joined(separator: " | "))
    let adjacentSeparators = zip(items, items.dropFirst()).contains { $0.0.isSeparatorItem && $0.1.isSeparatorItem }
    check(!adjacentSeparators, "menu: no two separators in a row")
    check(items.allSatisfy { $0.isSeparatorItem || !$0.title.isEmpty }, "menu: every item has a title")
    let settings = items.first { $0.title == tr("Settings…") }
    check(settings?.keyEquivalent == "," && settings?.keyEquivalentModifierMask == .command && settings?.image == nil,
          "menu: Settings… is ⌘, and has no symbol")
    let quit = items.first { $0.title == tr("Quit Nictate") }
    check(quit?.keyEquivalent == "q" && quit?.keyEquivalentModifierMask == .command, "menu: Quit Nictate is ⌘Q")
    let capture = items.first { $0.title == tr("Capture Text") }
    check(capture?.image != nil, "menu: the capture command keeps its symbol")
    let parents = items.filter { $0.hasSubmenu }
    check(parents.allSatisfy { $0.image == nil }, "menu: language, mode and history parents are plain text")
}

print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
