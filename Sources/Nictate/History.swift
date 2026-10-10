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

/// Whether the history can be read and written right now.
/// `loading` covers the time the key may take to authorize; nothing is written during it.
/// `unavailable` means the file or key could not be read: captures stay in memory and nothing on disk changes.
enum HistoryState: Equatable {
    case loading, available, disabled, locked, unavailable
}

/// Last captured texts, newest first, each with the time it was captured. Kept in the sealed `HistoryStore`.
@MainActor
final class History: ObservableObject {
    /// The app's history. It loads in the background (see `refresh`), never on the main thread.
    static let shared = History(loadsNow: false)
    private let limit = 50
    /// Longer captures are still copied but not kept: the whole history lives in one preferences file
    /// that is rewritten on every capture. A screen of text is a few thousand characters.
    static let maxStoredLength = 100_000

    @Published private(set) var items: [String]
    /// The capture time of each item, same order and length. `.distantPast` means unknown (captures saved
    /// before times were kept).
    @Published private(set) var dates: [Date]
    @Published private(set) var state: HistoryState
    @Published var query = ""

    var filtered: [String] {
        query.isEmpty ? items : items.filter { $0.localizedCaseInsensitiveContains(query) }
    }

    private let store: any HistoryStore
    /// Removals made while the file could not be read. They are applied to the file once it can be read, so
    /// a deletion is not undone by the older copy on disk.
    private var pendingRemovals: Set<String> = []
    private var pendingClear = false
    /// True from the start of a read until its result is applied, so a second refresh does not read again.
    private var loadInFlight = false
    /// The retention the user chose, read each time captures are pruned.
    private let retention: @MainActor () -> HistoryRetention
    /// Whether the history is switched on. Read by `refresh`, so a disabled history never touches the Keychain.
    private let isEnabled: @MainActor () -> Bool

    /// Every file operation runs here, serially and off the main thread, so a Keychain prompt cannot freeze
    /// the menu bar and writes happen in the order they were made.
    private static let io = DispatchQueue(label: "app.nictate.history.io", qos: .utility)

    /// The app uses `shared`, with the sealed file, the standard defaults and the retention in `Settings`.
    /// Tests pass a store and a retention of their own, so they never touch the user's captures. With
    /// `loadsNow` the file is read at once, on the calling thread; the app loads in the background instead.
    init(store: any HistoryStore = EncryptedHistoryStore.standard,
         retention: @escaping @MainActor () -> HistoryRetention = { Settings.shared.historyRetention },
         isEnabled: @escaping @MainActor () -> Bool = { Settings.shared.historyEnabled },
         loadsNow: Bool = true) {
        self.store = store
        self.retention = retention
        self.isEnabled = isEnabled
        items = []
        dates = []
        state = .loading
        if loadsNow { apply(store.load()) }
    }

    /// Starts or retries loading. Called at launch, when the panel opens, and when Keep History is turned on.
    /// Does nothing while the history is switched off, so no Keychain access happens for it.
    @discardableResult func refresh() -> Task<Void, Never>? {
        guard isEnabled() else {
            state = .disabled
            return nil
        }
        guard state != .available, !loadInFlight else { return nil }
        loadInFlight = true
        state = .loading
        return Task { await reload() }
    }

    /// Reads the file and key on the I/O queue, then applies the result here on the main actor.
    func reload() async {
        let store = self.store
        let result = await withCheckedContinuation { (continuation: CheckedContinuation<HistoryLoad, Never>) in
            Self.io.async { continuation.resume(returning: store.load()) }
        }
        apply(result)
    }

    /// Waits until every queued write has finished. Tests use it before reading the file back.
    static func flushWrites() {
        io.sync {}
    }

    /// Applies what a load found. Captures taken meanwhile are merged with the file, so neither side is lost.
    private func apply(_ result: HistoryLoad) {
        loadInFlight = false
        var changed = false
        switch result {
        case .loaded(let stored):
            var texts = stored.texts
            var times = Self.alignedDates(count: stored.texts.count, stored: stored.dates)
            let kept = zip(texts, times).filter { !pendingRemovals.contains($0.0) }
            texts = pendingClear ? [] : kept.map(\.0)
            times = pendingClear ? [] : kept.map(\.1)
            changed = texts.count != stored.texts.count
            let fresh = zip(items, dates).filter { !texts.contains($0.0) && !pendingRemovals.contains($0.0) }
            changed = changed || !fresh.isEmpty
            items = Array((fresh.map(\.0) + texts).prefix(limit))
            dates = Array((fresh.map(\.1) + times).prefix(limit))
        case .empty:
            // No file yet: the captures in memory are the whole history. Nothing is written when there are none.
            let kept = zip(items, dates).filter { !pendingRemovals.contains($0.0) }
            changed = !kept.isEmpty
            items = Array(kept.map(\.0).prefix(limit))
            dates = Array(kept.map(\.1).prefix(limit))
        case .locked, .corrupt, .unavailable:
            // Nothing is kept in memory and nothing is written: the file is the user's, and an unreadable one is not
            // empty. Removals stay pending until the file can be read again.
            state = result == .locked ? .locked : .unavailable
            items = []
            dates = []
            return
        }
        pendingRemovals = []
        pendingClear = false
        state = .available
        if changed { save() }
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

    /// Keeps a capture in the history. Only while the history is available: a locked, loading, disabled or
    /// unavailable history keeps no plaintext copy and no queue. The clipboard copy happens regardless.
    func add(_ text: String, at date: Date = Date()) {
        guard state == .available else { return }
        guard text.count <= Self.maxStoredLength else { return }
        // Whitespace-only text is never kept. Valid text is stored exactly as captured, with its spaces.
        guard !text.allSatisfy(\.isWhitespace) else { return }
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
        pendingRemovals.insert(text)
        let kept = zip(items, dates).filter { $0.0 != text }
        items = kept.map(\.0)
        dates = kept.map(\.1)
        save()
    }

    func clear() {
        pendingClear = true
        items = []
        dates = []
        save()
    }

    /// Writes the history when it is known to be readable. While it is loading or unavailable nothing is written.
    private func save() {
        guard state == .available else { return }
        let snapshot = HistorySnapshot(texts: items, dates: dates.map(\.timeIntervalSince1970))
        let store = self.store
        Self.io.async { [weak self] in
            guard store.save(snapshot) else {
                Log.app.error("History was not saved; the unsaved captures are dropped and the file is unchanged")
                Task { @MainActor in self?.persistenceFailed() }
                return
            }
        }
    }

    /// A write failed: the captures that were not saved are dropped from memory, not kept as a pending copy,
    /// and the history reports itself unavailable until it can be read again.
    /// Available means a save can succeed, not that the file is in memory. When a write fails, the capture that
    /// was shown is dropped, the state drops to unavailable, and the history is read again from the file: the
    /// saved entries come back as they were, and the new capture is never reported as saved.
    private func persistenceFailed() {
        items = []
        dates = []
        state = .unavailable
        refresh()
    }
}
