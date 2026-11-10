import Observation
import SwiftUI

/// The cards the dashboard can show. The raw value is what is saved in the layout, so do not rename a case.
enum CardKind: String, CaseIterable, Codable {
    case today, lastRun, steps, restingHR, sleep, hrv, bodyBattery, week, weight, bodyFat, leanMass, nutrition, stress, calories, intensity, floors, distance, sleepScore, respiration, spo2, facts, all

    var title: String {
        switch self {
        case .today: "Next session"
        case .lastRun: "Last run"
        case .week: "This week"
        case .weight: "Weight"
        case .nutrition: "Nutrition"
        case .sleep: "Sleep"
        case .facts: "Fun facts"
        case .intensity: "Intensity minutes"
        case .all: "Everything from your watch"
        default: MetricSpec.all[self]?.title ?? rawValue
        }
    }

    var icon: String {
        switch self {
        case .today: "calendar"
        case .lastRun: "figure.run"
        case .week: "checkmark.circle"
        case .weight: "scalemass"
        case .nutrition: "fork.knife"
        case .sleep: "bed.double.fill"
        case .facts: "sparkles"
        case .intensity: "bolt.heart.fill"
        case .all: "list.bullet.rectangle"
        default: MetricSpec.all[self]?.icon ?? "circle"
        }
    }

    var tint: Color {
        switch self {
        case .today, .week: Theme.Palette.accent
        case .lastRun: Theme.Palette.run
        case .weight: Theme.Palette.calm
        case .nutrition: Theme.Palette.ok
        case .sleep: Theme.Palette.sleep
        case .facts: Theme.Palette.test
        case .intensity: Theme.Palette.heart
        case .all: Theme.Palette.muted
        default: MetricSpec.all[self]?.tint ?? Theme.Palette.accent
        }
    }

    /// Cards that only make sense across the full width.
    var alwaysWide: Bool { self == .facts || self == .all }

    /// Cards with a chart over time, whose range of days can be chosen.
    var hasRange: Bool { ![.today, .lastRun, .week, .facts, .all].contains(self) }
}

/// The ranges a widget's chart can cover.
struct RangeOption: Identifiable {
    let days: Int
    let label: String
    var id: Int { days }
    static let all: [RangeOption] = [.init(days: 2, label: "2 days"), .init(days: 7, label: "1 week"), .init(days: 14, label: "2 weeks"),
                                     .init(days: 30, label: "1 month"), .init(days: 90, label: "3 months"), .init(days: 180, label: "6 months")]
    static func label(_ days: Int) -> String { all.first { $0.days == days }?.label ?? "\(days) days" }
}

/// How many days go into one bar or point of a widget's chart.
struct ResolutionOption: Identifiable {
    let days: Int
    let label: String
    var id: Int { days }
    static let all: [ResolutionOption] = [.init(days: 1, label: "Every day"), .init(days: 2, label: "2 day average"), .init(days: 3, label: "3 day average"),
                                          .init(days: 7, label: "Weekly average"), .init(days: 14, label: "2 week average"), .init(days: 30, label: "Monthly average")]
    static func label(_ days: Int) -> String { all.first { $0.days == days }?.label.lowercased() ?? "\(days) day average" }
}

/// A card that shows one daily metric from the watch: latest value, a short caption and a small chart.
/// `key` is Garmin's own field name as stored by the server.
struct MetricSpec {
    let title: String
    let icon: String
    let tint: Color
    let key: String
    var unit: String = ""
    var style: Spark.Style = .line
    /// Metric holding the day's goal, drawn as a ring and a dashed line.
    var goalKey: String? = nil
    /// Multiplier from the stored value to the shown one (metres to km).
    var scale: Double = 1
    var digits: Int = 0
    /// Second metric shown in the caption, with its label.
    var extra: (label: String, key: String)? = nil

