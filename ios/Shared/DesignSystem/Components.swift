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

/// Behind every screen: charcoal with soft coloured lights and grain.
struct Backdrop: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                Theme.Palette.background
                Circle().fill(Theme.Palette.glow[0]).frame(width: w * 0.95).position(x: w * 0.1, y: h * 0.12)
                Circle().fill(Theme.Palette.glow[1]).frame(width: w * 0.7).position(x: w * 0.95, y: h * 0.42)
                Circle().fill(Theme.Palette.glow[2]).frame(width: w * 0.8).position(x: w * 0.15, y: h * 0.85)
            }
            .blur(radius: 90)
            .overlay { Theme.Palette.background.opacity(0.45) }
            .overlay { Grain().blendMode(.overlay).opacity(0.35) }
        }
    }
}

/// Vertical stack of cards inside a ScrollView, used by every tab.
struct Screen<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Theme.Space.m) { content }
                .padding(.horizontal, Theme.Space.l)
                .padding(.bottom, Theme.Space.xl)
        }
        .screenBackground()
        .scrollDismissesKeyboard(.interactively)
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

/// Round glass button face with an arrow, on cards that open something.
struct OpenGlyph: View {
    var body: some View {
        Image(systemName: "arrow.up.right").font(.footnote.weight(.bold)).foregroundStyle(Theme.Palette.text)
            .frame(width: 36, height: 36).glass(in: Circle())
    }
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
            Row(title: title, subtitle: subtitle, titleColor: tone?.color ?? Theme.Palette.text) {
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.Palette.muted)
            }
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
            .foregroundStyle(.white)
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
