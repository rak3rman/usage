import Foundation
import OSLog

extension AccountStore {
    private static let usageLog = Logger(subsystem: "io.radison.usage", category: "usage")

    /**
     * Read every stored account's limits, in stored order.
     *
     * A failure becomes that account's reading; it never hides the other accounts.
     *
     * - Throws: when the account list itself cannot be read.
     */
    public nonisolated func readUsage() async throws -> [AccountUsage] {
        let accounts = try await list()
        return await withTaskGroup(of: (Int, AccountUsage).self) { group in
            for (index, account) in accounts.enumerated() {
                group.addTask { (index, await self.readUsage(of: account)) }
            }
            var readings: [(Int, AccountUsage)] = []
            for await reading in group { readings.append(reading) }
            return readings.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    private nonisolated func readUsage(of account: StoredAccount) async -> AccountUsage {
        do {
            let report = try await report(account)
            return AccountUsage(
                id: account.id, name: account.name, plan: report.plan, reading: .limits(report.limits))
        } catch {
            let failure = (error as? UsageError)?.failure ?? .unexpectedResponse
            Self.usageLog.error("\(account.id, privacy: .public): \(String(describing: error), privacy: .public)")
            return AccountUsage(
                id: account.id, name: account.name, plan: account.plan, reading: .failed(failure))
        }
    }

    /**
     * Fetch the account's usage.
     *
     * A refused access token is discarded and the request retried once with a fresh one.
     */
    private nonisolated func report(_ account: StoredAccount) async throws -> UsageReport {
        guard let service = services[account.id.provider] else {
            throw UsageError(.signInRequired, "no service for \(account.id.provider.rawValue)")
        }
        let token = try await accessToken(for: account.id)
        do {
            return try await service.usage(of: account, accessToken: token)
        } catch let error as UsageError where error.failure == .signInRequired {
            await discard(accessToken: token, for: account.id)
            let fresh = try await accessToken(for: account.id)
            guard fresh != token else { throw error }
            return try await service.usage(of: account, accessToken: fresh)
        }
    }
}
