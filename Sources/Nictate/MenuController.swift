// Nictate: a macOS menu bar app that copies text from anywhere on your screen.
// Copyright (c) 2026 jrthormann. MIT License, see LICENSE.

import AppKit

/// The status item's menu. It is rebuilt each time it opens, so it always reflects the current
/// settings, history and the latest capture's detections.
@MainActor
final class MenuController: NSObject, NSMenuDelegate {
    let menu = NSMenu()
    private let settings = Settings.shared
    private let capture: CaptureCoordinator
    private let windows: WindowCoordinator

    init(capture: CaptureCoordinator, windows: WindowCoordinator) {
        self.capture = capture
        self.windows = windows
        super.init()
        menu.delegate = self
        menu.autoenablesItems = false
    }

    @objc private func captureText() { capture.capture(mode: .text) }
    @objc private func captureCode() { capture.capture(mode: .code) }
    @objc private func rotateHistory() { capture.rotateHistory() }
    @objc private func showPreferences() { windows.showPreferences() }
    @objc private func showHistory() { windows.showHistory() }

    @objc private func copyDetected(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String else { return }
        capture.copyDetected(value)
    }

    @objc private func openDetected(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        capture.openLink(url)
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        History.shared.pruneExpired()

        let capture = item(tr("Capture Text"), #selector(captureText), symbol: "text.viewfinder")
        capture.keyEquivalent = Settings.keyEquivalent(forLabel: settings.hotKeyLabel)
        capture.keyEquivalentModifierMask = Settings.modifierMask(for: settings.hotKeyMods)
        menu.addItem(capture)
        let code = item(tr("Capture QR Code or Barcode"), #selector(captureCode), symbol: "qrcode.viewfinder")
        if let saved = settings.shortcut(for: .captureCode) {
            code.keyEquivalent = Settings.keyEquivalent(forLabel: saved.label)
            code.keyEquivalentModifierMask = Settings.modifierMask(for: saved.shortcut.mods)
        }
        menu.addItem(code)
        if settings.historyEnabled {
            let rotate = item(tr("Cycle History"), #selector(rotateHistory), symbol: "arrow.triangle.2.circlepath")
            rotate.keyEquivalent = Settings.keyEquivalent(forLabel: settings.rotateHotKeyLabel)
            rotate.keyEquivalentModifierMask = Settings.modifierMask(for: settings.rotateHotKeyMods)
            menu.addItem(rotate)
        }
        menu.addItem(.separator())

        for entry in detectionItems() { menu.addItem(entry) }

        menu.addItem(languageMenu())
        menu.addItem(modeMenu())
        menu.addItem(toggle(tr("Append Mode"), \.appendMode))
        menu.addItem(.separator())

        if settings.historyEnabled {
            menu.addItem(historyMenu())
            menu.addItem(item(tr("Show History…"), #selector(showHistory)))
            menu.addItem(.separator())
        } else if HistoryDeletion.showsClearControl(historyEnabled: false, savedCount: History.shared.items.count) {
            // Captures kept when history was turned off can still be deleted from here.
            menu.addItem(item(tr("Clear History…"), #selector(clearHistory)))
            menu.addItem(.separator())
        }
        menu.addItem(item(tr("Settings…"), #selector(showPreferences), key: ","))
        menu.addItem(item(tr("About Nictate"), #selector(about)))
        menu.addItem(item(tr("Check for Updates…"), #selector(checkForUpdates)))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: tr("Quit Nictate"),
                                action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func item(_ title: String, _ action: Selector, key: String = "", symbol: String? = nil) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.target = self
        if let symbol { i.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
        return i
    }

    private func toggle(_ title: String, _ keyPath: ReferenceWritableKeyPath<Settings, Bool>,
                        enabled: Bool = true) -> NSMenuItem {
        let i = item(title, #selector(toggleSetting(_:)))
        i.isEnabled = enabled
        i.representedObject = keyPath
        i.state = settings[keyPath: keyPath] ? .on : .off
        return i
    }

    @objc private func toggleSetting(_ sender: NSMenuItem) {
        guard let keyPath = sender.representedObject as? ReferenceWritableKeyPath<Settings, Bool> else { return }
        settings[keyPath: keyPath].toggle()
    }

    /// The reading switches, grouped like the language: "Mode: Normal" or "Mode: Faithful", with the mode as
    /// a radio choice and the three switches that shape the text under it.
    private func modeMenu() -> NSMenuItem {
        let sub = NSMenu()
        for faithful in [false, true] {
            let i = item(faithful ? tr("Faithful Mode (Code and Structure)") : tr("Normal"), #selector(setFaithful(_:)))
            i.representedObject = faithful
            i.state = settings.codeMode == faithful ? .on : .off
            sub.addItem(i)
        }
        sub.addItem(.separator())
        sub.addItem(toggle(tr("Clean Code"), \.codeClean))
        // Faithful mode ignores these two, so they are shown but unavailable.
        sub.addItem(toggle(tr("Language Correction"), \.languageCorrection, enabled: !settings.codeMode))
        sub.addItem(toggle(tr("Keep Line Breaks"), \.keepLineBreaks, enabled: !settings.codeMode))

        let parent = NSMenuItem(title: tr("Mode: %@", settings.codeMode ? tr("Faithful") : tr("Normal")),
                                action: nil, keyEquivalent: "")
        parent.submenu = sub
        return parent
    }

    @objc private func setFaithful(_ sender: NSMenuItem) {
        guard let faithful = sender.representedObject as? Bool else { return }
        settings.codeMode = faithful
    }

    private func languageMenu() -> NSMenuItem {
        let current: String
        switch settings.languages.count {
        case 0: current = tr("Automatic")
        case 1: current = languageName(settings.languages[0])
        default: current = tr("%d languages", settings.languages.count)
        }

        let sub = NSMenu()
        let auto = item(tr("Automatic"), #selector(setLanguage(_:)))
        auto.representedObject = ""
        auto.state = settings.languages.isEmpty ? .on : .off
        sub.addItem(auto)
        sub.addItem(.separator())
        for code in Recognizer.supportedLanguages {
            let i = item(languageName(code), #selector(setLanguage(_:)))
            i.representedObject = code
            i.state = settings.languages == [code] ? .on : .off
            sub.addItem(i)
        }
        sub.addItem(.separator())
        sub.addItem(item(tr("Multiple Languages…"), #selector(showPreferences)))

        let parent = NSMenuItem(title: tr("Language: %@", current), action: nil, keyEquivalent: "")
        parent.submenu = sub
        return parent
    }

    @objc private func setLanguage(_ sender: NSMenuItem) {
        guard let code = sender.representedObject as? String else { return }
        settings.languages = code.isEmpty ? [] : [code]
    }

    private func historyMenu() -> NSMenuItem {
        let sub = NSMenu()
        let recent = History.shared.items.prefix(10)
        if recent.isEmpty {
            let empty = NSMenuItem(title: tr("No Captures"), action: nil, keyEquivalent: "")
            empty.isEnabled = false
            sub.addItem(empty)
        } else {
            for text in recent {
                let oneLine = text.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\t", with: " ")
                let i = item(String(oneLine.prefix(50)) + (oneLine.count > 50 ? "…" : ""), #selector(recopy(_:)))
                i.representedObject = text
                sub.addItem(i)
            }
            sub.addItem(.separator())
            sub.addItem(item(tr("Clear History…"), #selector(clearHistory)))
        }
        let parent = NSMenuItem(title: tr("History"), action: nil, keyEquivalent: "")
        parent.submenu = sub
        return parent
    }

    @objc private func recopy(_ sender: NSMenuItem) {
        guard let text = sender.representedObject as? String else { return }
        capture.copy(text)
    }

    @objc private func clearHistory() { HistoryClearing.confirmClear() }

    @objc private func about() { AboutPanel.show() }
    @objc private func checkForUpdates() { Task { @MainActor in await UpdateAlert.run() } }

    // MARK: Detected content

    private func detectionItems() -> [NSMenuItem] {
        let found = capture.lastDetections
        guard !found.isEmpty else { return [] }

        let header = NSMenuItem(title: tr("Found in the last capture"), action: nil, keyEquivalent: "")
        header.isEnabled = false
        var items = [header]

        for detected in found.colors {
            let parent = NSMenuItem(title: detected.source, action: nil, keyEquivalent: "")
            parent.image = detected.color.swatch
            let sub = NSMenu()
            for format in detected.color.formats {
                let entry = item("\(format.name): \(format.value)", #selector(copyDetected(_:)))
                entry.representedObject = format.value
                sub.addItem(entry)
            }
            parent.submenu = sub
            items.append(parent)
        }
        for url in found.links {
            items.append(actionsItem(title: LinkPolicy.menuTitle(for: url), symbol: "link",
                                     open: (tr("Open in Browser"), url),
                                     copy: (tr("Copy Link"), url.absoluteString)))
        }
        for address in found.emails {
            guard let mailto = LinkPolicy.mailtoURL(for: address) else { continue }
            items.append(actionsItem(title: address.count > 48 ? String(address.prefix(47)) + "…" : address, symbol: "envelope",
                                     open: (tr("Write Email"), mailto),
                                     copy: (tr("Copy Address"), address)))
        }
        for number in found.phones {
            let entry = item(number, #selector(copyDetected(_:)), symbol: "phone")
            entry.representedObject = number
            entry.toolTip = tr("Copy Number")
            items.append(entry)
        }
        items.append(.separator())
        return items
    }

    private func actionsItem(title: String, symbol: String, open: (title: String, url: URL),
                             copy: (title: String, value: String)) -> NSMenuItem {
        let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        parent.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        let sub = NSMenu()
        let openItem = item(open.title, #selector(openDetected(_:)))
        openItem.representedObject = open.url
        let copyItem = item(copy.title, #selector(copyDetected(_:)))
        copyItem.representedObject = copy.value
        sub.addItem(openItem)
        sub.addItem(copyItem)
        parent.submenu = sub
        return parent
    }
}
