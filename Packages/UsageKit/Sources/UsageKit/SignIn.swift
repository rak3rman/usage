import Foundation
import Network

public enum SignInError: Error, Sendable, Equatable {
    case portUnavailable(UInt16?)
    case browserUnavailable
    case denied(String)
    case timedOut
}

enum SignIn {
    static let timeout: Duration = .seconds(300)

    /**
     * Open the provider's consent page and complete the OAuth code flow through a
     * listener on the loopback interface.
     *
     * Cancelling the calling task stops the listener.
     *
     * - Parameter open: Opens the consent page in the browser; returns `false` if it could not.
     * - Throws: `SignInError`, or `UsageError` when the code exchange fails.
     */
    static func run(
        _ service: any LoopbackService, open: @Sendable (URL) async -> Bool
    ) async throws -> StoredAccount {
        let pkce = PKCE()
        let state = UUID().uuidString
        let listener: LoopbackListener
        do {
            listener = try await LoopbackListener.start(port: service.redirect.port)
        } catch {
            throw SignInError.portUnavailable(service.redirect.port)
        }
        let deadline = Task {
            try await Task.sleep(for: timeout)
            listener.stop()
        }
        defer {
            deadline.cancel()
            listener.stop()
        }
        let redirectURI = service.redirect.uri(port: listener.port)
        guard await open(service.authorizationURL(redirectURI: redirectURI, pkce: pkce, state: state))
        else { throw SignInError.browserUnavailable }

        for await request in listener.requests {
            switch OAuthCallback.parse(requestHead: request.head, path: service.redirect.path, state: state) {
            case .unrelated:
                request.respond(status: "404 Not Found", page: nil)
            case .stateMismatch:
                request.respond(status: "400 Bad Request", page: .failed)
            case .denied(let reason):
                request.respond(status: "400 Bad Request", page: .failed)
                throw SignInError.denied(reason)
            case .code(let code):
                do {
                    let account = try await service.signIn(
                        code: code, pkce: pkce, redirectURI: redirectURI, state: state)
                    request.respond(status: "200 OK", page: .signedIn)
                    return account
                } catch {
                    request.respond(status: "400 Bad Request", page: .failed)
                    throw error
                }
            }
        }
        try Task.checkCancellation()
        throw SignInError.timedOut
    }
}

private final class LoopbackListener: Sendable {
    struct Request: Sendable {
        let head: String
        let connection: NWConnection

        func respond(status: String, page: ResultPage?) {
            let body = page?.html ?? ""
            let response = "HTTP/1.1 \(status)\r\n"
                + "Content-Type: text/html; charset=utf-8\r\n"
                + "Content-Length: \(body.utf8.count)\r\n"
                + "Cache-Control: no-store\r\nConnection: close\r\n\r\n\(body)"
            connection.send(content: Data(response.utf8), completion: .contentProcessed { [connection] _ in
                connection.cancel()
            })
        }
    }

    let port: UInt16
    let requests: AsyncStream<Request>
    private let listener: NWListener

    private static let queue = DispatchQueue(label: "io.radison.usage.loopback")
    private static let maximumHeadBytes = 8192

    private init(port: UInt16, requests: AsyncStream<Request>, listener: NWListener) {
        self.port = port
        self.requests = requests
        self.listener = listener
    }

    static func start(port: UInt16?) async throws -> LoopbackListener {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(
            host: .ipv4(.loopback), port: port.flatMap(NWEndpoint.Port.init(rawValue:)) ?? .any)
        let listener = try NWListener(using: parameters)
        let (requests, continuation) = AsyncStream.makeStream(of: Request.self)
        listener.newConnectionHandler = { connection in
            connection.start(queue: queue)
            readHead(connection, received: Data()) { continuation.yield(Request(head: $0, connection: connection)) }
        }
        let bound: UInt16 = try await withCheckedThrowingContinuation { started in
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    listener.stateUpdateHandler = { state in
                        switch state {
                        case .failed, .cancelled: continuation.finish()
                        default: break
                        }
                    }
                    started.resume(returning: listener.port?.rawValue ?? 0)
                case .failed(let error):
                    listener.stateUpdateHandler = nil
                    continuation.finish()
                    started.resume(throwing: error)
                case .cancelled:
                    listener.stateUpdateHandler = nil
                    continuation.finish()
                    started.resume(throwing: CancellationError())
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }
        return LoopbackListener(port: bound, requests: requests, listener: listener)
    }

    func stop() { listener.cancel() }

    private static func readHead(
        _ connection: NWConnection, received: Data, then deliver: @escaping @Sendable (String) -> Void
    ) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: maximumHeadBytes - received.count) {
            data, _, isComplete, error in
            let buffer = received + (data ?? Data())
            if let head = String(data: buffer, encoding: .utf8), head.contains("\r\n\r\n") {
                deliver(head)
            } else if error != nil || isComplete || buffer.count >= maximumHeadBytes {
                connection.cancel()
            } else {
                readHead(connection, received: buffer, then: deliver)
            }
        }
    }
}

private enum ResultPage {
    case signedIn, failed

    var html: String {
        let (title, detail) = switch self {
        case .signedIn: ("Signed in", "Usage is connected. You can close this tab.")
        case .failed: ("Sign-in did not complete", "Return to Usage and try again.")
        }
        return """
        <!doctype html><html><head><meta charset="utf-8"><title>\(title) · Usage</title>
        <style>body{background:#08090A;color:#F7F8F8;font:15px/1.5 -apple-system,sans-serif;
        max-width:30em;margin:18vh auto;padding:0 24px}h1{font-size:18px;font-weight:400;margin:0 0 4px}
        p{color:#86868B;font-size:12px;margin:0}</style></head>
        <body><h1>\(title)</h1><p>\(detail)</p>
        <script>history.replaceState(null,"",location.pathname)</script></body></html>
        """
    }
}
