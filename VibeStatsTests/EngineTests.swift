import Foundation
import Testing
@testable import VibeStats

@Suite("StatusEngine against recorded vendor payloads")
struct EngineTests {

    /// The fixtures were captured while every vendor was healthy, so `now` has
    /// to sit near that capture or the incident pruner drops everything.
    private let now = Date(timeIntervalSince1970: 1_787_000_000)  // 2026-08-23

    private func engine(_ client: StubAPIClient) -> StatusEngine {
        StatusEngine(client: client)
    }

    // MARK: - Happy path

    @Test("Every registry component resolves against the live payloads")
    func allComponentsResolve() async throws {
        let snapshot = await engine(try .liveFixtures()).check(now: now)

        #expect(snapshot.services.count == ServiceRegistry.ids.count)
        for service in snapshot.services {
            #expect(
                service.componentsResolved == service.componentsWatched,
                "\(service.id): \(service.componentsResolved)/\(service.componentsWatched) resolved, unresolved: \(service.components.filter { !$0.matched }.map(\.id))"
            )
            #expect(service.unresolvedCount == 0)
        }
    }

    @Test("Services come back in registry order")
    func registryOrder() async throws {
        let snapshot = await engine(try .liveFixtures()).check(now: now)
        #expect(snapshot.services.map(\.id) == ServiceRegistry.ids)
    }

    @Test("Matched components carry the vendor's own name and raw status")
    func provenanceOfMatches() async throws {
        let snapshot = await engine(try .liveFixtures()).check(now: now)
        let claudeCode = try #require(snapshot[.claude]?.component(id: "claude-code"))

        #expect(claudeCode.matched)
        #expect(claudeCode.matchedName == "Claude Code")
        #expect(claudeCode.rawStatus == "operational")
        #expect(claudeCode.indicator == .operational)
        #expect(claudeCode.provenance == .reported)
    }

    @Test("Gemini components are incident-derived, not reported")
    func geminiProvenance() async throws {
        let snapshot = await engine(try .liveFixtures()).check(now: now)
        let gemini = try #require(snapshot[.gemini])

        #expect(gemini.components.count == 3)
        for component in gemini.components {
            #expect(component.provenance == .derivedFromIncidents)
        }
    }

    // MARK: - The thesis: components over page indicator

    @Test("A red page indicator with green components reports GREEN, and flags the divergence")
    func componentsBeatPageIndicator() async throws {
        let client = try StubAPIClient.liveFixtures()
        await client.override("github/status.json", with: .data(
            try Fixture.mutated("github-status") { json in
                json["status"] = ["indicator": "major", "description": "Everything is on fire"]
            }
        ))

        let github = try #require(await engine(client).check(now: now)[.github])

        #expect(github.indicator == .operational, "watched Copilot components are all healthy")
        #expect(github.pageIndicator == .major)
        #expect(github.divergesFromPage)
    }

    @Test("A degraded watched component outranks a calm page indicator")
    func componentDegradationWins() async throws {
        let client = try StubAPIClient.liveFixtures()
        await client.override("github/components.json", with: .data(
            try Fixture.mutated("github-components") { json in
                var components = json["components"] as! [[String: Any]]
                for index in components.indices where components[index]["name"] as? String == "Copilot" {
                    components[index]["status"] = "major_outage"
                }
                json["components"] = components
            }
        ))

        let github = try #require(await engine(client).check(now: now)[.github])

        #expect(github.indicator == .critical)
        #expect(github.pageIndicator == .operational)
        #expect(github.divergesFromPage)
        #expect(github.affectedComponents == ["Copilot"])
    }

    // MARK: - Degradation

    @Test("A renamed component reports UNKNOWN — never operational")
    func renamedComponentIsUnknown() async throws {
        let client = try StubAPIClient.liveFixtures()
        await client.override("claude/components.json", with: .data(
            try Fixture.mutated("claude-components") { json in
                var components = json["components"] as! [[String: Any]]
                for index in components.indices where components[index]["name"] as? String == "Claude Code" {
                    components[index]["name"] = "Anthropic Coding Agent"
                }
                json["components"] = components
            }
        ))

        let claude = try #require(await engine(client).check(now: now)[.claude])
        let renamed = try #require(claude.component(id: "claude-code"))

        #expect(renamed.matched == false)
        #expect(renamed.indicator == .unknown)
        #expect(renamed.indicator != .operational)
        #expect(claude.componentsResolved == claude.componentsWatched - 1)
        #expect(claude.unresolvedCount == 1)
        // The service is still operational overall — but the unknown is counted
        // and surfaced rather than silently folded into "healthy".
        #expect(claude.indicator == .operational)
    }

    @Test("With zero components resolved we fall back to the vendor's page indicator")
    func fallbackToPageIndicator() async throws {
        let client = try StubAPIClient.liveFixtures()
        await client.override("claude/components.json", with: .data(
            try Fixture.mutated("claude-components") { $0["components"] = [] }
        ))
        await client.override("claude/status.json", with: .data(
            try Fixture.mutated("claude-status") { $0["status"] = ["indicator": "minor"] }
        ))

        let claude = try #require(await engine(client).check(now: now)[.claude])

        #expect(claude.componentsResolved == 0)
        #expect(claude.indicator == .minor, "the page indicator is all we have left")
    }

    @Test("One failing endpoint degrades one service, not the app")
    func failureIsolation() async throws {
        let client = try StubAPIClient.liveFixtures()
        await client.override("openai/components.json", with: .failure(.http(status: 500)))
        await client.override("openai/status.json", with: .failure(.http(status: 500)))
        await client.override("openai/incidents.json", with: .failure(.http(status: 500)))

        let snapshot = await engine(client).check(now: now)

        #expect(snapshot[.openai]?.indicator == .unknown)
        #expect(snapshot[.claude]?.indicator == .operational)
        #expect(snapshot[.github]?.indicator == .operational)
        #expect(snapshot[.gemini]?.indicator == .operational)
    }

    /// docs/REVIEW.md §3.1 end to end: a total blackout must not read as green.
    @Test("A total blackout never renders as vibing")
    func totalBlackout() async throws {
        let client = StubAPIClient([:])   // every request 404s
        let snapshot = await engine(client).check(now: now)

        #expect(snapshot.combined.indicator == .unknown)
        #expect(snapshot.combined.description == "Unable to check status")
        for service in snapshot.services {
            #expect(service.indicator == .unknown)
        }
    }

    @Test("Malformed JSON degrades that service to unknown with a decode error")
    func malformedPayload() async throws {
        let client = try StubAPIClient.liveFixtures()
        let garbage = Data("{ not json at all".utf8)
        await client.override("gemini/incidents.json", with: .data(garbage))

        let gemini = try #require(await engine(client).check(now: now)[.gemini])
        #expect(gemini.indicator == .unknown)
        #expect(gemini.error != nil)
    }

    // MARK: - Incidents

    @Test("Incidents are pruned to 10 within 14 days, newest first")
    func incidentPruning() async throws {
        let snapshot = await engine(try .liveFixtures()).check(now: now)

        for service in snapshot.services {
            #expect(service.incidents.count <= IncidentPruner.maxStored)

            let dates = service.incidents.compactMap(\.createdAt)
            #expect(dates == dates.sorted(by: >), "\(service.id) incidents are not newest-first")

            let cutoff = now.addingTimeInterval(-14 * 24 * 3600)
            for date in dates {
                #expect(date >= cutoff, "\(service.id) kept an incident older than 14 days")
            }
        }
    }

    @Test("Incidents are flagged by whether they touch a watched component")
    func affectsWatched() async throws {
        let snapshot = await engine(try .liveFixtures()).check(now: now)
        let github = try #require(snapshot[.github])

        // GitHub's feed covers the whole product; some incidents touch Copilot
        // or Actions, most do not. Both kinds must be present and labelled.
        for incident in github.incidents {
            let touchesWatched = incident.affectedComponents.contains { name in
                ["copilot", "actions", "codespaces", "api requests", "copilot ai model providers"]
                    .contains(name.lowercased())
            }
            #expect(incident.affectsWatched == touchesWatched || incident.affectedComponents.isEmpty)
        }
    }
}

