import Testing
@testable import VibeStats

@Suite("StatusIndicator mapping")
struct StatusIndicatorTests {

    @Test("Statuspage component states map onto the five-level scale", arguments: [
        ("operational",           StatusIndicator.operational),
        ("under_maintenance",     .minor),
        ("degraded_performance",  .minor),
        ("partial_outage",        .major),
        ("major_outage",          .critical)
    ])
    func componentStatusTable(raw: String, expected: StatusIndicator) {
        #expect(StatusIndicator(componentStatus: raw) == expected)
    }

    @Test("Unrecognised vendor states fall back to keyword sniffing", arguments: [
        ("degraded_availability", StatusIndicator.minor),
        ("MAJOR_DISRUPTION",      .critical),
        ("critical_failure",      .critical),
        ("scheduled_maintenance", .minor),
        ("none",                  .operational),
        ("fully_operational",     .operational)
    ])
    func componentStatusSniffing(raw: String, expected: StatusIndicator) {
        #expect(StatusIndicator(componentStatus: raw) == expected)
    }

    @Test("Sniffing precedence: major/critical beats partial beats degraded")
    func sniffingPrecedence() {
        #expect(StatusIndicator(componentStatus: "partial_degradation") == .major)
        #expect(StatusIndicator(componentStatus: "major_partial") == .critical)
        #expect(StatusIndicator(componentStatus: "degraded") == .minor)
    }

    @Test("Empty, nil and nonsense component states are unknown — never operational")
    func componentStatusUnknown() {
        #expect(StatusIndicator(componentStatus: nil) == .unknown)
        #expect(StatusIndicator(componentStatus: "") == .unknown)
        #expect(StatusIndicator(componentStatus: "   ") == .unknown)
        #expect(StatusIndicator(componentStatus: "banana") == .unknown)
    }

    @Test("Whitespace and case are normalised")
    func normalisation() {
        #expect(StatusIndicator(componentStatus: "  MAJOR_OUTAGE  ") == .critical)
        #expect(StatusIndicator(pageIndicator: " Minor ") == .minor)
    }

    @Test("Page indicators map onto the same scale", arguments: [
        ("none",        StatusIndicator.operational),
        ("operational", .operational),
        ("minor",       .minor),
        ("major",       .major),
        ("critical",    .critical),
        ("maintenance", .minor),
        ("weird",       .unknown)
    ])
    func pageIndicatorTable(raw: String, expected: StatusIndicator) {
        #expect(StatusIndicator(pageIndicator: raw) == expected)
    }

    @Test("unknown is not on the severity scale")
    func unknownHasNoSeverity() {
        #expect(StatusIndicator.unknown.severity == nil)
        #expect(StatusIndicator.unknown.isKnown == false)
        for indicator in StatusIndicator.allCases where indicator != .unknown {
            #expect(indicator.severity != nil)
        }
    }

    @Test("Every case has a title and a compact title")
    func labels() {
        for indicator in StatusIndicator.allCases {
            #expect(!indicator.title.isEmpty)
            #expect(!indicator.compactTitle.isEmpty)
        }
        #expect(StatusIndicator.operational.compactTitle == "OK")
        #expect(StatusIndicator.critical.compactTitle == "OUTAGE")
    }
}
