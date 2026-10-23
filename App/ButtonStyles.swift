import SwiftUI
import UsageViews

struct PillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12))
            .foregroundStyle(Palette.content.color)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                (configuration.isPressed ? Palette.base300 : Palette.base200).color,
                in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Palette.base300.color, lineWidth: 1.5))
    }
}

struct LinkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12))
            .foregroundStyle((configuration.isPressed ? Palette.content : Palette.neutral).color)
            .contentShape(Rectangle())
    }
}
