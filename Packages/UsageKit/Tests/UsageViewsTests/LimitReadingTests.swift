import Foundation
import Testing
import UsageKit
@testable import UsageViews

@Suite struct LimitReadingTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func reading(
        _ percent: Double, resetsIn seconds: TimeInterval, _ kind: WindowKind
    ) -> LimitReading {
        LimitReading(
            LimitWindow(percent: percent, resetsAt: now.addingTimeInterval(seconds)), kind, now: now)
    }

    private func printed(_ reading: LimitReading) -> String { reading.figure + (reading.pace ?? "") }

    @Test func staysQuietOnPace() {
        let onPace = reading(41, resetsIn: 3 * 3600, .session)
        #expect(printed(onPace) == "3h:41%")
        #expect(onPace.tone == .quiet)
    }

    @Test func showsTheSurplusWhenUnderPace() {
        let under = reading(41, resetsIn: 2 * 3600, .session)
        #expect(printed(under) == "2h:41%+19")
        #expect(under.tone == .underPace)
    }

    @Test func needsALargerSurplusOnTheSessionWindow() {
        #expect(reading(52, resetsIn: 2 * 3600, .session).tone == .quiet)
        #expect(printed(reading(49, resetsIn: 3 * 86_400, .weekly)) == "3d:49%+8")
    }

    @Test func showsTheDeficitWhenOverPace() {
        let over = reading(64, resetsIn: 3 * 86_400, .weekly)
        #expect(printed(over) == "3d:64%-7")
        #expect(over.tone == .overPace)
    }

    @Test func turnsCriticalFromNinetyPercent() {
        let critical = reading(93, resetsIn: 600, .session)
        #expect(printed(critical) == "10m:93%+4")
        #expect(critical.tone == .critical)
    }

    @Test func neverCountsPastTheWindowLength() {
        #expect(reading(0, resetsIn: 18_025, .session).figure == "5h:0%")
        #expect(reading(0, resetsIn: 604_825, .weekly).figure == "7d:0%")
    }

    @Test(arguments: [(59.0, "1m"), (3_600, "1h"), (3_601, "2h"), (86_401, "2d")])
    func roundsTheTimeToResetUp(seconds: TimeInterval, label: String) {
        #expect(reading(0, resetsIn: seconds, .weekly).figure == "\(label):0%")
    }

    @Test func placesTheEvenBurnByTimeElapsed() {
        #expect(reading(20, resetsIn: 2 * 3600, .session).evenBurn == 60)
        #expect(LimitReading(LimitWindow(percent: 60, resetsAt: nil), .session, now: now).evenBurn == nil)
    }
}
