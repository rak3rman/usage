import AppKit
import Observation
import OSLog
import ServiceManagement
import UsageKit
import WidgetKit

@MainActor @Observable
final class UsageModel {
    private(set) var accounts: [StoredAccount] = []
    private(set) var snapshot: UsageSnapshot?
    private(set) var isRefreshing = false
    private(set) var keychainProblem: String?
    private(set) var signingIn: Provider?
    private(set) var accountProblem: String?
    private(set) var opensAtLogin = SMAppService.mainApp.status == .enabled

    private let store = AccountStore(
        storage: Keychain(service: "io.radison.usage.accounts"), services: [Claude(), Codex()])
    private var signInTask: Task<Void, Never>?

    private static let pollInterval: Duration = .seconds(300)
    private static let log = Logger(subsystem: "io.radison.usage", category: "model")

    var peakPercent: Double? {
        snapshot?.accounts.compactMap { $0.limits?.peak?.percent }.max()
    }

    func poll() async {
        while !Task.isCancelled {
            await refresh()
            try? await Task.sleep(for: Self.pollInterval)
        }
    }

    func refresh(ifOlderThan age: TimeInterval) async {
        if let capturedAt = snapshot?.capturedAt, Date().timeIntervalSince(capturedAt) < age { return }
        await refresh()
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            accounts = try await store.list()
            keychainProblem = nil
            let readings = try await store.readUsage()
            Self.log.info("read \(readings.count, privacy: .public) accounts")
            publish(UsageSnapshot(accounts: readings, capturedAt: Date()))
        } catch {
            Self.log.error("accounts not read: \(String(describing: error), privacy: .public)")
            keychainProblem = String(describing: error)
        }
    }

    func signIn(_ provider: Provider) {
        guard signingIn == nil, let service = store.services[provider] else { return }
        signingIn = provider
        accountProblem = nil
        signInTask = Task {
            do {
                let account = try await SignIn.run(service) { url in
                    await MainActor.run { NSWorkspace.shared.open(url) }
                }
                try await store.save(account)
                await refresh()
            } catch is CancellationError {
            } catch {
                Self.log.error("sign-in failed: \(String(describing: error), privacy: .public)")
                accountProblem = Self.sentence(for: error)
            }
            signingIn = nil
        }
    }

    func cancelSignIn() { signInTask?.cancel() }

    func remove(_ id: AccountID) async {
        do {
            try await store.remove(id)
        } catch {
            Self.log.error("account not removed: \(String(describing: error), privacy: .public)")
            accountProblem = "Could not remove the account: \(error)."
        }
        await refresh()
    }

    func setOpensAtLogin(_ enabled: Bool) {
        do {
            try enabled ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
        } catch {
            Self.log.error("login item not changed: \(String(describing: error), privacy: .public)")
        }
        opensAtLogin = SMAppService.mainApp.status == .enabled
    }

    private func publish(_ next: UsageSnapshot) {
        let changed = next.accounts != snapshot?.accounts
        snapshot = next
        SnapshotStore.shared.write(next)
        if changed { WidgetCenter.shared.reloadAllTimelines() }
    }

    private static func sentence(for error: any Error) -> String {
        switch error {
        case SignInError.portUnavailable(let port?):
            "Port \(port) is in use. Close any other Codex sign-in and try again."
        case SignInError.portUnavailable(nil):
            "Could not listen for the browser's reply."
        case SignInError.browserUnavailable:
            "Could not open the browser."
        case SignInError.denied:
            "Sign-in was declined."
        case SignInError.timedOut:
            "Sign-in timed out."
        case let error as UsageError:
            "Sign-in failed: \(error.detail)."
        default:
            "Sign-in failed: \(error)."
        }
    }
}
