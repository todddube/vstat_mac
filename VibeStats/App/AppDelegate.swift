//  AppDelegate.swift
//  Owns the process-level objects. Everything with a lifetime longer than a
//  view lives here, or is reachable from here.

import AppKit
import Observation
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let services = AppServices.shared
    private var preferences: Preferences { services.preferences }
    private var coordinator: MonitorCoordinator { services.coordinator }
    private var statusItemController: StatusItemController?
    private var appearanceObserver: (any NSObjectProtocol)?
    private lazy var notifications = NotificationDispatcher(preferences: preferences)

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.app.info("Vibe Stats launching")

        let controller = StatusItemController(coordinator: coordinator, preferences: preferences)
        controller.install()
        statusItemController = controller

        UNUserNotificationCenter.current().delegate = self

        coordinator.onSnapshotChange = { [weak self, weak controller] previous, current in
            controller?.render()
            Task { await self?.notifications.handle(previous: previous, current: current) }
        }

        // Redraw on every observable change of the coordinator, not only when a
        // snapshot lands — `phase` moving to .checking or .offline is a visible
        // state too.
        observePhase()

        // Appearance settings change the glyph but not the data, so they need
        // their own nudge.
        appearanceObserver = NotificationCenter.default.addObserver(
            forName: .vibeStatsAppearanceChanged, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { controller.render() }
        }

        NSApp.setActivationPolicy(preferences.showInDock ? .regular : .accessory)

        coordinator.start()

        #if DEBUG
        if ProcessInfo.processInfo.environment["VIBESTATS_OPEN_SETTINGS"] == "1" {
            Task {
                try? await Task.sleep(for: .seconds(2))
                SettingsLauncher.open()
            }
        }
        if ProcessInfo.processInfo.environment["VIBESTATS_OPEN_POPOVER"] == "1" {
            Task {
                try? await Task.sleep(for: .seconds(3))
                self.statusItemController?.openPopoverForDebug()
            }
        }
        #endif
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator.stop()
        if let appearanceObserver {
            NotificationCenter.default.removeObserver(appearanceObserver)
        }
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    /// Opens the popover on the service a notification came from.
    private func revealPopover(for service: ServiceID?) {
        statusItemController?.revealPopover()
    }

    /// `withObservationTracking` fires once per change, so it re-arms itself.
    private func observePhase() {
        withObservationTracking {
            _ = coordinator.phase
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.statusItemController?.render()
                self.observePhase()
            }
        }
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    /// Show our own notifications even while the app is frontmost — an
    /// accessory app is "frontmost" far more often than the user thinks.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let raw = response.notification.request.content
            .userInfo[SystemNotificationPresenter.serviceKey] as? String
        revealPopover(for: raw.flatMap(ServiceID.init(rawValue:)))
    }
}
