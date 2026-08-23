//  PopoverController.swift
//  Hosts the SwiftUI popover under the status item.

import AppKit
import SwiftUI

@MainActor
final class PopoverController {
    private let popover = NSPopover()
    private let coordinator: MonitorCoordinator

    init(coordinator: MonitorCoordinator, preferences: Preferences) {
        self.coordinator = coordinator

        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 420, height: 560)
        popover.contentViewController = NSHostingController(
            rootView: PopoverView(coordinator: coordinator, preferences: preferences)
        )
    }

    var isShown: Bool { popover.isShown }

    #if DEBUG
    /// A transient popover closes the moment anything else takes focus, which
    /// makes it impossible to screenshot during development.
    func pinOpenForDebug() {
        popover.behavior = .applicationDefined
    }
    #endif

    func toggle(relativeTo button: NSStatusBarButton) {
        if popover.isShown {
            close()
        } else {
            show(relativeTo: button)
        }
    }

    func show(relativeTo button: NSStatusBarButton) {
        // Activating first means keyboard focus actually lands in the popover;
        // without it an accessory app's popover takes clicks but not keys.
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    func close() {
        popover.performClose(nil)
    }
}
