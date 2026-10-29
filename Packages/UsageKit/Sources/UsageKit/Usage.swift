import Foundation

public enum Provider: String, Codable, Sendable, CaseIterable {
    case claude, codex, cursor

    public var title: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        case .cursor: "Cursor"
        }
    }
}

public struct AccountID: Codable, Sendable, Hashable, CustomStringConvertible {
    public let provider: Provider
    /** Claude account UUID, ChatGPT account ID, or Cursor user ID such as `auth0|user_01K…`. */
    public let handle: String

    public init(provider: Provider, handle: String) {
        self.provider = provider
        self.handle = handle
    }

    public var description: String { "\(provider.rawValue)/\(handle)" }
}

public enum LimitKind: String, Codable, Sendable, Hashable {
    /** The rolling five-hour window. */
    case session
    /** The seven-day window. */
    case weekly
    /** Cursor's Auto + Composer allowance for the billing cycle. */
    case auto
    /** Cursor's API allowance for the billing cycle. */
    case api
}

public struct LimitWindow: Codable, Sendable, Hashable {
    public let kind: LimitKind
    /** Share of the window used, 0...100. */
    public let percent: Double
    /** Rounded to the whole minute. */
    public let resetsAt: Date?
    /** Seconds from the window's start to its reset, above zero. */
    public let length: TimeInterval

    public init(_ kind: LimitKind, percent: Double, resetsAt: Date?, length: TimeInterval) {
        self.kind = kind
        self.percent = percent
        self.resetsAt = resetsAt
        self.length = length
    }

    public static func session(percent: Double, resetsAt: Date?) -> LimitWindow {
        LimitWindow(.session, percent: percent, resetsAt: resetsAt, length: 18_000)
    }

    public static func weekly(percent: Double, resetsAt: Date?) -> LimitWindow {
        LimitWindow(.weekly, percent: percent, resetsAt: resetsAt, length: 604_800)
    }
}

public struct Limits: Codable, Sendable, Hashable {
    /** In display order, one per kind. */
    public let windows: [LimitWindow]

    public init(_ windows: [LimitWindow]) {
        self.windows = windows
    }

    public var peak: LimitWindow? {
        windows.max { $0.percent < $1.percent }
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
