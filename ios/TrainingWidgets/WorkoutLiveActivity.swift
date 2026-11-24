import ActivityKit
import SwiftUI
import WidgetKit

@main
struct TrainingWidgetsBundle: WidgetBundle {
    var body: some Widget { WorkoutLiveActivity() }
}

struct WorkoutLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            let look = Look(context.attributes, context.state.phase)
            LockScreenView(attributes: context.attributes, state: context.state, look: look)
                .padding(Theme.Space.l)
                // A card of grainy colour, like the session card in the app.
                .background { GrainyGradient(colors: look.fill) }
                .activityBackgroundTint(look.fill[1])
                .activitySystemActionForegroundColor(look.ink)
        } dynamicIsland: { context in
            let tint = Look(context.attributes, context.state.phase).tint
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.attributes.name, systemImage: context.attributes.icon)
                        .font(Theme.Typography.label).foregroundStyle(tint)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.attributes.startedAt, style: .timer)
                        .font(Theme.Typography.label).monospacedDigit().foregroundStyle(Theme.Palette.muted)
                        .multilineTextAlignment(.trailing).frame(maxWidth: 64)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(context.state.title).font(Theme.Typography.headline).lineLimit(1)
                            Text(context.state.detail).font(Theme.Typography.caption).foregroundStyle(Theme.Palette.muted).lineLimit(1)
                        }
                        Spacer()
                        PhaseTimer(state: context.state, startedAt: context.attributes.startedAt)
                            .font(Theme.Typography.numeral).foregroundStyle(tint)
                            .multilineTextAlignment(.trailing).frame(maxWidth: 90)
                    }
                }
            } compactLeading: {
                Image(systemName: context.attributes.icon).foregroundStyle(tint)
            } compactTrailing: {
                IslandTimer(state: context.state, startedAt: context.attributes.startedAt, size: 14).foregroundStyle(tint)
            } minimal: {
                // The timer here too: with a podcast playing the system may give this activity only the small circle.
                IslandTimer(state: context.state, startedAt: context.attributes.startedAt, size: 11).foregroundStyle(tint)
            }
        }
    }
}

/// The colours of the activity: the theme the workout was started in, and the phase it is in.
private struct Look {
    /// The card, top left to bottom right.
    let fill: [Color]
    /// Text on the card: black or white, whichever reads.
    let ink: Color
    /// The phase's colour on black, for the Dynamic Island.
    let tint: Color

    init(_ attributes: WorkoutActivityAttributes, _ phase: WorkoutActivityAttributes.Phase) {
        let colors = ThemeColors.make(attributes.theme.flatMap(ThemeKind.init) ?? .dark, hue: attributes.hue ?? 0.6)
        // Lifting is the main card colour; a run changes colour with its phase, so a glance says work or recover.
        switch phase {
        case .lift: fill = colors.fills[0]; tint = colors.accent
        case .work: fill = colors.fills[3]; tint = colors.danger
        case .recover, .cooldown: fill = colors.fills[2]; tint = colors.ok
        case .warmup, .steady: fill = colors.fills[1]; tint = colors.warn
        }
        ink = Theme.Palette.on(fill[0])
    }
}

/// The heading face on the lock screen. There the weight and width set through `Font` alone came out as the regular
/// cut, so both are also stated as view modifiers.
private struct Heading: ViewModifier {
    let size: CGFloat
    let weight: Font.Weight
    init(_ size: CGFloat, _ weight: Font.Weight) { self.size = size; self.weight = weight }
    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: weight).width(Theme.Typography.headingWidth)).fontWeight(weight).fontWidth(Theme.Typography.headingWidth)
    }
}

private struct LockScreenView: View {
    let attributes: WorkoutActivityAttributes
    let state: WorkoutActivityAttributes.ContentState
    let look: Look