    static let all: [CardKind: MetricSpec] = [
        .steps: .init(title: "Steps", icon: "figure.walk", tint: Theme.Palette.accent, key: "movement.steps.value", style: .bars, goalKey: "movement.steps.goal"),
        .restingHR: .init(title: "Resting heart rate", icon: "heart.fill", tint: Theme.Palette.heart, key: "heartRate.restingValue", unit: "bpm"),
        .hrv: .init(title: "HRV", icon: "waveform.path.ecg", tint: Theme.Palette.test, key: "hrv.lastNightAvg", unit: "ms", extra: ("weekly", "hrv.weeklyAvg")),
        .bodyBattery: .init(title: "Body Battery", icon: "battery.75percent", tint: Theme.Palette.ok, key: "bodyBattery.maxValue", style: .bars, extra: ("low", "bodyBattery.minValue")),
        .stress: .init(title: "Stress", icon: "brain.head.profile", tint: Theme.Palette.energy, key: "stress.avgLevel", extra: ("max", "stress.maxLevel")),
        .calories: .init(title: "Active calories", icon: "flame.fill", tint: Theme.Palette.energy, key: "calories.burnedActive", unit: "kcal", style: .bars, extra: ("total", "calories.burnedTotal")),
        .floors: .init(title: "Floors climbed", icon: "stairs", tint: Theme.Palette.calm, key: "movement.floorsAscended.value", style: .bars, goalKey: "movement.floorsAscended.goal"),
        .distance: .init(title: "Distance on foot", icon: "point.topleft.down.to.point.bottomright.curvepath", tint: Theme.Palette.accent, key: "movement.steps.distanceInMeters", unit: "km", style: .bars, scale: 0.001, digits: 1),
        .sleepScore: .init(title: "Sleep score", icon: "moon.stars.fill", tint: Theme.Palette.sleep, key: "sleep.sleepScores.overall.value"),
        .respiration: .init(title: "Breathing rate", icon: "lungs.fill", tint: Theme.Palette.calm, key: "respiration.avgValue", unit: "/min"),
        // From a scale through Apple Health.
        .bodyFat: .init(title: "Body fat", icon: "percent", tint: Theme.Palette.calm, key: "body.fatPercent", unit: "%", digits: 1),
        .leanMass: .init(title: "Lean mass", icon: "figure.strengthtraining.traditional", tint: Theme.Palette.calm, key: "body.leanMassKg", unit: "kg", digits: 1),
        .spo2: .init(title: "Blood oxygen", icon: "drop.fill", tint: Theme.Palette.heart, key: "pulseOx.avgValue", unit: "%"),
    ]
}

/// One card's place in the grid.
struct CardSetting: Codable, Identifiable, Hashable {
    var kind: CardKind
    var wide: Bool
    var hidden = false
    /// Days the card's chart covers. nil is the card's own default.
    var range: Int? = nil
    /// Days averaged into one point of the chart: 1 is every day. nil lets the widget choose.
    var resolution: Int? = nil
    /// "bars" or "line". nil is the widget's own default.
    var chart: String? = nil

    // What the widget shows until a choice is made. Every one of these is an entry in the widget's menu, so the
    // menu can always tick the setting in use.

    /// Days the chart covers.
    func span(wide: Bool) -> Int {
        if let range { return range }
        switch kind {
        case .bodyFat, .leanMass: return 90 // weighed now and then, so a longer stretch
        case .weight: return wide ? 90 : 30
        case .sleep: return 14
        default: return wide ? 30 : 14
        }
    }

    /// Days averaged into one point: every day while there is room, weekly beyond that.
    func every(wide: Bool) -> Int { resolution ?? (span(wide: wide) > (wide ? 92 : 45) ? 7 : 1) }

    var chartStyle: Spark.Style {
        if let chart { return chart == "line" ? .line : .bars }
        return kind == .weight ? .line : MetricSpec.all[kind]?.style ?? .bars
    }
    var id: String { kind.rawValue }

    static let defaults: [CardSetting] = [
        .init(kind: .today, wide: true), .init(kind: .lastRun, wide: true), .init(kind: .steps, wide: false), .init(kind: .restingHR, wide: false),
        .init(kind: .sleep, wide: true), .init(kind: .hrv, wide: false), .init(kind: .bodyBattery, wide: false),
        .init(kind: .week, wide: true), .init(kind: .weight, wide: false), .init(kind: .nutrition, wide: false),
        .init(kind: .bodyFat, wide: false), .init(kind: .leanMass, wide: false),
        .init(kind: .stress, wide: false), .init(kind: .calories, wide: false), .init(kind: .intensity, wide: false), .init(kind: .floors, wide: false),
        .init(kind: .facts, wide: true), .init(kind: .sleepScore, wide: false), .init(kind: .distance, wide: false),
        .init(kind: .respiration, wide: false), .init(kind: .spo2, wide: false), .init(kind: .all, wide: true),
    ]
}

