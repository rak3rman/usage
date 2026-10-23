import CryptoKit
import Foundation

public protocol UsageService: Sendable {
    var provider: Provider { get }
    var redirect: LoopbackRedirect { get }
    func authorizationURL(redirectURI: String, pkce: PKCE, state: String) -> URL
    func signIn(code: String, pkce: PKCE, redirectURI: String, state: String) async throws -> StoredAccount
    /**
     * Exchange a refresh token for a new access token.
     *
     * - Throws: `RefreshRejected` when the provider will never accept this refresh token again.
     */
    func refresh(_ refreshToken: String) async throws -> Tokens
    func usage(of account: StoredAccount, accessToken: String) async throws -> UsageReport
}

public struct UsageReport: Sendable, Hashable {
    public let plan: String
    public let limits: Limits
}

public struct LoopbackRedirect: Sendable, Hashable {
    /** `nil` binds any free port. */
    public let port: UInt16?
    public let path: String

    public func uri(port bound: UInt16) -> String { "http://localhost:\(bound)\(path)" }
}

public struct Tokens: Sendable, Hashable {
    public let accessToken: String
    public let refreshToken: String?
    public let expiresIn: TimeInterval?

    public init(accessToken: String, refreshToken: String?, expiresIn: TimeInterval?) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresIn = expiresIn
    }

    static func decode(_ data: Data, now: Date = Date()) throws -> Tokens {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = root["access_token"] as? String, !access.isEmpty
        else { throw UsageError(.unexpectedResponse, "token response has no access_token") }
        let expiresIn = (root["expires_in"] as? NSNumber)?.doubleValue
            ?? (JSONWebToken.claims(access)?["exp"] as? NSNumber).map {
                $0.doubleValue - now.timeIntervalSince1970
            }
        return Tokens(
            accessToken: access, refreshToken: root["refresh_token"] as? String,
            expiresIn: expiresIn)
    }

    static func refreshed(_ data: Data, status: Int) throws -> Tokens {
        if status == 400 || status == 401, refreshWasRejected(data) { throw RefreshRejected() }
        guard status == 200 else { throw UsageError(Failure(status: status), "refresh HTTP \(status)") }
        return try decode(data)
    }

    private static let rejectionCodes: Set<String> = [
        "invalid_grant", "refresh_token_expired", "refresh_token_reused", "refresh_token_invalid",
    ]

    /** Accepts `{"error": "invalid_grant"}` and `{"error": {"code": "invalid_grant"}}`. */
    private static func refreshWasRejected(_ data: Data) -> Bool {
        let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let code = root?["error"] as? String
            ?? (root?["error"] as? [String: Any])?["code"] as? String
        return code.map(rejectionCodes.contains) ?? false
    }
}

public struct RefreshRejected: Error, Sendable {}

public struct PKCE: Sendable, Hashable {
    public let verifier: String
    public let challenge: String

    public init() {
        var generator = SystemRandomNumberGenerator()
        let bytes = (0..<32).map { _ in UInt8.random(in: .min ... .max, using: &generator) }
        verifier = Self.base64URL(Data(bytes))
        challenge = Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

enum CallbackOutcome: Sendable, Equatable {
    case code(String)
    case denied(String)
    case stateMismatch
    case unrelated
}

enum OAuthCallback {
    /**
     * Classify a request that reached the loopback listener.
     *
     * - Parameter requestHead: Raw HTTP request, e.g. `GET /callback?code=abc&state=xyz HTTP/1.1`.
     */
    static func parse(requestHead: String, path: String, state: String) -> CallbackOutcome {
        let line = requestHead.split(whereSeparator: \.isNewline).first ?? ""
        let parts = line.split(separator: " ")
        guard parts.count >= 2, parts[0] == "GET", parts[1].hasPrefix("/"), !parts[1].hasPrefix("//"),
              let components = URLComponents(string: "http://localhost\(parts[1])"),
              components.path == path
        else { return .unrelated }
        let items = components.queryItems ?? []
        func values(_ name: String) -> [String] { items.filter { $0.name == name }.compactMap(\.value) }
        guard !values("code").isEmpty || !values("error").isEmpty else { return .unrelated }
        guard values("state") == [state] else { return .stateMismatch }
        if let error = values("error").first { return .denied(error) }
        guard let code = values("code").first, values("code").count == 1, !code.isEmpty else {
            return .unrelated
        }
        return .code(code)
    }
}

/**
 * Send a request and return its body and status code.
 *
 * - Throws: `UsageError` with `.offline` when no response arrives.
 */
func send(
    _ method: String, _ url: URL, headers: [String: String], body: Data? = nil
) async throws -> (Data, Int) {
    var request = URLRequest(url: url, timeoutInterval: 30)
    request.httpMethod = method
    request.httpBody = body
    for (field, value) in headers { request.setValue(value, forHTTPHeaderField: field) }
    do {
        let (data, response) = try await URLSession.shared.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    } catch {
        let code = (error as? URLError)?.code.rawValue ?? 0
        throw UsageError(.offline, "\(url.host() ?? "request") failed, URLError \(code)")
    }
}

enum FormBody {
    private static let unreserved = CharacterSet(
        charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")

    static func encode(_ fields: [String: String]) -> Data {
        let pairs = fields.sorted { $0.key < $1.key }.map { key, value in
            "\(escape(key))=\(escape(value))"
        }
        return Data(pairs.joined(separator: "&").utf8)
    }

    private static func escape(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: unreserved) ?? text
    }
}

enum JSONWebToken {
    /** The payload of a JWT, without verifying its signature. */
    static func claims(_ token: String) -> [String: Any]? {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        var payload = parts[1].replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 { payload += "=" }
        guard let data = Data(base64Encoded: payload) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}
