import Foundation

public struct Cursor: UsageService {
    public let provider = Provider.cursor

    private static let login = URL(string: "https://cursor.com/loginDeepControl")!
    private static let poll = URL(string: "https://api2.cursor.sh/auth/poll")!
    private static let token = URL(string: "https://api2.cursor.sh/oauth/token")!
    private static let me = URL(string: "https://cursor.com/api/auth/me")!
    private static let membership = URL(string: "https://api2.cursor.sh/auth/full_stripe_profile")!
    private static let usage = URL(
        string: "https://api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentPeriodUsage")!
    /** The Cursor editor's public OAuth client. */
    private static let clientID = "KbZUR41cY7W6zRSdpSUJ7I7mLYBKOCmB"
    private static let pollInterval: Duration = .seconds(2)

    public init() {}

    public func signIn(open: @Sendable (URL) async -> Bool) async throws -> StoredAccount {
        let pkce = PKCE()
        let uuid = UUID().uuidString.lowercased()
        var page = URLComponents(url: Self.login, resolvingAgainstBaseURL: false)!
        page.queryItems = [
            URLQueryItem(name: "challenge", value: pkce.challenge),
            URLQueryItem(name: "uuid", value: uuid),
            URLQueryItem(name: "mode", value: "login"),
        ]
        guard await open(page.url!) else { throw SignInError.browserUnavailable }
        var poll = URLComponents(url: Self.poll, resolvingAgainstBaseURL: false)!
        poll.queryItems = [
            URLQueryItem(name: "uuid", value: uuid),
            URLQueryItem(name: "verifier", value: pkce.verifier),
        ]
        let deadline = ContinuousClock.now + SignIn.timeout
        while ContinuousClock.now < deadline {
            try await Task.sleep(for: Self.pollInterval)
            let (data, status) = try await send("GET", poll.url!, headers: [:])
            if status == 404 { continue }
            guard status == 200 else { throw UsageError(Failure(status: status), "poll HTTP \(status)") }
            let session = try CursorSession.login(data)
            return try await account(userID: session.userID, tokens: session.tokens)
        }
        throw SignInError.timedOut
    }

    public func refresh(_ refreshToken: String) async throws -> Tokens {
        let body = try JSONSerialization.data(withJSONObject: [
            "grant_type": "refresh_token",
            "client_id": Self.clientID,
            "refresh_token": refreshToken,
        ])
        let (data, status) = try await send(
            "POST", Self.token, headers: ["Content-Type": "application/json"], body: body)
        return try CursorSession.refreshed(data, status: status)
    }

    public func usage(of account: StoredAccount, accessToken: String) async throws -> UsageReport {
        var headers = Self.headers(accessToken)
        headers["Content-Type"] = "application/json"
        headers["Connect-Protocol-Version"] = "1"
        let (data, status) = try await send("POST", Self.usage, headers: headers, body: Data("{}".utf8))
        guard status == 200 else { throw UsageError(Failure(status: status), "usage HTTP \(status)") }
        return UsageReport(plan: account.plan, limits: try CursorUsage.parse(data))
    }

    private func account(userID: String, tokens: Tokens) async throws -> StoredAccount {
        let (meData, meStatus) = try await send(
            "GET", Self.me, headers: ["Cookie": Self.sessionCookie(userID: userID, tokens.accessToken)])
        guard meStatus == 200 else {
            throw UsageError(Failure(status: meStatus), "profile HTTP \(meStatus)")
        }
        let (membershipData, membershipStatus) = try await send(
            "GET", Self.membership, headers: Self.headers(tokens.accessToken))
        guard membershipStatus == 200 else {
            throw UsageError(Failure(status: membershipStatus), "membership HTTP \(membershipStatus)")
        }
        let profile = try CursorProfile.parse(me: meData, membership: membershipData, userID: userID)
        return try StoredAccount(
            id: AccountID(provider: .cursor, handle: userID),
            name: profile.name, plan: profile.plan, tokens: tokens, now: Date())
    }

