import Foundation
import Testing
@testable import UsageKit

@Suite struct UsageSnapshotTests {
    private let id = AccountID(provider: .claude, handle: "one")
    private let limits = UsageReport.sample.limits

    private func usage(_ reading: Reading, plan: String = "Pro") -> AccountUsage {
        AccountUsage(id: id, name: "one@example.com", plan: plan, reading: reading)
    }

    private func snapshot(_ reading: Reading, plan: String = "Pro") -> UsageSnapshot {
        UsageSnapshot(accounts: [usage(reading, plan: plan)], capturedAt: .distantPast)
    }

    @Test(arguments: [Reading.limits(UsageReport.sample.limits), .rateLimited(UsageReport.sample.limits)])
    func holdsTheLastLimitsWhenRateLimited(previous: Reading) {
        let next = UsageSnapshot(
            accounts: [usage(.failed(.rateLimited))], capturedAt: .now,
            previous: snapshot(previous, plan: "Max 20x"))

        #expect(next.accounts == [usage(.rateLimited(limits), plan: "Max 20x")])
    }

    @Test func dropsTheLastLimitsOnAnyOtherFailure() {
        let next = UsageSnapshot(
            accounts: [usage(.failed(.signInRequired))], capturedAt: .now, previous: snapshot(.limits(limits)))

        #expect(next.accounts.map(\.reading) == [.failed(.signInRequired)])
    }

    @Test func staysRateLimitedWithNoLimitsToHold() {
        let next = UsageSnapshot(
            accounts: [usage(.failed(.rateLimited))], capturedAt: .now, previous: snapshot(.failed(.offline)))

        #expect(next.accounts.map(\.reading) == [.failed(.rateLimited)])
    }
}
