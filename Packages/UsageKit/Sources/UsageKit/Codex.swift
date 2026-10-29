import Foundation

public struct Codex: LoopbackService {
    public let provider = Provider.codex
    /** The Codex CLI's OAuth client accepts only this redirect. */
    public let redirect = LoopbackRedirect(port: 1455, path: "/auth/callback")

    private static let authorize = URL(string: "https://auth.openai.com/oauth/authorize")!
    private static let token = URL(string: "https://auth.openai.com/oauth/token")!
    private static let usage = URL(string: "https://chatgpt.com/backend-api/wham/usage")!
    /** The Codex CLI's public OAuth client. */
    private static let clientID = "app_EMoamEEZ73f0CkXaXp7hrann"
    private static let formHeaders = ["Content-Type": "application/x-www-form-urlencoded"]

    public init() {}

    public func authorizationURL(redirectURI: String, pkce: PKCE, state: String) -> URL {
        var components = URLComponents(url: Self.authorize, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: Self.clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: "openid profile email offline_access"),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "id_token_add_organizations", value: "true"),
            URLQueryItem(name: "codex_cli_simplified_flow", value: "true"),
            URLQueryItem(name: "originator", value: "codex_cli_rs"),
            URLQueryItem(name: "prompt", value: "login"),
        ]
        return components.url!
    }

    public func signIn(
        code: String, pkce: PKCE, redirectURI: String, state: String
    ) async throws -> StoredAccount {
        let (data, status) = try await send(
            "POST", Self.token, headers: Self.formHeaders,
            body: FormBody.encode([
                "grant_type": "authorization_code",
                "code": code,
                "client_id": Self.clientID,
                "redirect_uri": redirectURI,
                "code_verifier": pkce.verifier,
            ]))
        guard status == 200 else {
            throw UsageError(Failure(status: status), "code exchange HTTP \(status)")
        }
        let tokens = try Tokens.decode(data)
        let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard let idToken = root?["id_token"] as? String else {
            throw UsageError(.unexpectedResponse, "code exchange has no id_token")
        }
        let identity = try CodexIdentity.parse(idToken: idToken)
        return try StoredAccount(
            id: AccountID(provider: .codex, handle: identity.accountID),
            name: identity.name, plan: identity.plan, tokens: tokens, now: Date())
    }

    public func refresh(_ refreshToken: String) async throws -> Tokens {
        let (data, status) = try await send(
            "POST", Self.token, headers: Self.formHeaders,
            body: FormBody.encode([
                "grant_type": "refresh_token",
                "refresh_token": refreshToken,
                "client_id": Self.clientID,
            ]))
        return try Tokens.refreshed(data, status: status)
    }

    public func usage(of account: StoredAccount, accessToken: String) async throws -> UsageReport {
        let (data, status) = try await send("GET", Self.usage, headers: [
            "Authorization": "Bearer \(accessToken)",
            "ChatGPT-Account-Id": account.id.handle,
            "Accept": "application/json",
        ])
        guard status == 200 else { throw UsageError(Failure(status: status), "usage HTTP \(status)") }
        let report = try CodexUsage.parse(data)
        return UsageReport(plan: report.plan ?? account.plan, limits: report.limits)
    }
}

struct CodexIdentity: Equatable {
    let accountID: String
    let name: String
    let plan: String

    /**
     * Read the account from an OpenID Connect ID token without verifying its signature.
     *
     * - Parameter idToken: JWT whose claims carry `email`, `name`, and
     *   `https://api.openai.com/auth` with `chatgpt_account_id` and `chatgpt_plan_type`.
     */
    static func parse(idToken: String) throws -> CodexIdentity {
        guard let claims = JSONWebToken.claims(idToken) else {
            throw UsageError(.unexpectedResponse, "id_token not parsed")
        }
        let auth = claims["https://api.openai.com/auth"] as? [String: Any] ?? [:]
        guard let accountID = auth["chatgpt_account_id"] as? String, !accountID.isEmpty else {
            throw UsageError(.unexpectedResponse, "id_token has no chatgpt_account_id")
        }
        return CodexIdentity(
            accountID: accountID,
            name: claims["email"] as? String ?? claims["name"] as? String ?? accountID,
            plan: (auth["chatgpt_plan_type"] as? String)?.capitalized ?? "ChatGPT")
    }
}

/**
 * Parser for `rate_limit.primary_window` and `secondary_window`.
 *
 * Each window is classified by `limit_window_seconds` when present: under a day is the
 * session window. An unused window reports its reset a full window away on every
 * request; it is read as not started, with no reset.
 */
enum CodexUsage {
    private struct Body: Decodable {
        struct RateLimit: Decodable {
            let primaryWindow: Window?
            let secondaryWindow: Window?
        }
        struct Window: Decodable {
            let usedPercent: Double
            let limitWindowSeconds: Double?
            let resetAt: Double?
            let resetAfterSeconds: Double?
        }
        let planType: String?
        let rateLimit: RateLimit
    }

    static func parse(_ data: Data, now: Date = Date()) throws -> (plan: String?, limits: Limits) {
        guard let body = try? snakeCase.decode(Body.self, from: data) else {
            throw UsageError(.unexpectedResponse, "usage not parsed")
        }
        var session: LimitWindow?
        var weekly: LimitWindow?
        for (window, isSessionByPosition) in [
            (body.rateLimit.primaryWindow, true), (body.rateLimit.secondaryWindow, false),
        ] {
            guard let window else { continue }
            guard window.usedPercent.isFinite, (0...100).contains(window.usedPercent) else {
                throw UsageError(.unexpectedResponse, "used_percent out of range")
            }
            let started = window.limitWindowSeconds.map { (window.resetAfterSeconds ?? 0) < $0 } ?? true
            let resetsAt = !started ? nil : window.resetAt.map { Date(timeIntervalSince1970: $0) }
                ?? window.resetAfterSeconds.map { now.addingTimeInterval($0) }
            if window.limitWindowSeconds.map({ $0 < 86_400 }) ?? isSessionByPosition {
                session = .session(percent: window.usedPercent, resetsAt: resetsAt.map(wholeMinute))
            } else {
                weekly = .weekly(percent: window.usedPercent, resetsAt: resetsAt.map(wholeMinute))
            }
        }
        let windows = [session, weekly].compactMap { $0 }
        guard !windows.isEmpty else {
            throw UsageError(.unexpectedResponse, "usage has no rate limit windows")
        }
        return (body.planType?.capitalized, Limits(windows))
    }
}
