//  SettingsWindowController.swift
//  One settings window, created on first use and reused thereafter.

import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()

    private var window: NSWindow?

    private init() {}

    func show() {
        NSApp.activate(ignoringOtherApps: true)

        if let window {
            window.makeKeyAndOrderFront(nil)
            return
        }

        let hosting = NSHostingController(rootView: SettingsRootView())
        let window = NSWindow(contentViewController: hosting)
        window.title = String(localized: "Vibe Stats Settings")
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        // Sized from the content, not a hardcoded pair. The hardcoded 520x470
        // was the width SettingsRootView pins its content to, which left no
        // room for the scene padding around it — the content was wider than the
        // window that held it.
        window.setContentSize(hosting.view.fittingSize)
        window.center()
        window.makeKeyAndOrderFront(nil)

        self.window = window
    }
}

/// Kept as the single call site the rest of the app uses.
@MainActor
enum SettingsLauncher {
    static func open() {
        SettingsWindowController.shared.show()
    }
}
