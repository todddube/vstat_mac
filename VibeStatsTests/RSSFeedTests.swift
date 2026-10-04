import Foundation
import Testing
@testable import VibeStats

@Suite("RSS incident feeds (Grok)")
struct RSSFeedTests {
    /// The recorded feed's newest item: an outage resolved on 22 Sep 2026.
    private let afterFeed = RSSFeed.date("Wed, 23 Sep 2026 12:00:00 GMT")!

    @Test("The recorded feed parses: bracketed component, dates, updates")
    func parses() throws {
        let items = try RSSFeed.parse(Fixture.data("grok-feed", extension: "xml"))
        #expect(items.count > 50)

        let first = try #require(items.first)
        #expect(first.componentName == "API (us-east-1.api.x.ai)")
        #expect(first.incidentName == "Outages across API, Grok.com, and Grok Build")
        #expect(first.isResolved)
        #expect(first.published != nil)
        #expect(first.resolvedAt != nil)
        #expect(first.updates.count == 3)
        #expect(first.updates.first?.title == "Resolved")
    }

    @Test("A feed of resolved incidents is healthy — and only claims what it derived")
    func resolvedIsHealthy() async throws {
        let engine = StatusEngine(client: try StubAPIClient.liveFixtures())
        let snapshot = await engine.check(ServiceRegistry.grok, now: afterFeed)

        #expect(snapshot.indicator == .operational)
        #expect(snapshot.error == nil)
        #expect(snapshot.components.count == ServiceRegistry.grok.components.count)
        #expect(snapshot.components.allSatisfy { $0.provenance == .derivedFromIncidents })
        #expect(!snapshot.incidents.isEmpty)
    }

    @Test("An open incident marks only the component it names")
    func openIncident() async throws {
        // Re-open the newest item and move it to Grok (Web).
        let feed = try Fixture.text("grok-feed", extension: "xml") { xml in
            var xml = xml
            if let range = xml.range(of: "[API (us-east-1.api.x.ai)] Outages across API") {
                xml.replaceSubrange(range, with: "[Grok (Web)] Outages across API")
            }
            if let range = xml.range(of: "<h3>Status: RESOLVED</h3>") {
                xml.replaceSubrange(range, with: "<h3>Status: INVESTIGATING</h3>")
            }
            if let range = xml.range(of: "<p>Resolved: Tue, 22 Sep 2026 01:28:30 GMT</p>") {
                xml.replaceSubrange(range, with: "")
            }
            if let range = xml.range(of: "<category>resolved</category>") {
                xml.replaceSubrange(range, with: "<category>investigating</category>")
            }
            return xml
        }
        let client = try StubAPIClient.liveFixtures()
        await client.override("grok/feed.xml", with: .data(feed))

        let snapshot = await StatusEngine(client: client).check(ServiceRegistry.grok, now: afterFeed)
        let web = try #require(snapshot.components.first { $0.id == "grok-web" })

        // "Severity: available" on an OPEN incident still floors at minor.
        #expect(web.indicator == .minor)
        #expect(snapshot.indicator == .minor)
        #expect(snapshot.affectedComponents == ["Grok.com"])
        #expect(snapshot.components.filter { $0.id != "grok-web" }.allSatisfy { $0.indicator == .operational })
    }

    @Test("Open-incident severity never reads as healthy", arguments: [
        ("available", StatusIndicator.minor),
        ("", .minor),
        ("degraded_performance", .minor),
        ("partial_outage", .major),
        ("outage", .major),
        ("unavailable", .major),
        ("major_outage", .critical)
    ])
    func severity(raw: String, expected: StatusIndicator) {
        #expect(RSSFeedAdapter.indicator(forOpenIncidentSeverity: raw) == expected)
    }

    @Test("Every API region rolls into the one API component")
    func regions() {
        let api = ServiceRegistry.grok.component(id: "grok-api")!
        for region in ["api (us-east-1.api.x.ai)", "api (us-west-2.api.x.ai)", "api (eu-west-1.api.x.ai)"] {
            #expect(RSSFeedAdapter.matches(api, region))
        }
        #expect(!RSSFeedAdapter.matches(api, "api console"))
    }

    @Test("Not XML is a decoding error, which degrades only Grok to unknown")
    func garbage() async throws {
        let client = try StubAPIClient.liveFixtures()
        await client.override("grok/feed.xml", with: .data(Data("<html><body>blocked".utf8)))
        let snapshot = await StatusEngine(client: client).check(ServiceRegistry.grok, now: afterFeed)
        #expect(snapshot.indicator == .unknown)
        #expect(snapshot.error != nil)
    }
}
