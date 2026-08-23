import AppKit
import SwiftUI
import Testing
@testable import VibeStats

/// Renders the popover offscreen so the design can be reviewed by eye without
/// fighting the window server for focus.
@Suite("Popover snapshots", .serialized)
@MainActor
struct PopoverSnapshotTests {

    private func coordinator(_ client: StubAPIClient) async -> (MonitorCoordinator, Preferences) {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let preferences = Preferences(defaults: UserDefaults(suiteName: "snap-\(UUID().uuidString)")!)
        let coordinator = MonitorCoordinator(
            engine: StatusEngine(client: client),
            store: SnapshotStore(directory: directory),
            history: HistoryLog(directory: directory),
            preferences: preferences
        )
        await coordinator.refresh(reason: .manual)
        return (coordinator, preferences)
    }

    private func render(
        _ coordinator: MonitorCoordinator,
        _ preferences: Preferences,
        appearance name: NSAppearance.Name,
        to filename: String
    ) throws {
        // The scrolling body only — ImageRenderer lays a ScrollView out to
        // nothing, and Menu/link buttons render as placeholder glyphs.
        let view = PopoverContentView(
            coordinator: coordinator,
            preferences: preferences,
            history: [:],
            motion: .off
        )
            .frame(width: 420)
            .environment(\.colorScheme, name == .darkAqua ? .dark : .light)
            .background(name == .darkAqua ? Color(nsColor: NSColor(hex: 0x1C222E))
                                          : Color(nsColor: NSColor(hex: 0xF2F4F8)))

        let renderer = ImageRenderer(content: view)
        renderer.scale = 2

        let appearance = try #require(NSAppearance(named: name))
        var png: Data?
        appearance.performAsCurrentDrawingAppearance {
            if let image = renderer.nsImage,
               let bitmap = image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)) {
                png = bitmap.representation(using: .png, properties: [:])
            }
        }

        let data = try #require(png)
        let url = FileManager.default.temporaryDirectory.appending(path: filename)
        try data.write(to: url)
        print("POPOVER SNAPSHOT: \(url.path)")
    }

    @Test("Healthy state renders in both appearances")
    func healthy() async throws {
        let (coordinator, preferences) = await coordinator(try .liveFixtures())
        try render(coordinator, preferences, appearance: .darkAqua, to: "popover-healthy-dark.png")
        try render(coordinator, preferences, appearance: .aqua, to: "popover-healthy-light.png")
    }

    @Test("A degraded state renders the divergence chip and the affected subtitle")
    func degraded() async throws {
        let client = try StubAPIClient.liveFixtures()

        // GitHub: Copilot in a partial outage, under a calm page indicator.
        await client.override("github/components.json", with: .data(
            try Fixture.mutated("github-components") { json in
                var components = json["components"] as! [[String: Any]]
                for index in components.indices {
                    switch components[index]["name"] as? String {
                    case "Copilot":     components[index]["status"] = "partial_outage"
                    case "Codespaces":  components[index]["status"] = "degraded_performance"
                    default: break
                    }
                }
                json["components"] = components
            }
        ))
        // Claude: a component renamed out from under us, so it reads UNKNOWN.
        await client.override("claude/components.json", with: .data(
            try Fixture.mutated("claude-components") { json in
                var components = json["components"] as! [[String: Any]]
                for index in components.indices
                where components[index]["name"] as? String == "Claude Code" {
                    components[index]["name"] = "Anthropic Coding Agent"
                }
                json["components"] = components
            }
        ))
        // OpenAI: entirely unreachable.
        await client.override("openai/status.json", with: .failure(.http(status: 503)))
        await client.override("openai/components.json", with: .failure(.http(status: 503)))
        await client.override("openai/incidents.json", with: .failure(.http(status: 503)))

        let (coordinator, preferences) = await coordinator(client)
        try render(coordinator, preferences, appearance: .darkAqua, to: "popover-degraded-dark.png")
        try render(coordinator, preferences, appearance: .aqua, to: "popover-degraded-light.png")

        #expect(coordinator.combined.indicator == .major)
        #expect(coordinator.snapshot?[.github]?.divergesFromPage == true)
        #expect(coordinator.snapshot?[.claude]?.unresolvedCount == 1)
        #expect(coordinator.snapshot?[.openai]?.indicator == .unknown)
    }
}
