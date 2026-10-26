import Foundation

public enum Provider: String, Codable, Sendable, CaseIterable {
    case claude, codex

    public var title: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        }
    }
}

public struct AccountID: Codable, Sendable, Hashable, CustomStringConvertible {
    public let provider: Provider
    /** Claude account UUID or ChatGPT account ID. */
    public let handle: String

    public init(provider: Provider, handle: String) {
        self.provider = provider
        self.handle = handle
    }

    public var description: String { "\(provider.rawValue)/\(handle)" }
}

public struct LimitWindow: Codable, Sendable, Hashable {
    /** Share of the window used, 0...100. */
    public let percent: Double
    /** Rounded to the whole minute. */
    public let resetsAt: Date?

    public init(percent: Double, resetsAt: Date?) {
        self.percent = percent
        self.resetsAt = resetsAt
    }
}

public struct Limits: Codable, Sendable, Hashable {
    /** The rolling five-hour window. */
    public let session: LimitWindow?
    /** The seven-day window. */
    public let weekly: LimitWindow?

    public init(session: LimitWindow?, weekly: LimitWindow?) {
        self.session = session
        self.weekly = weekly
    }

    public var peak: LimitWindow? {
        [session, weekly].compactMap { $0 }.max { $0.percent < $1.percent }
    }
}

public enum Failure: String, Codable, Sendable, Hashable {
    case signInRequired
    case offline
    case rateLimited
    case unexpectedResponse

    init(status: Int) {
        switch status {
        case 401, 403: self = .signInRequired
        case 429: self = .rateLimited
        default: self = .unexpectedResponse
        }
    }
}

public enum Reading: Codable, Sendable, Hashable {
    case limits(Limits)
    case failed(Failure)
    case rateLimited(Limits)
}

public struct AccountUsage: Codable, Sendable, Hashable, Identifiable {
    public let id: AccountID
    public let name: String
    public let plan: String
    public let reading: Reading

    public init(id: AccountID, name: String, plan: String, reading: Reading) {
        self.id = id
        self.name = name
        self.plan = plan
        self.reading = reading
    }

    public var limits: Limits? {
        switch reading {
        case .limits(let limits), .rateLimited(let limits): limits
        case .failed: nil
        }
    }
}

public struct UsageSnapshot: Codable, Sendable, Hashable {
    public let accounts: [AccountUsage]
    public let capturedAt: Date

    init(accounts: [AccountUsage], capturedAt: Date) {
        self.accounts = accounts
        self.capturedAt = capturedAt
    }

    public init(accounts: [AccountUsage], capturedAt: Date, previous: UsageSnapshot?) {
        self.init(
            accounts: accounts.map { usage in
                guard usage.reading == .failed(.rateLimited),
                      let held = previous?.accounts.first(where: { $0.id == usage.id }),
                      let limits = held.limits
                else { return usage }
                return AccountUsage(id: usage.id, name: usage.name, plan: held.plan, reading: .rateLimited(limits))
            },
            capturedAt: capturedAt)
    }
}

public struct UsageError: Error, Sendable, CustomStringConvertible {
    public let failure: Failure
    public let detail: String

    public init(_ failure: Failure, _ detail: String) {
        self.failure = failure
        self.detail = detail
    }

    public var description: String { "\(failure.rawValue): \(detail)" }
}
