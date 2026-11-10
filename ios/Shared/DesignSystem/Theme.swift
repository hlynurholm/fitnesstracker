import SwiftUI
import UIKit

/// Central design tokens for the app and the Live Activity.
/// Restyling starts here: colors, type, spacing and radii are only defined in this file.
enum Theme {
    enum Palette {
        static let background = dynamic(light: 0xF2F2F7, dark: 0x000000)
        static let surface = dynamic(light: 0xFFFFFF, dark: 0x1C1C1E)
        static let surfaceRaised = dynamic(light: 0xF2F2F7, dark: 0x2C2C2E)
        static let fill = Color(uiColor: .tertiarySystemFill)
        static let separator = Color(uiColor: .separator)
        static let text = Color.primary
        static let muted = Color.secondary

        static let accent = dynamic(light: 0x007AFF, dark: 0x0A84FF)
        static let ok = dynamic(light: 0x34C759, dark: 0x30D158)
        static let warn = dynamic(light: 0xFF9500, dark: 0xFF9F0A)
        static let danger = dynamic(light: 0xFF3B30, dark: 0xFF453A)

        // Session kinds
        static let lift = accent
        static let run = warn
        static let rest = dynamic(light: 0x8E8E93, dark: 0x8E8E93)
        static let test = dynamic(light: 0xAF52DE, dark: 0xBF5AF2)

        // Health metrics on the dashboard
        static let heart = dynamic(light: 0xFF2D55, dark: 0xFF375F)
        static let sleep = dynamic(light: 0x5856D6, dark: 0x5E5CE6)
        static let energy = dynamic(light: 0xFF9500, dark: 0xFF9F0A)
        static let calm = dynamic(light: 0x30B0C7, dark: 0x40C8E0)

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
        static let card: CGFloat = 16
        static let control: CGFloat = 10
        static let small: CGFloat = 6
    }

    enum Typography {
        /// Typeface for headings, labels, buttons and numbers. Body text keeps the standard face for long reading.
        /// Set to `.default` to turn the rounded look off everywhere, navigation titles included.
        static let headingDesign: Font.Design = .rounded

        static let screenTitle = Font.system(.largeTitle, design: headingDesign, weight: .bold)
        static let title = Font.system(.title2, design: headingDesign, weight: .bold)
        static let headline = Font.system(.headline, design: headingDesign)
        static let body = Font.system(.body)
        static let callout = Font.system(.callout)
        static let caption = Font.system(.footnote)
        static let label = Font.system(.caption, design: headingDesign, weight: .semibold)
        /// Big numbers: tiles, timers.
        static let numeral = Font.system(.title2, design: headingDesign, weight: .semibold).monospacedDigit()
        static let timer = Font.system(.largeTitle, design: headingDesign, weight: .semibold).monospacedDigit()

        /// Navigation bar titles are drawn by UIKit, so they get the heading typeface through the bar's appearance.
        /// Call once at launch.
        static func applyToNavigationBars() {
            let bar = UINavigationBar.appearance()
            bar.largeTitleTextAttributes = [.font: uiFont(.largeTitle, weight: .bold)]
            bar.titleTextAttributes = [.font: uiFont(.headline, weight: .semibold)]
        }

        private static func uiFont(_ style: UIFont.TextStyle, weight: UIFont.Weight) -> UIFont {
            let base = UIFont.systemFont(ofSize: UIFont.preferredFont(forTextStyle: style).pointSize, weight: weight)
            guard headingDesign == .rounded, let rounded = base.fontDescriptor.withDesign(.rounded) else { return base }
            return UIFont(descriptor: rounded, size: 0)
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

private extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}