/// Data and layout for the dashboard: the watch's daily metrics, the training data the other tabs use, and which
/// cards are shown in what order and width. The layout is saved on the phone.
@MainActor @Observable
final class HomeModel {
    private(set) var days: [String: [String: MetricDay.Value]] = [:]
    private(set) var dash: Dashboard?
    /// Tomorrow's planned session, shown once today's is done.
    private(set) var tomorrow: ScheduleDay?
    /// The most recent run from the watch, with its track.
    private(set) var lastRun: GarminActivity?
    private(set) var error: String?
    private(set) var loaded = false
    private(set) var syncing = false
    var syncMessage: String?
    var layout: [CardSetting] { didSet { UserDefaults.standard.set(try? JSONEncoder().encode(layout), forKey: "homeLayout") } }
    var today: String { Day.today() }

    init() {
        let saved = UserDefaults.standard.data(forKey: "homeLayout").flatMap { try? JSONDecoder().decode([CardSetting].self, from: $0) } ?? []
        // Cards added in a later version join a saved layout, before the two lists that close it.
        let added = CardSetting.defaults.filter { d in !saved.contains { $0.kind == d.kind } }
        let tail = saved.filter { $0.kind.alwaysWide }, head = saved.filter { !$0.kind.alwaysWide }
        var merged = saved.isEmpty ? added : head + added + tail
        // The run widget belongs near the top, next to the session.
        if !saved.isEmpty, !saved.contains(where: { $0.kind == .lastRun }), let run = merged.firstIndex(where: { $0.kind == .lastRun }) {
            let card = merged.remove(at: run)
            merged.insert(card, at: min(merged.count, (merged.firstIndex { $0.kind == .today } ?? -1) + 1))
        }
        layout = merged
    }

    func load() async {
        // The two are independent: training cards still load if the watch data cannot (an older server has no /api/metrics).
        async let metrics: MetricsResponse = API.shared.get("/api/metrics?days=190", cache: true)
        async let dashboard: Dashboard = API.shared.get("/api/dashboard", cache: true)
        if let m = try? await metrics { days = Dictionary(m.days.map { ($0.date, $0.data) }, uniquingKeysWith: { _, b in b }) }
        do { dash = try await dashboard; error = nil } catch { self.error = error.localizedDescription }
        loaded = true
        // Extras for single widgets. Each is optional: a widget without its data just stays off the dashboard.
        let next = Day.add(today, 1)
        if let s: Schedule = try? await API.shared.get("/api/schedule?from=\(next)&to=\(next)", cache: true) { tomorrow = s.days.first }
        if let all: [GarminActivity] = try? await API.shared.get("/api/activities", cache: true),
           let latest = all.first(where: { $0.isRun && ($0.distance_m ?? 0) > 0 }),
           latest.id != lastRun?.id || lastRun?.track == nil {
            lastRun = (try? await API.shared.get("/api/activities/\(latest.id)", cache: true)) ?? latest
        }
    }

    /// The session to show on the dashboard: today's until it is done, then tomorrow's.
    var nextSession: (date: String, name: String, subtitle: String?, kind: String, isTomorrow: Bool, status: String?, started: Bool, week: Int)? {
        guard let day = dash?.today else { return nil }
        let workout = dash?.workouts.first { $0.date == day.date && $0.template_key == day.templateKey }
        if workout?.status == "done", let t = tomorrow {
            return (t.date, t.name, t.subtitle, t.kind, true, t.main?.status, false, t.week)
        }
        return (day.date, day.template.name, day.template.subtitle, day.template.kind, false, workout?.status, workout?.started_at != nil, day.week)
    }

    /// Asks the server to pull from Garmin now, then reloads.
    func syncGarmin() async {
        syncing = true
        defer { syncing = false }
        do {
            let r: GarminSyncResult = try await API.shared.send("POST", "/api/garmin/sync")
            syncMessage = r.error ?? "Garmin is up to date."
            await load()
        } catch { syncMessage = error.localizedDescription }
    }

    // MARK: Reading metrics

