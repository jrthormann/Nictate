// Nictate: a macOS menu bar app that copies text from anywhere on your screen.
// Copyright (c) 2026 jrthormann. MIT License, see LICENSE.

import Combine
import Foundation

/// Whether the history can be read and written right now.
/// `available` means a save can succeed: the file was read and the last write, if any, was saved.
/// `loading` covers the time the file takes to read; nothing is written during it.
/// `unavailable` keeps nothing new and never writes over the file.
enum HistoryState: Equatable {
    case loading, available, disabled, unavailable
}

/// Last captured texts, newest first, each with the time it was captured. Kept in `HistoryStore`, a plain JSON file.
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

    /// What the History interface shows. Each entry is already in history.json.
    @Published private(set) var items: [String]
    /// The capture time of each item, same order and length. `.distantPast` means unknown (captures saved
    /// before times were kept).
    @Published private(set) var dates: [Date]
    @Published private(set) var state: HistoryState
    /// True when the file was read and could not be decoded or read. Only an explicit discard replaces it.
    @Published private(set) var fileIsUnreadable = false
    /// True once a deletion has begun and could not be confirmed, or for quit: no change is saved until restart.
    @Published private(set) var isClosed = false
    @Published var query = ""

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
    /// True once the file has been read (and is not unreadable), so its entries are known and can be changed.
    private var hasLoadedFile = false
    /// Changes to saved entries can be written: the file is readable, whether or not saving is on. Never during an import.
    private var canWriteExisting: Bool { !importing && (state == .available || (state == .disabled && hasLoadedFile)) }
    /// True from `beginImport` to `endImport`. Reads that finish meanwhile are stale, so they are ignored.
    private var importing = false
    /// True once a deletion for quit or for a reset has begun. From then on no read is applied and no write starts.
    private var closed = false
    /// The read in flight, if any, so `finishLoading` can wait for it.
    private var loadTask: Task<Void, Never>?
    /// The longest the app waits on the file at quit. Past it, nothing is claimed as written.
    static let quitTimeout: TimeInterval = 3
    /// Numbers each write. A write's result is published only if it is newer than the last one published.
    private var writeCount = 0
    private var publishedWrite = 0
    /// Writes queued on the I/O queue whose results have not yet reached the main actor.
    private var writesInFlight = 0
    /// Whether the history is switched on. Read by `refresh`, which records nothing new while it is false.
    private let isEnabled: @MainActor () -> Bool

    /// Every file operation runs here, serially and off the main thread, so a slow disk cannot freeze
    /// the menu bar and writes happen in the order they were made.
    private static let io = DispatchQueue(label: "app.nictate.history.io", qos: .utility)

    /// The app uses `shared`. Tests pass a store of their own, so they never touch the user's captures. With
    /// `loadsNow` the file is read at once, on the calling thread; the app loads in the background instead.
    /// Captures never expire by age: the 15-capture limit is the only thing that removes them.
    init(store: any HistoryStore = AppHistoryStore.make(),
         isEnabled: @escaping @MainActor () -> Bool = { Settings.shared.historyEnabled },
         loadsNow: Bool = true) {
        self.store = store
        self.isEnabled = isEnabled
        items = []
        dates = []
        state = .loading
        if loadsNow { apply(store.load()) }
    }

    /// Starts or retries loading. Called at launch, when the panel opens, and when Save Captures is turned on.
    /// While saving is off it still loads saved captures, so they can be shown and deleted, but records nothing new.
    @discardableResult func refresh() -> Task<Void, Never>? {
        guard !importing, !closed else { return nil }
        guard isEnabled() else {
            // Saving is off: nothing new is recorded, but the saved captures stay shown, copied and deletable.
            state = .disabled
            guard !hasLoadedFile, !loadInFlight else { return nil }
            loadInFlight = true
            return startLoad()
        }
        guard state != .available, !loadInFlight else { return nil }
        if hasLoadedFile { state = .available; return nil }
        loadInFlight = true
        state = .loading
        return startLoad()
    }

    /// Starts a read and keeps its task, so a caller can wait for the saved captures to be shown.
    private func startLoad() -> Task<Void, Never> {
        let task = Task { await reload() }
        loadTask = task
        return task
    }

    /// Waits for a read in flight, and for queued writes, so a decision that depends on the saved captures sees them.
    func finishLoading() async {
        if loadInFlight { await loadTask?.value }
        let deadline = Date().addingTimeInterval(History.quitTimeout)
        while writesInFlight > 0, Date() < deadline { try? await Task.sleep(nanoseconds: 5_000_000) }
    }

    /// Reads the file and key on the I/O queue, then applies the result here on the main actor.
    func reload() async {
        let store = self.store
        let result = await withCheckedContinuation { (continuation: CheckedContinuation<HistoryLoad, Never>) in
            Self.io.async { continuation.resume(returning: store.load()) }
        }
        apply(result)
    }

    /// Test variant only: fills an empty history with the fixtures, through the normal write path, newest
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

    /// Holds History still while an import rewrites the file. Until `endImport`, captures are not kept (the clipboard
    /// copy still happens), and reads that finish meanwhile are ignored, so no save built from the older list can
    /// overwrite the merged file.
    func beginImport() {
        importing = true
        loadInFlight = true
        state = .loading
    }

    /// Ends the hold and reads the file, which now holds whatever the import wrote.
    func endImport() {
        importing = false
        loadInFlight = false
        reloadFromFile()
    }

    /// Waits until everything queued on the I/O queue before this call has run, or until `deadline`. False means it
    /// did not finish in time.
    static func drainIO(until deadline: Date) -> Bool {
        let done = DispatchSemaphore(value: 0)
        io.async { done.signal() }
        return done.wait(timeout: .now() + max(0, deadline.timeIntervalSinceNow)) == .success
    }

    /// Waits, at most `timeout`, until a read in flight is applied and every queued write has finished. Returns true
    /// only when everything finished in time, so a caller that is about to end the process knows the changes are on
    /// disk. Bounded, so a slow disk cannot hold up quit or a reset forever.
    @discardableResult func waitForPendingWrites(timeout: TimeInterval = History.quitTimeout) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while loadInFlight || writesInFlight > 0 {
            guard Date() < deadline, History.drainIO(until: deadline) else {
                Log.app.error("History changes were not written in time; they may be lost")
                return false
            }
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.005))
        }
        return true
    }

    /// Clear on Quit. The history closes: a read still running is ignored, and no write starts. The empty history is
    /// written after everything queued before it. True only when the store confirms it; a false result claims nothing.
    func clearForQuit(timeout: TimeInterval = History.quitTimeout) -> Bool {
        closed = true
        isClosed = true
        guard writeEmpty(until: Date().addingTimeInterval(timeout)) == .confirmed else { return false }
        emptyInMemory()
        return true
    }

    /// Reset with "Also delete saved captures". Like `clearForQuit`, but it returns the store's answer, so the reset can
    /// say what happened.
    func clearForReset(timeout: TimeInterval = History.quitTimeout) -> HistoryPersistOutcome {
        closed = true
        isClosed = true
        // The history stays closed whatever the answer: a write still running may yet empty the file.
        let outcome = writeEmpty(until: Date().addingTimeInterval(timeout))
        if outcome == .confirmed { emptyInMemory() }
        return outcome
    }

    private func emptyInMemory() {
        items = []
        dates = []
        intendedTexts = []
        intendedDates = []
    }

    /// "Discard Unreadable History": replaces a file that could not be read, after the user's explicit Discard. A refused
    /// write leaves the file and the state as they were; a write that is not confirmed is settled by reading the file again.
    func discardUnreadableFile() async -> HistoryPersistOutcome {
        guard fileIsUnreadable, !closed else { return .notWritten }
        let store = self.store
        let outcome = await History.performFileWork { store.save(HistorySnapshot(texts: [], dates: [])) }
        if outcome == .confirmed { fileIsUnreadable = false }
        if outcome != .notWritten { reloadFromFile() }
        return outcome
    }

    /// Queues the empty history behind everything already queued, and waits until `deadline`. A write still running then is unconfirmed.
    private func writeEmpty(until deadline: Date) -> HistoryPersistOutcome {
        let store = self.store
        let answer = WriteOutcome()
        let finished = DispatchSemaphore(value: 0)
        Self.io.async {
            answer.outcome = store.save(HistorySnapshot(texts: [], dates: []))
            finished.signal()
        }
        guard finished.wait(timeout: .now() + max(0, deadline.timeIntervalSinceNow)) == .success else {
            Log.app.error("Clear on Quit: the history write did not finish in time; nothing is claimed as cleared")
            return .unconfirmed
        }
        if answer.outcome != .confirmed {
            Log.app.error("Clear on Quit: the empty history is \(answer.outcome.rawValue, privacy: .public); the choice stays on for the next launch")
        }
        return answer.outcome
    }

    /// Reads the file again, after something outside History changed it (an import). Captures are then shown as
    /// the file holds them.
    func reloadFromFile() {
        guard !loadInFlight else { return }
        loadInFlight = true
        state = .loading
        _ = startLoad()
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
        // A read that ends during an import is ignored. Once closed, a read still ends but is never shown or written.
        guard !importing else { return }
        loadInFlight = false
        guard !closed else { return }
        switch result {
        case .loaded(let file):
            hasLoadedFile = true
            fileIsUnreadable = false
            let stored = file.capped()
            let times = Self.alignedDates(count: stored.texts.count, stored: stored.dates)
            let kept = pendingClear ? [] : zip(stored.texts, times).filter { !pendingRemovals.contains($0.0) }
            let texts = kept.map(\.0)
            let dates = kept.map(\.1)
            let changed = texts.count != stored.texts.count
            pendingRemovals = []
            pendingClear = false
            state = isEnabled() ? .available : .disabled
            items = texts
            self.dates = dates
            intendedTexts = texts
            intendedDates = dates
            if changed { commit(texts, dates) }
        case .empty:
            hasLoadedFile = true
            fileIsUnreadable = false
            pendingRemovals = []
            pendingClear = false
            state = isEnabled() ? .available : .disabled
            items = []
            dates = []
            intendedTexts = []
            intendedDates = []
        case .corrupt, .unavailable:
            // Nothing is shown from a file that cannot be read, and nothing is written over it.
            hasLoadedFile = false
            fileIsUnreadable = true
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

    func remove(_ text: String) {
        guard canWriteExisting else {
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
        guard canWriteExisting else {
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
        // After Clear on Quit nothing new is written: a late capture or deletion must not restore captures.
        guard !closed else { return }
        intendedTexts = texts
        intendedDates = dates
        guard canWriteExisting else { return }
        writeCount += 1
        writesInFlight += 1
        let number = writeCount
        let snapshot = HistorySnapshot(texts: texts, dates: dates.map(\.timeIntervalSince1970))
        let store = self.store
        Self.io.async { [weak self] in
            let outcome = store.save(snapshot)
            Task { @MainActor in self?.writeFinished(number, snapshot, outcome) }
        }
    }

    /// Publishes a write the store confirmed, unless a newer one has already been published. Any other answer publishes
    /// nothing: the entries shown stay what the file holds, the state drops to unavailable, and the file is read again,
    /// so that it, not memory, decides what is shown. An unconfirmed write may or may not be in the file.
    private func writeFinished(_ number: Int, _ snapshot: HistorySnapshot, _ outcome: HistoryPersistOutcome) {
        writesInFlight -= 1
        // After Clear on Quit the list is the empty one; a write that finishes later must not bring captures back into it.
        guard !closed, number > publishedWrite else { return }
        guard outcome == .confirmed else {
            Log.app.error("History write \(outcome.rawValue, privacy: .public): the change is not shown, and the file is read again")
            intendedTexts = items
            intendedDates = dates
            state = .unavailable
            hasLoadedFile = false
            refresh()
            return
        }
        publishedWrite = number
        items = snapshot.texts
        dates = Self.alignedDates(count: snapshot.texts.count, stored: snapshot.dates)
    }
}
