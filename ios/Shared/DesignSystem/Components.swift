import SwiftUI

// Reusable building blocks. Screens compose these and never set colors, fonts or radii directly.

extension View {
    /// Grouped surface with the standard padding and corner radius.
    func card() -> some View {
        self
            .padding(Theme.Space.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()
    }

    /// What a card is made of: dark glass that lets the lights behind the screen through, or, with `fill`, a grainy
    /// gradient of its own. `lightFill` says the fill is a light colour, so what sits on it turns dark.
    @ViewBuilder
    func cardSurface(fill: [Color]? = nil, lightFill: Bool = false) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
        if let fill {
            self.environment(\.onColor, true).environment(\.colorScheme, lightFill ? .light : .dark)
                .background { GrainyGradient(colors: fill).clipShape(shape) }
                .overlay { shape.strokeBorder(.white.opacity(0.18), lineWidth: 1) }
        } else if #available(iOS 26.0, *) {
            self.glassEffect(.regular.tint(Theme.Palette.surface.opacity(0.55)), in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape)
        }
    }

    /// A small piece of glass under a control or a chip.
    @ViewBuilder
    func glass(in shape: some Shape = Capsule()) -> some View {
        if #available(iOS 26.0, *) { self.glassEffect(.regular, in: shape) } else { self.background(.ultraThinMaterial, in: shape) }
    }

    /// Standard scrolling screen: the page background, which stays put while the cards scroll over it.
    func screenBackground() -> some View {
        self.background { Backdrop().ignoresSafeArea() }
    }
}

/// Secondary text. On a card of colour the system's grey would sink into the card, so it is the text colour, thinned.
struct MutedStyle: ViewModifier {
    @Environment(\.onColor) private var onColor
    func body(content: Content) -> some View { content.foregroundStyle(onColor ? Theme.Palette.text.opacity(0.72) : Theme.Palette.muted) }
}

extension View {
    func muted() -> some View { modifier(MutedStyle()) }
}

extension View {
    /// The title of a pushed screen or a sheet: small, in the bar, drawn by the app in the heading typeface. Every
    /// screen that keeps its navigation bar uses this instead of `navigationTitle`, so no title falls back to the
    /// system's own font. (First screens of tabs use `Screen(title:)`.)
    func inlineTitle(_ title: String) -> some View {
        navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .principal) { Text(title).font(Theme.Typography.headline).lineLimit(1).accessibilityAddTraits(.isHeader) } }
    }
}

extension EnvironmentValues {
    /// The view sits on a card that is filled with colour, so it draws in the text colour instead of its own tint.
    @Entry var onColor = false
}

