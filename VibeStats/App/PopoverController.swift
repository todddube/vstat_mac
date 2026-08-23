//  PopoverController.swift
//  Hosts the SwiftUI popover under the status item, and owns its lifetime.

import AppKit
import SwiftUI

@MainActor
final class PopoverController {
    private let popover = NSPopover()
    private let coordinator: MonitorCoordinator
    private let preferences: Preferences
    private let session = PopoverSession()

    /// How long the content's exit animation runs before the window closes.
    /// The popover's own fade is disabled so ours is the only one on screen.
    private static let exitDuration: Duration = .milliseconds(260)

    /// `behavior` is injectable so a test can isolate OUR auto-close from
    /// AppKit's transient dismissal, which fires whenever the anchor window
    /// stops being key and would otherwise mask the thing under test.
    init(
        coordinator: MonitorCoordinator,
        preferences: Preferences,
        behavior: NSPopover.Behavior = .transient
    ) {
        self.coordinator = coordinator
        self.preferences = preferences

        popover.behavior = behavior
        // Our content animates itself out; AppKit's default fade on top of that
        // reads as two competing animations.
        popover.animates = false
        popover.contentSize = NSSize(width: 420, height: 560)
        popover.contentViewController = NSHostingController(
            rootView: PopoverView(
                coordinator: coordinator,
                preferences: preferences,
                session: session
            )
        )
    }

    var isShown: Bool { popover.isShown }

    func toggle(relativeTo anchor: NSView) {
        if popover.isShown {
            dismiss(animated: false)
        } else {
            show(relativeTo: anchor)
        }
    }

    /// Takes an NSView rather than an NSStatusBarButton so the lifetime can be
    /// exercised against any anchor in a test.
    func show(relativeTo anchor: NSView) {
        // Activating first means keyboard focus actually lands in the popover;
        // without it an accessory app's popover takes clicks but not keys.
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()

        let autoClose = preferences.popoverAutoClose
        Log.menuBar.info("popover shown (auto-close: \(autoClose.rawValue)s)")
        session.begin(autoClose) { [weak self] in
            Log.menuBar.info("popover auto-close expired — dismissing")
            self?.dismiss(animated: true)
        }
    }

    /// Animated dismissal: the content scales down and fades (driven by
    /// `session.isDismissing` inside the view), then the window closes once the
    /// animation has actually played.
    func dismiss(animated: Bool) {
        guard popover.isShown else { return }

        guard animated, Motion.effectiveLevel(preferences.motionLevel) != .off else {
            session.end()
            popover.close()
            return
        }

        Task { [weak self] in
            try? await Task.sleep(for: Self.exitDuration)
            guard let self else { return }
            self.session.end()
            self.popover.close()
            Log.menuBar.info("popover closed")
        }
    }

    func close() {
        dismiss(animated: false)
    }

    #if DEBUG
    /// A transient popover closes the moment anything else takes focus, which
    /// makes it impossible to screenshot during development.
    func pinOpenForDebug() {
        popover.behavior = .applicationDefined
    }
    #endif
}
