import Foundation
import Testing
import Observation
import Synchronization
@testable import VibeStats

@Suite("MonitorCoordinator")
@MainActor
struct CoordinatorTests {

    private func makeCoordinator(_ client: StubAPIClient) -> MonitorCoordinator {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "VibeStatsCoordinator-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        return MonitorCoordinator(
            engine: StatusEngine(client: client),
            store: SnapshotStore(directory: directory),
            history: HistoryLog(directory: directory),
            preferences: Preferences(defaults: defaults)
        )
    }

    @Test("A refresh publishes a snapshot and settles back to idle")
    func refreshPublishes() async throws {
        let coordinator = makeCoordinator(try .liveFixtures())
        #expect(coordinator.snapshot == nil)
        #expect(coordinator.hasCompletedFirstCheck == false)

        await coordinator.refresh(reason: .manual)

        #expect(coordinator.hasCompletedFirstCheck)
        #expect(coordinator.phase == .idle)
        #expect(coordinator.snapshot?.services.count == ServiceRegistry.ids.count)
        #expect(coordinator.combined.indicator == .operational)
    }

    @Test("A total blackout lands in .failed, not a cheerful idle")
    func blackoutFails() async {
        let coordinator = makeCoordinator(StubAPIClient([:]))
        await coordinator.refresh(reason: .manual)

        #expect(coordinator.phase == .failed("Unable to check status"))
        #expect(coordinator.combined.indicator == .unknown)
    }

    @Test("Fresh data is not re-fetched when the popover opens")
    func staleCheckSkipsFreshData() async throws {
        let client = try StubAPIClient.liveFixtures()
        let coordinator = makeCoordinator(client)

        await coordinator.refresh(reason: .manual)
        let callsAfterFirst = await client.callCount("claude/status.json")

        await coordinator.refreshIfStale()
        #expect(await client.callCount("claude/status.json") == callsAfterFirst)
    }

    @Test("With no data at all, the stale check does fetch")
    func staleCheckFetchesWhenEmpty() async throws {
        let client = try StubAPIClient.liveFixtures()
        let coordinator = makeCoordinator(client)

        await coordinator.refreshIfStale()
        #expect(coordinator.snapshot != nil)
    }

    @Test("Concurrent refreshes join the one in flight instead of stacking")
    func concurrentRefreshesCoalesce() async throws {
        let client = try StubAPIClient.liveFixtures()
        let coordinator = makeCoordinator(client)

        async let first: Void = coordinator.refresh(reason: .manual)
        async let second: Void = coordinator.refresh(reason: .scheduled)
        _ = await (first, second)

        #expect(await client.callCount("claude/status.json") == 1)
    }

    @Test("A disabled service is not fetched and does not feed the roll-up")
    func disabledServiceIsSkipped() async throws {
        let client = try StubAPIClient.liveFixtures()
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let preferences = Preferences(defaults: defaults)
        preferences.setEnabled(false, for: .openai)

        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let coordinator = MonitorCoordinator(
            engine: StatusEngine(client: client),
            store: SnapshotStore(directory: directory),
            history: HistoryLog(directory: directory),
            preferences: preferences
        )

        await coordinator.refresh(reason: .manual)

        #expect(coordinator.snapshot?.services.count == ServiceRegistry.ids.count - 1)
        #expect(coordinator.snapshot?[.openai] == nil)
        #expect(await client.callCount("openai/status.json") == 0)
    }

    @Test("Offline blocks the scheduled sweep but never a manual refresh")
    func offlineGating() {
        // A user pressing Refresh and getting nothing at all — no attempt, no
        // error — is worse than one wasted request while genuinely offline.
        #expect(MonitorCoordinator.allows(.manual, in: .offline))
        #expect(MonitorCoordinator.allows(.networkRestored, in: .offline))

        for reason in [MonitorCoordinator.RefreshReason.scheduled, .launch, .wake, .popoverOpened, .settingsChanged] {
            #expect(MonitorCoordinator.allows(reason, in: .offline) == false, "\(reason.rawValue) burns a retry while offline")
        }
    }

    @Test("Every reason is allowed once we are back online")
    func onlineAllowsEverything() {
        for phase in [MonitorCoordinator.Phase.idle, .checking, .failed("boom")] {
            for reason in [MonitorCoordinator.RefreshReason.scheduled, .launch, .manual, .wake, .networkRestored, .popoverOpened, .settingsChanged] {
                #expect(MonitorCoordinator.allows(reason, in: phase))
            }
        }
    }

    @Test("Preferences round-trip through their own defaults suite")
    func preferencesRoundTrip() {
        let preferences = Preferences(defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!)

        #expect(preferences.refreshInterval == .fiveMinutes)
        #expect(preferences.iconRenderMode == .monochromeWithPip)
        #expect(preferences.motionLevel == .full)
        #expect(preferences.isEnabled(.claude))

        preferences.refreshInterval = .oneMinute
        preferences.motionLevel = .off
        preferences.setEnabled(false, for: .gemini)

        #expect(preferences.refreshInterval == .oneMinute)
        #expect(preferences.motionLevel == .off)
        #expect(!preferences.isEnabled(.gemini))
        #expect(preferences.enabledServices.map(\.id) == [.claude, .github, .openai, .grok])
    }

    @Test("Writing a preference is observable, so Settings and the menu bar hear it")
    func preferencesAreObservable() {
        let preferences = Preferences(defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!)
        let fired = Mutex(false)

        // Every setting is computed over UserDefaults, which `@Observable`
        // does not instrument: the icon-style cards wrote the value but no
        // `onChange` fired, so the menu bar kept the old glyph.
        withObservationTracking {
            _ = preferences.iconStyle
        } onChange: {
            fired.withLock { $0 = true }
        }
        preferences.iconStyle = .minimal

        #expect(fired.withLock { $0 })
        #expect(preferences.iconStyle == .minimal)
    }
}
