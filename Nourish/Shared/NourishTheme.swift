import SwiftUI

// MARK: - Feed side

enum FeedSide: String, Equatable {
    case left, right

    var label: String    { self == .left ? "L" : "R" }
    var name: String     { self == .left ? "Left" : "Right" }
    var opposite: Self   { self == .left ? .right : .left }
    var feedType: FeedType { self == .left ? .left : .right }
}

// MARK: - Accent variant (left)

enum AccentVariant: String, CaseIterable {
    case terra, rose, sage, plum

    var displayName: String { rawValue.capitalized }

    var swatchColor: Color {
        switch self {
        case .terra: Color(hex: "C05840")
        case .rose:  Color(hex: "B85275")
        case .sage:  Color(hex: "5A8A6A")
        case .plum:  Color(hex: "7060A4")
        }
    }

    var leftAccent: Color {
        switch self {
        case .terra: Color(hex: "C05840")
        case .rose:  Color(hex: "B85275")
        case .sage:  Color(hex: "5A8A6A")
        case .plum:  Color(hex: "7060A4")
        }
    }

    var leftBg: Color {
        switch self {
        case .terra: Color(hex: "FAF0EC")
        case .rose:  Color(hex: "FAF0F3")
        case .sage:  Color(hex: "EEF4F0")
        case .plum:  Color(hex: "F2EEF8")
        }
    }

    var leftText: Color {
        switch self {
        case .terra: Color(hex: "6A2E1A")
        case .rose:  Color(hex: "6A1A3A")
        case .sage:  Color(hex: "1E4A2A")
        case .plum:  Color(hex: "3A206A")
        }
    }

    var leftShadow: Color { leftAccent.opacity(0.14) }
}

// MARK: - Accent variant (right)

enum RightAccentVariant: String, CaseIterable {
    case blue, teal, slate, indigo

    var displayName: String { rawValue.capitalized }

    var swatchColor: Color {
        switch self {
        case .blue:   Color(hex: "5A87A4")
        case .teal:   Color(hex: "3D9090")
        case .slate:  Color(hex: "6B7A8D")
        case .indigo: Color(hex: "5C5FA4")
        }
    }

    var rightAccent: Color { swatchColor }

    var rightBg: Color {
        switch self {
        case .blue:   Color(hex: "EEF4F8")
        case .teal:   Color(hex: "E8F4F4")
        case .slate:  Color(hex: "EEF0F4")
        case .indigo: Color(hex: "EEEEF8")
        }
    }

    var rightText: Color {
        switch self {
        case .blue:   Color(hex: "2A5474")
        case .teal:   Color(hex: "1A4848")
        case .slate:  Color(hex: "2A3848")
        case .indigo: Color(hex: "2A2A6A")
        }
    }

    var rightShadow: Color { rightAccent.opacity(0.12) }
}

// MARK: - Color palette

struct NourishColors {
    let accent: AccentVariant
    let rightVariant: RightAccentVariant

    init(accent: AccentVariant, rightAccent: RightAccentVariant = .blue) {
        self.accent = accent
        self.rightVariant = rightAccent
    }

    var bg: Color      { Color(hex: "FAF7F2") }
    var surface: Color { .white }
    var ink: Color     { Color(hex: "1A130E") }
    var muted: Color   { Color(hex: "7A6E67") }
    var border: Color  { Color(hex: "1A130E").opacity(0.09) }
    var green: Color   { Color(hex: "5A9470") }
    var greenBg: Color { Color(hex: "E8F4EC") }

    var leftAccent: Color  { accent.leftAccent }
    var leftBg: Color      { accent.leftBg }
    var leftText: Color    { accent.leftText }
    var leftShadow: Color  { accent.leftShadow }

    var rightAccent: Color { rightVariant.rightAccent }
    var rightBg: Color     { rightVariant.rightBg }
    var rightText: Color   { rightVariant.rightText }
    var rightShadow: Color { rightVariant.rightShadow }

    var bottleAccent: Color  { Color(hex: "9C7A3C") }
    var bottleBg: Color      { Color(hex: "F7F3EC") }
    var bottleBorder: Color  { Color(hex: "9C7A3C").opacity(0.28) }

    func accentColor(for side: FeedSide) -> Color { side == .left ? leftAccent : rightAccent }
    func bgColor(for side: FeedSide) -> Color     { side == .left ? leftBg : rightBg }
    func textColor(for side: FeedSide) -> Color   { side == .left ? leftText : rightText }
    func shadowColor(for side: FeedSide) -> Color { side == .left ? leftShadow : rightShadow }
}

// MARK: - Environment

private struct NourishColorsKey: EnvironmentKey {
    static let defaultValue = NourishColors(accent: .terra, rightAccent: .blue)
}

extension EnvironmentValues {
    var nourishColors: NourishColors {
        get { self[NourishColorsKey.self] }
        set { self[NourishColorsKey.self] = newValue }
    }
}

// MARK: - Color hex init

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:  (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:  (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:  (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB, red: Double(r)/255, green: Double(g)/255, blue: Double(b)/255, opacity: Double(a)/255)
    }
}

// MARK: - Typography
// Add DMSerifDisplay-Regular, DMSerifDisplay-Italic, and PlusJakartaSans-* font files
// to the Xcode project (target membership checked) and register them in Info.plist
// under "Fonts provided by application". Until then, system serif / default sans are used.

extension Font {
    static func nSerif(_ size: CGFloat, italic: Bool = false) -> Font {
        NourishFont.serif(size, italic: italic)
    }
    static func nSans(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        NourishFont.sans(size, weight: weight)
    }
}

// MARK: - Shared button style

struct ScaleButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.963
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1.0)
            .animation(.spring(response: 0.28, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - Pill label

struct NourishPill: View {
    let label: String
    let fill: Color
    let border: Color
    let color: Color
    var size: CGFloat = 13

    var body: some View {
        Text(label)
            .font(.nSans(size, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(fill)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(border, lineWidth: 1))
    }
}
