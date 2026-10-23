import Testing
@testable import UsageViews

@Suite struct DotTests {
    @Test func fillsSpareAllotmentUpToTheEvenBurn() {
        #expect(Dot.bar(columns: 5, percent: 20, evenBurn: 60) == [.used, .spare, .spare, .unearned, .unearned])
    }

    @Test func leavesEveryUnusedDotUnearnedOverPace() {
        #expect(Dot.bar(columns: 5, percent: 60, evenBurn: 40) == [.used, .used, .used, .unearned, .unearned])
    }

    @Test func earnsNothingBeforeTheWindowStarts() {
        #expect(Dot.bar(columns: 5, percent: 0, evenBurn: nil) == [.unearned, .unearned, .unearned, .unearned, .unearned])
    }
}
