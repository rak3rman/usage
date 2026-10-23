import SwiftUI

/** The radical-ui dark theme, converted from its oklch tokens to sRGB. */
public enum Palette {
    public static let base100 = Swatch(0x08090A)
    public static let base200 = Swatch(0x111213)
    public static let base300 = Swatch(0x191A1B)
    public static let content = Swatch(0xF7F8F8)
    public static let neutral = Swatch(0x86868B)
    public static let secondary = Swatch(0x586CB2)
    public static let warning = Swatch(0xFF5A00)
    public static let error = Swatch(0xDC3757)

    static func severity(_ percent: Double) -> Swatch {
        switch percent {
        case ..<75: secondary
        case ..<90: warning
        default: error
        }
    }

    enum Pace {
        static let quiet = Color(.displayP3, red: 0.4686, green: 0.4686, blue: 0.4804)
        static let under = Color(.displayP3, red: 0.3098, green: 0.6627, blue: 0.5725)
        static let over = Color(.displayP3, red: 0.8706, green: 0.7333, blue: 0.4196)
        static let critical = Color(.displayP3, red: 0.8745, green: 0.349, blue: 0.3255)
    }
}

public struct Swatch: Sendable, Hashable {
    let red: Double
    let green: Double
    let blue: Double

    init(_ hex: UInt32) {
        red = Double((hex >> 16) & 0xFF) / 255
        green = Double((hex >> 8) & 0xFF) / 255
        blue = Double(hex & 0xFF) / 255
    }

    private init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    public var color: Color { Color(.sRGB, red: red, green: green, blue: blue) }

    /** `amount` of `self` over `base`, as CSS `color-mix(self amount, base)`. */
    func mixed(over base: Swatch, amount: Double) -> Swatch {
        Swatch(
            red: base.red + (red - base.red) * amount,
            green: base.green + (green - base.green) * amount,
            blue: base.blue + (blue - base.blue) * amount)
    }
}
