import Foundation
import Testing
@testable import UsageKit

@Suite struct ReadUsageTests {
    @Test func retriesOnceWithAFreshTokenWhenTheCachedOneIsRefused() async throws {
        let account = StoredAccount.sample("one", accessToken: "stale", expiresAt: .distantFuture)
        let service = FakeService(usage: { token in
            guard token != "stale" else { throw UsageError(.signInRequired, "HTTP 401") }
            return .sample
        })
        let store = AccountStore(storage: MemoryStorage([account]), services: [service])

        let readings = try await store.readUsage()

        #expect(readings.map(\.reading) == [.limits(UsageReport.sample.limits)])
        #expect(await service.refreshes == ["refresh-0"])
    }

    @Test func keepsEveryAccountInOrderWhenOneFails() async throws {
        let claude = StoredAccount.sample("one")
        let codex = StoredAccount.sample("two", provider: .codex)
        let services: [any UsageService] = [
            FakeService(.claude, usage: { _ in throw UsageError(.rateLimited, "HTTP 429") }),
            FakeService(.codex),
        ]
        let store = AccountStore(storage: MemoryStorage([claude, codex]), services: services)

        let readings = try await store.readUsage()

        #expect(readings.map(\.id) == [claude.id, codex.id])
        #expect(readings.map(\.reading) == [.failed(.rateLimited), .limits(UsageReport.sample.limits)])
    }
}