    var body: some View {
        let ink = look.ink, soft = look.ink.opacity(0.72)
        // The big number is the countdown or the rest; the time since the start then sits small at the top. When the
        // big number is itself the time since the start, it is not repeated.
        let showsElapsed = state.countdown != nil || state.restSince != nil
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(spacing: Theme.Space.s) {
                Label(attributes.name.uppercased(), systemImage: attributes.icon).modifier(Heading(13, .bold)).foregroundStyle(ink)
                Spacer()
                if showsElapsed {
                    Text(attributes.startedAt, style: .timer).modifier(Heading(13, .bold)).monospacedDigit().foregroundStyle(soft)
                        .multilineTextAlignment(.trailing).frame(maxWidth: 80)
                } else {
                    Text(state.progress.uppercased()).modifier(Heading(13, .bold)).foregroundStyle(soft).lineLimit(1)
                }
            }
            HStack(alignment: .center, spacing: Theme.Space.m) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.title.uppercased()).modifier(Heading(30, .heavy)).foregroundStyle(ink).lineLimit(1).minimumScaleFactor(0.6)
                    // "Set 1 of 4 · 122.5 kg × 4 reps" goes on two lines at the dot, so the weight and reps stay together.
                    let parts = state.detail.split(separator: " · ", maxSplits: 1).map(String.init)
                    ForEach(parts, id: \.self) { part in
                        Text(part).font(Theme.Typography.callout.weight(.medium)).foregroundStyle(soft).lineLimit(1).minimumScaleFactor(0.7)
                    }
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 0) {
                    // On the dimmed always-on lock screen the system swaps the timer for text like "<1 minute": let it shrink, not truncate.
                    PhaseTimer(state: state, startedAt: attributes.startedAt)
                        .modifier(Heading(38, .heavy)).monospacedDigit().foregroundStyle(ink)
                        .lineLimit(1).minimumScaleFactor(0.4)
                        .multilineTextAlignment(.trailing).frame(maxWidth: 120)
                    Text(state.timerLabel).modifier(Heading(13, .bold)).foregroundStyle(soft)
                }
            }
            if let range = state.countdown {
                ProgressView(timerInterval: range, countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                    .tint(ink)
            }
            if showsElapsed || state.target != nil {
                HStack {
                    if showsElapsed { Text(state.progress) }
                    Spacer()
                    if let target = state.target { Label(target, systemImage: "heart.fill") }
                }
                .font(Theme.Typography.caption).foregroundStyle(soft)
            }
        }
    }
}

/// The one number that matters right now: a countdown, else the rest timer, else elapsed time.
private struct PhaseTimer: View {
    let state: WorkoutActivityAttributes.ContentState
    let startedAt: Date
    var body: some View {
        if let range = state.countdown {
            Text(timerInterval: range, countsDown: true)
        } else if let rest = state.restSince {
            Text(rest, style: .timer)
        } else {
            Text(startedAt, style: .timer)
        }
    }
}

/// The timer for the island's small spots. A timer text asks for far more room than its digits need and is cut to
/// "0:…" when the island is narrow (a second activity next to it), so a hidden "0:00" claims the room and the timer
/// is drawn over it.
private struct IslandTimer: View {
    let state: WorkoutActivityAttributes.ContentState
    let startedAt: Date
    let size: CGFloat
    var body: some View {
        let showing = state.countdown.map { $0.upperBound.timeIntervalSinceNow } ?? Date().timeIntervalSince(state.restSince ?? startedAt)
        Text(showing >= 3540 ? "0:00:00" : showing >= 540 ? "00:00" : "0:00").hidden()
            .overlay(alignment: .trailing) {
                PhaseTimer(state: state, startedAt: startedAt).lineLimit(1).minimumScaleFactor(0.6).multilineTextAlignment(.trailing)
            }
            .font(.system(size: size, weight: .semibold).monospacedDigit())
    }
}

private extension WorkoutActivityAttributes {
    var icon: String { isRun ? "figure.run" : "dumbbell.fill" }
}

private extension WorkoutActivityAttributes.ContentState {
    var timerLabel: String {
        if countdown != nil { return phase == .lift ? "HOLD" : "LEFT" }
        return restSince != nil ? "REST" : "ELAPSED"
    }
}
