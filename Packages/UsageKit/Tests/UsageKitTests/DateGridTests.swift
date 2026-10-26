import Foundation
import Testing
@testable import UsageKit

@Suite struct DateGridTests {
    @Test func floorsToMarksCountedFromTheTopOfTheLocalHour() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Asia/Kathmandu"))
        let date = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 10, day: 23, hour: 14, minute: 7, second: 40)))

        let floored = calendar.dateComponents([.hour, .minute, .second], from: date.floored(toEvery: 300))

        #expect(floored == DateComponents(hour: 14, minute: 5, second: 0))
    }
}