    var hasWatchData: Bool { !days.isEmpty }

    func value(_ key: String, on date: String) -> Double? { days[date]?[key]?.number }

    /// The most recent day that has the metric, today first. Looks two months back, for things measured now and then.
    func latest(_ key: String) -> (date: String, value: Double)? {
        for back in 0..<60 { let d = Day.add(today, -back); if let v = value(key, on: d) { return (d, v) } }
        return nil
    }

    func latestText(_ key: String) -> String? {
        for back in 0..<14 { if let t = days[Day.add(today, -back)]?[key]?.text { return t } }
        return nil
    }

    /// One value per day for the last `count` days, oldest first, with nil where the watch has nothing.
    func series(_ key: String, _ count: Int) -> [Double?] { series(count) { self.value(key, on: $0) } }

    func series(_ count: Int, _ value: (String) -> Double?) -> [Double?] {
        (0..<count).map { value(Day.add(today, -(count - 1 - $0))) }
    }

    /// Values for a chart over `count` days, with `every` days averaged into each point (1 is every day).
    /// Groups are counted back from today, so the newest one is whole.
    func chart(_ count: Int, every: Int, _ value: (String) -> Double?) -> [Double?] {
        let daily = series(count, value)
        let size = max(1, every)
        guard size > 1 else { return daily }
        var out: [Double?] = []
        var end = daily.count
        while end > 0 {
            let group = daily[max(0, end - size)..<end].compactMap { $0 }
            out.append(group.isEmpty ? nil : group.reduce(0, +) / Double(group.count))
            end -= size
        }
        return out.reversed()
    }

    func average(_ key: String, _ count: Int) -> Double? {
        let v = series(key, count).compactMap { $0 }
        return v.isEmpty ? nil : v.reduce(0, +) / Double(v.count)
    }

    /// Garmin counts a vigorous minute twice towards the weekly goal.
    func intensity(on date: String) -> Double? {
        let m = value("intensityMinutes.moderate", on: date), v = value("intensityMinutes.vigorous", on: date)
        return m == nil && v == nil ? nil : (m ?? 0) + 2 * (v ?? 0)
    }

    // MARK: Layout

    func update(_ kind: CardKind, _ change: (inout CardSetting) -> Void) {
        if let i = layout.firstIndex(where: { $0.kind == kind }) { change(&layout[i]) }
    }

    /// Sets a widget's range, and asks the server for older watch data when the range reaches past what is stored.
    func setRange(_ kind: CardKind, _ days: Int?) {
        update(kind) { $0.range = days }
        if let days { ensureHistory(days) }
    }

    /// Gives every widget that has a chart the same range and resolution.
    func applyToAll(range days: Int, every: Int) {
        for i in layout.indices where layout[i].kind.hasRange { layout[i].range = days; layout[i].resolution = every }
        ensureHistory(days)
    }

    /// Shows a hidden widget again, at the end of the dashboard.
    func add(_ kind: CardKind) {
        guard let i = layout.firstIndex(where: { $0.kind == kind }) else { return }
        var card = layout.remove(at: i)
        card.hidden = false
        layout.append(card)
    }

    /// The first import covers about four months. A longer range triggers one deeper fetch from Garmin.
    private func ensureHistory(_ days: Int) {
        guard hasWatchData, days > 31, let first = self.days.keys.min(), Day.daysBetween(first, today) < days - 10,
              UserDefaults.standard.integer(forKey: "historyRequested") < days else { return }
        UserDefaults.standard.set(days, forKey: "historyRequested")
        Task {
            let _: GarminSyncResult? = try? await API.shared.send("POST", "/api/garmin/sync", ["daily_days": days + 5])
            await load()
        }
    }

    /// Whether there is anything to show for a card. Cards without data stay out of the grid until there is.
    func hasData(_ kind: CardKind) -> Bool {
        switch kind {
        case .today: dash?.today != nil
        case .lastRun: lastRun != nil
        case .week: dash != nil
        case .weight: dash?.body.contains { $0.weight_kg != nil } ?? false
        case .nutrition: !(dash?.nutrition.isEmpty ?? true)
        case .sleep: latest("sleep.sleepTimeSeconds") != nil
        case .intensity: (0..<14).contains { intensity(on: Day.add(today, -$0)) != nil }
        case .facts, .all: hasWatchData
        default: MetricSpec.all[kind].map { latest($0.key) != nil } ?? false
        }
    }

