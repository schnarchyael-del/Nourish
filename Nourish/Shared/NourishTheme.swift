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

// MARK: - App theme

enum AppTheme: String, CaseIterable {
    case system, light, dark

    var displayName: String {
        switch self {
        case .system: return "System"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }

    /// Value to pass to `.preferredColorScheme(_:)`. nil = follow system.
    var preferredScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}

// MARK: - Color palette

struct NourishColors {
    let accent: AccentVariant
    let rightVariant: RightAccentVariant
    let darkMode: Bool

    init(accent: AccentVariant,
         rightAccent: RightAccentVariant = .blue,
         darkMode: Bool = false) {
        self.accent = accent
        self.rightVariant = rightAccent
        self.darkMode = darkMode
    }

    // MARK: Neutrals

    var bg: Color {
        darkMode ? Color(hex: "1C1917") : Color(hex: "FAF7F2")
    }
    var surface: Color {
        darkMode ? Color(hex: "292524") : .white
    }
    var ink: Color {
        darkMode ? Color(hex: "FAF7F2") : Color(hex: "1A130E")
    }
    var muted: Color {
        darkMode ? Color(hex: "A8A29E") : Color(hex: "7A6E67")
    }
    var border: Color {
        darkMode ? Color.white.opacity(0.10) : Color(hex: "1A130E").opacity(0.09)
    }
    var green: Color {
        darkMode ? Color(hex: "7BB68C") : Color(hex: "5A9470")
    }
    var greenBg: Color {
        darkMode ? Color(hex: "5A9470").opacity(0.20) : Color(hex: "E8F4EC")
    }

    // MARK: Sides

    var leftAccent: Color { accent.leftAccent }
    var leftBg: Color {
        darkMode ? leftAccent.opacity(0.20) : accent.leftBg
    }
    var leftText: Color {
        darkMode ? leftAccent : accent.leftText
    }
    var leftShadow: Color { accent.leftShadow }

    var rightAccent: Color { rightVariant.rightAccent }
    var rightBg: Color {
        darkMode ? rightAccent.opacity(0.20) : rightVariant.rightBg
    }
    var rightText: Color {
        darkMode ? rightAccent : rightVariant.rightText
    }
    var rightShadow: Color { rightVariant.rightShadow }

    // MARK: Bottle

    var bottleAccent: Color {
        darkMode ? Color(hex: "D4A75E") : Color(hex: "9C7A3C")
    }
    var bottleBg: Color {
        darkMode ? bottleAccent.opacity(0.18) : Color(hex: "F7F3EC")
    }
    var bottleBorder: Color {
        bottleAccent.opacity(0.28)
    }

    // MARK: Pump

    var pumpAccent: Color {
        darkMode ? Color(hex: "6FBAAD") : Color(hex: "2E9080")
    }
    var pumpBg: Color {
        darkMode ? pumpAccent.opacity(0.18) : Color(hex: "EAF4F2")
    }
    var pumpBorder: Color {
        pumpAccent.opacity(0.28)
    }

    // MARK: Helpers

    /// Backing color for fields/inputs that previously hard-coded `.white` —
    /// stays white in light mode, swaps to a slightly lighter card color in dark.
    var input: Color {
        darkMode ? Color(hex: "33302E") : .white
    }

    func accentColor(for side: FeedSide) -> Color { side == .left ? leftAccent : rightAccent }
    func bgColor(for side: FeedSide) -> Color     { side == .left ? leftBg : rightBg }
    func textColor(for side: FeedSide) -> Color   { side == .left ? leftText : rightText }
    func shadowColor(for side: FeedSide) -> Color { side == .left ? leftShadow : rightShadow }
}

// MARK: - Environment

private struct NourishColorsKey: EnvironmentKey {
    static let defaultValue = NourishColors(accent: .terra, rightAccent: .blue, darkMode: false)
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
