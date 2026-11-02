import SwiftUI

enum Theme {
    static let accent = Color(red: 0.78, green: 1.0, blue: 0.24)
    static let danger = Color(red: 1.0, green: 0.33, blue: 0.33)
    static let background = Color.black
    static let card = Color.white.opacity(0.07)
    static let secondaryText = Color.white.opacity(0.6)

    static func number(_ size: CGFloat) -> Font { .system(size: size, weight: .heavy, design: .rounded) }
}

struct PrimaryButtonStyle: ButtonStyle {
    var tint: Color = Theme.accent

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 17)
            .foregroundStyle(.black)
            .background(tint, in: .rect(cornerRadius: 18))
            .opacity(configuration.isPressed ? 0.8 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 17)
            .foregroundStyle(.white)
            .background(Theme.card, in: .rect(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.12)))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .background(Theme.card, in: .rect(cornerRadius: 24))
    }
}

/// The wordmark: a lime "u-turn" glyph plus the name.
struct Wordmark: View {
    var size: CGFloat = 28

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.uturn.backward.circle.fill")
                .font(.system(size: size * 0.9, weight: .bold))
                .foregroundStyle(Theme.accent)
            Text("Unscroll")
                .font(.system(size: size, weight: .heavy, design: .rounded))
        }
    }
}
