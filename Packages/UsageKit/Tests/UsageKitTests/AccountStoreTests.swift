import Foundation
import Testing
@testable import UsageKit

@Suite struct AccountStoreTests {
    private let account = StoredAccount.sample("one")

    @Test func neverWritesOverAListItCouldNotRead() async throws {
        let storage = MemoryStorage(readError: KeychainError(operation: "read", status: -25293))
        let store = AccountStore(storage: storage, services: [FakeService()])

        await #expect(throws: KeychainError.self) { try await store.save(account) }
        #expect(storage.writes == 0)
    }

    @Test func refreshesOnceForConcurrentCallersAndSavesTheRotatedToken() async throws {
        let storage = MemoryStorage([account])
        let service = FakeService()
        let store = AccountStore(storage: storage, services: [service])

        async let first = store.accessToken(for: account.id)
        async let second = store.accessToken(for: account.id)
        let tokens = try await [first, second]

        #expect(tokens == ["access-for-refresh-0", "access-for-refresh-0"])
        #expect(await service.refreshes == ["refresh-0"])
        #expect(storage.accounts.first?.grant?.refreshToken == "rotated-refresh-0")
    }

    @Test func servesTheCachedAccessTokenUntilItExpires() async throws {
        let now = Date()
        let cached = StoredAccount.sample("one", accessToken: "cached", expiresAt: now.addingTimeInterval(10))
        let service = FakeService()
        let store = AccountStore(storage: MemoryStorage([cached]), services: [service], now: { now })

        #expect(try await store.accessToken(for: cached.id) == "cached")
        #expect(await service.refreshes.isEmpty)
    }

    @Test func dropsTheGrantWhenTheRefreshTokenIsRejected() async throws {
        let storage = MemoryStorage([account])
        let service = FakeService(refresh: { _ in throw RefreshRejected() })
        let store = AccountStore(storage: storage, services: [service])

        await #expect(throws: UsageError.self) { try await store.accessToken(for: account.id) }
        #expect(storage.accounts.first?.grant == nil)
    }
}
