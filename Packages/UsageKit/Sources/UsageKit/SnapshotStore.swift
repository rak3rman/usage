import Foundation
import OSLog

/**
 * The snapshot file shared by the app and the widget.
 *
 * The app writes it after every poll; the widget only reads it. Both targets name their
 * app group under the `AppGroup` key of their Info.plist.
 */
public struct SnapshotStore: Sendable {
    public let url: URL?
    private static let log = Logger(subsystem: "io.radison.usage", category: "snapshot")

    private init(url: URL?) { self.url = url }

    public static let shared: SnapshotStore = {
        let group = Bundle.main.object(forInfoDictionaryKey: "AppGroup") as? String ?? ""
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: group)
        else {
            log.error("no container for app group '\(group, privacy: .public)'")
            return SnapshotStore(url: nil)
        }
        return SnapshotStore(url: container.appendingPathComponent("snapshot.json"))
    }()

    public func read() -> UsageSnapshot? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try JSONDecoder().decode(UsageSnapshot.self, from: data)
        } catch {
            Self.log.error("snapshot not decoded: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    public func write(_ snapshot: UsageSnapshot) {
        guard let url else { return }
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(snapshot).write(to: url, options: .atomic)
        } catch {
            Self.log.error("snapshot not written: \(String(describing: error), privacy: .public)")
        }
    }
}
