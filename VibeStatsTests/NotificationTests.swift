import Foundation
import Testing
@testable import VibeStats

/// Records what would have been announced, without a notification centre or a
/// permission prompt.
actor SpyPresenter: NotificationPresenting {
    private(set) var posted: [VibeNotification] = []
    private(set) var authorizationRequests = 0
    private let authorized: Bool

    init(authorized: Bool = true) { self.authorized = authorized }

    func requestAuthorizationIfNeeded() async -> Bool {
        authorizationRequests += 1
        return authorized
    }

    func post(_ notification: VibeNotification) async {
        posted.append(notification)
    }
}

@Suite("Transition diffing")
struct TransitionDiffTests {

    private func snapshot(_ states: [ServiceID: [String: StatusIndicator]]) -> Snapshot {
        let services = ServiceRegistry.all.compactMap { definition -> ServiceSnapshot? in
            guard let overrides = states[definition.id] else { return nil }
            let components = definition.components.map { component in
                ComponentState(
                    id: component.id, label: component.label, isPrimary: component.isPrimary,
                    matched: true, matchedName: component.label, rawStatus: nil,
                    indicator: overrides[component.id] ?? .operational,
                    detail: nil, provenance: .reported
                )
            }
            let rollUp = RollUp(components.map(\.indicator))
            return ServiceSnapshot(
                id: definition.id, name: definition.name,
                indicator: rollUp.indicator, pageIndicator: rollUp.indicator,
                componentsResolved: components.count, componentsWatched: components.count,
                unresolvedCount: rollUp.unresolved, components: components, incidents: [],
                affectedComponents: components.filter(\.isAffected).map(\.label),
                error: nil, checkedAt: .distantPast
            )
        }
        return Snapshot(services: services, combined: .combine(services), updatedAt: .distantPast)
    }

    @Test("A degradation is detected with its before and after")
    func degradation() {
        let before = snapshot([.claude: [:]])
        let after = snapshot([.claude: ["claude-code": .major]])

        let transitions = TransitionDiff.transitions(from: before, to: after)
        #expect(transitions.count == 1)

        let transition = transitions[0]
        #expect(transition.componentID == "claude-code")
        #expect(transition.from == .operational)
        #expect(transition.to == .major)
        #expect(transition.isDegradation)
        #expect(!transition.isRecovery)
        #expect(transition.judgedSeverity == .major)
    }

    @Test("A recovery is detected and judged on where it came from")
    func recovery() {
        let before = snapshot([.claude: ["claude-code": .critical]])
        let after = snapshot([.claude: [:]])

        let transition = TransitionDiff.transitions(from: before, to: after)[0]
        #expect(transition.isRecovery)
        #expect(!transition.isDegradation)
        #expect(transition.judgedSeverity == .critical)
    }

    @Test("There are no transitions without a previous snapshot")
    func noPrevious() {
        #expect(TransitionDiff.transitions(from: nil, to: snapshot([.claude: [:]])).isEmpty)
    }

    @Test("Unchanged components produce nothing")
    func unchanged() {
        let state = snapshot([.claude: ["claude-code": .minor]])
        #expect(TransitionDiff.transitions(from: state, to: state).isEmpty)
    }

    /// "We stopped being able to measure this" is not an outage.
    @Test("Transitions into or out of unknown are never reported")
    func unknownIsNotAnEvent() {
        let healthy = snapshot([.claude: [:]])
        let unmeasured = snapshot([.claude: ["claude-code": .unknown]])

        #expect(TransitionDiff.transitions(from: healthy, to: unmeasured).isEmpty)
        #expect(TransitionDiff.transitions(from: unmeasured, to: healthy).isEmpty)
    }

    @Test("A service absent from the previous snapshot contributes nothing")
    func newService() {
        let before = snapshot([.claude: [:]])
        let after = snapshot([.claude: [:], .github: ["copilot": .critical]])
        #expect(TransitionDiff.transitions(from: before, to: after).isEmpty)
    }
}

@Suite("Notification policy")
@MainActor
struct NotificationPolicyTests {

