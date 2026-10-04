import AppKit
import SwiftUI
import Testing
@testable import VibeStats

/// Renders each settings tab offscreen for review.
@Suite("Settings snapshots", .serialized)
@MainActor
struct SettingsSnapshotTests {

    /// ImageRenderer lays a Form (and any ScrollView) out to nothing, so these
    /// go through a real NSHostingView in an offscreen window and capture the
    /// actual AppKit hierarchy instead.
    private func render(
        _ view: some View,
        appearance name: NSAppearance.Name,
        size: NSSize = NSSize(width: 520, height: 470),
        to filename: String
    ) throws {
        let hosting = NSHostingView(rootView: AnyView(view.frame(width: size.width)))
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.appearance = NSAppearance(named: name)

        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.appearance = NSAppearance(named: name)
        window.contentView = hosting
        window.layoutIfNeeded()
        hosting.layoutSubtreeIfNeeded()

        let rep = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: rep)

        let data = try #require(rep.representation(using: .png, properties: [:]))
        let url = FileManager.default.temporaryDirectory.appending(path: filename)
        try data.write(to: url)
        print("SETTINGS SNAPSHOT: \(url.path)")
    }

    @Test("General tab")
    func general() throws {
        try render(GeneralSettingsView(), appearance: .darkAqua, to: "settings-general-dark.png")
    }

    @Test("Services tab")
    func services() async throws {
        // Give the tab real resolution data to display.
        await AppServices.shared.coordinator.refresh(reason: .manual)
        try render(ServicesSettingsView(), appearance: .darkAqua, to: "settings-services-dark.png")
    }

    @Test("Notifications tab")
    func notifications() throws {
        try render(NotificationSettingsView(), appearance: .darkAqua,
                   size: NSSize(width: 520, height: 560), to: "settings-notifications-dark.png")
    }

    @Test("About window")
    func about() throws {
        try render(AboutView(), appearance: .darkAqua,
                   size: NSSize(width: 380, height: 430), to: "about-dark.png")
    }

    @Test("Appearance tab, including the live icon previews")
    func appearance() throws {
        try render(AppearanceSettingsView(), appearance: .darkAqua, to: "settings-appearance-dark.png")
    }
}
