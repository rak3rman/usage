import SwiftUI
import WidgetKit

enum DotGrid {
    static let diameter: CGFloat = 3
    static let gap: CGFloat = 2.5
    static var pitch: CGFloat { diameter + gap }

    static func height(rows: Int) -> CGFloat { CGFloat(rows) * pitch - gap }

    static func draw(
        _ context: GraphicsContext, columns: Int, rows: Int, color: (_ column: Int, _ row: Int) -> Color
    ) {
        for row in 0..<rows {
            for column in 0..<columns {
                let dot = CGRect(
                    x: CGFloat(column) * pitch, y: CGFloat(row) * pitch,
                    width: diameter, height: diameter)
                context.fill(Path(ellipseIn: dot), with: .color(color(column, row)))
            }
        }
    }
}

struct DotBar: View {
    let percent: Double
    @Environment(\.widgetRenderingMode) private var renderingMode
    private static let rows = 2

    var body: some View {
        Canvas { context, size in
            let columns = max(1, Int((size.width + DotGrid.gap) / DotGrid.pitch))
            let filled = percent > 0 ? max(1, Int((percent / 100 * Double(columns)).rounded())) : 0
            let tint = Palette.severity(percent)
            let fullColor = renderingMode == .fullColor
            DotGrid.draw(context, columns: columns, rows: Self.rows) { column, _ in
                guard column < filled else {
                    return fullColor ? Palette.neutral.mixed(over: Palette.base300, amount: 0.2).color
                        : .white.opacity(0.15)
                }
                let intensity = 0.35 + 0.65 * Double(column + 1) / Double(filled)
                return fullColor ? tint.mixed(over: Palette.base300, amount: intensity).color
                    : .white.opacity(intensity)
            }
        }
        .frame(height: DotGrid.height(rows: Self.rows))
    }
}

/** The 15 × 3 status grid from the radical-ui sign-in header. */
public struct StatusDots: View {
    public enum State: Sendable { case idle, loading, error }

    private let state: State
    @Environment(\.widgetRenderingMode) private var renderingMode
    private static let columns = 15
    private static let rows = 3

    public init(_ state: State) { self.state = state }

    public var body: some View {
        Canvas { context, _ in
            DotGrid.draw(context, columns: Self.columns, rows: Self.rows) { column, row in
                color(column: column, row: row)
            }
        }
        .frame(
            width: CGFloat(Self.columns) * DotGrid.pitch - DotGrid.gap,
            height: DotGrid.height(rows: Self.rows))
    }

    private func color(column: Int, row: Int) -> Color {
        let rising = 0.2 + 0.6 * Double(column) / Double(Self.columns - 1)
        let falling = 0.2 + 0.6 * (1 - Double(column) / Double(Self.columns - 1))
        let (swatch, amount): (Swatch, Double) = switch (state, row) {
        case (.error, _): (Palette.error, rising)
        case (.loading, _): (Palette.secondary, rising)
        case (.idle, 0): (Palette.secondary, falling)
        case (.idle, Self.rows - 1): (Palette.secondary, rising)
        case (.idle, _): (Palette.neutral, 0.48)
        }
        guard renderingMode == .fullColor else { return .white.opacity(amount) }
        return swatch.mixed(over: Palette.base300, amount: amount).color
    }
}
