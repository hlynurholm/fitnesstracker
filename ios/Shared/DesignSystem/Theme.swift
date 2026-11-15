import Observation
import SwiftUI
import UIKit

/// Central design tokens for the app and the Live Activity.
/// Restyling starts here: colors, type, spacing and radii are only defined in this file.
enum Theme {
    /// Colours. They come from the theme chosen in Settings (`ThemeStore`), so nothing here is a fixed value:
    /// a view that reads one of these is redrawn when the theme changes.
    enum Palette {
        private static var colors: ThemeColors { ThemeStore.shared.colors }

        static var background: Color { colors.background }
        static var surface: Color { colors.surface }
        static var surfaceRaised: Color { colors.surfaceRaised }
        static let fill = Color(uiColor: .tertiarySystemFill)
        static let separator = Color(uiColor: .separator)
        static let text = Color.primary
        static let muted = Color.secondary

        static var accent: Color { colors.accent }
        static var ok: Color { colors.ok }
        static var warn: Color { colors.warn }
        static var danger: Color { colors.danger }
        /// Text and icons on top of the accent colour: black or white, whichever reads.
        static var onAccent: Color { on(accent) }

        // Session kinds
        static var lift: Color { accent }
        static var run: Color { warn }
        static var rest: Color { colors.rest }
        static var test: Color { colors.test }

        // Health metrics on the dashboard
        static var heart: Color { colors.heart }
        static var sleep: Color { colors.sleep }
        static var energy: Color { colors.energy }
        static var calm: Color { colors.calm }

        /// Two-colour fills for the widgets that carry a whole card of colour, top left to bottom right.
        static var periwinkle: [Color] { colors.fills[0] }
        static var butter: [Color] { colors.fills[1] }
        static var dusk: [Color] { colors.fills[2] }
        static var coral: [Color] { colors.fills[3] }
        /// The waves behind every screen, quietest first.
        static var waves: [Color] { colors.waves }

        /// Black or white, whichever reads on the given colour.
        static func on(_ color: Color) -> Color { isLight(color) ? .black : .white }

        /// Whether a colour is light enough that dark text belongs on it.
        static func isLight(_ color: Color) -> Bool {
            var (r, g, b, a): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
            UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
            return 0.299 * r + 0.587 * g + 0.114 * b > 0.6
        }

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
        static var series: [Color] { [accent, warn, ok, test, danger, rest] }

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
        /// The main value of a tile or widget, whether a number or a name. In the heading face, so "Lift B" and
        /// "4.71" look alike; the unit after it is set in `caption` or `callout`.
        static let numeral = Font.system(.title2, design: headingDesign, weight: .heavy).width(headingWidth).monospacedDigit()
        static let timer = Font.system(.largeTitle, design: headingDesign, weight: .heavy).width(headingWidth).monospacedDigit()

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

// MARK: Themes

/// The colour themes offered in Settings.
enum ThemeKind: String, CaseIterable, Identifiable {
    case dark, light, colorful, monoDark, monoLight
    var id: String { rawValue }
    var title: String {
        switch self {
        case .dark: "Dark"
        case .light: "Light"
        case .colorful: "Colourful"
        case .monoDark: "Mono dark"
        case .monoLight: "Mono light"
        }
    }
}

/// Every colour a theme decides.
struct ThemeColors {
    /// Light text on dark ground. Sets the system appearance, and with it the primary and secondary text colours.
    var isDark: Bool
    var background: Color, surface: Color, surfaceRaised: Color
    var accent: Color, ok: Color, warn: Color, danger: Color, rest: Color, test: Color
    var heart: Color, sleep: Color, energy: Color, calm: Color
    /// Three shades for the waves behind every screen, quietest first.
    var waves: [Color]
    /// Four two-colour fills for the cards of colour: next session, steps, sleep, intensity.
    var fills: [[Color]]

    private static func hex(_ value: UInt32) -> Color { Color(uiColor: UIColor(hex: value)) }
    private static func pairs(_ values: [UInt32]) -> [[Color]] { stride(from: 0, to: values.count, by: 2).map { [hex(values[$0]), hex(values[$0 + 1])] } }