    private static func headers(_ accessToken: String) -> [String: String] {
        ["Authorization": "Bearer \(accessToken)"]
    }

    private static func sessionCookie(userID: String, _ accessToken: String) -> String {
        let user = userID.split(separator: "|").last.map(String.init) ?? userID
        return "WorkosCursorSessionToken=\(user)%3A%3A\(accessToken)"
    }
}

/**
 * A Cursor session token: a JWT whose `sub` is the user ID.
 *
 * Cursor stores one session token as both the access and the refresh token. It is
 * exchanged a day before its `exp`, while it is still valid as a refresh token.
 */
enum CursorSession {
    static let refreshLead: TimeInterval = 86_400

    static func login(_ data: Data, now: Date = Date()) throws -> (userID: String, tokens: Tokens) {
        let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard let session = root?["accessToken"] as? String,
              let userID = JSONWebToken.claims(session)?["sub"] as? String, !userID.isEmpty
        else { throw UsageError(.unexpectedResponse, "login has no session token") }
        return (userID, try tokens(session, now: now))
    }

    /**
     * Read the `oauth/token` body, e.g. `{"access_token": "<jwt>", "shouldLogout": false}`.
     *
     * - Throws: `RefreshRejected` when `shouldLogout` is true.
     */
    static func refreshed(_ data: Data, status: Int, now: Date = Date()) throws -> Tokens {
        guard status == 200 else { throw UsageError(Failure(status: status), "refresh HTTP \(status)") }
        let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        if root?["shouldLogout"] as? Bool == true { throw RefreshRejected() }
        guard let session = root?["access_token"] as? String else {
            throw UsageError(.unexpectedResponse, "refresh has no access_token")
        }
        return try tokens(session, now: now)
    }

    private static func tokens(_ session: String, now: Date) throws -> Tokens {
        guard let expiry = (JSONWebToken.claims(session)?["exp"] as? NSNumber)?.doubleValue else {
            throw UsageError(.unexpectedResponse, "session token has no exp")
        }
        return Tokens(
            accessToken: session, refreshToken: session,
            expiresIn: expiry - now.timeIntervalSince1970 - refreshLead)
    }
}

struct CursorProfile: Equatable {
    let name: String
    let plan: String

    static func parse(me: Data, membership: Data, userID: String) throws -> CursorProfile {
        let profile = (try? JSONSerialization.jsonObject(with: me)) as? [String: Any]
        let stripe = (try? JSONSerialization.jsonObject(with: membership)) as? [String: Any]
        guard let profile, let stripe else { throw UsageError(.unexpectedResponse, "profile not parsed") }
        return CursorProfile(
            name: profile["email"] as? String ?? profile["name"] as? String ?? userID,
            plan: (stripe["membershipType"] as? String)?
                .replacingOccurrences(of: "_", with: " ").capitalized ?? "Cursor")
    }
}

/**
 * Parser for `GetCurrentPeriodUsage`.
 *
 * Reads `planUsage.autoPercentUsed` and `apiPercentUsed` over the billing cycle, whose
 * bounds arrive as epoch milliseconds in strings.
 */
enum CursorUsage {
    private struct Body: Decodable {
        struct PlanUsage: Decodable {
            let autoPercentUsed: Double
            let apiPercentUsed: Double
        }
        let billingCycleStart: String
        let billingCycleEnd: String
        let planUsage: PlanUsage
    }

    static func parse(_ data: Data) throws -> Limits {
        guard let body = try? JSONDecoder().decode(Body.self, from: data),
              let start = Double(body.billingCycleStart), let end = Double(body.billingCycleEnd), end > start
        else { throw UsageError(.unexpectedResponse, "usage not parsed") }
        let resetsAt = wholeMinute(Date(timeIntervalSince1970: end / 1000))
        let length = (end - start) / 1000
        return Limits([
            LimitWindow(.auto, percent: body.planUsage.autoPercentUsed, resetsAt: resetsAt, length: length),
            LimitWindow(.api, percent: body.planUsage.apiPercentUsed, resetsAt: resetsAt, length: length),
        ])
    }
}
