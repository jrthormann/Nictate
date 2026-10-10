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
/// `available` means a save can succeed: the file was read and the last write, if any, was saved.
/// `loading` covers the time the file takes to read; nothing is written during it.
/// `unavailable` keeps nothing new and never writes over the file.
enum HistoryState: Equatable {
    case loading, available, disabled, unavailable
}

/// Last captured texts, newest first, each with the time it was captured. Kept in the sealed `HistoryStore`.
///
/// Persist first, publish after success: `items` and `dates` only ever hold entries that the file already holds.
/// A change is written in full on one serial queue, and it becomes visible only when its write has succeeded.
/// An older write never replaces a newer one, because a write is published only if it is the newest that succeeded.
@MainActor
final class History: ObservableObject {
    /// The app's history. It loads in the background (see `refresh`), never on the main thread.
    static let shared = History(store: AppHistoryStore.make(), loadsNow: false)
    /// Longer captures are still copied but not kept: the whole history lives in one preferences file
    /// that is rewritten on every capture. A screen of text is a few thousand characters.
    static let maxStoredLength = 100_000

    /// What the History interface shows. Each entry is already in the encrypted file.
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
    /// What the file should hold once the writes in flight are done. Changes are built here and published later.
    private var intendedTexts: [String] = []
    private var intendedDates: [Date] = []
    /// Removals and clears made while the file could not be written. They apply to the file once it can be read,
    /// so a deletion is not undone by the older copy on disk.
    private var pendingRemovals: Set<String> = []
    private var pendingClear = false
    /// True from the start of a read until its result is applied, so a second refresh does not read again.
    private var loadInFlight = false
    /// Numbers each write. A write's result is published only if it is newer than the last one published.
    private var writeCount = 0
    private var publishedWrite = 0
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
    /// Captures never expire by age: the 15-capture limit is the only thing that removes them.
    init(store: any HistoryStore = AppHistoryStore.make(),
         retention: @escaping @MainActor () -> HistoryRetention = { .never },
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

    /// Test variant only: fills an empty history with the fixtures, through the normal encrypted write path, newest
    /// first as listed. Does nothing once the history has anything in it, so a restart does not add them again.
    func seedFixtures(_ texts: [String]) {
        guard state == .available, items.isEmpty else { return }
        let now = Date()
        for (offset, text) in texts.enumerated().reversed() {
            add(text, at: now.addingTimeInterval(-Double(offset) * 300))
        }
    }

    /// Runs file work on the same serial queue as the writes, so an import never races a capture being saved.
    static func performFileWork<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { (continuation: CheckedContinuation<T, Never>) in
            io.async { continuation.resume(returning: work()) }
        }
    }

    /// Reads the file again, after something outside History changed it (an import). Captures are then shown as
    /// the file holds them.
    func reloadFromFile() {
        guard !loadInFlight else { return }
        loadInFlight = true
        state = .loading
        Task { await reload() }
    }

