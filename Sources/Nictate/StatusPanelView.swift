// Nictate: a macOS menu bar app that copies text from anywhere on your screen.
// Copyright (c) 2026 jrthormann. MIT License, see LICENSE.

import SwiftUI

/// The menu bar panel: the main screen with every action, and the history as a second screen of the same panel.
struct StatusPanelView: View {
    @ObservedObject var model: StatusPanelModel

    var body: some View {
        Group {
            switch model.screen {
            case .main: MainScreen(model: model)
            case .history: HistoryScreen(model: model)
            }
        }
        .frame(width: 300)
        .padding(.vertical, 8)
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

private struct MainScreen: View {
    @ObservedObject var model: StatusPanelModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PanelRow(tr("Capture Text"), symbol: "text.viewfinder", shortcut: model.hotKeyLabel, action: model.captureText)
            PanelRow(tr("Capture QR Code or Barcode"), symbol: "qrcode.viewfinder", shortcut: model.codeHotKeyLabel, action: model.captureCode)
            if model.historyEnabled {
                PanelRow(tr("Cycle History"), symbol: "arrow.triangle.2.circlepath", shortcut: model.rotateHotKeyLabel, action: model.cycleHistory)
            }
            Divider().padding(.vertical, 4)
            detections
            modeAndLanguage
            Toggle(tr("Append Mode"), isOn: Binding(get: { model.appendMode }, set: { model.appendMode = $0 }))
                .toggleStyle(.switch).controlSize(.small).padding(.horizontal, 12).padding(.vertical, 4)
            Divider().padding(.vertical, 4)
            if model.historyEnabled {
                PanelRow(tr("History"), symbol: "clock.arrow.circlepath", badge: "\(model.historyCount)") { model.screen = .history }
            }
            PanelRow(tr("Settings…"), symbol: "gearshape", shortcut: "⌘,", action: model.showPreferences)
            PanelRow(tr("About Nictate"), symbol: "info.circle", action: model.showAbout)
            PanelRow(tr("Check for Updates…"), symbol: "arrow.down.circle", action: model.checkForUpdates)
            PanelRow(tr("Quit Nictate"), symbol: "power", shortcut: "⌘Q", action: model.quit)
        }
    }

