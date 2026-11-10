import SwiftUI

// Reusable building blocks. Screens compose these and never set colors, fonts or radii directly.

extension View {
    /// Grouped surface with the standard padding and corner radius.
    func card() -> some View {
        self
            .padding(Theme.Space.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }

    /// Standard scrolling screen: page background and vertical rhythm between cards.
    func screenBackground() -> some View {
        self.background(Theme.Palette.background.ignoresSafeArea())
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
        Text(text)
            .font(Theme.Typography.label)
            .foregroundStyle(tone == .neutral ? Theme.Palette.muted : tone.color)
            .padding(.horizontal, Theme.Space.s)
            .padding(.vertical, 3)
            .background(tone.soft, in: Capsule())
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
