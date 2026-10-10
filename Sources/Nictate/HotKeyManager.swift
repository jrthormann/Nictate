// Nictate: a macOS menu bar app that copies text from anywhere on your screen.
// Copyright (c) 2026 jrthormann. MIT License, see LICENSE.

import Carbon.HIToolbox
import Foundation

/// Registers global hotkeys via Carbon (no Accessibility permission needed), one per slot.
@MainActor
final class HotKeyManager {
    typealias Slot = ShortcutSlot

    static let shared = HotKeyManager()
    private var actions: [UInt32: () -> Void] = [:]
    private var refs: [UInt32: EventHotKeyRef] = [:]
    /// The combination of every slot that has one, kept while suspended so `resume` can register it again.
    private var combos: [UInt32: Shortcut] = [:]
    private var handler: EventHandlerRef?
    /// While the shortcut recorder listens, every hotkey is released: otherwise pressing the current
    /// combination would run the action instead of being recorded. A count, so a relaunch and the recorder
    /// can each suspend and resume without undoing the other.
    private var suspensions = 0
    var isSuspended: Bool { suspensions > 0 }

    /// How many combinations the system holds for Nictate right now.
    var registeredCount: Int { refs.count }

    func setAction(_ slot: Slot, _ action: @escaping () -> Void) {
        actions[slot.rawValue] = action
    }

    /// (Re)registers the slot's key combination. Returns false if the system refused it, for
    /// example because another app already owns that combination. It registers at once even while
    /// suspended, because the answer is needed now; the recorder resumes before it hands over a new shortcut.
    @discardableResult
    func register(_ slot: Slot, code: Int, mods: Int) -> Bool {
        installHandlerIfNeeded()
        unregister(slot)

        let id = EventHotKeyID(signature: OSType(0x4E435454), id: slot.rawValue) // 'NCTT'
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(code), UInt32(mods), id, GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else {
            Log.hotKeys.error("could not register slot \(slot.rawValue, privacy: .public) (status \(status, privacy: .public))")
            return false
        }
        refs[slot.rawValue] = ref
        combos[slot.rawValue] = Shortcut(code: code, mods: mods)
        return true
    }

    /// Frees the slot's key combination, for an optional shortcut the user removed.
    func unregister(_ slot: Slot) {
        if let old = refs.removeValue(forKey: slot.rawValue) { UnregisterEventHotKey(old) }
        combos[slot.rawValue] = nil
    }

    /// Releases every combination but remembers it, until the matching `resume`. Calls nest.
    func suspend() {
        suspensions += 1
        guard suspensions == 1 else { return }
        for ref in refs.values { UnregisterEventHotKey(ref) }
        refs.removeAll()
    }

    /// Balances one `suspend`. When the last one is balanced, registers again every combination that was
    /// released; one the system now refuses is logged and dropped.
    func resume() {
        guard suspensions > 0 else { return }
        suspensions -= 1
        guard suspensions == 0 else { return }
        for (id, combo) in combos.sorted(by: { $0.key < $1.key }) {
            guard let slot = Slot(rawValue: id) else { continue }
            register(slot, code: combo.code, mods: combo.mods)
        }
    }

    private func installHandlerIfNeeded() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            // Carbon delivers hotkey events on the main thread's event loop.
            MainActor.assumeIsolated { HotKeyManager.shared.actions[id.id]?() }
            return noErr
        }, 1, &spec, nil, &handler)
    }
}
