//  NotificationPresenter.swift
//  The seam between "decide what to announce" and "actually announce it", so
//  the policy can be tested without a notification centre or a permission
//  prompt.

import Foundation
import UserNotifications

struct VibeNotification: Sendable, Hashable, Identifiable {
    let id: String
    let title: String
    let body: String
    let service: ServiceID
    let playsSound: Bool
}

protocol NotificationPresenting: Sendable {
    /// Returns false when the user has declined; the dispatcher then stops
    /// asking rather than prompting on every transition.
    func requestAuthorizationIfNeeded() async -> Bool
    func post(_ notification: VibeNotification) async
}

struct SystemNotificationPresenter: NotificationPresenting {
    /// Identifies which service a notification came from, so activating it can
    /// open the popover focused on that card.
    static let serviceKey = "vibeStatsService"

    func requestAuthorizationIfNeeded() async -> Bool {
        let centre = UNUserNotificationCenter.current()
        let settings = await centre.notificationSettings()

        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            // Asked lazily, the first time something would actually be
            // announced — requesting at launch is how apps get quit on day one.
            do {
                return try await centre.requestAuthorization(options: [.alert, .sound])
            } catch {
                Log.notify.error("authorization request failed: \(error.localizedDescription)")
                return false
            }
        @unknown default:
            return false
        }
    }

    func post(_ notification: VibeNotification) async {
        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.body
        content.sound = notification.playsSound ? .default : nil
        content.userInfo = [Self.serviceKey: notification.service.rawValue]
        content.interruptionLevel = .active

        let request = UNNotificationRequest(
            identifier: notification.id,
            content: content,
            trigger: nil        // deliver immediately
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            Log.notify.error("failed to post notification: \(error.localizedDescription)")
        }
    }
}
