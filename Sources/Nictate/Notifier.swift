// Nictate: a macOS menu bar app that copies text from anywhere on your screen.
// Copyright (c) 2026 jrthormann. MIT License, see LICENSE.

import UserNotifications

/// Delivers the banner that confirms a capture, according to the notification style the user chose.
/// Permission is requested once, the first time a banner is actually due.
@MainActor
final class Notifier {
    /// How long a banner stays in Notification Center before it is removed, so a captured secret does not linger.
    nonisolated static let lifetime: Duration = .seconds(10)

    /// The center holds its delegate weakly, so the one delegate lives here for the whole run.
    private static let presenter = ForegroundPresenter()
    private var gate = NotificationGate()
    private let settings = Settings.shared

    func notify(generic: String, text: String) {
        guard let body = settings.notificationStyle.body(generic: generic, text: text) else { return }
        let identifier = UUID().uuidString
        let center = UNUserNotificationCenter.current()
        // Set here rather than at launch, so nothing touches the notification center until a banner is due.
        if center.delegate == nil { center.delegate = Self.presenter }
        if gate.shouldRequest() {
            // The first notification waits for the answer, then is delivered if it was yes. The callback
            // builds the request from plain strings and fetches the center itself (a process-wide singleton),
            // so nothing that is not Sendable crosses to its thread.
            center.requestAuthorization(options: [.alert]) { granted, error in
                if let error { Log.app.error("notification permission failed: \(error.localizedDescription, privacy: .public)") }
                if granted { Self.deliver(identifier: identifier, body: body) }
            }
        } else {
            Self.deliver(identifier: identifier, body: body)
        }
    }

    /// Removes every banner Nictate has delivered, for when the history is cleared.
    static func removeAllDelivered() {
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
    }

    private nonisolated static func deliver(identifier: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = "Nictate"
        content.body = body
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                Log.app.error("notification not delivered: \(error.localizedDescription, privacy: .public)")
                return
            }
            // The clock starts once the banner is really there: the first one waits for the permission answer,
            // which can come much later than the capture.
            Task { @MainActor in scheduleRemoval(of: identifier) }
        }
    }

    private static func scheduleRemoval(of identifier: String) {
        Task { @MainActor in
            try? await Task.sleep(for: lifetime)
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [identifier])
        }
    }
}

/// macOS holds back a notification that arrives while its own app is frontmost unless the delegate asks for
/// it, so with the Settings or History window key the capture's banner never appeared.
private final class ForegroundPresenter: NSObject, UNUserNotificationCenterDelegate, Sendable {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner])
    }
}
