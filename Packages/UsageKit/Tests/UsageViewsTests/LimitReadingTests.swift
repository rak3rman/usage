import Foundation
import Testing
import UsageKit
@testable import UsageViews

@Suite struct LimitReadingTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func reading(
        _ percent: Double, resetsIn seconds: TimeInterval, _ window: (Double, Date?) -> LimitWindow
    ) -> LimitReading {
        LimitReading(window(percent, now.addingTimeInterval(seconds)), now: now)
    }

    private func printed(_ reading: LimitReading) -> String { reading.figure + (reading.pace ?? "") }

    @Test func staysQuietOnPace() {
        let onPace = reading(41, resetsIn: 3 * 3600, LimitWindow.session)
        #expect(printed(onPace) == "3h:41%")
        #expect(onPace.tone == .quiet)
    }

    @Test func showsTheSurplusWhenUnderPace() {
        let under = reading(41, resetsIn: 2 * 3600, LimitWindow.session)
        #expect(printed(under) == "2h:41%+19")
        #expect(under.tone == .underPace)
    }

    @Test func needsALargerSurplusOnTheSessionWindow() {
        #expect(reading(52, resetsIn: 2 * 3600, LimitWindow.session).tone == .quiet)
        #expect(printed(reading(49, resetsIn: 3 * 86_400, LimitWindow.weekly)) == "3d:49%+8")
    }

    @Test func showsTheDeficitWhenOverPace() {
        let over = reading(64, resetsIn: 3 * 86_400, LimitWindow.weekly)
        #expect(printed(over) == "3d:64%-7")
        #expect(over.tone == .overPace)
    }

    @Test func turnsCriticalFromNinetyPercent() {
        let critical = reading(93, resetsIn: 600, LimitWindow.session)
        #expect(printed(critical) == "10m:93%+4")
        #expect(critical.tone == .critical)
    }

    @Test func neverCountsPastTheWindowLength() {
        #expect(reading(0, resetsIn: 18_025, LimitWindow.session).figure == "5h:0%")
        #expect(reading(0, resetsIn: 604_825, LimitWindow.weekly).figure == "7d:0%")
    }

    @Test(arguments: [(59.0, "1m"), (3_600, "1h"), (3_601, "2h"), (86_401, "2d")])
    func roundsTheTimeToResetUp(seconds: TimeInterval, label: String) {
        #expect(reading(0, resetsIn: seconds, LimitWindow.weekly).figure == "\(label):0%")
    }

    @Test func placesTheEvenBurnByTimeElapsed() {
        #expect(reading(20, resetsIn: 2 * 3600, LimitWindow.session).evenBurn == 60)
        #expect(LimitReading(.session(percent: 60, resetsAt: nil), now: now).evenBurn == nil)
    }

    @Test func namesACursorAllowanceInPlaceOfTheTimeToReset() {
        let cycle: TimeInterval = 31 * 86_400
        let auto = LimitReading(
            LimitWindow(.auto, percent: 7, resetsAt: now.addingTimeInterval(20 * 86_400), length: cycle), now: now)
        #expect(printed(auto) == "auto:7%+28")
        #expect(LimitReading(LimitWindow(.api, percent: 0, resetsAt: nil, length: cycle), now: now).figure == "api:0%")
    }
}