/// Fine film grain, tiled. Laid over gradients so they do not look like plastic.
struct Grain: View {
    private static let tile: UIImage = {
        let side = 128
        var pixels = [UInt8](repeating: 0, count: side * side)
        var generator = SystemRandomNumberGenerator()
        for i in pixels.indices { pixels[i] = UInt8.random(in: 0...255, using: &generator) }
        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        let image = CGImage(width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: side, space: CGColorSpaceCreateDeviceGray(),
                            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        return UIImage(cgImage: image, scale: 3, orientation: .up)
    }()
    var body: some View { Image(uiImage: Self.tile).resizable(resizingMode: .tile).accessibilityHidden(true) }
}

/// A two-colour gradient with grain over it.
struct GrainyGradient: View {
    let colors: [Color]
    var body: some View {
        LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            .overlay { Grain().blendMode(.overlay).opacity(0.32) }
    }
}

/// Behind every screen: charcoal with slow waves of a quiet blue rolling across it, and grain.
struct Backdrop: View {
    var body: some View {
        ZStack {
            Theme.Palette.background
            // Each band is a wave along its top edge, filled downwards and fading out, so the bands overlap softly.
            Wave(height: 0.10, swell: 0.07, turns: 1.0, phase: 0.6).fill(LinearGradient(colors: [Theme.Palette.waves[2], Theme.Palette.waves[1].opacity(0)], startPoint: .top, endPoint: .bottom))
            Wave(height: 0.36, swell: 0.085, turns: 0.8, phase: 2.6).fill(LinearGradient(colors: [Theme.Palette.waves[1], Theme.Palette.waves[0].opacity(0)], startPoint: .top, endPoint: .bottom))
            Wave(height: 0.60, swell: 0.075, turns: 1.2, phase: 4.4).fill(LinearGradient(colors: [Theme.Palette.waves[2].opacity(0.85), Theme.Palette.waves[0].opacity(0)], startPoint: .top, endPoint: .bottom))
            Wave(height: 0.84, swell: 0.06, turns: 0.9, phase: 1.2).fill(LinearGradient(colors: [Theme.Palette.waves[1], Theme.Palette.waves[0].opacity(0)], startPoint: .top, endPoint: .bottom))
        }
        .blur(radius: 10)
        .overlay { Grain().blendMode(.overlay).opacity(0.3) }
    }
}

/// The area under a sine wave: `height` is where the wave sits (0 top, 1 bottom), `swell` how far it rises and falls,
/// both as shares of the view's height; `turns` is how many waves cross the width.
private struct Wave: Shape {
    let height: CGFloat
    let swell: CGFloat
    let turns: CGFloat
    let phase: CGFloat
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let y = { (x: CGFloat) in rect.height * (height + swell * sin(x / rect.width * turns * 2 * .pi + phase)) }
        path.move(to: CGPoint(x: -40, y: y(-40)))
        for x in stride(from: -40, through: rect.width + 40, by: 8) { path.addLine(to: CGPoint(x: x, y: y(x))) }
        path.addLine(to: CGPoint(x: rect.width + 40, y: rect.height * min(height + 0.38, 1.1)))
        path.addLine(to: CGPoint(x: -40, y: rect.height * min(height + 0.38, 1.1)))
        path.closeSubpath()
        return path
    }
}

/// Vertical stack of cards inside a ScrollView, used by every tab.
struct Screen<Content: View>: View {
    /// The page's heading, for the first screen of a tab. With one, the navigation bar is hidden and the heading is
    /// drawn here in the heading typeface, so every tab's title looks the same and no empty bar sits above it.
    /// Screens that are pushed (and need the back button) leave it nil and set an inline `navigationTitle`.
    var title: String? = nil
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Theme.Space.m) {
                if let title {
                    Text(title).font(Theme.Typography.screenTitle).lineLimit(1).minimumScaleFactor(0.7)
                        .padding(.horizontal, Theme.Space.xs).padding(.top, Theme.Space.s).accessibilityAddTraits(.isHeader)
                }
                content
            }
            .padding(.horizontal, Theme.Space.l)
            .padding(.bottom, Theme.Space.xl)
        }
        .screenBackground()
        .scrollDismissesKeyboard(.interactively)
        .toolbar(title == nil ? .automatic : .hidden, for: .navigationBar)
        .overlay(alignment: .top) { if title != nil { StatusBarFade() } }
    }
}

/// With the navigation bar hidden, the page scrolls under the clock. This blurs it out there.
private struct StatusBarFade: View {
    var body: some View {
        GeometryReader { geo in
            Rectangle().fill(.ultraThinMaterial)
                .mask(LinearGradient(stops: [.init(color: .black, location: 0.65), .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
                .frame(height: geo.safeAreaInsets.top + 12)
                .offset(y: -geo.safeAreaInsets.top)
        }
        .allowsHitTesting(false)
    }
}

struct Badge: View {
    let text: String
    var tone: Tone = .neutral
    init(_ text: String, tone: Tone = .neutral) { self.text = text; self.tone = tone }
    var body: some View {
        let label = Text(text)
            .font(Theme.Typography.label)
            .padding(.horizontal, Theme.Space.s + 2)
            .padding(.vertical, Theme.Space.xs)
        // On a card of colour the tones would clash with the card, so the badge turns into a piece of glass.
        if onColor { label.foregroundStyle(Theme.Palette.text).glass() } else { label.foregroundStyle(tone == .neutral ? Theme.Palette.muted : tone.color).background(tone.soft, in: Capsule()) }
    }
    @Environment(\.onColor) private var onColor
}

struct SectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased())
            .font(Theme.Typography.label)
            .foregroundStyle(Theme.Palette.muted)
            .padding(.horizontal, Theme.Space.xs)
            .padding(.top, Theme.Space.s)
    }
}

