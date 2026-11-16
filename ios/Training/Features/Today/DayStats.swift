import SwiftUI

/// The watch's and the scale's numbers for the last months, shared by every day page so they are fetched once.
@MainActor @Observable
final class DayStatsStore {
    static let shared = DayStatsStore()
    private(set) var days: [String: [String: MetricDay.Value]] = [:]
    private var loadedAt: Date?

    /// Fetches again when the last fetch is more than a few minutes old.
    func load(force: Bool = false) async {
        if !force, let loadedAt, Date().timeIntervalSince(loadedAt) < 300 { return }
        if let m: MetricsResponse = try? await API.shared.get("/api/metrics?days=190", cache: true) {
            days = Dictionary(m.days.map { ($0.date, $0.data) }, uniquingKeysWith: { _, b in b })
            loadedAt = Date()
        }
    }
}

/// How one day went, from the watch and the scale: the night before it, energy, movement, heart and body. Each group
/// shows only when the day has something for it, so an old or empty day shows nothing at all.
struct DayStatsCard: View {
    let date: String
    /// The weight logged that day, typed in or from the scale.
    var weight: Double? = nil
    private var store: DayStatsStore { .shared }

    var body: some View {
        let day = store.days[date] ?? [:]
        let n = { (key: String) in day[key]?.number }
        let whole = { (key: String) in n(key).map { Fmt.whole($0) } }
        let groups: [(title: String, icon: String, color: Color, items: [(String, String?, String?)])] = [
            ("Night before", "moon.zzz.fill", Theme.Palette.sleep, [
                ("Fell asleep", clock("bed", day), nil),
                ("Woke up", clock("wake", day) ?? wakeFromLength(day), nil),
                ("Slept", n("sleep.sleepTimeSeconds").map { Fmt.hours($0) }, n("sleep.awakeSleepSeconds").flatMap { $0 > 0 ? "awake \(Fmt.time($0 / 60)) min" : nil }),
                ("Sleep score", whole("sleep.sleepScores.overall.value"), day["sleep.sleepScores.overall.qualifierKey"]?.text?.lowercased()),
            ]),
            ("Energy", "battery.75percent", Theme.Palette.ok, [
                // Garmin's daily summary gives the day's highest and lowest. The highest is normally the charge on waking.
                ("Body Battery high", whole(first(day, "bodyBattery.", containing: ["wake"]) ?? "bodyBattery.maxValue"), "usually on waking"),
                ("Body Battery low", whole(first(day, "bodyBattery.", containing: ["sleep", "bed"]) ?? "bodyBattery.minValue"), "lowest of the day"),
                ("Stress", whole("stress.avgLevel"), n("stress.maxLevel").map { "peak \(Fmt.whole($0))" }),
            ]),
            ("Movement", "figure.walk", Theme.Palette.accent, [
                ("Steps", whole("movement.steps.value"), n("movement.steps.goal").map { "goal \(Fmt.whole($0))" }),
                ("On foot", n("movement.steps.distanceInMeters").map { String(format: "%.1f km", $0 / 1000) }, nil),
                ("Floors", whole("movement.floorsAscended.value"), nil),
                ("Intensity", intensity(day).map { "\(Fmt.whole($0)) min" }, nil),
                ("Active calories", whole("calories.burnedActive").map { "\($0) kcal" }, n("calories.burnedTotal").map { "total \(Fmt.whole($0))" }),
            ]),
            ("Heart", "heart.fill", Theme.Palette.heart, [
                ("Resting", whole("heartRate.restingValue").map { "\($0) bpm" }, nil),
                ("HRV", whole("hrv.lastNightAvg").map { "\($0) ms" }, n("hrv.weeklyAvg").map { "7d avg \(Fmt.whole($0))" }),
                ("Breathing", n("respiration.avgValue").map { String(format: "%.1f /min", $0) }, nil),
                ("Blood oxygen", whole("pulseOx.avgValue").map { "\($0) %" }, nil),
            ]),
            ("Body", "scalemass", Theme.Palette.calm, [
                ("Weight", weight.map { String(format: "%.1f kg", $0) }, nil),
                ("Body fat", n("body.fatPercent").map { String(format: "%.1f %%", $0) }, nil),
                ("Lean mass", n("body.leanMassKg").map { String(format: "%.1f kg", $0) }, nil),
                ("BMI", n("body.bmi").map { String(format: "%.1f", $0) }, nil),
                ("Waist", n("body.waistCm").map { String(format: "%.1f cm", $0) }, nil),
            ]),
        ]
        let shown = groups.map { g in (g.title, g.icon, g.color, g.items.filter { $0.1 != nil }) }.filter { !$0.3.isEmpty }
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            if !shown.isEmpty {
                CardTitle("The day", note: date == Day.today() ? "so far" : nil)
                ForEach(shown, id: \.0) { group in
                    VStack(alignment: .leading, spacing: Theme.Space.s) {
                        Label(group.0.uppercased(), systemImage: group.1).font(Theme.Typography.label).foregroundStyle(group.2)
                        LazyVGrid(columns: [GridItem(.flexible(), alignment: .topLeading), GridItem(.flexible(), alignment: .topLeading)], alignment: .leading, spacing: Theme.Space.m) {
                            ForEach(group.3, id: \.0) { item in
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.0).font(Theme.Typography.caption).foregroundStyle(Theme.Palette.muted)
                                    Text(item.1 ?? "").font(Theme.Typography.numeral).lineLimit(1).minimumScaleFactor(0.6)
                                    if let detail = item.2 { Text(detail).font(Theme.Typography.caption).foregroundStyle(Theme.Palette.muted).lineLimit(1) }
                                }
                                .accessibilityElement(children: .combine)
                            }
                        }
                    }
                }
            }
        }
        .modifier(CardIf(shown: !shown.isEmpty))
        .task { await store.load() }
    }

    /// A stored time of the night ("bed" or "wake") as a clock time on the phone.
    private func clock(_ name: String, _ day: [String: MetricDay.Value]) -> String? {
        let minutes = day["sleep.\(name)MinutesLocal"]?.number ?? day["sleep.\(name)MinutesGMT"]?.number.map { $0 + Double(TimeZone.current.secondsFromGMT()) / 60 }
        return minutes.map(Self.time)
    }

    /// Waking worked out from bedtime and the length of the night, when the watch gave no waking time.
    private func wakeFromLength(_ day: [String: MetricDay.Value]) -> String? {
        let bed = day["sleep.bedMinutesLocal"]?.number ?? day["sleep.bedMinutesGMT"]?.number.map { $0 + Double(TimeZone.current.secondsFromGMT()) / 60 }
        guard let bed, let asleep = day["sleep.sleepTimeSeconds"]?.number else { return nil }
        return Self.time(bed + (asleep + (day["sleep.awakeSleepSeconds"]?.number ?? 0)) / 60)
    }

    private static func time(_ minutes: Double) -> String {
        let m = ((Int(minutes.rounded()) % 1440) + 1440) % 1440
        return String(format: "%02d:%02d", m / 60, m % 60)
    }

    /// Garmin counts a vigorous minute twice.
    private func intensity(_ day: [String: MetricDay.Value]) -> Double? {
        let m = day["intensityMinutes.moderate"]?.number, v = day["intensityMinutes.vigorous"]?.number
        return m == nil && v == nil ? nil : (m ?? 0) + 2 * (v ?? 0)
    }

    /// The first numeric key under a prefix whose name mentions one of the words, for fields Garmin may or may not send.
    private func first(_ day: [String: MetricDay.Value], _ prefix: String, containing words: [String]) -> String? {
        day.keys.sorted().first { key in key.hasPrefix(prefix) && day[key]?.number != nil && words.contains { key.lowercased().contains($0) } }
    }
}

/// Card styling only when there is something inside, so an empty day leaves no empty box.
private struct CardIf: ViewModifier {
    let shown: Bool
    func body(content: Content) -> some View { if shown { content.card() } else { content } }
}
