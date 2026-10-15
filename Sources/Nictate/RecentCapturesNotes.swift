// Nictate: a macOS menu bar app that copies text from anywhere on your screen.
// Copyright (c) 2026 jrthormann. MIT License, see LICENSE.

import SwiftUI

/// What the Recent Captures list says above, or instead of, its entries. Kept apart from the view so the rules are tested.
enum RecentCapturesNotice: Equatable {
    case nothing, loading, unavailable, savingOff, savingOffWithCaptures, noCaptures

    static func of(state: HistoryState, count: Int, historyEnabled: Bool) -> RecentCapturesNotice {
        if state == .loading { return .loading }
        if state == .unavailable { return .unavailable }
        if !historyEnabled { return count == 0 ? .savingOff : .savingOffWithCaptures }
        return count == 0 ? .noCaptures : .nothing
    }
}

/// Says why the Recent Captures list is not a plain list: loading, unreadable, or saving off with captures kept.
/// Saving off with nothing kept is said by `RecentCapturesSavingOff` instead, where the empty list would be.
struct RecentCapturesNote: View {
    @ObservedObject var model: StatusPanelModel

    var body: some View {
        switch RecentCapturesNotice.of(state: model.historyState, count: model.historyCount, historyEnabled: model.historyEnabled) {
        case .loading:
            Text(tr("Loading history…")).font(Self.noteFont).foregroundStyle(.secondary).padding(.horizontal, 10)
        case .unavailable:
            Text(tr("History is unavailable right now. New captures are still copied but won't be saved."))
                .font(Self.noteFont).foregroundStyle(.secondary).padding(.horizontal, 10)
        case .savingOffWithCaptures:
            Text(tr("Save Captures is off. New captures aren't saved."))
                .font(Self.noteFont).foregroundStyle(.secondary).padding(.horizontal, 10)
        case .nothing, .savingOff, .noCaptures:
            EmptyView()
        }
    }

    /// DESIGN.md sets 11 pt as the smallest text. macOS's caption style is 10 pt, so the size is fixed here.
    static let noteFont = Font.system(size: 11)
}

/// An empty list while saving is off: nothing was kept, which is not the same as nothing having been captured.
struct RecentCapturesSavingOff: View {
    var body: some View {
        Text(tr("Save Captures is off, so new captures aren't kept. Turn it on in the menu to keep them."))
            .font(.system(size: 13)).foregroundStyle(.secondary).multilineTextAlignment(.center)
    }
}

/// The keys a picker needs, shown once, under the list.
struct RecentCapturesHints: View {
    var body: some View {
        Text(tr("Arrow keys choose, Return copies, Escape closes"))
            .font(RecentCapturesNote.noteFont).foregroundStyle(.secondary).padding(.horizontal, 10).padding(.top, 4)
    }
}
