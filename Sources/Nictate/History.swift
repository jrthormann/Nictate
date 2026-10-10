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
    /// Whether the history is switched on. Read by `refresh`, so a disabled history never touches the Keychain.
    private let isEnabled: @MainActor () -> Bool

    /// Every file operation runs here, serially and off the main thread, so a Keychain prompt cannot freeze
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

    /// Starts or retries loading. Called at launch, when the panel opens, and when Keep History is turned on.
    /// Does nothing while the history is switched off, so no Keychain access happens for it.
    @discardableResult func refresh() -> Task<Void, Never>? {
        guard !importing, !closed else { return nil }
        guard isEnabled() else {
            // Saving is off: no new captures are recorded. The saved ones stay loaded, so they can still be
            // shown, copied and deleted, and a deletion is written straight away.
            state = .disabled
            guard !hasLoadedFile, !loadInFlight else { return nil }
            loadInFlight = true
            return startLoad()
        }
        guard state != .available, !loadInFlight else { return nil }
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

    /// Waits for a read in flight to be applied, so a decision that depends on the saved captures sees them.
    func finishLoading() async {
        guard loadInFlight else { return }
        await loadTask?.value
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

    /// Clear on Quit. From this call on, a read that finishes is ignored and no write starts, so a load still running
    /// cannot bring captures back. The empty history is written on the serial I/O queue, after everything queued
    /// before it, and the call waits at most `timeout` for the store's answer. It returns true only when the store
    /// confirmed the empty history is on disk. Only then is the in-memory list cleared. A false result claims nothing.
    func clearForQuit(timeout: TimeInterval = History.quitTimeout) -> Bool {
        closed = true
        guard writeEmpty(until: Date().addingTimeInterval(timeout)) else { return false }
        emptyInMemory()
        return true
    }

    /// Reset with "Also delete saved captures". Like `clearForQuit`, but a refused or late write reopens the history,
    /// so the app keeps saving and the reset can stop with a message instead of restarting over captures that remain.
    func clearForReset(timeout: TimeInterval = History.quitTimeout) -> Bool {
        closed = true
        guard writeEmpty(until: Date().addingTimeInterval(timeout)) else {
            closed = false
            refresh()
            return false
        }
        emptyInMemory()
        return true
    }

    private func emptyInMemory() {
        items = []
        dates = []
        intendedTexts = []
        intendedDates = []
    }

    /// Clear on Quit is on and the file could not be read (corrupt or unreadable): it is overwritten with an empty
    /// history, off the main thread, so a stuck disk cannot freeze the menu bar. A failure is retried next launch.
    func clearUnreadableFile() async {
        guard state == .unavailable, !closed else { return }
        let store = self.store
        let saved = await History.performFileWork { store.save(HistorySnapshot(texts: [], dates: [])) }
        guard saved else {
            Log.app.error("Clear on Quit: the unreadable history could not be overwritten; it is retried on the next launch")
            return
        }
        reloadFromFile()
    }

    /// Queues the empty history behind everything already queued, and waits until `deadline` for the store's answer.
    private func writeEmpty(until deadline: Date) -> Bool {
        let store = self.store
        let outcome = WriteOutcome()
        let finished = DispatchSemaphore(value: 0)
        Self.io.async {
            outcome.saved = store.save(HistorySnapshot(texts: [], dates: []))
            finished.signal()
        }
        guard finished.wait(timeout: .now() + max(0, deadline.timeIntervalSinceNow)) == .success else {
            Log.app.error("Clear on Quit: the history write did not finish in time; nothing is claimed as cleared")
            return false
        }
        if !outcome.saved {
            Log.app.error("Clear on Quit: the history could not be cleared; the choice stays on for the next launch")
        }
        return outcome.saved
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
        // A read that finishes during an import belongs to the import's hold, and is ignored. Once the history is
        // closed, a read still ends (so `loadInFlight` is cleared), but its captures are not shown or written.
        guard !importing else { return }
        loadInFlight = false
        guard !closed else { return }
        switch result {
        case .loaded(let file):
            hasLoadedFile = true
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
            let saved = store.save(snapshot)
            Task { @MainActor in self?.writeFinished(number, snapshot, saved) }
        }
    }

    /// Publishes a write that succeeded, unless a newer one has already been published. A failed write publishes
    /// nothing: the entries shown stay what the file holds, the state drops to unavailable, and the file is read
    /// again so that it, not memory, decides what is shown.
    private func writeFinished(_ number: Int, _ snapshot: HistorySnapshot, _ saved: Bool) {
        writesInFlight -= 1
        // After Clear on Quit the list is the empty one; a write that finishes later must not bring captures back into it.
        guard !closed, number > publishedWrite else { return }
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
