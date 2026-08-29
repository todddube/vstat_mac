//  NotificationDispatcher.swift
//  Decides what is worth interrupting someone for.
//
//  This is the capability the browser extension could never have: under MV3 the
//  worker is terminated when idle, so the extension can only tell you something
//  is wrong at the moment you happen to click it.

import Foundation

@MainActor
final class NotificationDispatcher {
    private let preferences: Preferences
    private let presenter: any NotificationPresenting

    /// Last announcement per component, for the cooldown.
    private var lastNotified: [String: Date] = [:]
    /// The first snapshot after launch is diffed against whatever was on disk,
    /// which may be hours stale. Announcing that would mean a burst of
    /// notifications about things that resolved while the machine was asleep.
    private var hasSeenFirstSnapshot = false
    /// Set once the user declines, so we stop asking.
    private var authorizationDenied = false

    /// A service degrading wholesale should be one notification, not six.
    static let groupingThreshold = 3

    init(preferences: Preferences, presenter: any NotificationPresenting = SystemNotificationPresenter()) {
        self.preferences = preferences
        self.presenter = presenter
    }

    // MARK: - Entry point

    func handle(previous: Snapshot?, current: Snapshot, now: Date = .now) async {
        guard hasSeenFirstSnapshot else {
            hasSeenFirstSnapshot = true
            return
        }

        let notifications = plan(
            transitions: TransitionDiff.transitions(from: previous, to: current),
            now: now
        )
        guard !notifications.isEmpty else { return }

        guard !authorizationDenied else { return }
        guard await presenter.requestAuthorizationIfNeeded() else {
            authorizationDenied = true
            Log.notify.info("notifications not authorised — staying quiet")
            return
        }

        for notification in notifications {
            await presenter.post(notification)
        }
    }

    // MARK: - Policy

    /// Pure: given transitions and a clock, what should be announced. Records
    /// the cooldown stamps for whatever it decides to send.
    func plan(transitions: [StatusTransition], now: Date) -> [VibeNotification] {
        guard !preferences.quietHoursEnabled || !isQuietHour(now) else {
            Log.notify.debug("suppressed \(transitions.count) transitions: quiet hours")
            return []
        }

        let eligible = transitions.filter { allows($0) }.filter { !isInCooldown($0, now: now) }
        guard !eligible.isEmpty else { return [] }

        var notifications: [VibeNotification] = []

        for (service, group) in Dictionary(grouping: eligible, by: \.service) {
            let sorted = group.sorted { severity($0) > severity($1) }
            for transition in sorted {
                lastNotified[transition.id] = now
            }

            if sorted.count >= Self.groupingThreshold {
                notifications.append(summary(for: service, transitions: sorted))
            } else {
                notifications.append(contentsOf: sorted.map(single(for:)))
            }
        }

        // Worst first, so a burst arrives in a sensible order. Sorting by id
        // instead — as this did — ordered an outage after a recovery purely
        // because "claude" sorts before "github".
        return notifications.sorted { left, right in
            let leftSeverity = left.severity.severity ?? -1
            let rightSeverity = right.severity.severity ?? -1
            // Ties break on id so a burst has a stable, reproducible order.
            return leftSeverity == rightSeverity
                ? left.id < right.id
                : leftSeverity > rightSeverity
        }
    }

    private func allows(_ transition: StatusTransition) -> Bool {
        if preferences.notifyPrimaryOnly && !transition.isPrimary { return false }

        let threshold = preferences.notifyMinimumSeverity.threshold
        guard let judged = transition.judgedSeverity.severity,
              let minimum = threshold.severity,
              judged >= minimum
        else { return false }

        if transition.isDegradation { return preferences.notifyOnDegradation }
        if transition.isRecovery { return preferences.notifyOnRecovery }
        return false
    }

    private func isInCooldown(_ transition: StatusTransition, now: Date) -> Bool {
        guard let last = lastNotified[transition.id] else { return false }
        let cooldown = TimeInterval(preferences.notifyCooldown.components.seconds)
        return now.timeIntervalSince(last) < cooldown
    }

    /// Handles a window that wraps past midnight (22:00 → 08:00).
    func isQuietHour(_ date: Date) -> Bool {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        let minutes = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        let start = preferences.quietHoursStart
        let end = preferences.quietHoursEnd

        if start == end { return false }
        return start < end
            ? (minutes >= start && minutes < end)
            : (minutes >= start || minutes < end)
    }

    private func severity(_ transition: StatusTransition) -> Int {
        transition.judgedSeverity.severity ?? -1
    }

    // MARK: - Copy

    private func single(for transition: StatusTransition) -> VibeNotification {
        let title = transition.isRecovery
            ? String(localized: "\(transition.serviceName) recovered")
            : String(localized: "\(transition.serviceName) \(transition.to.title.lowercased())")

        let body = transition.isRecovery
            ? String(localized: "\(transition.componentLabel) is operational again.")
            : String(localized: "\(transition.componentLabel) is now \(transition.to.title.lowercased()).")

        return VibeNotification(
            id: "\(transition.id).\(transition.to.rawValue)",
            title: title,
            body: body,
            service: transition.service,
            playsSound: preferences.notifySound,
            severity: transition.judgedSeverity
        )
    }

    private func summary(for service: ServiceID, transitions: [StatusTransition]) -> VibeNotification {
        let name = transitions.first?.serviceName ?? service.rawValue
        let allRecovered = transitions.allSatisfy(\.isRecovery)
        let labels = transitions.map(\.componentLabel).formatted(.list(type: .and))

        return VibeNotification(
            id: "\(service.rawValue).summary.\(transitions.count)",
            title: allRecovered
                ? String(localized: "\(name) recovered")
                : String(localized: "\(name): \(transitions.count) components affected"),
            body: labels,
            service: service,
            playsSound: preferences.notifySound,
            // `transitions` is already sorted worst-first by plan().
            severity: transitions.first?.judgedSeverity ?? .unknown
        )
    }
}
