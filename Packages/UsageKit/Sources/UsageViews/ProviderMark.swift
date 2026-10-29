import SwiftUI
import UsageKit

/**
 * The Anthropic, OpenAI and Cursor marks in a 24 × 24 box, fill rule even-odd.
 *
 * Path data traced from Lobe Icons 1.95.1, MIT License, Copyright (c) 2023 LobeHub.
 * The marks are trademarks of Anthropic, OpenAI and Anysphere.
 */
struct ProviderMark: Shape {
    let provider: Provider

    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 24
        var path = Path()
        let segments = switch provider {
        case .claude: Self.anthropic
        case .codex: Self.openAI
        case .cursor: Self.cursor
        }
        for segment in segments {
            switch segment {
            case .move(let x, let y):
                path.move(to: CGPoint(x: x, y: y))
            case .line(let x, let y):
                path.addLine(to: CGPoint(x: x, y: y))
            case .curve(let x1, let y1, let x2, let y2, let x, let y):
                path.addCurve(
                    to: CGPoint(x: x, y: y),
                    control1: CGPoint(x: x1, y: y1), control2: CGPoint(x: x2, y: y2))
            case .close:
                path.closeSubpath()
            }
        }
        return path.applying(
            CGAffineTransform(
                translationX: rect.midX - 12 * scale, y: rect.midY - 12 * scale
            ).scaledBy(x: scale, y: scale))
    }

    private enum Segment {
        case move(CGFloat, CGFloat)
        case line(CGFloat, CGFloat)
        case curve(CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat)
        case close
    }

    private static let anthropic: [Segment] = [
        .move(13.827, 3.52),
        .line(17.43, 3.52),
        .line(24, 20),
        .line(20.397, 20),
        .line(13.827, 3.52),
        .close,
        .move(6.569, 3.52),
        .line(10.336, 3.52),
        .line(16.906, 20),
        .line(13.232, 20),
        .line(11.889, 16.539),
        .line(5.017, 16.539),
        .line(3.673, 19.999),
        .line(0, 19.999),
        .line(6.57, 3.522),
        .close,
        .move(10.701, 13.479),
        .line(8.453, 7.687),
        .line(6.205, 13.48),
        .line(10.7, 13.48),
        .close,
    ]

    private static let openAI: [Segment] = [
        .move(9.205, 8.658),
        .line(9.205, 6.398),
        .curve(9.205, 6.208, 9.277, 6.065, 9.443, 5.97),
        .line(13.986, 3.354),
        .curve(14.605, 2.997, 15.342, 2.831, 16.103, 2.831),
        .curve(18.957, 2.831, 20.765, 5.043, 20.765, 7.397),
        .curve(20.765, 7.564, 20.765, 7.754, 20.741, 7.944),
        .line(16.031, 5.185),
        .curve(15.77, 5.019, 15.436, 5.019, 15.175, 5.185),
        .line(9.205, 8.658),
        .close,
        .move(19.814, 17.458),
        .line(19.814, 12.06),
        .curve(19.814, 11.727, 19.671, 11.49, 19.385, 11.323),
        .line(13.415, 7.85),
        .line(15.365, 6.732),
        .curve(15.509, 6.637, 15.697, 6.637, 15.841, 6.732),
        .line(20.384, 9.349),
        .curve(21.693, 10.109, 22.573, 11.727, 22.573, 13.297),
        .curve(22.573, 15.105, 21.503, 16.77, 19.813, 17.46),
        .close,
        .move(7.802, 12.703),
        .line(5.852, 11.561),
        .curve(5.685, 11.466, 5.613, 11.323, 5.613, 11.133),
        .line(5.613, 5.899),
        .curve(5.613, 3.354, 7.563, 1.427, 10.204, 1.427),
        .curve(11.204, 1.427, 12.131, 1.76, 12.916, 2.355),
        .line(8.23, 5.067),
        .curve(7.945, 5.233, 7.802, 5.471, 7.802, 5.804),
        .line(7.802, 12.702),
        .close,
        .move(12, 15.128),
        .line(9.205, 13.558),
        .line(9.205, 10.228),
        .line(12, 8.658),
        .line(14.795, 10.228),
        .line(14.795, 13.558),
        .line(12, 15.128),
        .close,
        .move(13.796, 22.358),
        .curve(12.796, 22.358, 11.869, 22.026, 11.084, 21.431),
        .line(15.77, 18.719),
        .curve(16.055, 18.553, 16.198, 18.315, 16.198, 17.982),
        .line(16.198, 11.084),
        .line(18.172, 12.226),
        .curve(18.339, 12.321, 18.41, 12.464, 18.41, 12.654),
        .line(18.41, 17.887),
        .curve(18.41, 20.432, 16.436, 22.359, 13.796, 22.359),
        .close,
        .move(8.159, 17.055),
        .line(3.615, 14.438),
        .curve(2.307, 13.677, 1.427, 12.06, 1.427, 10.49),
        .curve(1.421, 8.665, 2.521, 7.019, 4.21, 6.327),
        .line(4.21, 11.75),
        .curve(4.21, 12.083, 4.353, 12.321, 4.638, 12.488),
        .line(10.585, 15.937),
        .line(8.635, 17.055),
        .curve(8.491, 17.15, 8.303, 17.15, 8.159, 17.055),
        .close,
        .move(7.897, 20.955),
        .curve(5.209, 20.955, 3.235, 18.934, 3.235, 16.436),
        .curve(3.235, 16.246, 3.259, 16.056, 3.282, 15.866),
        .line(7.968, 18.576),
        .curve(8.254, 18.743, 8.539, 18.743, 8.824, 18.576),
        .line(14.794, 15.128),
        .line(14.794, 17.388),
        .curve(14.794, 17.578, 14.724, 17.721, 14.557, 17.816),
        .line(10.014, 20.432),
        .curve(9.395, 20.789, 8.658, 20.955, 7.897, 20.955),
        .close,
        .move(13.796, 23.785),
        .curve(16.622, 23.785, 19.057, 21.797, 19.623, 19.029),
        .curve(22.287, 18.339, 24, 15.84, 24, 13.296),
        .curve(24, 11.631, 23.287, 10.014, 22.002, 8.848),
        .curve(22.121, 8.348, 22.192, 7.849, 22.192, 7.35),
        .curve(22.192, 3.949, 19.433, 1.403, 16.246, 1.403),
        .curve(15.604, 1.403, 14.986, 1.498, 14.366, 1.713),
        .curve(13.256, 0.62, 11.763, 0.006, 10.205, 0),
        .curve(7.379, 0, 4.943, 1.988, 4.378, 4.757),
        .curve(1.713, 5.447, 0, 7.945, 0, 10.49),
        .curve(0, 12.156, 0.713, 13.773, 1.998, 14.938),
        .curve(1.879, 15.438, 1.808, 15.938, 1.808, 16.437),
        .curve(1.808, 19.838, 4.567, 22.383, 7.754, 22.383),
        .curve(8.396, 22.383, 9.014, 22.288, 9.634, 22.074),
        .curve(10.744, 23.167, 12.238, 23.782, 13.796, 23.787),
        .close,
    ]

    private static let cursor: [Segment] = [
        .move(22.106, 5.68),
        .line(12.5, 0.135),
        .curve(12.191, -0.043, 11.811, -0.043, 11.502, 0.135),
        .line(1.893, 5.68),
        .curve(1.634, 5.83, 1.474, 6.107, 1.474, 6.406),
        .line(1.474, 17.592),
        .curve(1.474, 17.892, 1.634, 18.169, 1.894, 18.319),
        .line(11.501, 23.866),
        .curve(11.81, 24.044, 12.19, 24.044, 12.499, 23.866),
        .line(22.107, 18.319),
        .curve(22.367, 18.169, 22.527, 17.892, 22.527, 17.592),
        .line(22.527, 6.407),
        .curve(22.526, 6.107, 22.366, 5.831, 22.107, 5.681),
        .close,
        .move(21.503, 6.856),
        .line(12.228, 22.92),
        .curve(12.165, 23.028, 12, 22.984, 12, 22.859),
        .line(12, 12.34),
        .curve(12, 12.13, 11.887, 11.935, 11.705, 11.83),
        .line(2.595, 6.57),
        .curve(2.488, 6.508, 2.532, 6.342, 2.657, 6.342),
        .line(21.207, 6.342),
        .curve(21.471, 6.342, 21.635, 6.628, 21.503, 6.856),
        .close,
    ]
}
