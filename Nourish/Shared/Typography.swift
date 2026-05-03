import SwiftUI
import CoreText

// MARK: - NourishFont

enum NourishFont {
    static func serif(_ size: CGFloat, italic: Bool = false) -> Font {
        .custom(
            italic ? "DMSerifDisplay-Italic" : "DMSerifDisplay-Regular",
            size: size,
            relativeTo: .title
        )
    }

    static func sans(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let suffix: String
        switch weight {
        case .light:         suffix = "Light"
        case .medium:        suffix = "Medium"
        case .semibold:      suffix = "SemiBold"
        case .bold:          suffix = "Bold"
        case .heavy, .black: suffix = "ExtraBold"
        default:             suffix = "Regular"
        }
        return .custom("PlusJakartaSans-\(suffix)", size: size)
    }

    // Register all bundled TTF fonts at app launch.
    static func registerAll() {
        let names = [
            "DMSerifDisplay-Regular",
            "DMSerifDisplay-Italic",
            "PlusJakartaSans-Light",
            "PlusJakartaSans-Regular",
            "PlusJakartaSans-Medium",
            "PlusJakartaSans-SemiBold",
            "PlusJakartaSans-Bold",
            "PlusJakartaSans-ExtraBold",
        ]
        for name in names {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}
