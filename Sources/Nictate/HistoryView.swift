// Nictate: a macOS menu bar app that copies text from anywhere on your screen.
// Copyright (c) 2026 jrthormann. MIT License, see LICENSE.

import AppKit
import SwiftUI

private extension View {
    /// ⌘F focuses the search field on macOS 15 and later. On macOS 14 `searchFocused` does not exist, so the
    /// field is reached with the pointer or Tab; the view still works.
    @ViewBuilder func focusSearch(_ isFocused: FocusState<Bool>.Binding) -> some View {
        if #available(macOS 15.0, *) {
            searchFocused(isFocused)
        } else {
            self
        }
    }
}

/// The selected row. An object rather than `@State`, whose macro needs a toolchain this project's
/// command-line build does not have.
private final class HistorySelection: ObservableObject {
    @Published var text: String?
}

struct HistoryView: View {
    @ObservedObject private var history = History.shared
    @StateObject private var selection = HistorySelection()
    @FocusState private var searchFocused: Bool

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(tr("History"))
                .searchable(text: $history.query, placement: .toolbar, prompt: Text("Search"))
                .focusSearch($searchFocused)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Clear History…") { HistoryClearing.confirmClear(history) }
                            .disabled(history.items.isEmpty)
                    }
                }
        }
        .frame(minWidth: Design.Size.history.width, minHeight: Design.Size.history.height)
        .background(shortcuts)
        .onAppear { history.pruneExpired() }
        // ⌘F is the main menu's Find…, which asks only while this window is key.
        .onReceive(NotificationCenter.default.publisher(for: MainMenu.findRequested)) { _ in searchFocused = true }
    }

    /// Three states, each native: no captures yet, no match for the search, or the list.
    @ViewBuilder private var content: some View {
        if history.items.isEmpty {
            ContentUnavailableView {
                Label("No captures yet", systemImage: "clock.arrow.circlepath")
            } description: {
                Text("Press ⇧⌘2 and drag over any text.")
            }
        } else if history.filtered.isEmpty {
            ContentUnavailableView.search(text: history.query)
        } else {
            List(history.filtered, id: \.self, selection: $selection.text) { text in
                row(text)
                    .contextMenu {
                        Button("Copy") { copy(text) }
                        Divider()
                        Button("Delete", role: .destructive) { remove(text) }
                    }
            }
            .onDeleteCommand { if let text = selection.text { remove(text) } }
        }
    }

    private func row(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Design.Space.compact) {
            VStack(alignment: .leading, spacing: Design.Space.tight) {
                Text(text).lineLimit(4)
                if let label = history.date(for: text).flatMap({ History.ageLabel(for: $0) }) {
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(Design.Ink.text(.standard))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button("Copy") { copy(text) }
                .controlSize(.small)
            Button { remove(text) } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless)
                .help("Delete")
                .accessibilityLabel("Delete")
        }
        .padding(.vertical, Design.Space.tight)
    }

    private func remove(_ text: String) {
        if selection.text == text { selection.text = nil }
        history.remove(text)
    }

    /// Return copies the selected capture, or the first match when nothing is selected, so typing a few
    /// letters and pressing Return is enough.
    private var shortcuts: some View {
        Button("") { if let text = selection.text ?? history.filtered.first { copy(text) } }
            .keyboardShortcut(.defaultAction)
            .frame(width: 0, height: 0)
            .opacity(0)
            .accessibilityHidden(true)
    }

    private func copy(_ text: String) {
        ClipboardWriter.shared.write(text)
    }
}