/// Card heading with an optional trailing note or view.
struct CardTitle<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(Theme.Typography.headline)
            Spacer(minLength: Theme.Space.s)
            trailing
        }
    }
}

extension CardTitle where Trailing == Text {
    init(_ title: String, note: String? = nil) {
        self.title = title
        self.trailing = Text(note ?? "").font(Theme.Typography.caption).foregroundStyle(Theme.Palette.muted)
    }
}

struct Banner: View {
    let text: String
    var tone: Tone = .warn
    init(_ text: String, tone: Tone = .warn) { self.text = text; self.tone = tone }
    var body: some View {
        Text(text)
            .font(Theme.Typography.callout)
            .padding(Theme.Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tone.soft, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
    }
}

/// Stat tile: small label, big value, optional detail line.
struct Tile: View {
    let label: String
    let value: String
    var detail: String? = nil
    var tone: Tone? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text(label).font(Theme.Typography.label).foregroundStyle(Theme.Palette.muted)
            Text(value).font(Theme.Typography.numeral).foregroundStyle(tone?.color ?? Theme.Palette.text).minimumScaleFactor(0.6).lineLimit(1)
            if let detail { Text(detail).font(Theme.Typography.caption).foregroundStyle(Theme.Palette.muted) }
        }
        .frame(maxHeight: .infinity, alignment: .top) // tiles in one grid row share a height
        .card()
    }
}

/// Two-column grid of tiles.
struct TileGrid<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: Theme.Space.m), GridItem(.flexible())], spacing: Theme.Space.m) { content }
    }
}

/// List row inside a card: title, optional subtitle, optional trailing view.
struct Row<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    var titleColor: Color = Theme.Palette.text
    @ViewBuilder var trailing: Trailing
    var body: some View {
        HStack(alignment: .center, spacing: Theme.Space.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.Typography.body).foregroundStyle(titleColor)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle).font(Theme.Typography.caption).foregroundStyle(Theme.Palette.muted)
                }
            }
            Spacer(minLength: Theme.Space.s)
            trailing
        }
        .padding(.vertical, Theme.Space.s)
        .contentShape(Rectangle())
    }
}

extension Row where Trailing == EmptyView {
    init(_ title: String, subtitle: String? = nil, titleColor: Color = Theme.Palette.text) {
        self.title = title; self.subtitle = subtitle; self.titleColor = titleColor
        self.trailing = EmptyView()
    }
}

/// Row that navigates or acts: shows a chevron.
struct ActionRow: View {
    let title: String
    var subtitle: String? = nil
    var tone: Tone? = nil
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Row(title: title, subtitle: subtitle, titleColor: tone?.color ?? Theme.Palette.text) { EmptyView() }
        }
        .buttonStyle(.plain)
    }
}

struct Divided<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group(subviews: content) { subviews in
                ForEach(Array(subviews.enumerated()), id: \.offset) { index, subview in
                    if index > 0 { Divider().overlay(Theme.Palette.separator) }
                    subview
                }
            }
        }
    }
}

// MARK: Buttons

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Typography.headline)
            .foregroundStyle(Theme.Palette.onAccent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Space.m)
            .background(Theme.Palette.accent.opacity(configuration.isPressed ? 0.7 : 1), in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
    }
}

struct TintedButtonStyle: ButtonStyle {
    var tone: Tone = .accent
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Typography.headline)
            .foregroundStyle(tone.color)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Space.m)
            .background(tone.soft.opacity(configuration.isPressed ? 0.6 : 1), in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle { static var primary: PrimaryButtonStyle { .init() } }
extension ButtonStyle where Self == TintedButtonStyle {
    static var tinted: TintedButtonStyle { .init() }
    static func tinted(_ tone: Tone) -> TintedButtonStyle { .init(tone: tone) }
}

// MARK: Inputs

/// Rounded input surface for text fields.
struct FieldStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, Theme.Space.m)
            .padding(.vertical, Theme.Space.s)
            .background(Theme.Palette.fill, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
    }
}

extension View {
    func fieldStyle() -> some View { modifier(FieldStyle()) }
}

/// Labeled field: caption above the input.
struct LabeledField<Content: View>: View {
    let label: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text(label).font(Theme.Typography.caption).foregroundStyle(Theme.Palette.muted)
            content.fieldStyle()
        }
    }
}
