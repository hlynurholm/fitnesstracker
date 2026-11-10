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
            LockScreenView(attributes: context.attributes, state: context.state)
                .padding(Theme.Space.l)
                .activityBackgroundTint(Theme.Palette.surface)
                .activitySystemActionForegroundColor(Theme.Palette.text)
        } dynamicIsland: { context in
            let tint = context.state.phase.tint
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
                PhaseTimer(state: context.state, startedAt: context.attributes.startedAt)
                    .monospacedDigit().foregroundStyle(tint).frame(maxWidth: 48)
            } minimal: {
                Image(systemName: context.attributes.icon).foregroundStyle(tint)
            }
        }
    }
}

private struct LockScreenView: View {
    let attributes: WorkoutActivityAttributes
    let state: WorkoutActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack {
                Label(attributes.name, systemImage: attributes.icon)
                    .font(Theme.Typography.label).foregroundStyle(state.phase.tint)
                Spacer()
                Text(attributes.startedAt, style: .timer)
                    .font(Theme.Typography.label).monospacedDigit().foregroundStyle(Theme.Palette.muted)
                    .multilineTextAlignment(.trailing).frame(maxWidth: 80)
            }
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.title).font(Theme.Typography.title).lineLimit(1).minimumScaleFactor(0.7)
                    Text(state.detail).font(Theme.Typography.callout).foregroundStyle(Theme.Palette.muted).lineLimit(1)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    // On the dimmed always-on lock screen the system swaps the timer for text like "<1 minute": let it shrink, not truncate.
                    PhaseTimer(state: state, startedAt: attributes.startedAt)
                        .font(Theme.Typography.timer).foregroundStyle(state.phase.tint)
                        .lineLimit(1).minimumScaleFactor(0.4)
                        .multilineTextAlignment(.trailing).frame(maxWidth: 130)
                    Text(state.timerLabel).font(Theme.Typography.label).foregroundStyle(Theme.Palette.muted)
                }
            }
            if let range = state.countdown {
                ProgressView(timerInterval: range, countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                    .tint(state.phase.tint)
            }
            HStack {
                Text(state.progress)
                Spacer()
                if let target = state.target { Label(target, systemImage: "heart.fill") }
            }
            .font(Theme.Typography.caption).foregroundStyle(Theme.Palette.muted)
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

private extension WorkoutActivityAttributes {
    var icon: String { isRun ? "figure.run" : "dumbbell.fill" }
}

private extension WorkoutActivityAttributes.ContentState {
    var timerLabel: String {
        if countdown != nil { return phase == .lift ? "HOLD" : "LEFT" }
        return restSince != nil ? "REST" : "ELAPSED"
    }
}

private extension WorkoutActivityAttributes.Phase {
    var tint: Color {
        switch self {
        case .lift: Theme.Palette.lift
        case .work: Theme.Palette.danger
        case .recover, .cooldown: Theme.Palette.ok
        case .warmup, .steady: Theme.Palette.run
        }
    }
}
