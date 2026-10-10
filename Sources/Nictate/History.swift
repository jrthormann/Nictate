// Nictate: a macOS menu bar app that copies text from anywhere on your screen.
// Copyright (c) 2026 jrthormann. MIT License, see LICENSE.

import Combine
import Foundation

/// How long captures are kept: never, an hour, a day or a week.
enum HistoryRetention: String, CaseIterable {
    case never, hour, day, week

    /// Nil means captures never expire.
    var seconds: TimeInterval? {
        switch self {
        case .never: return nil
        case .hour: return 3_600
        case .day: return 86_400
        case .week: return 604_800
        }
    }
}

/// Last captured texts, newest first, each with the time it was captured. Kept in the sealed `HistoryStore`.
@MainActor
final class History: ObservableObject {
    static let shared = History()
    private let limit = 50
    /// Longer captures are still copied but not kept: the whole history lives in one preferences file
    /// that is rewritten on every capture. A screen of text is a few thousand characters.
    static let maxStoredLength = 100_000

    @Published private(set) var items: [String]
    /// The capture time of each item, same order and length. `.distantPast` means unknown (captures saved
    /// before times were kept).
    @Published private(set) var dates: [Date]
    @Published var query = ""

    var filtered: [String] {
        query.isEmpty ? items : items.filter { $0.localizedCaseInsensitiveContains(query) }
    }

    private let store: any HistoryStore
    /// False while the key is unavailable: saving then would replace a file that may still be readable.
    private var mayWrite = true
    /// The retention the user chose, read each time captures are pruned.
    private let retention: @MainActor () -> HistoryRetention

    /// The app uses `shared`, with the sealed file, the standard defaults and the retention in `Settings`.
    /// Tests pass a store and a retention of their own, so they never touch the user's captures.
    init(store: any HistoryStore = EncryptedHistoryStore.standard,
         retention: @escaping @MainActor () -> HistoryRetention = { Settings.shared.historyRetention }) {
        self.store = store
        self.retention = retention
        let snapshot: HistorySnapshot
        switch store.load() {
        case .loaded(let stored):
            snapshot = stored
        case .empty, .corrupt:
            snapshot = .empty
        case .unavailable:
            snapshot = .empty
            mayWrite = false
        }
        items = snapshot.texts
        dates = Self.alignedDates(count: snapshot.texts.count, stored: snapshot.dates)
    }

    /// Tries the store again once the key may be back. Captures taken while it was unavailable are merged with
    /// what the file holds, so neither side is lost.
    private func reopen() {
        switch store.load() {
        case .unavailable:
            return
        case .loaded(let stored):
            let known = Set(stored.texts)
            let fresh = zip(items, dates).filter { !known.contains($0.0) }
            items = Array((fresh.map(\.0) + stored.texts).prefix(limit))
            dates = Array((fresh.map(\.1) + Self.alignedDates(count: stored.texts.count, stored: stored.dates)).prefix(limit))
        case .empty, .corrupt:
            break
        }
        mayWrite = true
    }

    /// Times that line up with `count` texts. If the stored list is not the same length it cannot be trusted
    /// to belong to these texts, so every time is unknown rather than risk showing the wrong one.
    static func alignedDates(count: Int, stored: [Double]) -> [Date] {
        stored.count == count
            ? stored.map { Date(timeIntervalSince1970: $0) }
            : Array(repeating: .distantPast, count: count)
    }

    /// "5 min. ago" style text for a capture time, or nil when the time is unknown.
    static func ageLabel(for date: Date, now: Date = Date(), locale: Locale = .current) -> String? {
        guard date != .distantPast else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        formatter.dateTimeStyle = .named
        formatter.locale = locale
        return formatter.localizedString(for: date, relativeTo: now)
    }

    func date(for text: String) -> Date? {
        guard let index = items.firstIndex(of: text), dates[index] != .distantPast else { return nil }
        return dates[index]
    }

    func add(_ text: String, at date: Date = Date()) {
        guard text.count <= Self.maxStoredLength else { return }
        let kept = zip(items, dates).filter { $0.0 != text }
        items = Array(([text] + kept.map(\.0)).prefix(limit))
        dates = Array(([date] + kept.map(\.1)).prefix(limit))
        save()
    }

    /// Removes captures older than `limit` seconds. A capture with an unknown time (saved before times were
    /// kept) stays: its age cannot be judged.
    func prune(olderThan limit: TimeInterval?, now: Date = Date()) {
        guard let limit else { return }
        let kept = zip(items, dates).filter { $0.1 == .distantPast || now.timeIntervalSince($0.1) <= limit }
        guard kept.count != items.count else { return }
        items = kept.map(\.0)
        dates = kept.map(\.1)
        save()
    }

    /// Applies the retention the user chose.
    func pruneExpired(now: Date = Date()) {
        prune(olderThan: retention().seconds, now: now)
    }

    func remove(_ text: String) {
        let kept = zip(items, dates).filter { $0.0 != text }
        items = kept.map(\.0)
        dates = kept.map(\.1)
        save()
    }

    func clear() {
        items = []
        dates = []
        save()
    }

    private func save() {
        if !mayWrite { reopen() }
        guard mayWrite else { return }
        if !store.save(HistorySnapshot(texts: items, dates: dates.map(\.timeIntervalSince1970))) {
            Log.app.error("History was not saved; it is kept for this session only")
        }
    }
}
