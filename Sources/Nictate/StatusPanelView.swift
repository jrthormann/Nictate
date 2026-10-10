// Nictate: a macOS menu bar app that copies text from anywhere on your screen.
// Copyright (c) 2026 jrthormann. MIT License, see LICENSE.

import SwiftUI

/// The menu bar panel, styled as a compact native menu. History is a second screen of the same panel.
struct StatusPanelView: View {
    @ObservedObject var model: StatusPanelModel

    var body: some View {
        Group {
            switch model.screen {
            case .main: MainScreen(model: model)
            case .history: HistoryScreen(model: model)
            }
        }
        .frame(width: Panel.width)
        .padding(.vertical, Panel.verticalInset)
        .onExitCommand(perform: escape)
    }

    /// Esc clears the search first, then goes back, then closes the panel.
    private func escape() {
        switch model.screen {
        case .history where !model.query.isEmpty: model.searchChanged("")
        case .history: model.backToMain()
        case .main: model.dismiss()
        }
    }
}

/// Sizes shared by every screen, so the rows line up as they do in a system menu.
private enum Panel {
    static let width: CGFloat = 260
    static let verticalInset: CGFloat = 6
    /// The most the main screen takes before it scrolls.
    static let maximumMainHeight: CGFloat = 520
}

private struct MainScreen: View {
    @ObservedObject var model: StatusPanelModel
    @ObservedObject private var login = LoginItem.shared

    var body: some View {
        // Scrolls when many detections are listed, so Settings and Quit stay reachable on short displays.
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 0) {
                MenuAction(tr("Capture Text"), shortcut: model.hotKeyLabel, leadingSymbol: "text.viewfinder", action: model.captureText)
                MenuAction(tr("Capture QR Code or Barcode"), shortcut: model.codeHotKeyLabel, leadingSymbol: "qrcode.viewfinder", action: model.captureCode)
                if model.historyEnabled {
                    MenuAction(tr("Cycle History"), shortcut: model.rotateHotKeyLabel, leadingSymbol: "arrow.triangle.2.circlepath", action: model.cycleHistory)
                }
                // Saved captures stay reachable while saving is off, so they can be read or deleted.
                if model.historyEnabled || model.historyCount > 0 {
                    MenuAction(tr("History"), leadingSymbol: "clock.arrow.circlepath", trailingSymbol: "chevron.right", action: model.openHistory)
                }
                MenuDivider()
                detections
                captureOptions
                MenuDivider()
                MenuToggle(tr("Save Captures"), symbol: "clock", isOn: Binding(get: { model.keepHistory }, set: { model.setKeepHistory($0) }))
                MenuToggle(tr("Launch at Login"), symbol: "power", isOn: Binding(get: { login.enabled }, set: { model.setLaunchAtLogin($0) }))
                MenuDivider()
                MenuAction(tr("Settings…"), shortcut: "⌘,", leadingSymbol: "gearshape", action: model.showPreferences)
                MenuAction(tr("About Nictate"), leadingSymbol: "info.circle", action: model.showAbout)
                MenuAction(tr("Support the Developer…"), leadingSymbol: "heart", action: model.supportDeveloper)
                MenuAction(tr("Check for Updates…"), leadingSymbol: "arrow.down.circle", action: model.checkForUpdates)
                MenuDivider()
                MenuAction(tr("Quit Nictate"), shortcut: "⌘Q", action: model.quit)
            }
            .padding(.horizontal, Panel.verticalInset)
        }
        .frame(maxHeight: Panel.maximumMainHeight)
    }

    @ViewBuilder private var detections: some View {
        let found = model.lastDetections
        if !found.isEmpty {
            Text(tr("Found in the last capture"))
                .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 10).padding(.top, 4)
            ForEach(Array(found.colors.enumerated()), id: \.offset) { _, detected in
                Menu {
                    ForEach(Array(detected.color.formats.enumerated()), id: \.offset) { _, format in
                        Button("\(format.name): \(format.value)") { model.copyDetected(format.value) }
                    }
                } label: {
                    MenuLine(detected.source, swatch: detected.color.swatch, trailingSymbol: "chevron.right")
                }
                .menuStyle(.button).menuIndicator(.hidden).buttonStyle(.plain)
            }
            ForEach(found.links, id: \.self) { url in
                Menu {
                    Button(tr("Open in Browser")) { model.openDetected(url) }
                    Button(tr("Copy Link")) { model.copyDetected(url.absoluteString) }
                } label: {
                    MenuLine(LinkPolicy.menuTitle(for: url), leadingSymbol: "link", trailingSymbol: "chevron.right")
                }
                .menuStyle(.button).menuIndicator(.hidden).buttonStyle(.plain)
            }
            ForEach(found.emails, id: \.self) { address in
                Menu {
                    if let mailto = LinkPolicy.mailtoURL(for: address) {
                        Button(tr("Write Email")) { model.openDetected(mailto) }
                    }
                    Button(tr("Copy Address")) { model.copyDetected(address) }
                } label: {
                    MenuLine(address, leadingSymbol: "envelope", trailingSymbol: "chevron.right")
                }
                .menuStyle(.button).menuIndicator(.hidden).buttonStyle(.plain)
            }
            ForEach(found.phones, id: \.self) { number in
                MenuAction(number, leadingSymbol: "phone") { model.copyDetected(number) }
            }
            MenuDivider()
        }
    }

    /// Mode, language and append mode: the settings that change how a capture is read.
    private var captureOptions: some View {
        VStack(alignment: .leading, spacing: 0) {
            Menu {
                Button { model.setFaithful(false) } label: { CheckLabel(tr("Normal"), checked: !model.codeMode) }
                Button { model.setFaithful(true) } label: { CheckLabel(tr("Faithful Mode (Code and Structure)"), checked: model.codeMode) }
            } label: {
                MenuLine(tr("Mode"), value: model.codeMode ? tr("Faithful") : tr("Normal"), leadingSymbol: "slider.horizontal.3", trailingSymbol: "chevron.right")
            }
            .menuStyle(.button).menuIndicator(.hidden).buttonStyle(.plain)
            Menu {
                Button { model.setLanguage("") } label: { CheckLabel(tr("Automatic"), checked: model.languages.isEmpty) }
                Divider()
                ForEach(model.supportedLanguages, id: \.self) { code in
                    Button { model.setLanguage(code) } label: {
                        CheckLabel(languageName(code), checked: model.languages == [code])
                    }
                }
                Divider()
                Button(tr("Multiple Languages…"), action: model.showPreferences)
            } label: {
                MenuLine(tr("Language"), value: languageTitle, leadingSymbol: "globe", trailingSymbol: "chevron.right")
            }
            .menuStyle(.button).menuIndicator(.hidden).buttonStyle(.plain)
            MenuToggle(tr("Append Mode"), symbol: "text.append", isOn: Binding(get: { model.appendMode }, set: { model.appendMode = $0 }))
        }
    }

    private var languageTitle: String {
        switch model.languages.count {
        case 0: tr("Automatic")
        case 1: languageName(model.languages[0])
        default: tr("%d languages", model.languages.count)
        }
    }
}

