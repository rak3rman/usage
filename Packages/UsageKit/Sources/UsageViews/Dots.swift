import AppKit
import SwiftUI
import WidgetKit

enum DotGrid {
    static let diameter: CGFloat = 3
    static let gap: CGFloat = 2.5
    static var pitch: CGFloat { diameter + gap }

    static func height(rows: Int) -> CGFloat { CGFloat(rows) * pitch - gap }

    static func dot(column: Int, row: Int, columnPitch: CGFloat) -> CGRect {
        CGRect(x: CGFloat(column) * columnPitch, y: CGFloat(row) * pitch, width: diameter, height: diameter)
    }

    /** Spreads the columns across `width`; the last dot ends flush with it. */
    static func draw(
        _ context: GraphicsContext, columns: Int, rows: Int, width: CGFloat,
        color: (_ column: Int, _ row: Int) -> Color
    ) {
        let columnPitch = (width - diameter) / CGFloat(max(1, columns - 1))
        for row in 0..<rows {
            for column in 0..<columns {
                let dot = dot(column: column, row: row, columnPitch: columnPitch)
                context.fill(Path(ellipseIn: dot), with: .color(color(column, row)))
            }
        }
    }
}

/** A usage-bar dot: used, spare up to the even-burn point, or unearned past it. */
enum Dot: Equatable {
    case used, spare, unearned

    static func bar(columns: Int, percent: Int, evenBurn: Int?) -> [Dot] {
        func count(_ percent: Int) -> Int { Int((Double(percent) / 100 * Double(columns)).rounded()) }
        let used = percent > 0 ? max(1, count(percent)) : 0
        let earned = evenBurn.map(count) ?? 0
        return (0..<columns).map { column in
            if column < used { return .used }
            return column < earned ? .spare : .unearned
        }
    }
}

/** The 3 × 3 menu bar meter: a dot lit per ninth of `percent`, in reading order. */
public enum MenuBarMeter {
    private static let side = 3

    public static func image(percent: Double?) -> NSImage {
        let dots = Dot.bar(columns: side * side, percent: Int((percent ?? 0).rounded()), evenBurn: nil)
        let length = DotGrid.height(rows: side)
        let image = NSImage(size: NSSize(width: length, height: length), flipped: true) { _ in
            for (index, dot) in dots.enumerated() {
                NSColor.black.withAlphaComponent(dot == .used ? 1 : 0.35).setFill()
                NSBezierPath(ovalIn: DotGrid.dot(column: index % side, row: index / side, columnPitch: DotGrid.pitch))
                    .fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}

struct DotBar: View {
    let percent: Int
    let evenBurn: Int?
    @Environment(\.widgetRenderingMode) private var renderingMode
    private static let rows = 2

    var body: some View {
        Canvas { context, size in
            let dots = Dot.bar(
                columns: max(1, Int((size.width + DotGrid.gap) / DotGrid.pitch)),
                percent: percent, evenBurn: evenBurn)
            let used = dots.filter { $0 == .used }.count
            let tint = Palette.severity(Double(percent))
            let fullColor = renderingMode == .fullColor
            DotGrid.draw(context, columns: dots.count, rows: Self.rows, width: size.width) { column, _ in
                switch dots[column] {
                case .used:
                    let intensity = 0.35 + 0.65 * Double(column + 1) / Double(used)
                    return fullColor ? tint.mixed(over: Palette.base300, amount: intensity).color
                        : .white.opacity(intensity)
                case .spare:
                    return fullColor ? Palette.neutral.mixed(over: Palette.base300, amount: 0.5).color
                        : .white.opacity(0.4)
                case .unearned:
                    return fullColor ? Palette.neutral.mixed(over: Palette.base300, amount: 0.22).color
                        : .white.opacity(0.18)
                }
            }
        }
        .frame(height: DotGrid.height(rows: Self.rows))
    }
}

struct StatusDots: View {
    @Environment(\.widgetRenderingMode) private var renderingMode
    private static let columns = 15
    private static let rows = 3

    var body: some View {
        Canvas { context, size in
            DotGrid.draw(context, columns: Self.columns, rows: Self.rows, width: size.width) { column, row in
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
        let (swatch, amount): (Swatch, Double) = switch row {
        case 0: (Palette.secondary, falling)
        case Self.rows - 1: (Palette.secondary, rising)
        default: (Palette.neutral, 0.48)
        }
        guard renderingMode == .fullColor else { return .white.opacity(amount) }
        return swatch.mixed(over: Palette.base300, amount: amount).color
    }
}
