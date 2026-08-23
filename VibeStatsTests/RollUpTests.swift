import Testing
@testable import VibeStats

@Suite("RollUp — the docs/REVIEW.md §3.1 regression suite")
struct RollUpTests {

    @Test("Worst known state wins")
    func worstWins() {
        #expect(RollUp([.operational, .minor, .major]).indicator == .major)
        #expect(RollUp([.critical, .operational]).indicator == .critical)
        #expect(RollUp([.operational, .operational]).indicator == .operational)
        #expect(RollUp([.minor, .minor]).indicator == .minor)
    }

    /// The defect this whole type exists to prevent. In the extension,
    /// rollUpStatus(['unknown','unknown','unknown','unknown']) returns
    /// 'operational', which renders a total API blackout as
    /// "All dev tools are vibing!".
    @Test("All-unknown rolls up to unknown, NOT operational")
    func allUnknownIsUnknown() {
        let rollUp = RollUp([.unknown, .unknown, .unknown, .unknown])
        #expect(rollUp.indicator == .unknown)
        #expect(rollUp.unresolved == 4)
        #expect(rollUp.isConclusive == false)
    }

    @Test("An empty roll-up is unknown")
    func emptyIsUnknown() {
        let rollUp = RollUp([StatusIndicator]())
        #expect(rollUp.indicator == .unknown)
        #expect(rollUp.unresolved == 0)
    }

    @Test("Unknowns neither raise nor lower the verdict, but are counted")
    func unknownsAreCountedNotRanked() {
        let rollUp = RollUp([.operational, .unknown, .unknown, .operational])
        #expect(rollUp.indicator == .operational)
        #expect(rollUp.unresolved == 2)
        #expect(rollUp.isConclusive)
    }

    @Test("An unknown never masks a real problem")
    func unknownDoesNotMask() {
        let rollUp = RollUp([.unknown, .critical, .unknown])
        #expect(rollUp.indicator == .critical)
        #expect(rollUp.unresolved == 2)
    }

    @Test("Order does not affect the verdict")
    func orderIndependent() {
        let indicators: [StatusIndicator] = [.minor, .critical, .unknown, .operational, .major]
        #expect(RollUp(indicators).indicator == .critical)
        #expect(RollUp(indicators.reversed()).indicator == .critical)
        #expect(RollUp(indicators.shuffled()).indicator == .critical)
    }
}