private struct HistoryScreen: View {
    @ObservedObject var model: StatusPanelModel
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MenuAction(tr("Back"), leadingSymbol: "chevron.left", action: model.backToMain)
            MenuDivider()
            TextField(tr("Search history"), text: Binding(get: { model.query }, set: { model.searchChanged($0) }))
                .textFieldStyle(.roundedBorder)
                .focused($searchFocused)
                .onKeyPress(.downArrow) { model.moveSelection(by: 1); return .handled }
                .onKeyPress(.upArrow) { model.moveSelection(by: -1); return .handled }
                .onSubmit { model.copySelected() }
                .padding(.horizontal, 10).padding(.vertical, 4)
            stateNote
            if let copyError = model.copyError {
                Text(copyError).font(.caption).foregroundStyle(.red).padding(.horizontal, 10)
            }
            content
            if model.historyCount > 0 {
                MenuDivider()
                MenuAction(tr("Clear History…"), destructive: true, action: model.clearHistory)
            }
        }
        .padding(.horizontal, Panel.verticalInset)
        .onAppear { searchFocused = true }
        .onChange(of: model.searchFocusRequests) { _, _ in searchFocused = true }
    }

    /// Says when the saved captures are not shown, so an empty list is never mistaken for an empty history.
    @ViewBuilder private var stateNote: some View {
        switch model.historyState {
        case .loading:
            Text(tr("Loading history…")).font(.caption).foregroundStyle(.secondary).padding(.horizontal, 10)
        case .unavailable:
            Text(tr("History is unavailable right now. New captures are still copied but won't be saved."))
                .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 10)
        case .available, .disabled:
            EmptyView()
        }
    }

    @ViewBuilder private var content: some View {
        let entries = model.entries
        // While the history loads, or cannot be read, the note above says so: "No captures yet" would be false.
        let waiting = model.historyCount == 0 && [HistoryState.loading, .unavailable].contains(model.historyState)
        if waiting {
            EmptyView()
        } else if model.historyCount == 0 {
            VStack(spacing: 4) {
                Text(tr("No captures yet")).font(.headline)
                Text(tr("Press %@, then drag to select an area.", model.hotKeyLabel))
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 20)
        } else if entries.isEmpty {
            Text(tr("No matches")).font(.callout).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity).padding(.vertical, 20)
        } else {
            // The highlighted row is kept in view as the arrow keys move it.
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(entries.enumerated()), id: \.element.text) { index, entry in
                            CaptureRow(text: entry.text, date: entry.date, selected: model.selection == index,
                                       copy: { model.copyCapture(entry.text) },
                                       delete: { model.deleteCapture(entry.text) })
                                .id(index)
                        }
                    }
                }
                .frame(maxHeight: 280)
                .onChange(of: model.selection) { _, index in
                    if let index { proxy.scrollTo(index) }
                }
            }
        }
    }
}

