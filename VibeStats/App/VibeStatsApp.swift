//  VibeStatsApp.swift
//  Entry point. The app has no windows of its own: it lives in the menu bar
//  (LSUIElement), so the only declared scene is Settings, which gives us ⌘, and
//  a real Settings window for free.

import SwiftUI

@main
struct VibeStatsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsRootView()
        }
    }
}

/// Placeholder until Phase 6. Declared here so the Settings scene — and the
/// ⌘, key equivalent it installs — exists from Phase 0 onward.
struct SettingsRootView: View {
    var body: some View {
        Text("Settings arrive in Phase 6.")
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(width: 460, height: 220)
    }
}
