import SwiftUI
import UsageKit
import UsageViews
import WidgetKit

struct UsageEntry: TimelineEntry {
    let date: Date
    let snapshot: UsageSnapshot?
}

struct UsageTimeline: TimelineProvider {
    private static let countdownMinutes = 60

    func placeholder(in context: Context) -> UsageEntry {
        UsageEntry(date: Date(), snapshot: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (UsageEntry) -> Void) {
        completion(UsageEntry(date: Date(), snapshot: SnapshotStore.shared.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UsageEntry>) -> Void) {
        let snapshot = SnapshotStore.shared.read()
        let now = Date()
        let minute = now.floored(toEvery: 60)
        let entries = [UsageEntry(date: now, snapshot: snapshot)] + (1..<Self.countdownMinutes).map {
            UsageEntry(date: minute.addingTimeInterval(Double($0) * 60), snapshot: snapshot)
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

@main
struct UsageWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "io.radison.usage", provider: UsageTimeline()) { entry in
            UsageEntryView(entry: entry)
        }
        .configurationDisplayName("Usage")
        .description("Claude Code and Codex limits.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

private struct UsageEntryView: View {
    let entry: UsageEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        UsageWidgetView(snapshot: entry.snapshot, family: family, now: entry.date)
            .containerBackground(Palette.base100.color, for: .widget)
    }
}
