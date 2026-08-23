import AppKit
import Testing
@testable import VibeStats

/// The Settings window silently failed to open when it depended on SwiftUI's
/// undocumented `showSettingsWindow:` selector. These tests assert that the
/// windows we now own actually come into existence.
@Suite("App windows", .serialized)
@MainActor
struct WindowTests {

    private func window(titled title: String) -> NSWindow? {
        NSApp.windows.first { $0.title == title }
    }

    @Test("Opening settings creates a visible window")
    func settingsOpens() {
        SettingsLauncher.open()

        let window = window(titled: "Vibe Stats Settings")
        #expect(window != nil, "the settings window was never created")
        #expect(window?.isVisible == true)
        #expect(window?.contentView != nil)

        window?.close()
    }

    @Test("Opening settings twice reuses the same window")
    func settingsReused() {
        SettingsLauncher.open()
        let first = window(titled: "Vibe Stats Settings")
        SettingsLauncher.open()

        let matches = NSApp.windows.count { $0.title == "Vibe Stats Settings" }
        #expect(matches == 1, "a second settings window was created")
        #expect(first === window(titled: "Vibe Stats Settings"))

        first?.close()
    }

    @Test("Opening About creates a visible window")
    func aboutOpens() {
        AboutWindowController.shared.show()

        let window = window(titled: "About Vibe Stats")
        #expect(window != nil, "the About window was never created")
        #expect(window?.isVisible == true)

        window?.close()
    }

    @Test("About links point at this project, not the extension")
    func links() {
        #expect(AppLinks.repository.absoluteString == "https://github.com/todddube/vstat_mac")
        #expect(AppLinks.extensionRepository.absoluteString == "https://github.com/todddube/vstat")
        for url in [AppLinks.repository, AppLinks.extensionRepository, AppLinks.privacy, AppLinks.author] {
            #expect(url.scheme == "https")
        }
    }
}
