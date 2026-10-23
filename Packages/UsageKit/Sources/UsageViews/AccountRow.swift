import SwiftUI
import UsageKit

public struct AccountRow: View {
    private let usage: AccountUsage
    private let now: Date
    private let staleSince: Date?

    private static let figureColumnWidth: CGFloat = 64

    /**
     * Create a row for one account.
     *
     * - Parameter staleSince: When set, the reading's age shows at the end of the label line.
     */
    public init(_ usage: AccountUsage, now: Date, staleSince: Date? = nil) {
        self.usage = usage
        self.now = now
        self.staleSince = staleSince
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                ProviderMark(provider: usage.id.provider)
                    .fill(Palette.content.color, style: FillStyle(eoFill: true))
                    .frame(width: 11, height: 11)
                    .frame(width: Self.figureColumnWidth, alignment: .leading)
                Text("\(usage.name) · \(usage.id.provider.title) \(usage.plan)")
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(Palette.neutral.color)
                Spacer(minLength: 4)
                if let staleSince {
                    Text("\(Format.duration(now.timeIntervalSince(staleSince))) old")
                        .foregroundStyle(Palette.warning.color)
                }
            }
            .font(.system(size: 10.5))

            switch usage.reading {
            case .limits(let limits):
                if let session = limits.session { bar(LimitReading(session, .session, now: now)) }
                if let weekly = limits.weekly { bar(LimitReading(weekly, .weekly, now: now)) }
            case .failed(let failure):
                HStack(spacing: 8) {
                    Text("—")
                        .frame(width: Self.figureColumnWidth, alignment: .leading)
                        .foregroundStyle(Palette.neutral.color)
                    Text(failure.sentence)
                        .foregroundStyle(failure == .signInRequired ? Palette.error.color : Palette.neutral.color)
                }
                .font(.system(size: 10.5))
            }
        }
    }

    private func bar(_ reading: LimitReading) -> some View {
        HStack(spacing: 8) {
            LimitFigure(reading: reading)
                .frame(width: Self.figureColumnWidth, alignment: .leading)
            DotBar(percent: reading.percent, evenBurn: reading.evenBurn)
        }
    }
}

public enum Format {
    public static func percent(_ value: Double) -> String { "\(Int(value.rounded()))%" }

    /** A compact duration such as `4d 3h`, `1h 12m`, `2h` or `38m`; `now` under a minute. */
    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        guard minutes > 0 else { return "now" }
        let (days, hours) = (minutes / 1440, minutes % 1440 / 60)
        if days > 0 { return hours > 0 ? "\(days)d \(hours)h" : "\(days)d" }
        if hours > 0 { return minutes % 60 > 0 ? "\(hours)h \(minutes % 60)m" : "\(hours)h" }
        return "\(minutes)m"
    }
}

extension Failure {
    var sentence: String {
        switch self {
        case .signInRequired: "Sign in again"
        case .offline: "Offline"
        case .rateLimited: "Rate limited, retrying"
        case .unexpectedResponse: "Unexpected response"
        }
    }
}