    private func dispatcher(
        _ configure: (Preferences) -> Void = { _ in }
    ) -> (NotificationDispatcher, Preferences) {
        let preferences = Preferences(defaults: UserDefaults(suiteName: "notify-\(UUID().uuidString)")!)
        configure(preferences)
        return (NotificationDispatcher(preferences: preferences, presenter: SpyPresenter()), preferences)
    }

    private func transition(
        _ id: String = "claude-code",
        from: StatusIndicator,
        to: StatusIndicator,
        service: ServiceID = .claude,
        primary: Bool = true
    ) -> StatusTransition {
        StatusTransition(
            service: service,
            serviceName: ServiceRegistry.definition(for: service).name,
            componentID: id, componentLabel: id, isPrimary: primary,
            from: from, to: to
        )
    }

    @Test("A degradation is announced")
    func announcesDegradation() {
        let (dispatcher, _) = dispatcher()
        let planned = dispatcher.plan(
            transitions: [transition(from: .operational, to: .major)], now: .now
        )
        #expect(planned.count == 1)
        #expect(planned[0].title.contains("Claude AI"))
        #expect(planned[0].service == .claude)
    }

    @Test("Degradation and recovery can each be switched off")
    func switches() {
        let (noDegradation, _) = dispatcher { $0.notifyOnDegradation = false }
        #expect(noDegradation.plan(
            transitions: [transition(from: .operational, to: .critical)], now: .now
        ).isEmpty)

        let (noRecovery, _) = dispatcher { $0.notifyOnRecovery = false }
        #expect(noRecovery.plan(
            transitions: [transition(from: .critical, to: .operational)], now: .now
        ).isEmpty)
    }

    @Test("The minimum severity filters both directions")
    func minimumSeverity() {
        let (dispatcher, _) = dispatcher { $0.notifyMinimumSeverity = .major }

        #expect(dispatcher.plan(
            transitions: [transition(from: .operational, to: .minor)], now: .now
        ).isEmpty, "a minor degradation is below the threshold")

        #expect(dispatcher.plan(
            transitions: [transition(from: .operational, to: .major)], now: .now
        ).count == 1)

        #expect(dispatcher.plan(
            transitions: [transition("x", from: .minor, to: .operational)], now: .now
        ).isEmpty, "recovering from a minor issue is below the threshold too")
    }

    @Test("Non-primary components can be excluded")
    func primaryOnly() {
        let (strict, _) = dispatcher { $0.notifyPrimaryOnly = true }
        #expect(strict.plan(
            transitions: [transition(from: .operational, to: .critical, primary: false)], now: .now
        ).isEmpty)

        let (loose, _) = dispatcher { $0.notifyPrimaryOnly = false }
        #expect(loose.plan(
            transitions: [transition(from: .operational, to: .critical, primary: false)], now: .now
        ).count == 1)
    }

    @Test("A second alert about the same component inside the cooldown is suppressed")
    func cooldown() {
        let (dispatcher, _) = dispatcher { $0.notifyCooldown = .seconds(900) }
        let now = Date(timeIntervalSince1970: 1_787_000_000)

        #expect(dispatcher.plan(transitions: [transition(from: .operational, to: .major)], now: now).count == 1)
        #expect(dispatcher.plan(
            transitions: [transition(from: .major, to: .critical)],
            now: now.addingTimeInterval(300)
        ).isEmpty, "still inside the 15 minute cooldown")

        #expect(dispatcher.plan(
            transitions: [transition(from: .major, to: .critical)],
            now: now.addingTimeInterval(1000)
        ).count == 1, "the cooldown has elapsed")
    }

    @Test("A service losing several components arrives as one notification")
    func grouping() {
        let (dispatcher, _) = dispatcher()
        let planned = dispatcher.plan(
            transitions: [
                transition("copilot", from: .operational, to: .critical, service: .github),
                transition("codespaces", from: .operational, to: .major, service: .github),
                transition("actions", from: .operational, to: .major, service: .github)
            ],
            now: .now
        )

        #expect(planned.count == 1, "three at once should not be three banners")
        #expect(planned[0].title.contains("3 components"))
    }

    @Test("Two at once stay as two separate notifications")
    func belowGroupingThreshold() {
        let (dispatcher, _) = dispatcher()
        let planned = dispatcher.plan(
            transitions: [
                transition("copilot", from: .operational, to: .critical, service: .github),
                transition("actions", from: .operational, to: .major, service: .github)
            ],
            now: .now
        )
        #expect(planned.count == 2)
    }

    @Test("Different services are never grouped together")
    func groupsPerService() {
        let (dispatcher, _) = dispatcher()
        let planned = dispatcher.plan(
            transitions: [
                transition("claude-code", from: .operational, to: .major, service: .claude),
                transition("copilot", from: .operational, to: .major, service: .github)
            ],
            now: .now
        )
        #expect(planned.count == 2)
        #expect(Set(planned.map(\.service)) == [.claude, .github])
    }

    @Test("Quiet hours suppress everything, including a window that wraps midnight")
    func quietHours() throws {
        let (dispatcher, preferences) = dispatcher {
            $0.quietHoursEnabled = true
            $0.quietHoursStart = 22 * 60
            $0.quietHoursEnd = 8 * 60
        }
        _ = preferences

        let calendar = Calendar.current
        let night = try #require(calendar.date(bySettingHour: 23, minute: 30, second: 0, of: .now))
        let earlyMorning = try #require(calendar.date(bySettingHour: 3, minute: 0, second: 0, of: .now))
        let midday = try #require(calendar.date(bySettingHour: 13, minute: 0, second: 0, of: .now))

        #expect(dispatcher.isQuietHour(night))
        #expect(dispatcher.isQuietHour(earlyMorning))
        #expect(!dispatcher.isQuietHour(midday))

        #expect(dispatcher.plan(
            transitions: [transition(from: .operational, to: .critical)], now: night
        ).isEmpty)
        #expect(dispatcher.plan(
            transitions: [transition(from: .operational, to: .critical)], now: midday
        ).count == 1)
    }

    @Test("The first snapshot after launch never notifies")
    func firstSnapshotIsSilent() async {
        let preferences = Preferences(defaults: UserDefaults(suiteName: "notify-\(UUID().uuidString)")!)
        let spy = SpyPresenter()
        let dispatcher = NotificationDispatcher(preferences: preferences, presenter: spy)

        // Whatever was on disk may be hours stale; announcing a diff against it
        // would mean a burst about things that resolved while asleep.
        await dispatcher.handle(previous: nil, current: emptySnapshot())
        #expect(await spy.posted.isEmpty)
        #expect(await spy.authorizationRequests == 0, "and no permission prompt either")
    }

    @Test("Declining permission stops us asking again")
    func declinedOnce() async {
        let preferences = Preferences(defaults: UserDefaults(suiteName: "notify-\(UUID().uuidString)")!)
        let spy = SpyPresenter(authorized: false)
        let dispatcher = NotificationDispatcher(preferences: preferences, presenter: spy)

        let before = componentSnapshot(.operational)
        let after = componentSnapshot(.critical)

        await dispatcher.handle(previous: nil, current: before)     // first: silent
        await dispatcher.handle(previous: before, current: after)
        await dispatcher.handle(previous: before, current: after)

        #expect(await spy.authorizationRequests == 1, "asked once, then stopped")
        #expect(await spy.posted.isEmpty)
    }

    // MARK: - Helpers

    private func emptySnapshot() -> Snapshot {
        Snapshot(services: [], combined: .empty, updatedAt: .distantPast)
    }

    private func componentSnapshot(_ indicator: StatusIndicator) -> Snapshot {
        let definition = ServiceRegistry.claude
        let components = definition.components.map { component in
            ComponentState(
                id: component.id, label: component.label, isPrimary: component.isPrimary,
                matched: true, matchedName: component.label, rawStatus: nil,
                indicator: component.id == "claude-code" ? indicator : .operational,
                detail: nil, provenance: .reported
            )
        }
        let service = ServiceSnapshot(
            id: .claude, name: definition.name, indicator: indicator, pageIndicator: indicator,
            componentsResolved: components.count, componentsWatched: components.count,
            unresolvedCount: 0, components: components, incidents: [],
            affectedComponents: [], error: nil, checkedAt: .distantPast
        )
        return Snapshot(services: [service], combined: .combine([service]), updatedAt: .distantPast)
    }
}
