import ActivityKit
import Foundation

/// Live Activity payload shared by the app (which starts and updates it) and the widget extension (which draws it).
struct WorkoutActivityAttributes: ActivityAttributes {
    enum Phase: String, Codable, Hashable {
        case lift, warmup, work, recover, cooldown, steady
    }

    struct ContentState: Codable, Hashable {
        var phase: Phase
        /// Current exercise or interval phase: "Back squat", "Run", "Walk".
        var title: String
        /// "Set 2 of 4 · 75 kg × 5" or "Rep 3 of 6 · 5:30/km".
        var detail: String
        /// "5 of 21 sets" or "Rep 3 of 6".
        var progress: String
        /// Heart rate target on run days.
        var target: String?
        /// Rest timer: counts up from the last logged set.
        var restSince: Date?
        /// Set countdown or interval phase.
        var countdown: ClosedRange<Date>?
    }

    /// "Lift A", "Intervals".
    var name: String
    var isRun: Bool
    var startedAt: Date
    /// The colour theme in use when the workout began (`ThemeKind`) and the colourful theme's hue. The lock screen
    /// draws from these, because it runs outside the app and cannot read the app's settings.
    var theme: String? = nil
    var hue: Double? = nil
}