    /// Waits until every queued write has finished and its result has been published. Tests use it before they
    /// look at the history or the file.
    static func flushWrites() {
        io.sync {}
        // A write publishes on the main actor after the queue finishes; let those run.
        for _ in 0..<5 { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.005)) }
    }

    /// Applies what a read found. Only what the file holds is shown; a removal that was made while the file
    /// could not be written is applied now and written back.
    private func apply(_ result: HistoryLoad) {
        loadInFlight = false
        switch result {
        case .loaded(let file):
            let stored = file.capped()
            let times = Self.alignedDates(count: stored.texts.count, stored: stored.dates)
            let kept = pendingClear ? [] : zip(stored.texts, times).filter { !pendingRemovals.contains($0.0) }
            let texts = kept.map(\.0)
            let dates = kept.map(\.1)
            let changed = texts.count != stored.texts.count
            pendingRemovals = []
            pendingClear = false
            state = .available
            items = texts
            self.dates = dates
            intendedTexts = texts
            intendedDates = dates
            if changed { commit(texts, dates) }
        case .empty:
            pendingRemovals = []
            pendingClear = false
            state = .available
            items = []
            dates = []
            intendedTexts = []
            intendedDates = []
        case .corrupt, .unavailable:
            // Nothing is shown from a file that cannot be read, and nothing is written over it.
            state = .unavailable
            items = []
            dates = []
            intendedTexts = []
            intendedDates = []
        }
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

    /// Keeps a capture in the history, once it is saved. Only while the history is available: a loading,
    /// disabled or unavailable history keeps no plaintext copy and no queue. The clipboard copy happens regardless.
    func add(_ text: String, at date: Date = Date()) {
        guard state == .available else { return }
        guard text.count <= Self.maxStoredLength else { return }
        // Whitespace-only text is never kept. Valid text is stored exactly as captured, with its spaces.
        guard !text.allSatisfy(\.isWhitespace) else { return }
        let kept = zip(intendedTexts, intendedDates).filter { $0.0 != text }
        commit(Array(([text] + kept.map(\.0)).prefix(HistoryPolicy.maximumHistoryEntries)), Array(([date] + kept.map(\.1)).prefix(HistoryPolicy.maximumHistoryEntries)))
    }

    /// Removes captures older than `limit` seconds. A capture with an unknown time (saved before times were
    /// kept) stays: its age cannot be judged.
    func prune(olderThan limit: TimeInterval?, now: Date = Date()) {
        guard let limit, state == .available else { return }
        let kept = zip(intendedTexts, intendedDates).filter { $0.1 == .distantPast || now.timeIntervalSince($0.1) <= limit }
        guard kept.count != intendedTexts.count else { return }
        commit(kept.map(\.0), kept.map(\.1))
    }

    /// Applies the retention the user chose.
    func pruneExpired(now: Date = Date()) {
        prune(olderThan: retention().seconds, now: now)
    }

    func remove(_ text: String) {
        guard state == .available else {
            // Not writable now: hide it here and apply the removal to the file once it can be written.
            pendingRemovals.insert(text)
            let kept = zip(items, dates).filter { $0.0 != text }
            items = kept.map(\.0)
            dates = kept.map(\.1)
            return
        }
        let kept = zip(intendedTexts, intendedDates).filter { $0.0 != text }
        commit(kept.map(\.0), kept.map(\.1))
    }

    func clear() {
        guard state == .available else {
            pendingClear = true
            items = []
            dates = []
            intendedTexts = []
            intendedDates = []
            return
        }
        commit([], [])
    }

    /// Writes the whole intended history on the I/O queue. The visible list changes only when this write has
    /// succeeded (see `writeFinished`). Nothing is written while the history is not available.
    private func commit(_ texts: [String], _ dates: [Date]) {
        intendedTexts = texts
        intendedDates = dates
        guard state == .available else { return }
        writeCount += 1
        let number = writeCount
        let snapshot = HistorySnapshot(texts: texts, dates: dates.map(\.timeIntervalSince1970))
        let store = self.store
        Self.io.async { [weak self] in
            let saved = store.save(snapshot)
            Task { @MainActor in self?.writeFinished(number, snapshot, saved) }
        }
    }

    /// Publishes a write that succeeded, unless a newer one has already been published. A failed write publishes
    /// nothing: the entries shown stay what the file holds, the state drops to unavailable, and the file is read
    /// again so that it, not memory, decides what is shown.
    private func writeFinished(_ number: Int, _ snapshot: HistorySnapshot, _ saved: Bool) {
        guard number > publishedWrite else { return }
        guard saved else {
            Log.app.error("History was not saved; the change is not shown and the file is unchanged")
            intendedTexts = items
            intendedDates = dates
            state = .unavailable
            refresh()
            return
        }
        publishedWrite = number
        items = snapshot.texts
        dates = Self.alignedDates(count: snapshot.texts.count, stored: snapshot.dates)
    }
}