    /// `hue` (0 to 1 around the colour wheel) is the main colour of the colourful theme.
    static func make(_ kind: ThemeKind, hue: Double) -> ThemeColors {
        switch kind {
        case .dark:
            return ThemeColors(isDark: true, background: hex(0x111113), surface: hex(0x1D1D21), surfaceRaised: hex(0x2B2B31),
                               accent: hex(0x9A97FF), ok: hex(0x5FE3A1), warn: hex(0xFFC94A), danger: hex(0xFF6B57), rest: hex(0x8E8E93), test: hex(0xCDA2FF),
                               heart: hex(0xFF6F86), sleep: hex(0x9B8CFF), energy: hex(0xFFB13D), calm: hex(0x6FD3F0),
                               waves: [hex(0x15181F), hex(0x1B2433), hex(0x24344F)],
                               fills: pairs([0xA7A4FF, 0x6C5CF2, 0xFFDF7A, 0xFF9F4A, 0x5B4BD6, 0xB56CF2, 0xFF8F6B, 0xF2507A]))
        case .light:
            return ThemeColors(isDark: false, background: hex(0xF3F2F7), surface: hex(0xFFFFFF), surfaceRaised: hex(0xE9E8F0),
                               accent: hex(0x5B54E8), ok: hex(0x1FA971), warn: hex(0xD98200), danger: hex(0xE5483A), rest: hex(0x8E8E93), test: hex(0x9B4FD6),
                               heart: hex(0xE8456A), sleep: hex(0x5B54D6), energy: hex(0xF08A00), calm: hex(0x1E9DBB),
                               waves: [hex(0xEEF1F8), hex(0xDFE7F6), hex(0xCCDAF3)],
                               fills: pairs([0xA7A4FF, 0x6C5CF2, 0xFFDF7A, 0xFF9F4A, 0x5B4BD6, 0xB56CF2, 0xFF8F6B, 0xF2507A]))
        case .monoDark:
            return ThemeColors(isDark: true, background: hex(0x0D0D0D), surface: hex(0x1A1A1A), surfaceRaised: hex(0x282828),
                               accent: hex(0xF5F5F5), ok: hex(0xE0E0E0), warn: hex(0xBDBDBD), danger: hex(0xFFFFFF), rest: hex(0x757575), test: hex(0xD6D6D6),
                               heart: hex(0xEDEDED), sleep: hex(0xC8C8C8), energy: hex(0xB0B0B0), calm: hex(0x8F8F8F),
                               waves: [hex(0x121212), hex(0x1B1B1B), hex(0x262626)],
                               fills: pairs([0xF5F5F5, 0xC2C2C2, 0xD9D9D9, 0x9E9E9E, 0x3A3A3A, 0x5C5C5C, 0x8A8A8A, 0x5E5E5E]))
        case .monoLight:
            return ThemeColors(isDark: false, background: hex(0xF4F4F4), surface: hex(0xFFFFFF), surfaceRaised: hex(0xE8E8E8),
                               accent: hex(0x111111), ok: hex(0x2B2B2B), warn: hex(0x5A5A5A), danger: hex(0x000000), rest: hex(0x9A9A9A), test: hex(0x3D3D3D),
                               heart: hex(0x1F1F1F), sleep: hex(0x4A4A4A), energy: hex(0x666666), calm: hex(0x808080),
                               waves: [hex(0xEFEFEF), hex(0xE5E5E5), hex(0xD9D9D9)],
                               fills: pairs([0x1C1C1C, 0x3D3D3D, 0x2E2E2E, 0x555555, 0xD0D0D0, 0xB5B5B5, 0x6E6E6E, 0x4A4A4A]))
        case .colorful:
            // Colour theory from one hue. The ground and the main accent are that hue. Charts take its neighbours on
            // the wheel (analogous, 30 and 60 degrees away), the loudest parts take the colours across from it
            // (the complement at 180 and the split complements at 150 and 210), and one card takes a triad (120).
            // Good, warning and bad stay green, amber and red, so their meaning does not move with the hue.
            func c(_ degrees: Double, _ saturation: Double, _ brightness: Double) -> Color {
                Color(hue: (hue + degrees / 360 + 1).truncatingRemainder(dividingBy: 1), saturation: saturation, brightness: brightness)
            }
            return ThemeColors(isDark: true, background: c(0, 0.62, 0.15), surface: c(0, 0.50, 0.23), surfaceRaised: c(0, 0.42, 0.31),
                               accent: c(0, 0.40, 1), ok: Color(hue: 0.40, saturation: 0.55, brightness: 0.92), warn: Color(hue: 0.12, saturation: 0.65, brightness: 1),
                               danger: Color(hue: 0.01, saturation: 0.62, brightness: 1), rest: c(0, 0.12, 0.62), test: c(-30, 0.40, 1),
                               heart: c(210, 0.50, 1), sleep: c(-60, 0.42, 1), energy: c(180, 0.55, 1), calm: c(30, 0.40, 1),
                               waves: [c(0, 0.62, 0.21), c(0, 0.66, 0.30), c(30, 0.66, 0.40)],
                               fills: [[c(0, 0.42, 1), c(0, 0.72, 0.86)], [c(180, 0.38, 1), c(150, 0.66, 0.94)], [c(-60, 0.70, 0.70), c(-30, 0.60, 0.95)], [c(120, 0.45, 1), c(120, 0.72, 0.86)]])
        }
    }
}

/// The theme in use. Changing `kind` or `hue` recolours the whole app and is remembered on the phone.
@Observable
final class ThemeStore {
    static let shared = ThemeStore()
    var kind: ThemeKind { didSet { UserDefaults.standard.set(kind.rawValue, forKey: "themeKind"); colors = .make(kind, hue: hue) } }
    /// The main colour of the colourful theme, as a position on the colour wheel from 0 to 1.
    var hue: Double { didSet { UserDefaults.standard.set(hue, forKey: "themeHue"); colors = .make(kind, hue: hue) } }
    private(set) var colors: ThemeColors

    private init() {
        let defaults = UserDefaults.standard
        let kind = defaults.string(forKey: "themeKind").flatMap(ThemeKind.init) ?? .dark
        let hue = defaults.object(forKey: "themeHue") as? Double ?? 0.58
        self.kind = kind; self.hue = hue; colors = .make(kind, hue: hue)
    }
}