    /// Visible cards arranged in rows: a full-width card alone, half-width cards in pairs.
    var rows: [[CardSetting]] {
        var out: [[CardSetting]] = []
        for card in layout where !card.hidden && hasData(card.kind) {
            if !(card.wide || card.kind.alwaysWide), let last = out.last, last.count == 1, !(last[0].wide || last[0].kind.alwaysWide) {
                out[out.count - 1].append(card)
            } else {
                out.append([card])
            }
        }
        return out
    }

    // MARK: Fun facts

    /// A few records and comparisons from everything imported so far.
    var facts: [(icon: String, text: String)] {
        var out: [(String, String)] = []
        let dates = days.keys.sorted()
        func best(_ key: String, lowest: Bool = false) -> (date: String, value: Double)? {
            let all = dates.compactMap { d in value(key, on: d).map { (d, $0) } }.filter { $0.1 > 0 }
            return lowest ? all.min { $0.1 < $1.1 } : all.max { $0.1 < $1.1 }
        }
        let steps = dates.compactMap { value("movement.steps.value", on: $0) }
        if !steps.isEmpty {
            let km = dates.compactMap { value("movement.steps.distanceInMeters", on: $0) }.reduce(0, +) / 1000
            // Route 1 around Iceland is 1,322 km.
            out.append(("figure.walk", "\(Fmt.whole(steps.reduce(0, +))) steps in \(steps.count) days" + (km > 0 ? ", about \(Fmt.whole(km)) km. That is \(Fmt.whole(km / 1322 * 100)) % of the Ring Road." : ".")))
        }
        if let b = best("movement.steps.value") { out.append(("trophy.fill", "Most steps in a day: \(Fmt.whole(b.value)) on \(Day.label(b.date)).")) }
        // Steps goal streak, counting back from today or yesterday.
        var streak = 0
        for back in 0..<dates.count {
            let d = Day.add(today, -back)
            if let v = value("movement.steps.value", on: d), let g = value("movement.steps.goal", on: d), v >= g { streak += 1; continue }
            if back > 0 { break } // today is not over yet, so it cannot break a streak
        }
        if streak >= 2 { out.append(("flame.fill", "Step goal reached \(streak) days in a row.")) }
        let climbed = dates.compactMap { value("movement.floorsAscended.distanceInMeters", on: $0) }.reduce(0, +)
        // Hvannadalshnúkur, Iceland's highest peak, is 2,110 m.
        if climbed > 0 { out.append(("mountain.2.fill", "\(Fmt.whole(climbed)) m climbed on stairs and hills, \(String(format: "%.1f", climbed / 2110)) times up Hvannadalshnúkur.")) }
        if let b = best("heartRate.restingValue", lowest: true) { out.append(("heart.fill", "Lowest resting heart rate: \(Fmt.whole(b.value)) bpm on \(Day.label(b.date)).")) }
        if let b = best("sleep.sleepTimeSeconds") { out.append(("moon.zzz.fill", "Longest night: \(Fmt.hours(b.value)) on \(Day.label(b.date)).")) }
        if let avg = average("sleep.sleepTimeSeconds", 7) { out.append(("bed.double.fill", "Average sleep over the last week: \(Fmt.hours(avg)) a night.")) }
        if let b = best("hrv.lastNightAvg") { out.append(("waveform.path.ecg", "Best overnight HRV: \(Fmt.whole(b.value)) ms on \(Day.label(b.date)).")) }
        return out.map { (icon: $0.0, text: $0.1) }
    }
}

extension Fmt {
    /// Seconds as "7 h 42 min".
    static func hours(_ seconds: Double) -> String {
        let m = Int((seconds / 60).rounded())
        return "\(m / 60) h \(String(format: "%02d", m % 60)) min"
    }

    /// "movement.steps.value" as "Movement, steps, value".
    static func metricName(_ key: String) -> String {
        key.split(separator: ".").map { part in
            part.replacingOccurrences(of: "([a-z0-9])([A-Z])", with: "$1 $2", options: .regularExpression).lowercased()
        }.joined(separator: ", ").capitalizedFirst
    }
}
