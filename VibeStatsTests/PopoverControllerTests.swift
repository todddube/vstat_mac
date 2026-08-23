import AppKit
import Testing
@testable import VibeStats

/// Drives the real NSPopover through a real NSStatusItem, because the thing
/// worth proving is that the countdown actually closes the window — not just
/// that a timer fired.
@Suite("Popover auto-close, end to end", .serialized)
@MainActor
struct PopoverControllerTests {

    /// An on-screen anchor window: NSPopover refuses to show relative to a view
    /// that is not in a visible window, and a status item button in a test host
    /// is not reliably laid out.
    private func makeAnchor() -> (NSWindow, NSView) {
        // .titled, not .borderless: a borderless window returns NO from
        // canBecomeKeyWindow, and an NSPopover anchored to a non-key window
        // behaves erratically.
        let window = NSWindow(
            contentRect: NSRect(x: 200, y: 200, width: 200, height: 60),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        let anchor = NSView(frame: NSRect(x: 0, y: 0, width: 40, height: 20))
        window.contentView?.addSubview(anchor)
        window.makeKeyAndOrderFront(nil)
        return (window, anchor)
    }

    /// Tear down in the right order. Closing the anchor window while a popover
    /// is still attached to one of its subviews makes AppKit close a window it
    /// does not own, which takes the process with it.
    private func teardown(_ controller: PopoverController, _ window: NSWindow) async {
        controller.close()
        try? await Task.sleep(for: .milliseconds(150))
        window.orderOut(nil)
    }

    private func makeController(
        autoClose: PopoverAutoClose,
        motion: MotionLevel = .off
    ) -> PopoverController {
        let defaults = UserDefaults(suiteName: "popover-\(UUID().uuidString)")!
        let preferences = Preferences(defaults: defaults)
        preferences.popoverAutoClose = autoClose
        preferences.motionLevel = motion

        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let coordinator = MonitorCoordinator(
            engine: StatusEngine(client: StubAPIClient([:])),
            store: SnapshotStore(directory: directory),
            history: HistoryLog(directory: directory),
            preferences: preferences
        )

        return PopoverController(
            coordinator: coordinator,
            preferences: preferences,
            behavior: .applicationDefined
        )
    }

    @Test("The popover closes itself once the countdown expires", .timeLimit(.minutes(1)))
    func closesAfterTimeout() async throws {
        let controller = makeController(autoClose: .fiveSeconds)
        let (window, anchor) = makeAnchor()

        controller.show(relativeTo: anchor)
        #expect(controller.isShown)

        try? await Task.sleep(for: .seconds(3))
        #expect(controller.isShown, "must still be open before the countdown expires")

        try? await Task.sleep(for: .seconds(3.5))
        #expect(!controller.isShown, "the countdown should have closed it")

        await teardown(controller, window)
    }

    @Test("With auto-close off the popover stays open", .timeLimit(.minutes(1)))
    func staysOpenWhenDisabled() async throws {
        let controller = makeController(autoClose: .never)
        let (window, anchor) = makeAnchor()

        controller.show(relativeTo: anchor)

        try? await Task.sleep(for: .seconds(6))
        #expect(controller.isShown, "a popover with auto-close off must never close on its own")

        await teardown(controller, window)
        #expect(!controller.isShown)
    }

    @Test("Toggling closes an open popover")
    func toggleCloses() async throws {
        let controller = makeController(autoClose: .never)
        let (window, anchor) = makeAnchor()

        controller.toggle(relativeTo: anchor)
        #expect(controller.isShown)

        // Let the show transaction finish. Tearing an NSPopover down inside the
        // same run loop turn that presented it is not something AppKit
        // tolerates, and it cannot happen from a user click anyway.
        try? await Task.sleep(for: .milliseconds(250))

        controller.toggle(relativeTo: anchor)
        try? await Task.sleep(for: .milliseconds(150))
        #expect(!controller.isShown)

        window.orderOut(nil)
    }
}
