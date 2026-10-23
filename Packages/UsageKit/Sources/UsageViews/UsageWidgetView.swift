import SwiftUI
import UsageKit
import WidgetKit

public struct UsageWidgetView: View {
    private let snapshot: UsageSnapshot?
    private let family: WidgetFamily
    private let now: Date

    private static let staleAfter: TimeInterval = 2 * 60 * 60

    public init(snapshot: UsageSnapshot?, family: WidgetFamily, now: Date) {
        self.snapshot = snapshot
        self.family = family
        self.now = now
    }

    public var body: some View {
        Group {
            if let snapshot, !snapshot.accounts.isEmpty {
                switch family {
                case .systemSmall: small(snapshot)
                case .systemLarge: list(snapshot, capacity: 5, header: true)
                default: list(snapshot, capacity: 2, header: false)
                }
            } else {
                empty
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .environment(\.colorScheme, .dark)
    }

    private func staleSince(_ snapshot: UsageSnapshot) -> Date? {
        now.timeIntervalSince(snapshot.capturedAt) > Self.staleAfter ? snapshot.capturedAt : nil
    }

    @ViewBuilder
    private func small(_ snapshot: UsageSnapshot) -> some View {
        if let busiest = snapshot.accounts.max(by: {
            ($0.limits?.peak?.percent ?? -1) < ($1.limits?.peak?.percent ?? -1)
        }) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    ProviderMark(provider: busiest.id.provider)
                        .fill(Palette.content.color, style: FillStyle(eoFill: true))
                        .frame(width: 11, height: 11)
                    Text(busiest.name)
                        .font(.system(size: 10.5))
                        .lineLimit(1)
                        .foregroundStyle(Palette.neutral.color)
                }
                Spacer(minLength: 0)
                switch busiest.reading {
                case .limits(let limits):
                    if let peak = limits.peak {
                        let reading = LimitReading(peak, peak == limits.session ? .session : .weekly, now: now)
                        Text(Format.percent(peak.percent))
                            .font(.system(size: 34, weight: .light).monospacedDigit())
                            .foregroundStyle(reading.tone == .critical ? Palette.Pace.critical : Palette.content.color)
                            .contentTransition(.numericText(value: peak.percent))
                        Group {
                            if let staleSince = staleSince(snapshot) {
                                Text("\(Format.duration(now.timeIntervalSince(staleSince))) old")
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(Palette.warning.color)
                            } else {
                                LimitFigure(reading: reading)
                            }
                        }
                        .padding(.bottom, 12)
                    }
                    VStack(spacing: 5) {
                        if let session = limits.session { bar(session, .session) }
                        if let weekly = limits.weekly { bar(weekly, .weekly) }
                    }
                case .failed(let failure):
                    Text(failure.sentence)
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.error.color)
                }
            }
        }
    }

    private func bar(_ window: LimitWindow, _ kind: WindowKind) -> some View {
        let reading = LimitReading(window, kind, now: now)
        return DotBar(percent: reading.percent, evenBurn: reading.evenBurn)
    }

    private func list(_ snapshot: UsageSnapshot, capacity: Int, header: Bool) -> some View {
        let shown = snapshot.accounts.prefix(capacity)
        let hidden = snapshot.accounts.count - shown.count
        return VStack(alignment: .leading, spacing: header ? 12 : 0) {
            if header {
                Text("Usage")
                    .font(.system(size: 15))
                    .foregroundStyle(Palette.content.color)
            }
            ForEach(shown) { account in
                AccountRow(account, now: now, staleSince: staleSince(snapshot))
                if !header, account.id != shown.last?.id { Spacer(minLength: 10) }
            }
            Spacer(minLength: 0)
            if hidden > 0 {
                Text("+\(hidden) more")
                    .font(.system(size: 9.5))
                    .foregroundStyle(Palette.neutral.color)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    private var empty: some View {
        VStack(spacing: 8) {
            StatusDots(.idle)
            Text("No accounts")
                .font(.system(size: 12))
                .foregroundStyle(Palette.content.color)
            Text("Open Usage to sign in.")
                .font(.system(size: 10.5))
                .foregroundStyle(Palette.neutral.color)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
