import Foundation
@testable import UsageKit

final class MemoryStorage: SecretStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var data: Data?
    private let readError: (any Error)?
    private(set) var writes = 0

    init(_ accounts: [StoredAccount] = [], readError: (any Error)? = nil) {
        data = try? JSONEncoder().encode(accounts)
        self.readError = readError
    }

    func read() throws -> Data? {
        if let readError { throw readError }
        return lock.withLock { data }
    }

    func write(_ data: Data) throws {
        lock.withLock {
            self.data = data
            writes += 1
        }
    }

    var accounts: [StoredAccount] {
        lock.withLock { data.flatMap { try? JSONDecoder().decode([StoredAccount].self, from: $0) } ?? [] }
    }
}

actor FakeService: UsageService {
    nonisolated let provider: Provider
    private(set) var refreshes: [String] = []
    private let refreshResult: @Sendable (String) throws -> Tokens
    private let usageResult: @Sendable (String) throws -> UsageReport

    init(
        _ provider: Provider = .claude,
        refresh: @escaping @Sendable (String) throws -> Tokens = {
            Tokens(accessToken: "access-for-\($0)", refreshToken: "rotated-\($0)", expiresIn: 3600)
        },
        usage: @escaping @Sendable (String) throws -> UsageReport = { _ in .sample }
    ) {
        self.provider = provider
        refreshResult = refresh
        usageResult = usage
    }

    nonisolated func signIn(open: @Sendable (URL) async -> Bool) async throws -> StoredAccount {
        throw UsageError(.unexpectedResponse, "not used")
    }

    func refresh(_ refreshToken: String) async throws -> Tokens {
        refreshes.append(refreshToken)
        try await Task.sleep(for: .milliseconds(20))
        return try refreshResult(refreshToken)
    }

    nonisolated func usage(of account: StoredAccount, accessToken: String) async throws -> UsageReport {
        try usageResult(accessToken)
    }
}

extension UsageReport {
    static let sample = UsageReport(
        plan: "Max 20x",
        limits: Limits([.session(percent: 42, resetsAt: nil), .weekly(percent: 18, resetsAt: nil)]))
}

extension StoredAccount {
    static func sample(
        _ handle: String, provider: Provider = .claude, refreshToken: String = "refresh-0",
        accessToken: String? = nil, expiresAt: Date? = nil
    ) -> StoredAccount {
        StoredAccount(
            id: AccountID(provider: provider, handle: handle), name: "\(handle)@example.com",
            plan: "Pro",
            grant: Grant(refreshToken: refreshToken, accessToken: accessToken, accessExpiresAt: expiresAt))
    }
}

func json(_ text: String) -> Data { Data(text.utf8) }