    @ViewBuilder private var detections: some View {
        let found = model.lastDetections
        if !found.isEmpty {
            Text(tr("Found in the last capture"))
                .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 12).padding(.top, 2)
            ForEach(Array(found.colors.enumerated()), id: \.offset) { _, detected in
                Menu {
                    ForEach(Array(detected.color.formats.enumerated()), id: \.offset) { _, format in
                        Button("\(format.name): \(format.value)") { model.copyDetected(format.value) }
                    }
                } label: {
                    Label { Text(detected.source) } icon: { Image(nsImage: detected.color.swatch) }
                }
                .menuStyle(.borderlessButton).padding(.horizontal, 12).padding(.vertical, 3)
            }
            ForEach(found.links, id: \.self) { url in
                Menu {
                    Button(tr("Open in Browser")) { model.openDetected(url) }
                    Button(tr("Copy Link")) { model.copyDetected(url.absoluteString) }
                } label: { Label(LinkPolicy.menuTitle(for: url), systemImage: "link") }
                .menuStyle(.borderlessButton).padding(.horizontal, 12).padding(.vertical, 3)
            }
            ForEach(found.emails, id: \.self) { address in
                Menu {
                    if let mailto = LinkPolicy.mailtoURL(for: address) {
                        Button(tr("Write Email")) { model.openDetected(mailto) }
                    }
                    Button(tr("Copy Address")) { model.copyDetected(address) }
                } label: { Label(address, systemImage: "envelope") }
                .menuStyle(.borderlessButton).padding(.horizontal, 12).padding(.vertical, 3)
            }
            ForEach(found.phones, id: \.self) { number in
                PanelRow(number, symbol: "phone") { model.copyDetected(number) }
            }
            Divider().padding(.vertical, 4)
        }
    }

    private var modeAndLanguage: some View {
        VStack(alignment: .leading, spacing: 0) {
            Menu {
                Button { model.setFaithful(false) } label: { CheckLabel(tr("Normal"), checked: !model.codeMode) }
                Button { model.setFaithful(true) } label: { CheckLabel(tr("Faithful Mode (Code and Structure)"), checked: model.codeMode) }
            } label: { Text(tr("Mode: %@", model.codeMode ? tr("Faithful") : tr("Normal"))) }
            .menuStyle(.borderlessButton).padding(.horizontal, 12).padding(.vertical, 3)
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
            } label: { Text(tr("Language: %@", languageTitle)) }
            .menuStyle(.borderlessButton).padding(.horizontal, 12).padding(.vertical, 3)
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
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button(action: model.backToMain) { Label(tr("Back"), systemImage: "chevron.left") }
                    .buttonStyle(.borderless)
                Spacer()
                Text(tr("History")).font(.headline)
                Spacer()
            }
            .padding(.horizontal, 12)
            TextField(tr("Search history"), text: Binding(get: { model.query }, set: { model.searchChanged($0) }))
                .textFieldStyle(.roundedBorder)
                .focused($searchFocused)
                .onKeyPress(.downArrow) { model.moveSelection(by: 1); return .handled }
                .onKeyPress(.upArrow) { model.moveSelection(by: -1); return .handled }
                .onSubmit { model.copySelected() }
                .padding(.horizontal, 12)
            stateNote
            if let copyError = model.copyError {
                Text(copyError).font(.caption).foregroundStyle(.red).padding(.horizontal, 12)
            }
            content
            if model.historyCount > 0 {
                Button(tr("Clear History…"), role: .destructive, action: model.clearHistory)
                    .buttonStyle(.borderless).font(.caption).padding(.horizontal, 12)
            }
        }
        .onAppear { searchFocused = true }
    }

    /// Says when the saved captures are not shown, so an empty list is never mistaken for an empty history.
    @ViewBuilder private var stateNote: some View {
        switch model.historyState {
        case .loading:
            Text(tr("Loading history…")).font(.caption).foregroundStyle(.secondary).padding(.horizontal, 12)
        case .unavailable:
            Text(tr("History is unavailable right now. New captures are still copied but won't be saved."))
                .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 12)
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
            .frame(maxWidth: .infinity).padding(.vertical, 24)
        } else if entries.isEmpty {
            Text(tr("No matches")).font(.callout).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity).padding(.vertical, 24)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(entries.enumerated()), id: \.element.text) { index, entry in
                        CaptureRow(text: entry.text, date: entry.date, selected: model.selection == index,
                                   copy: { model.copyCapture(entry.text) },
                                   delete: { model.deleteCapture(entry.text) })
                    }
                }
            }
            .frame(maxHeight: 300)
        }
    }
}

private struct CaptureRow: View {
    let text: String
    let date: Date
    var selected = false
    let copy: () -> Void
    let delete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Button(action: copy) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(text.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\t", with: " "))
                        .lineLimit(2).truncationMode(.tail)
                    if let age = History.ageLabel(for: date) {
                        Text(age).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(tr("Copies the whole capture"))
            .accessibilityAction(named: tr("Copy")) { copy() }
            Button(action: delete) { Image(systemName: "trash") }
                .buttonStyle(.borderless).foregroundStyle(selected ? Color.white : Color.secondary)
                .accessibilityLabel(tr("Delete"))
        }
        .foregroundStyle(selected ? Color.white : Color.primary)
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 5).fill(selected ? Color.accentColor : .clear).padding(.horizontal, 4))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .contextMenu {
            Button(tr("Copy"), action: copy)
            Button(tr("Delete"), role: .destructive, action: delete)
        }
    }
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

private struct PanelRow: View {
    let title: String
    let symbol: String
    var shortcut: String?
    var badge: String?
    let action: () -> Void

    init(_ title: String, symbol: String, shortcut: String? = nil, badge: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.symbol = symbol
        self.shortcut = shortcut
        self.badge = badge
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol).frame(width: 18).foregroundStyle(.secondary)
                Text(title)
                Spacer()
                if let badge { Text(badge).font(.caption).foregroundStyle(.secondary) }
                if let shortcut { Text(shortcut).font(.caption).foregroundStyle(.secondary) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12).padding(.vertical, 4)
    }
}
