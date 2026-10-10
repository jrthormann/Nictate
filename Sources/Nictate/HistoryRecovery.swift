// Nictate: a macOS menu bar app that copies text from anywhere on your screen.
// Copyright (c) 2026 jrthormann. MIT License, see LICENSE.

import SwiftUI

/// What the History screen says when its file cannot be used as it is. An unreadable file offers the one explicit
/// discard; a history closed by a refused deletion says it needs a restart. Nothing is shown in other cases.
struct HistoryRecoveryNotes: View {
    @ObservedObject var model: StatusPanelModel

    var body: some View {
        if model.historyFileUnreadable {
            Text(tr("Your saved captures can't be loaded from this file.")).font(.caption).foregroundStyle(.secondary).padding(.horizontal, 10)
            MenuAction(tr("Discard Unreadable History…"), destructive: true, action: model.discardUnreadableHistory)
        }
        if model.historyClosed {
            Text(tr("Restart Nictate to change saved captures again.")).font(.caption).foregroundStyle(.secondary).padding(.horizontal, 10)
        }
    }
}
