import SwiftUI
import CoreText
import UIKit

// MARK: - NourishFont

enum NourishFont {
    /// Designs are baselined for iPhone Pro Max (430pt). Narrower screens
    /// (iPhone 15 = 393pt, SE = 375pt) scale fonts down proportionally so
    /// text doesn't crowd the layout. Computed once at first access.
    static let screenScale: CGFloat = {
        let baselineWidth: CGFloat = 430
        let minScale: CGFloat = 0.86
        let width = UIScreen.main.bounds.width
        return max(minScale, min(1.0, width / baselineWidth))
    }()

    static func serif(_ size: CGFloat, italic: Bool = false) -> Font {
        .custom(
            italic ? "DMSerifDisplay-Italic" : "DMSerifDisplay-Regular",
            size: size * screenScale,
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
        return .custom("PlusJakartaSans-\(suffix)", size: size * screenScale)
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