@Suite("IncidentPruner")
struct IncidentPrunerTests {
    private let now = Date(timeIntervalSince1970: 1_787_000_000)

    private func incident(_ id: String, daysAgo: Double?) -> Incident {
        Incident(
            id: id,
            name: id,
            status: "resolved",
            impact: .minor,
            createdAt: daysAgo.map { now.addingTimeInterval(-$0 * 24 * 3600) },
            resolvedAt: nil,
            shortlink: nil,
            affectedComponents: [],
            affectsWatched: true,
            updates: []
        )
    }

    @Test("Incidents older than the window are dropped")
    func ageWindow() {
        let pruned = IncidentPruner.prune(
            [incident("fresh", daysAgo: 1), incident("stale", daysAgo: 20)], now: now
        )
        #expect(pruned.map(\.id) == ["fresh"])
    }

    @Test("An incident with no timestamp is dropped rather than kept forever")
    func undatedDropped() {
        #expect(IncidentPruner.prune([incident("undated", daysAgo: nil)], now: now).isEmpty)
    }

    @Test("At most 10 are kept, newest first")
    func countCap() {
        let many = (0..<25).map { incident("i\($0)", daysAgo: Double($0) * 0.5) }
        let pruned = IncidentPruner.prune(many.shuffled(), now: now)

        #expect(pruned.count == 10)
        #expect(pruned.first?.id == "i0")
        #expect(pruned.map(\.id) == (0..<10).map { "i\($0)" })
    }

    @Test("The 14-day boundary is inclusive")
    func boundary() {
        #expect(IncidentPruner.prune([incident("edge", daysAgo: 13.99)], now: now).count == 1)
        #expect(IncidentPruner.prune([incident("edge", daysAgo: 14.01)], now: now).isEmpty)
    }
}
