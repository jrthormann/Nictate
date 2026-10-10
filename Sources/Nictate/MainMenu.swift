// Nictate: a macOS menu bar app that copies text from anywhere on your screen.
// Copyright (c) 2026 jrthormann. MIT License, see LICENSE.

import AppKit

/// The app's main menu. While a window is open it is the menu bar; at all times it is where AppKit looks up
/// key equivalents, so without it ⌘C, ⌘V, ⌘A, ⌘Z and ⌘W do nothing in the History search or in Settings.
/// The Edit and Window items have no target: AppKit sends them along the responder chain to the text field
/// or window that has the focus, and enables each one only when something there can act on it.
@MainActor
final class MainMenu: NSObject, NSMenuItemValidation {
    /// Posted by Find… while History is the key window; its search field takes the focus.
    static let findRequested = Notification.Name("NictateFindInHistory")

    let menu = NSMenu()
    /// The Window menu, which AppKit fills with the open windows once it is `NSApp.windowsMenu`.
    let windowMenu: NSMenu
    private let showSettings: () -> Void
    private let canFind: () -> Bool

    /// `canFind` says whether a window with a search field (History) is the key window.
    init(showSettings: @escaping () -> Void, canFind: @escaping () -> Bool) {
        self.showSettings = showSettings
        self.canFind = canFind
        windowMenu = NSMenu(title: tr("Window"))
        super.init()
        menu.addItem(submenu(appMenu()))
        menu.addItem(submenu(editMenu()))
        fillWindowMenu()
        menu.addItem(submenu(windowMenu))
    }

    /// Makes this the app's main menu, and its Window menu the one AppKit lists the open windows in.
    func install() {
        NSApp.mainMenu = menu
        NSApp.windowsMenu = windowMenu
    }

    private func appMenu() -> NSMenu {
        let app = NSMenu(title: "Nictate")
        app.addItem(item(tr("About Nictate"), #selector(showAbout), target: self))
        app.addItem(item(tr("Support the Developer…"), #selector(supportDeveloper), target: self))
        app.addItem(item(tr("Check for Updates…"), #selector(checkForUpdates), target: self))
        app.addItem(.separator())
        app.addItem(item(tr("Settings…"), #selector(openSettings), key: ",", target: self))
        app.addItem(.separator())
        app.addItem(item(tr("Hide Nictate"), #selector(NSApplication.hide(_:)), key: "h"))
        app.addItem(item(tr("Hide Others"), #selector(NSApplication.hideOtherApplications(_:)), key: "h", mods: [.command, .option]))
        app.addItem(item(tr("Show All"), #selector(NSApplication.unhideAllApplications(_:))))
        app.addItem(.separator())
        app.addItem(item(tr("Quit Nictate"), #selector(NSApplication.terminate(_:)), key: "q"))
        return app
    }

    private func editMenu() -> NSMenu {
        let edit = NSMenu(title: tr("Edit"))
        // undo: and redo: are answered by the text view's undo manager; AppKit declares no selector for them.
        edit.addItem(item(tr("Undo"), Selector(("undo:")), key: "z"))
        edit.addItem(item(tr("Redo"), Selector(("redo:")), key: "z", mods: [.command, .shift]))
        edit.addItem(.separator())
        edit.addItem(item(tr("Cut"), #selector(NSText.cut(_:)), key: "x"))
        edit.addItem(item(tr("Copy"), #selector(NSText.copy(_:)), key: "c"))
        edit.addItem(item(tr("Paste"), #selector(NSText.paste(_:)), key: "v"))
        edit.addItem(item(tr("Select All"), #selector(NSResponder.selectAll(_:)), key: "a"))
        edit.addItem(.separator())
        edit.addItem(item(tr("Find…"), #selector(find), key: "f", target: self))
        return edit
    }

    private func fillWindowMenu() {
        windowMenu.addItem(item(tr("Close"), #selector(NSWindow.performClose(_:)), key: "w"))
        windowMenu.addItem(item(tr("Minimize"), #selector(NSWindow.performMiniaturize(_:)), key: "m"))
        windowMenu.addItem(item(tr("Zoom"), #selector(NSWindow.performZoom(_:))))
        windowMenu.addItem(.separator())
        windowMenu.addItem(item(tr("Bring All to Front"), #selector(NSApplication.arrangeInFront(_:))))
    }

    private func submenu(_ sub: NSMenu) -> NSMenuItem {
        let parent = NSMenuItem(title: sub.title, action: nil, keyEquivalent: "")
        parent.submenu = sub
        return parent
    }

    private func item(_ title: String, _ action: Selector, key: String = "",
                      mods: NSEvent.ModifierFlags = .command, target: AnyObject? = nil) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        if !key.isEmpty { i.keyEquivalentModifierMask = mods }
        i.target = target
        return i
    }

    @objc private func showAbout() { AboutPanel.show() }
    @objc private func supportDeveloper() { SupportDeveloper.open() }
    @objc private func checkForUpdates() { Task { @MainActor in await UpdateAlert.run() } }
    @objc private func openSettings() { showSettings() }
    @objc private func find() { NotificationCenter.default.post(name: Self.findRequested, object: nil) }

    /// Only Find… needs a say: the items without a target are validated by whoever answers them.
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        menuItem.action == #selector(find) ? canFind() : true
    }
}

/// "Support the Developer…": opens the developer's PayPal page in the default browser. Nothing is embedded or sent by
/// the app itself; the browser does the rest.
enum SupportDeveloper {
    static let url = URL(string: "https://paypal.me/jrthormann")!

    @MainActor
    static func open() {
        NSWorkspace.shared.open(url)
    }
}

/// The standard About panel, with the one-line pitch and the sign-off. Shared by the main menu
/// and the status menu.
@MainActor
enum AboutPanel {
    static func show() {
        NSApp.activate(ignoringOtherApps: true)
        let centered = NSMutableParagraphStyle()
        centered.alignment = .center
        centered.paragraphSpacing = 6
        let base: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11),
                                                   .foregroundColor: NSColor.secondaryLabelColor,
                                                   .paragraphStyle: centered]
        let credits = NSMutableAttributedString()
        credits.append(NSAttributedString(
            string: tr("Your screen is full of text you can't copy. Nictate fixes that. Your other problems are unfortunately outside the scope of this project.") + "\n",
            attributes: base))
        credits.append(NSAttributedString(string: madeWith, attributes: base))
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }

    /// The sign-off in the About panel; the same in every language, so it is not translated.
    private static let madeWith = "Made in the Dominican Republic."
}
