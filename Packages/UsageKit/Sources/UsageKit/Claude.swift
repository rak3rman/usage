import Foundation

public struct Claude: LoopbackService {
    public let provider = Provider.claude
    public let redirect = LoopbackRedirect(port: nil, path: "/callback")

    private static let authorize = URL(string: "https://claude.com/cai/oauth/authorize")!
    private static let token = URL(string: "https://platform.claude.com/v1/oauth/token")!
    private static let profile = URL(string: "https://api.anthropic.com/api/oauth/profile")!
    private static let usage = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    /** The Claude Code CLI's public OAuth client. */
    private static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    private static let scope =
        "user:inference user:profile user:sessions:claude_code user:mcp_servers user:file_upload"
    /** The usage and profile endpoints answer only requests that present as the CLI. */
    private static let userAgent = "claude-cli/2.0.0 (external, cli)"

    public init() {}

    public func authorizationURL(redirectURI: String, pkce: PKCE, state: String) -> URL {
        var components = URLComponents(url: Self.authorize, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: Self.clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: Self.scope),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
        ]
        return components.url!
    }

    public func signIn(
        code: String, pkce: PKCE, redirectURI: String, state: String
    ) async throws -> StoredAccount {
        let body = try JSONSerialization.data(withJSONObject: [
            "grant_type": "authorization_code",
            "code": code,
            "code_verifier": pkce.verifier,
            "client_id": Self.clientID,
            "redirect_uri": redirectURI,
            "state": state,
        ])
        let (data, status) = try await send("POST", Self.token, headers: Self.jsonHeaders, body: body)
        guard status == 200 else {
            throw UsageError(Failure(status: status), "code exchange HTTP \(status)")
        }
        let tokens = try Tokens.decode(data)
        let (profileData, profileStatus) = try await send(
            "GET", Self.profile, headers: Self.headers(tokens.accessToken))
        guard profileStatus == 200 else {
            throw UsageError(Failure(status: profileStatus), "profile HTTP \(profileStatus)")
        }
        let profile = try ClaudeProfile.parse(profileData)
        return try StoredAccount(
            id: AccountID(provider: .claude, handle: profile.uuid),
            name: profile.name, plan: profile.plan, tokens: tokens, now: Date())
    }

    public func refresh(_ refreshToken: String) async throws -> Tokens {
        let body = try JSONSerialization.data(withJSONObject: [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": Self.clientID,
        ])
        let (data, status) = try await send("POST", Self.token, headers: Self.jsonHeaders, body: body)
        return try Tokens.refreshed(data, status: status)
    }

    public func usage(of account: StoredAccount, accessToken: String) async throws -> UsageReport {
        let (data, status) = try await send("GET", Self.usage, headers: Self.headers(accessToken))
        guard status == 200 else { throw UsageError(Failure(status: status), "usage HTTP \(status)") }
        return UsageReport(plan: account.plan, limits: try ClaudeUsage.parse(data))
    }

    private static let jsonHeaders = ["Content-Type": "application/json", "User-Agent": userAgent]

    private static func headers(_ accessToken: String) -> [String: String] {
        [
            "Authorization": "Bearer \(accessToken)",
            "anthropic-beta": "oauth-2025-04-20",
            "User-Agent": userAgent,
        ]
    }
}

struct ClaudeProfile: Equatable {
    let uuid: String
    let name: String
    let plan: String

    private struct Body: Decodable {
        struct Account: Decodable {
            let uuid: String
            let email: String?
            let displayName: String?
        }
        struct Organization: Decodable {
            let rateLimitTier: String?
        }
        let account: Account
        let organization: Organization?
    }

    static func parse(_ data: Data) throws -> ClaudeProfile {
        guard let body = try? snakeCase.decode(Body.self, from: data) else {
            throw UsageError(.unexpectedResponse, "profile not parsed")
        }
        return ClaudeProfile(
            uuid: body.account.uuid,
            name: body.account.email ?? body.account.displayName ?? body.account.uuid,
            plan: plan(tier: body.organization?.rateLimitTier))
    }

    private static func plan(tier: String?) -> String {
        switch tier {
        case "default_claude_max_20x": "Max 20x"
        case "default_claude_max_5x": "Max 5x"
        case "default_claude_pro": "Pro"
        case let other?: other
        case nil: "Claude"
        }
    }
}

/**
 * Parser for the OAuth usage response.
 *
 * Reads `limits[]` kinds `session` and `weekly_all`, skipping per-model entries (those
 * carry a `scope`), and falls back to `five_hour` and `seven_day`.
 */
enum ClaudeUsage {
    private struct Body: Decodable {
        struct Utilization: Decodable {
            let utilization: Double
            let resetsAt: String?
        }
        struct Limit: Decodable {
            let kind: String
            let percent: Double
            let resetsAt: String?
            let scope: Scope?
        }
        /** Present and non-null on per-model limits, whatever its shape. */
        struct Scope: Decodable {
            init(from decoder: any Decoder) throws {}
        }
        struct Lenient<Value: Decodable>: Decodable {
            let value: Value?
            init(from decoder: any Decoder) throws { value = try? Value(from: decoder) }
        }
        let fiveHour: Lenient<Utilization>?
        let sevenDay: Lenient<Utilization>?
        let limits: [Lenient<Limit>]?
    }

    static func parse(_ data: Data) throws -> Limits {
        guard let body = try? snakeCase.decode(Body.self, from: data) else {
            throw UsageError(.unexpectedResponse, "usage not parsed")
        }
        let limits = (body.limits ?? []).compactMap(\.value).filter { $0.scope == nil }
        func limit(_ kind: String) -> Body.Limit? { limits.first { $0.kind == kind } }
        var windows = [
            limit("session").map { LimitWindow.session(percent: $0.percent, resetsAt: instant($0.resetsAt)) },
            limit("weekly_all").map { LimitWindow.weekly(percent: $0.percent, resetsAt: instant($0.resetsAt)) },
        ].compactMap { $0 }
        if windows.isEmpty {
            windows = [
                body.fiveHour?.value.map { LimitWindow.session(percent: $0.utilization, resetsAt: instant($0.resetsAt)) },
                body.sevenDay?.value.map { LimitWindow.weekly(percent: $0.utilization, resetsAt: instant($0.resetsAt)) },
            ].compactMap { $0 }
        }
        guard !windows.isEmpty else {
            throw UsageError(.unexpectedResponse, "usage has no session or weekly window")
        }
        return Limits(windows)
    }

    private static let timestamp = Date.ISO8601FormatStyle(includingFractionalSeconds: true)

    private static func instant(_ resetsAt: String?) -> Date? {
        resetsAt.flatMap { try? timestamp.parse($0) }.map(wholeMinute)
    }
}

let snakeCase: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return decoder
}()

func wholeMinute(_ date: Date) -> Date {
    Date(timeIntervalSince1970: (date.timeIntervalSince1970 / 60).rounded() * 60)
}
