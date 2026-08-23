//  AppDelegate.swift
//  Owns the process-level objects. Everything with a lifetime longer than a
//  view lives here, or is reachable from here.

import AppKit
import Observation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let preferences = Preferences.shared
    private lazy var coordinator = MonitorCoordinator(preferences: preferences)
    private var statusItemController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.app.info("Vibe Stats launching")

        let controller = StatusItemController(coordinator: coordinator, preferences: preferences)
        controller.install()
        statusItemController = controller

        coordinator.onSnapshotChange = { [weak controller] _, _ in
            controller?.render()
        }

        // Redraw on every observable change of the coordinator, not only when a
        // snapshot lands — `phase` moving to .checking or .offline is a visible
        // state too.
        observePhase()

        coordinator.start()

        #if DEBUG
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
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
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
