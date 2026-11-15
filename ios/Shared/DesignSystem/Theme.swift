import SwiftUI
import UIKit

/// Central design tokens for the app and the Live Activity.
/// Restyling starts here: colors, type, spacing and radii are only defined in this file.
enum Theme {
    enum Palette {
        static let background = dynamic(light: 0xF2F2F7, dark: 0x111113)
        static let surface = dynamic(light: 0xFFFFFF, dark: 0x1D1D21)
        static let surfaceRaised = dynamic(light: 0xF2F2F7, dark: 0x2B2B31)
        static let fill = Color(uiColor: .tertiarySystemFill)
        static let separator = Color(uiColor: .separator)
        static let text = Color.primary
        static let muted = Color.secondary

        // Stylized palette: periwinkle, mint, butter and coral on charcoal.
        static let accent = dynamic(light: 0x5B54E8, dark: 0x9A97FF)
        static let ok = dynamic(light: 0x1FA971, dark: 0x5FE3A1)
        static let warn = dynamic(light: 0xE08A00, dark: 0xFFC94A)
        static let danger = dynamic(light: 0xE5483A, dark: 0xFF6B57)

        // Session kinds
        static let lift = accent
        static let run = warn
        static let rest = dynamic(light: 0x8E8E93, dark: 0x8E8E93)
        static let test = dynamic(light: 0xAF52DE, dark: 0xCDA2FF)

        // Health metrics on the dashboard
        static let heart = dynamic(light: 0xFF2D55, dark: 0xFF6F86)
        static let sleep = dynamic(light: 0x5856D6, dark: 0x9B8CFF)
        static let energy = dynamic(light: 0xFF9500, dark: 0xFFB13D)
        static let calm = dynamic(light: 0x30B0C7, dark: 0x6FD3F0)

        /// Two-colour fills for the widgets that carry a whole card of colour, top left to bottom right.
        static let periwinkle = [hex(0xA7A4FF), hex(0x6C5CF2)]
        static let butter = [hex(0xFFDF7A), hex(0xFF9F4A)]
        static let dusk = [hex(0x5B4BD6), hex(0xB56CF2)]
        static let coral = [hex(0xFF8F6B), hex(0xF2507A)]
        /// The waves behind every screen: charcoal with a quiet blue, darkest first.
        static let waves = [hex(0x15181F), hex(0x1B2433), hex(0x24344F)]

        private static func hex(_ value: UInt32) -> Color { Color(uiColor: UIColor(hex: value)) }

        /// Colour along a route or pace chart: 0 is the slowest part of the run, 1 the fastest.
        static func effort(_ t: Double) -> Color {
            let stops: [UIColor] = [UIColor(calm), UIColor(energy), UIColor(heart)]
            let x = min(max(t, 0), 1) * Double(stops.count - 1)
            let i = min(Int(x), stops.count - 2)
            var (r1, g1, b1, a1): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0), (r2, g2, b2, a2): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
            stops[i].getRed(&r1, green: &g1, blue: &b1, alpha: &a1); stops[i + 1].getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
            let f = CGFloat(x - Double(i))
            return Color(red: r1 + (r2 - r1) * f, green: g1 + (g2 - g1) * f, blue: b1 + (b2 - b1) * f)
        }

        /// Chart series colors, in order.
        static let series: [Color] = [accent, warn, ok, test, danger, rest]

        static func kind(_ kind: String) -> Color {
            switch kind {
            case "lift": lift
            case "run": run
            case "rest": rest
            default: test
            }
        }
    }

    enum Space {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
    }

    enum Radius {
        static let card: CGFloat = 26
        static let control: CGFloat = 14
        static let small: CGFloat = 6
    }

    enum Typography {
        // Two faces. Headings are the system face in its condensed heavy cut, poster style. Everything else is the
        // accessory face, Avenir Next, which ships with iOS. The standard system face is not used for text.
        static let headingDesign: Font.Design = .default
        /// `.standard` turns the narrow headings off.
        static let headingWidth: Font.Width = .condensed
        /// Family prefix of the accessory face: "AvenirNext" gives AvenirNext-Regular, -Medium, -DemiBold and -Bold.
        static let accessory = "AvenirNext"

        static let screenTitle = Font.system(.largeTitle, design: headingDesign, weight: .heavy).width(headingWidth)
        static let title = Font.system(.title, design: headingDesign, weight: .heavy).width(headingWidth)
        static let headline = Font.system(.title3, design: headingDesign, weight: .heavy).width(headingWidth)
        static let label = Font.system(.caption, design: headingDesign, weight: .bold).width(headingWidth)
        static let body = text("Regular", 17, .body)
        static let callout = text("Regular", 16, .callout)
        static let caption = text("Medium", 13, .footnote)
        /// Big numbers: tiles, timers.
        static let numeral = text("Bold", 22, .title2).monospacedDigit()
        static let timer = text("Bold", 34, .largeTitle).monospacedDigit()

        /// The accessory face at a size that still follows the reader's text size setting.
        private static func text(_ weight: String, _ size: CGFloat, _ style: Font.TextStyle) -> Font {
            .custom("\(accessory)-\(weight)", size: size, relativeTo: style)
        }

        /// Navigation bar titles and tab bar labels are drawn by UIKit, so they get their typefaces through the bars'
        /// appearance. Call once at launch.
        static func applyToBars() {
            let bar = UINavigationBar.appearance()
            bar.largeTitleTextAttributes = [.font: heading(.largeTitle)]
            bar.titleTextAttributes = [.font: heading(.title3)]
            let tabs = [NSAttributedString.Key.font: UIFont(name: "\(accessory)-DemiBold", size: 10) ?? .systemFont(ofSize: 10, weight: .semibold)]
            UITabBarItem.appearance().setTitleTextAttributes(tabs, for: .normal)
            UITabBarItem.appearance().setTitleTextAttributes(tabs, for: .selected)
        }

        private static func heading(_ style: UIFont.TextStyle) -> UIFont {
            .systemFont(ofSize: UIFont.preferredFont(forTextStyle: style).pointSize, weight: .heavy, width: headingWidth == .condensed ? .condensed : .standard)
        }
    }

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }
}

/// Semantic tone for badges, banners and values.
enum Tone {
    case neutral, accent, ok, warn, danger

    var color: Color {
        switch self {
        case .neutral: Theme.Palette.muted
        case .accent: Theme.Palette.accent
        case .ok: Theme.Palette.ok
        case .warn: Theme.Palette.warn
        case .danger: Theme.Palette.danger
        }
    }

    var soft: Color { self == .neutral ? Theme.Palette.fill : color.opacity(0.15) }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}
