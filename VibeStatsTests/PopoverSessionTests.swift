import Foundation
import Testing
@testable import VibeStats

@Suite("Popover auto-close", .serialized)
@MainActor
struct PopoverSessionTests {

    @Test("With auto-close off there is no countdown at all")
    func disabled() {
        let session = PopoverSession()
        session.begin(.never) {}

        #expect(session.remaining == nil)
        #expect(session.isCountingDown == false)
        #expect(session.progress == 1)
    }

    @Test("A countdown starts full and depletes")
    func counts() async {
        let session = PopoverSession()
        session.begin(interval: 1.0) {}

        #expect(session.remaining == 1.0)
        #expect(session.progress == 1)

        try? await Task.sleep(for: .milliseconds(250))
        let left = try! #require(session.remaining)
        #expect(left < 1.0)
        #expect(left > 0.5)
        #expect(session.progress < 1)
    }

    @Test("Expiry fires once and marks the session as dismissing")
    func expires() async {
        let session = PopoverSession()
        let counter = Counter()
        session.begin(interval: 0.25) { counter.increment() }

        try? await Task.sleep(for: .milliseconds(600))

        #expect(counter.value == 1)
        #expect(session.isDismissing)
        #expect(session.remaining == 0)
    }

    /// The pointer entering is the clearest signal the user is still reading.
    @Test("Hovering pauses the countdown")
    func hoverPauses() async {
        let session = PopoverSession()
        session.begin(interval: 1.0) {}

        try? await Task.sleep(for: .milliseconds(120))
        session.pause()
        let atPause = try! #require(session.remaining)

        try? await Task.sleep(for: .milliseconds(250))

        #expect(session.remaining == atPause, "a paused countdown must not drift")
        #expect(session.isCountingDown == false)
        #expect(session.isWarning == false)
    }

    @Test("Leaving restarts from full rather than resuming a near-expired timer")
    func leaveRestarts() async {
        let session = PopoverSession()
        session.begin(interval: 1.0) {}

        try? await Task.sleep(for: .milliseconds(300))
        session.pause()
        session.resume()

        #expect(session.remaining == 1.0)
        #expect(session.progress == 1)
    }

    @Test("Pinning stops the countdown; unpinning starts a fresh one")
    func pinning() async {
        let session = PopoverSession()
        let counter = Counter()
        session.begin(interval: 0.3) { counter.increment() }

        session.isPinned = true
        #expect(session.remaining == nil)

        try? await Task.sleep(for: .milliseconds(500))
        #expect(counter.value == 0, "a pinned popover must never auto-close")

        session.isPinned = false
        #expect(session.remaining == 0.3)
    }

    @Test("The final seconds are flagged as a warning")
    func warning() async {
        let session = PopoverSession()
        session.begin(interval: PopoverSession.warningThreshold + 0.3) {}

        #expect(session.isWarning == false)
        try? await Task.sleep(for: .milliseconds(400))
        #expect(session.isWarning)
    }

    @Test("Ending clears the countdown and the dismissing flag")
    func end() {
        let session = PopoverSession()
        session.begin(interval: 5) {}
        session.end()

        #expect(session.remaining == nil)
        #expect(session.isDismissing == false)
    }

    @Test("Auto-close options map to sane intervals")
    func options() {
        #expect(PopoverAutoClose.never.isEnabled == false)
        #expect(PopoverAutoClose.fifteenSeconds.interval == 15)
        #expect(PopoverAutoClose.allCases.first == .never)
        for option in PopoverAutoClose.allCases {
            #expect(!option.title.isEmpty)
        }
    }
}

@MainActor
private final class Counter {
    private(set) var value = 0
    func increment() { value += 1 }
}
