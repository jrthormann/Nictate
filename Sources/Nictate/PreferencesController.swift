// Nictate: a macOS menu bar app that copies text from anywhere on your screen.
// Copyright (c) 2026 jrthormann. MIT License, see LICENSE.

import AppKit
import SwiftUI

/// Settings window content: tabs in the toolbar (icon over label, the System Settings idiom). The window
/// resizes to fit each tab.
final class PreferencesController: NSTabViewController {
    init() {
        super.init(nibName: nil, bundle: nil)
        tabStyle = .toolbar
        transitionOptions = []
        addTab(tr("General"), symbol: "gearshape", GeneralTab())
        addTab(tr("Recognition"), symbol: "text.viewfinder", RecognitionTab())
        addTab(tr("Output"), symbol: "square.and.arrow.up", OutputTab())
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    private func addTab<Page: View>(_ label: String, symbol: String, _ page: Page) {
        let pane = PageController(page)
        pane.title = label   // the window shows the name of the selected tab, as System Settings does
        let item = NSTabViewItem(viewController: pane)
        item.label = label
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        addTabViewItem(item)
    }
}

/// Hosts one settings page. The window takes the page's ideal height, so each tab fits its content; the
/// page scrolls itself only when the window is capped by the screen.
private final class PageController: NSHostingController<AnyView> {
    init<Page: View>(_ page: Page) {
        super.init(rootView: AnyView(page))
        sizingOptions = [.preferredContentSize]
    }

    @available(*, unavailable)
    @MainActor required dynamic init?(coder: NSCoder) { fatalError("not used") }
}
