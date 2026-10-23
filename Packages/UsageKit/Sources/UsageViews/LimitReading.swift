import SwiftUI
import UsageKit

enum WindowKind {
    case session, weekly

    var name: String {
        switch self {
        case .session: "5h"
        case .weekly: "7d"
        }
    }

    var seconds: Int {
        switch self {
        case .session: 18_000
        case .weekly: 604_800
        }
    }

    var underPaceMargin: Int {
        switch self {
        case .session: 10
        case .weekly: 8
        }
    }
}

/**
 * A limit window as the Claude Code status line prints it, e.g. `4h:9%+23`.
 *
 * The time to reset, rounded up, then the percent used, then the surplus: how many
 * points usage sits under (+) or over (−) an even burn to the reset.
 */
struct LimitReading: Equatable {
    enum Tone: Equatable { case quiet, underPace, overPace, critical }

    let figure: String
    let percent: Int
    /** The percent an even burn to the reset would have used by now. */
    let evenBurn: Int?
    let tone: Tone

    private static let overPaceMargin = 5
    private static let criticalPercent = 90

    init(_ window: LimitWindow, _ kind: WindowKind, now: Date) {
        percent = Int(window.percent.rounded(.toNearestOrEven))
        let critical = percent >= Self.criticalPercent
        guard let resetsAt = window.resetsAt else {
            figure = "\(kind.name):\(percent)%"
            evenBurn = nil
            tone = critical ? .critical : .quiet
            return
        }
        let untilReset = min(max(0, Int(resetsAt.timeIntervalSince(now))), kind.seconds)
        let elapsed = kind.seconds - untilReset
        let evenBurn = (elapsed * 100 + kind.seconds / 2) / kind.seconds
        let surplus = evenBurn - percent
        figure = "\(Self.label(untilReset)):\(percent)%"
        self.evenBurn = evenBurn
        tone = if critical {
            .critical
        } else if surplus >= kind.underPaceMargin {
            .underPace
        } else if surplus <= -Self.overPaceMargin {
            .overPace
        } else {
            .quiet
        }
    }

    var pace: String? {
        guard let evenBurn, tone != .quiet else { return nil }
        let surplus = evenBurn - percent
        return surplus >= 0 ? "+\(surplus)" : "\(surplus)"
    }

    private static func label(_ seconds: Int) -> String {
        let minutes = (seconds + 59) / 60
        let hours = (minutes + 59) / 60
        if hours >= 24 { return "\((hours + 23) / 24)d" }
        if minutes >= 60 { return "\(hours)h" }
        return "\(minutes)m"
    }
}

/** A reading in the status line's colours. */
struct LimitFigure: View {
    let reading: LimitReading

    var body: some View {
        let figure = Text(reading.figure)
            .foregroundStyle(reading.tone == .critical ? Palette.Pace.critical : Palette.Pace.quiet)
        return (figure + Text(reading.pace ?? "").foregroundStyle(paceColor))
            .font(.system(size: 10.5).monospacedDigit())
            .lineLimit(1)
            .minimumScaleFactor(0.85)
    }

    private var paceColor: Color {
        switch reading.tone {
        case .underPace: Palette.Pace.under
        case .overPace: Palette.Pace.over
        case .critical: Palette.Pace.critical
        case .quiet: Palette.Pace.quiet
        }
    }
}
