// Nictate: a macOS menu bar app that copies text from anywhere on your screen.
// Copyright (c) 2026 jrthormann. MIT License, see LICENSE.

import UserNotifications

/// What Notifier asks of the system's notification center. The app uses `SystemNoticeCenter`; the unit tests pass one
/// they answer by hand, so a deletion can come before a late answer.
protocol NoticeCenter: Sendable {
    /// Asks for permission to show banners. `answer` may run on any thread.
    func requestPermission(_ answer: @escaping @Sendable (Bool) -> Void)
    /// Shows a banner now. `added` may run on any thread, with false when the system did not take it.
    func add(identifier: String, body: String, _ added: @escaping @Sendable (Bool) -> Void)
    func remove(identifier: String)
    /// Takes down every banner Nictate has shown, and any request not yet shown.
    func removeAll()
}

/// Delivers the banner that confirms a capture, according to the notification style the user chose.
/// Permission is requested once, the first time a banner is actually due. Deleting saved captures withdraws every
/// banner, including one still on its way, so deleted text never appears afterwards.
@MainActor
final class Notifier {
    /// How long a banner stays in Notification Center before it is removed, so a captured secret does not linger.
    nonisolated static let lifetime: Duration = .seconds(10)
    /// Advanced by `withdrawAll`. A banner carries the generation it was asked for in; one from an earlier generation
    /// is never shown, however late the permission answer or the system's confirmation arrives.
    private static var generation = 0
    private var gate = NotificationGate()
    private let settings: Settings
    private let center: any NoticeCenter

    /// The app uses the defaults. Tests pass settings of their own and a center they answer by hand.
    init(settings: Settings = .shared, center: any NoticeCenter = SystemNoticeCenter()) {
        self.settings = settings
        self.center = center
    }

    func notify(generic: String, text: String) {
        guard let body = settings.notificationStyle.body(generic: generic, text: text) else { return }
        let identifier = UUID().uuidString
        let ticket = Self.generation
        let center = self.center
        if gate.shouldRequest() {
            // The first notification waits for the answer, which can come long after the capture. It is delivered only if
            // the answer was yes and no captures were deleted meanwhile.
            center.requestPermission { granted in
                guard granted else { return }
                Task { @MainActor in Notifier.deliver(identifier, body, ticket: ticket, to: center) }
            }
        } else {
            Self.deliver(identifier, body, ticket: ticket, to: center)
        }
    }

    /// Withdraws every banner, for when saved captures are deleted: the ones shown go, and the ones still on their way
    /// never appear. Called when captures are deleted, whatever the outcome of the history write.
    static func withdrawAll(from center: any NoticeCenter = SystemNoticeCenter()) {
        generation += 1
        center.removeAll()
    }

    private static func deliver(_ identifier: String, _ body: String, ticket: Int, to center: any NoticeCenter) {
        guard ticket == generation else { return }
        center.add(identifier: identifier, body: body) { added in
            guard added else { return }
            Task { @MainActor in
                // Added after a deletion began: it goes now. Otherwise the clock starts once the banner is really there.
                if ticket == generation { scheduleRemoval(of: identifier, from: center) } else { center.remove(identifier: identifier) }
            }
        }
    }

    private static func scheduleRemoval(of identifier: String, from center: any NoticeCenter) {
        Task { @MainActor in
            try? await Task.sleep(for: lifetime)
            center.remove(identifier: identifier)
        }
    }
}

/// The system's notification center, reached only when a banner is due or captures are deleted. A process without an
/// app bundle (the test runners) has none: `UNUserNotificationCenter.current()` raises there, so every call does nothing.
struct SystemNoticeCenter: NoticeCenter {
    /// The center holds its delegate weakly, so the one delegate lives here for the whole run.
    private static let presenter = ForegroundPresenter()

    func requestPermission(_ answer: @escaping @Sendable (Bool) -> Void) {
        guard let center = Self.presenting() else { return }
        center.requestAuthorization(options: [.alert]) { granted, error in
            if let error { Log.app.error("notification permission failed: \(error.localizedDescription, privacy: .public)") }
            answer(granted)
        }
    }

    func add(identifier: String, body: String, _ added: @escaping @Sendable (Bool) -> Void) {
        guard let center = Self.presenting() else { return }
        let content = UNMutableNotificationContent()
        content.title = "Nictate"
        content.body = body
        center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil)) { error in
            if let error { Log.app.error("notification not delivered: \(error.localizedDescription, privacy: .public)") }
            added(error == nil)
        }
    }

    func remove(identifier: String) { Self.current?.removeDeliveredNotifications(withIdentifiers: [identifier]) }

    func removeAll() {
        guard let center = Self.current else { return }
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
    }

    private static var current: UNUserNotificationCenter? {
        Bundle.main.bundleIdentifier == nil ? nil : UNUserNotificationCenter.current()
    }

    /// Set here rather than at launch, so nothing touches the notification center until a banner is due.
    private static func presenting() -> UNUserNotificationCenter? {
        guard let center = current else { return nil }
        if center.delegate == nil { center.delegate = presenter }
        return center
    }
}

/// macOS holds back a notification that arrives while its own app is frontmost unless the delegate asks for
/// it, so with the Settings window key the capture's banner never appeared.
private final class ForegroundPresenter: NSObject, UNUserNotificationCenterDelegate, Sendable {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner])
    }
}
