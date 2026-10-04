import Foundation
import Testing
@testable import VibeStats

@Suite("CombinedStatus — copy rules and roll-up")
struct CombinedStatusTests {

    private func snapshot(
        _ id: ServiceID,
        _ indicator: StatusIndicator,
        affected: [String] = [],
        unresolved: Int = 0
    ) -> ServiceSnapshot {
        let definition = ServiceRegistry.definition(id)
        return ServiceSnapshot(
            id: id,
            name: definition.name,
            indicator: indicator,
            pageIndicator: indicator,
            componentsResolved: definition.components.count - unresolved,
            componentsWatched: definition.components.count,
            unresolvedCount: unresolved,
            components: [],
            incidents: [],
            affectedComponents: affected,
            error: nil,
            checkedAt: .distantPast
        )
    }

    @Test("All healthy reads as vibing")
    func allHealthy() {
        let combined = CombinedStatus.combine(ServiceRegistry.ids.map { snapshot($0, .operational) })
        #expect(combined.indicator == .operational)
        #expect(combined.description == "All dev tools are vibing")
        #expect(combined.affectedCount == 0)
    }

    /// The headline defect: four unknown services must not read as healthy.
    @Test("A total blackout never says everything is vibing")
    func totalBlackout() {
        let combined = CombinedStatus.combine(ServiceRegistry.ids.map { snapshot($0, .unknown) })
        #expect(combined.indicator == .unknown)
        #expect(combined.description == "Unable to check status")
        #expect(combined.unknownServices.count == ServiceRegistry.ids.count)
    }

    @Test("One unknown service suppresses the cheerful copy")
    func partialUnknown() {
        let combined = CombinedStatus.combine([
            snapshot(.claude, .operational),
            snapshot(.github, .operational),
            snapshot(.openai, .operational),
            snapshot(.gemini, .unknown)
        ])
        #expect(combined.indicator == .operational)
        #expect(combined.description == "Status unavailable for Gemini")
        #expect(combined.description != "All dev tools are vibing")
    }

    @Test("Unresolved components are surfaced even when everything measured is OK")
    func unresolvedSurfaced() {
        let combined = CombinedStatus.combine([
            snapshot(.claude, .operational, unresolved: 2),
            snapshot(.github, .operational)
        ])
        #expect(combined.unresolvedCount == 2)
        #expect(combined.description == "All watched components OK · 2 unresolved")
    }

    @Test("Severity copy names the affected services")
    func severityCopy() {
        let minor = CombinedStatus.combine([
            snapshot(.claude, .minor, affected: ["Claude Code"]),
            snapshot(.github, .operational)
        ])
        #expect(minor.indicator == .minor)
        #expect(minor.description == "Minor issues with Claude AI")
        #expect(minor.affectedComponents == ["Claude AI: Claude Code"])
        #expect(minor.affectedCount == 1)

        let critical = CombinedStatus.combine([
            snapshot(.claude, .critical, affected: ["API"]),
            snapshot(.openai, .major, affected: ["Chat API"])
        ])
        #expect(critical.indicator == .critical)
        #expect(critical.description == "Outage: Claude AI and OpenAI")
    }

    @Test("A real problem outranks an unknown sibling")
    func problemBeatsUnknown() {
        let combined = CombinedStatus.combine([
            snapshot(.claude, .unknown),
            snapshot(.github, .major, affected: ["Copilot"])
        ])
        #expect(combined.indicator == .major)
        #expect(combined.description == "Major issues affecting GitHub Copilot")
    }

    @Test("Snapshot round-trips through JSON")
    func codable() throws {
        let services = ServiceRegistry.ids.map { snapshot($0, .operational) }
        let original = Snapshot(
            services: services,
            combined: .combine(services),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let decoded = try decoder.decode(Snapshot.self, from: encoder.encode(original))
        #expect(decoded == original)
        #expect(decoded[.claude]?.name == "Claude AI")
    }
}