/// One capture: a click copies the whole text. The trash button removes only this entry.
private struct CaptureRow: View {
    private var highlighted: Bool { selected || hover.on }

    let text: String
    let date: Date
    var selected = false
    let copy: () -> Void
    let delete: () -> Void
    @StateObject private var hover = HoverFlag()

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            Button(action: copy) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(text.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\t", with: " "))
                        .lineLimit(2).truncationMode(.tail)
                    if let age = History.ageLabel(for: date) {
                        Text(age).font(.caption).foregroundStyle(highlighted ? Color.white.opacity(0.85) : .secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(tr("Copies the whole capture"))
            .accessibilityAction(named: tr("Copy")) { copy() }
            Button(action: delete) { Image(systemName: "trash").font(.caption) }
                .buttonStyle(.borderless)
                .accessibilityLabel(tr("Delete"))
        }
        .foregroundStyle(highlighted ? Color.white : Color.primary)
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 5).fill(highlighted ? Color.accentColor : .clear))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .onHover { hover.on = $0 }
        .contextMenu {
            Button(tr("Copy"), action: copy)
            Button(tr("Delete"), role: .destructive, action: delete)
        }
    }
}

/// Whether the pointer is over a row. An object rather than `@State`, whose macro needs a toolchain this project's
/// build does not use.
@MainActor private final class HoverFlag: ObservableObject {
    @Published var on = false
}

/// A menu entry with a check mark when it is the current choice.
private struct CheckLabel: View {
    let title: String
    let checked: Bool

    init(_ title: String, checked: Bool) {
        self.title = title
        self.checked = checked
    }

    var body: some View {
        HStack {
            Text(title)
            if checked { Image(systemName: "checkmark") }
        }
    }
}

private struct MenuDivider: View {
    var body: some View {
        Divider().padding(.horizontal, 10).padding(.vertical, 4)
    }
}

/// The visual line of a menu entry. It highlights in the accent colour on hover, as a system menu does.
/// Used as a button's content, or as the label of a `Menu`.
private struct MenuLine: View {
    let title: String
    var value: String?
    var swatch: NSImage?
    var leadingSymbol: String?
    var trailingSymbol: String?
    var destructive = false
    @StateObject private var hover = HoverFlag()

    init(_ title: String, value: String? = nil, swatch: NSImage? = nil, leadingSymbol: String? = nil,
         trailingSymbol: String? = nil, destructive: Bool = false) {
        self.title = title
        self.value = value
        self.swatch = swatch
        self.leadingSymbol = leadingSymbol
        self.trailingSymbol = trailingSymbol
        self.destructive = destructive
    }

    /// Reserved even without an icon, so every label in the menu starts at the same x position.
    private static let iconColumn: CGFloat = 16

    @ViewBuilder private var leading: some View {
        if let swatch { Image(nsImage: swatch).resizable().frame(width: 12, height: 12).clipShape(Circle()) }
        else if let leadingSymbol { Image(systemName: leadingSymbol) }
    }

    var body: some View {
        HStack(spacing: 8) {
            leading.frame(width: Self.iconColumn)
            Text(title).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 12)
            if let value { Text(value).foregroundStyle(hover.on ? Color.white.opacity(0.85) : .secondary) }
            if let trailingSymbol { Image(systemName: trailingSymbol).font(.caption.weight(.semibold)) }
        }
        .foregroundStyle(hover.on ? Color.white : (destructive ? Color.red : Color.primary))
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 5).fill(hover.on ? Color.accentColor : .clear))
        .contentShape(Rectangle())
        .onHover { hover.on = $0 }
    }
}

/// A full-width menu action. Its shortcut or symbol sits at the trailing edge.
private struct MenuAction: View {
    let title: String
    var shortcut: String?
    var leadingSymbol: String?
    var trailingSymbol: String?
    var destructive = false
    let action: () -> Void

    init(_ title: String, shortcut: String? = nil, leadingSymbol: String? = nil, trailingSymbol: String? = nil,
         destructive: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.shortcut = shortcut
        self.leadingSymbol = leadingSymbol
        self.trailingSymbol = trailingSymbol
        self.destructive = destructive
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            MenuLine(title, value: shortcut, leadingSymbol: leadingSymbol, trailingSymbol: trailingSymbol, destructive: destructive)
        }
        .buttonStyle(.plain)
    }
}

/// A menu entry that shows a check mark when it is on, the way a system menu shows a choice.
private struct MenuToggle: View {
    let title: String
    var symbol: String?
    @Binding var isOn: Bool

    init(_ title: String, symbol: String? = nil, isOn: Binding<Bool>) {
        self.title = title
        self.symbol = symbol
        self._isOn = isOn
    }

    var body: some View {
        Button { isOn.toggle() } label: {
            MenuLine(title, leadingSymbol: symbol, trailingSymbol: isOn ? "checkmark" : nil)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
