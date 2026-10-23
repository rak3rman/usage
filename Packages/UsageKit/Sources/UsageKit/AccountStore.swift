import Foundation
import OSLog
import Security

public struct StoredAccount: Codable, Sendable, Hashable, Identifiable {
    public let id: AccountID
    public var name: String
    public var plan: String
    /** `nil` once the provider rejects the refresh token. */
    public var grant: Grant?

    public init(id: AccountID, name: String, plan: String, grant: Grant?) {
        self.id = id
        self.name = name
        self.plan = plan
        self.grant = grant
    }

    init(id: AccountID, name: String, plan: String, tokens: Tokens, now: Date) throws {
        guard let refreshToken = tokens.refreshToken, !refreshToken.isEmpty else {
            throw UsageError(.signInRequired, "sign-in returned no refresh_token")
        }
        self.init(id: id, name: name, plan: plan, grant: Grant(
            refreshToken: refreshToken, tokens: tokens, now: now))
    }
}

public struct Grant: Codable, Sendable, Hashable {
    public var refreshToken: String
    public var accessToken: String?
    public var accessExpiresAt: Date?

    /** Seconds before the provider's stated expiry that an access token is retired. */
    static let expiryMargin: TimeInterval = 60
}

extension Grant {
    init(refreshToken: String, tokens: Tokens, now: Date) {
        self.refreshToken = tokens.refreshToken.flatMap { $0.isEmpty ? nil : $0 } ?? refreshToken
        if let life = tokens.expiresIn, life > Self.expiryMargin {
            accessToken = tokens.accessToken
            accessExpiresAt = now.addingTimeInterval(life - Self.expiryMargin)
        }
    }
}

public protocol SecretStorage: Sendable {
    func read() throws -> Data?
    func write(_ data: Data) throws
}

/** One generic-password item in the login keychain. */
public struct Keychain: SecretStorage {
    private let service: String

    public init(service: String) { self.service = service }

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service]
    }

    public func read() throws -> Data? {
        var lookup = query
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(lookup as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw KeychainError(operation: "read", status: status)
        }
        return data
    }

    public func write(_ data: Data) throws {
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else {
            throw KeychainError(operation: "update", status: status)
        }
        var item = query
        item[kSecValueData as String] = data
        let added = SecItemAdd(item as CFDictionary, nil)
        guard added == errSecSuccess else { throw KeychainError(operation: "add", status: added) }
    }
}

public struct KeychainError: Error, Sendable, CustomStringConvertible {
    let operation: String
    let status: OSStatus

    public var description: String {
        let message = SecCopyErrorMessageString(status, nil) as String? ?? "unknown"
        return "keychain \(operation) failed: \(message) (\(status))"
    }
}

/**
 * The signed-in accounts and their OAuth grants.
 *
 * A list that could not be read is never written. Refreshes run one at a time per
 * account, and a rotated refresh token is saved before its access token is returned.
 */
public actor AccountStore {
    private let storage: any SecretStorage
    public nonisolated let services: [Provider: any UsageService]
    private let now: @Sendable () -> Date
    private var accounts: [StoredAccount]?
    private var refreshes: [AccountID: Task<String, any Error>] = [:]
    private static let log = Logger(subsystem: "io.radison.usage", category: "accounts")

    public init(
        storage: any SecretStorage,
        services: [any UsageService],
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.storage = storage
        self.services = Dictionary(uniqueKeysWithValues: services.map { ($0.provider, $0) })
        self.now = now
    }

    public func list() throws -> [StoredAccount] {
        if let accounts { return accounts }
        let loaded = try storage.read().map {
            try JSONDecoder().decode([StoredAccount].self, from: $0)
        } ?? []
        accounts = loaded
        return loaded
    }

    /** Add the account, or replace the one with the same ID. */
    public func save(_ account: StoredAccount) throws {
        var updated = try list()
        if let index = updated.firstIndex(where: { $0.id == account.id }) {
            updated[index] = account
        } else {
            updated.append(account)
        }
        try persist(updated)
    }

    public func remove(_ id: AccountID) throws {
        try persist(try list().filter { $0.id != id })
    }

    public func accessToken(for id: AccountID) async throws -> String {
        if let running = refreshes[id] { return try await running.value }
        guard let grant = try list().first(where: { $0.id == id })?.grant else {
            throw UsageError(.signInRequired, "\(id) has no grant")
        }
        if let token = grant.accessToken, let expiry = grant.accessExpiresAt, expiry > now() {
            return token
        }
        let refresh = Task { try await self.refresh(id, spending: grant.refreshToken) }
        refreshes[id] = refresh
        defer { refreshes[id] = nil }
        return try await refresh.value
    }

    public func discard(accessToken: String, for id: AccountID) {
        guard var account = accounts?.first(where: { $0.id == id }),
              account.grant?.accessToken == accessToken else { return }
        account.grant?.accessToken = nil
        account.grant?.accessExpiresAt = nil
        keep(account)
    }

    private func refresh(_ id: AccountID, spending refreshToken: String) async throws -> String {
        guard let service = services[id.provider] else {
            throw UsageError(.signInRequired, "no service for \(id.provider.rawValue)")
        }
        let tokens: Tokens
        do {
            tokens = try await service.refresh(refreshToken)
        } catch is RefreshRejected {
            Self.log.error("\(id, privacy: .public): refresh token rejected")
            if var account = holding(refreshToken, id) {
                account.grant = nil
                keep(account)
            }
            throw UsageError(.signInRequired, "refresh token rejected")
        }
        if var account = holding(refreshToken, id) {
            account.grant = Grant(refreshToken: refreshToken, tokens: tokens, now: now())
            keep(account)
        }
        return tokens.accessToken
    }

    private func holding(_ refreshToken: String, _ id: AccountID) -> StoredAccount? {
        accounts?.first { $0.id == id && $0.grant?.refreshToken == refreshToken }
    }

    /** Save the account; one the keychain refuses stays in memory until the next save. */
    private func keep(_ account: StoredAccount) {
        do {
            try save(account)
        } catch {
            Self.log.error("\(account.id, privacy: .public): not saved: \(String(describing: error), privacy: .public)")
            accounts = accounts?.map { $0.id == account.id ? account : $0 }
        }
    }

    private func persist(_ updated: [StoredAccount]) throws {
        try storage.write(try JSONEncoder().encode(updated))
        accounts = updated
    }
}
