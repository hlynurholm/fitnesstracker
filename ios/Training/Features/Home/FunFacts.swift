import SwiftUI

/// One number for the fun facts widget: what it is, the number, and a line about it.
struct Fact: Identifiable {
    let id: String
    let icon: String
    let tint: Color
    let label: String
    let value: String
    var unit = ""
    var detail = ""
    /// How far along a famous distance this is, 0 to 1. Drawn as a ring.
    var progress: Double? = nil
}

/// What the fun facts widget shows on one day: a theme, the facts that fit it, and how they are laid out. Theme,
/// choice of facts, order, layout and look all follow from the date, so the widget is new every day and the same
/// all day.
struct FactSheet {
    /// Where the full-width facts go among the pairs. `list` is one fact per line.
    enum Layout: CaseIterable { case heroFirst, heroMiddle, heroLast, twoHeroes, list }
    /// How the tiles are painted: a wash of the fact's colour, solid colour for the wide ones, or outlines for the small ones.
    enum Look: CaseIterable { case wash, bold, lines }
    let title: String
    let facts: [Fact]
    let layout: Layout
    let look: Look

    /// The facts in rows: one fact alone is a wide tile, two share a row.
    var rows: [[Fact]] {
        guard layout != .list, facts.count >= 3 else { return facts.prefix(5).map { [$0] } }
        // The widest claim goes to a fact with a ring, if the theme has one.
        var rest = facts
        let hero = rest.remove(at: rest.firstIndex { $0.progress != nil } ?? 0)
        func pairs(_ list: [Fact]) -> [[Fact]] { stride(from: 0, to: list.count, by: 2).map { Array(list[$0..<min($0 + 2, list.count)]) } }
        switch layout {
        case .heroFirst: return [[hero]] + pairs(Array(rest.prefix(4)))
        case .heroLast: return pairs(Array(rest.prefix(4))) + [[hero]]
        case .heroMiddle: return pairs(Array(rest.prefix(2))) + [[hero]] + pairs(Array(rest.dropFirst(2).prefix(2)))
        case .twoHeroes:
            let second = rest.remove(at: rest.firstIndex { $0.progress != nil } ?? 0)
            return [[hero]] + pairs(Array(rest.prefix(2))) + [[second]]
        case .list: return []
        }
    }
}

/// A daily metric the facts can be about.
@MainActor private struct FunMetric {
    let id: String
    let title: String
    let icon: String
    let tint: Color
    /// What its best and worst day are called.
    let best: String
    let worst: String
    /// After an average: "steps a day", "a night", "on average".
    let per: String
    var unit = ""
    /// Adding the days up makes sense (steps), as opposed to a level (heart rate).
    var sums = false
    var higherIsBetter = true
    var digits = 0
    var hours = false
    let value: (HomeModel, String) -> Double?

    func show(_ v: Double) -> String { hours ? Fmt.hours(v) : digits == 0 ? Fmt.whole(v) : String(format: "%.\(digits)f", v) }
    /// "Average steps", "Average HRV": names keep their capitals, ordinary words do not.
    var averageLabel: String { "Average " + (["hrv", "battery"].contains(id) ? title : title.lowercased()) }
    func withUnit(_ v: Double) -> String { show(v) + (unit.isEmpty ? "" : " \(unit)") }

    static func key(_ key: String, scale: Double = 1) -> (HomeModel, String) -> Double? { { model, day in model.value(key, on: day).map { $0 * scale } } }

    static var all: [FunMetric] { [
        .init(id: "steps", title: "Steps", icon: "figure.walk", tint: Theme.Palette.accent, best: "Most steps", worst: "Fewest steps", per: "steps a day", sums: true, value: key("movement.steps.value")),
        .init(id: "distance", title: "Distance", icon: "point.topleft.down.to.point.bottomright.curvepath", tint: Theme.Palette.calm, best: "Longest day on foot", worst: "Shortest day on foot", per: "a day", unit: "km", sums: true, digits: 1, value: key("movement.steps.distanceInMeters", scale: 0.001)),
        .init(id: "climb", title: "Climbing", icon: "mountain.2.fill", tint: Theme.Palette.ok, best: "Biggest climb", worst: "Flattest day", per: "a day", unit: "m", sums: true, value: key("movement.floorsAscended.distanceInMeters")),
        .init(id: "burn", title: "Active calories", icon: "flame.fill", tint: Theme.Palette.energy, best: "Biggest burn", worst: "Smallest burn", per: "a day", unit: "kcal", sums: true, value: key("calories.burnedActive")),
        .init(id: "intensity", title: "Intensity", icon: "bolt.heart.fill", tint: Theme.Palette.heart, best: "Hardest day", worst: "Easiest day", per: "a day", unit: "min", sums: true, value: { model, day in model.intensity(on: day) }),
        .init(id: "sleep", title: "Sleep", icon: "moon.zzz.fill", tint: Theme.Palette.sleep, best: "Longest night", worst: "Shortest night", per: "a night", sums: true, hours: true, value: key("sleep.sleepTimeSeconds")),
        .init(id: "sleepScore", title: "Sleep score", icon: "moon.stars.fill", tint: Theme.Palette.sleep, best: "Best sleep score", worst: "Worst sleep score", per: "on average", value: key("sleep.sleepScores.overall.value")),
        .init(id: "hrv", title: "HRV", icon: "waveform.path.ecg", tint: Theme.Palette.test, best: "Highest HRV", worst: "Lowest HRV", per: "on average", unit: "ms", value: key("hrv.lastNightAvg")),
        .init(id: "restingHR", title: "Resting heart rate", icon: "heart.fill", tint: Theme.Palette.heart, best: "Lowest resting heart rate", worst: "Highest resting heart rate", per: "on average", unit: "bpm", higherIsBetter: false, value: key("heartRate.restingValue")),
        .init(id: "stress", title: "Stress", icon: "brain.head.profile", tint: Theme.Palette.warn, best: "Calmest day", worst: "Most stressful day", per: "on average", higherIsBetter: false, value: key("stress.avgLevel")),
        .init(id: "battery", title: "Body Battery", icon: "battery.75percent", tint: Theme.Palette.ok, best: "Fullest Body Battery", worst: "Emptiest Body Battery", per: "at its peak", value: key("bodyBattery.maxValue")),
    ] }
}

/// Random numbers that come out the same for the same seed (SplitMix64), so a day always looks the same.
private struct Seeded: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

extension HomeModel {
    /// Today's fun facts. nil until there is enough from the watch to say anything.
    var factSheet: FactSheet? {
        // TRAINING_FACTS_DAY=3 shows the widget as it will be in three days, to look through the themes in the simulator.
        let shift = ProcessInfo.processInfo.environment["TRAINING_FACTS_DAY"].flatMap(Int.init) ?? 0
        let day = Day.daysBetween("2026-01-01", today) + shift
        let themes: [(title: String, facts: () -> [Fact])] = [
            ("Record days", { self.extremes(best: true) }), ("Last 7 days", lastSevenDays), ("Best months", bestMonths), ("All-time totals", totals),
            ("Best weekdays", bestWeekdays), ("Off days", { self.extremes(best: false) }), ("Best weeks", bestWeeks), ("Streaks and counts", streaks),
        ]
        // Go through the themes in order, skipping the ones without enough to show yet.
        for step in 0..<themes.count {
            let theme = themes[(day + step) % themes.count]
            var facts = theme.facts()
            guard facts.count >= 3 else { continue }
            var random = Seeded(state: UInt64(truncatingIfNeeded: day) &* 0x2545_F491_4F6C_DD1D)
            facts.shuffle(using: &random)
            return FactSheet(title: theme.title, facts: Array(facts.prefix(6)), layout: FactSheet.Layout.allCases.randomElement(using: &random)!, look: FactSheet.Look.allCases.randomElement(using: &random)!)
        }
        return nil
    }

    /// Every day that has the metric, oldest first. Days of nothing (a watch left at home) are left out.
    private func points(_ metric: FunMetric, upTo last: String? = nil) -> [(date: String, value: Double)] {
        days.keys.sorted().compactMap { d in
            guard d <= (last ?? today), let v = metric.value(self, d), v > 0 else { return nil }
            return (d, v)
        }
    }

    private func mean(_ values: [Double]) -> Double { values.reduce(0, +) / Double(max(values.count, 1)) }

    /// The best (or worst) single day of each metric. Today is left out of the worst ones: it is not over yet.
    private func extremes(best: Bool) -> [Fact] {
        FunMetric.all.compactMap { m in
            let all = points(m, upTo: best ? nil : Day.add(today, -1))
            guard all.count >= 7 else { return nil }
            let top = (m.higherIsBetter == best) ? all.max { $0.value < $1.value } : all.min { $0.value < $1.value }
            return top.map { Fact(id: m.id, icon: m.icon, tint: m.tint, label: best ? m.best : m.worst, value: m.show($0.value), unit: m.unit, detail: Day.label($0.date)) }
        }
    }

    /// The last seven days added up (or averaged, for levels), against the seven before.
    private func lastSevenDays() -> [Fact] {
        FunMetric.all.compactMap { m in
            let all = points(m)
            let now = all.filter { $0.date > Day.add(today, -7) }.map(\.value), before = all.filter { $0.date > Day.add(today, -14) && $0.date <= Day.add(today, -7) }.map(\.value)
            guard now.count >= 3 else { return nil }
            let a = m.sums ? now.reduce(0, +) : mean(now), b = m.sums ? before.reduce(0, +) : mean(before)
            let change = before.count >= 3 && b > 0 ? (a - b) / b * 100 : nil
            let detail = change.map { abs($0) < 1 ? "same as the week before" : "\($0 > 0 ? "up" : "down") \(Fmt.whole(abs($0))) % on the week before" } ?? ""
            return Fact(id: m.id, icon: m.icon, tint: m.tint, label: m.sums ? m.title : m.averageLabel, value: m.show(a), unit: m.unit, detail: detail)
        }
    }

    /// For each metric, the group of days (a month, a weekday, a week) with the best daily average.
    private func bestGroup(of metric: FunMetric, minDays: Int, group: (String) -> String) -> (key: String, days: [(date: String, value: Double)], average: Double)? {
        let groups = Dictionary(grouping: points(metric), by: { group($0.date) }).filter { $0.value.count >= minDays }
        guard groups.count >= 2 else { return nil } // one group is not a contest
        let ranked = groups.map { (key: $0.key, days: $0.value, average: mean($0.value.map(\.value))) }
        return metric.higherIsBetter ? ranked.max { $0.average < $1.average } : ranked.min { $0.average < $1.average }
    }

    private func bestMonths() -> [Fact] {
        FunMetric.all.compactMap { m in
            bestGroup(of: m, minDays: 10) { String($0.prefix(7)) }.map {
                Fact(id: m.id, icon: m.icon, tint: m.tint, label: m.title, value: String(Day.month($0.key + "-01").split(separator: " ")[0]), detail: "\(m.withUnit($0.average)) \(m.per)")
            }
        }
    }

    private func bestWeekdays() -> [Fact] {
        let names = ["Mondays", "Tuesdays", "Wednesdays", "Thursdays", "Fridays", "Saturdays", "Sundays"]
        return FunMetric.all.compactMap { m in
            bestGroup(of: m, minDays: 3) { String(Day.weekday($0)) }.map {
                Fact(id: m.id, icon: m.icon, tint: m.tint, label: m.title, value: names[(Int($0.key) ?? 1) - 1], detail: "\(m.withUnit($0.average)) \(m.per)")
            }
        }
    }

    private func bestWeeks() -> [Fact] {
        FunMetric.all.compactMap { m in
            bestGroup(of: m, minDays: 5) { Day.monday(of: $0) }.map {
                let total = $0.days.map(\.value).reduce(0, +)
                return Fact(id: m.id, icon: m.icon, tint: m.tint, label: m.sums ? m.title : m.averageLabel, value: m.show(m.sums ? total : $0.average), unit: m.unit, detail: "week of \(Day.short($0.key))")
            }
        }
    }

    /// Everything added up since the first day stored, each against something to picture it by.
    private func totals() -> [Fact] {
        var out: [Fact] = []
        func total(_ id: String) -> (metric: FunMetric, sum: Double, days: Int)? {
            guard let m = FunMetric.all.first(where: { $0.id == id }) else { return nil }
            let all = points(m)
            return all.isEmpty ? nil : (m, all.map(\.value).reduce(0, +), all.count)
        }
        /// "31 % of X" until the first full one, then "1.4 times X".
        func share(_ times: Double, part: String, whole: String) -> String {
            times < 1 ? "\(Fmt.whole(times * 100)) % \(part)" : "\(String(format: "%.1f", times)) times \(whole)"
        }
        if let t = total("distance") {
            let laps = t.sum / 1322 // Route 1 around Iceland is 1,322 km.
            out.append(Fact(id: "distance", icon: "figure.walk", tint: Theme.Palette.accent, label: "Walked in \(t.days) days", value: Fmt.whole(t.sum), unit: "km",
                            detail: share(laps, part: "of the Ring Road around Iceland", whole: "around Iceland on the Ring Road"), progress: laps.truncatingRemainder(dividingBy: 1)))
        }
        if let t = total("climb") {
            let peaks = t.sum / 2110 // Hvannadalshnúkur, Iceland's highest peak, is 2,110 m.
            out.append(Fact(id: "climb", icon: t.metric.icon, tint: t.metric.tint, label: "Climbed", value: Fmt.whole(t.sum), unit: "m",
                            detail: share(peaks, part: "of the way up Hvannadalshnúkur", whole: "up Hvannadalshnúkur"), progress: peaks.truncatingRemainder(dividingBy: 1)))
        }
        if let t = total("steps") { out.append(Fact(id: "steps", icon: t.metric.icon, tint: t.metric.tint, label: "Steps taken", value: Fmt.whole(t.sum), detail: "\(Fmt.whole(t.sum / Double(t.days))) a day")) }
        // A kilo of body fat holds about 7,700 kcal.
        if let t = total("burn") { out.append(Fact(id: "burn", icon: t.metric.icon, tint: t.metric.tint, label: "Burned moving", value: Fmt.whole(t.sum), unit: "kcal", detail: "the energy in \(String(format: "%.1f", t.sum / 7700)) kg of body fat")) }
        if let t = total("sleep") { out.append(Fact(id: "sleep", icon: t.metric.icon, tint: t.metric.tint, label: "Time asleep", value: Fmt.whole(t.sum / 3600), unit: "h", detail: "\(String(format: "%.1f", t.sum / 86400)) whole days in bed")) }
        if let t = total("intensity") { out.append(Fact(id: "intensity", icon: t.metric.icon, tint: t.metric.tint, label: "Intensity minutes", value: Fmt.whole(t.sum), unit: "min", detail: "\(Fmt.whole(t.sum / 60)) hours of hard work")) }
        return out
    }

    private func streaks() -> [Fact] {
        var out: [Fact] = []
        let dates = days.keys.sorted()
        /// The longest and the current run of days in a row that pass. Today cannot break a run: it is not over.
        func runs(_ pass: (String) -> Bool?) -> (longest: Int, current: Int, count: Int)? {
            guard let first = dates.first else { return nil }
            var longest = 0, run = 0, count = 0, seen = false
            for i in 0...max(Day.daysBetween(first, today), 0) {
                let d = Day.add(first, i)
                guard let ok = pass(d) else { if d != today { run = 0 }; continue }
                seen = true
                if ok { run += 1; count += 1; longest = max(longest, run) } else if d != today { run = 0 }
            }
            return seen ? (longest, run, count) : nil
        }
        let steps = { (d: String) in self.value("movement.steps.value", on: d) }
        if let r = runs({ d in steps(d).flatMap { v in self.value("movement.steps.goal", on: d).map { v >= $0 } } }) {
            out.append(Fact(id: "goalLongest", icon: "flame.fill", tint: Theme.Palette.danger, label: "Longest step goal streak", value: "\(r.longest)", unit: "days", detail: "in a row"))
            out.append(Fact(id: "goalNow", icon: "figure.walk", tint: Theme.Palette.accent, label: "Step goal streak now", value: "\(r.current)", unit: "days", detail: r.current >= r.longest && r.current > 0 ? "your longest yet" : "\(r.longest - r.current) short of your longest"))
            out.append(Fact(id: "goalDays", icon: "checkmark.seal.fill", tint: Theme.Palette.ok, label: "Step goal days", value: "\(r.count)", detail: "since \(Day.short(dates.first ?? today))"))
        }
        if let r = runs({ d in steps(d).map { $0 >= 10000 } }) { out.append(Fact(id: "tenK", icon: "trophy.fill", tint: Theme.Palette.energy, label: "10,000 step days", value: "\(r.count)", detail: "longest run \(r.longest) days")) }
        if let r = runs({ d in self.value("sleep.sleepTimeSeconds", on: d).map { $0 >= 7 * 3600 } }) {
            out.append(Fact(id: "sevenHours", icon: "moon.zzz.fill", tint: Theme.Palette.sleep, label: "Nights of 7 hours or more", value: "\(r.count)", detail: "longest run \(r.longest) nights"))
        }
        if let r = runs({ d in self.value("sleep.sleepScores.overall.value", on: d).map { $0 >= 80 } }) {
            out.append(Fact(id: "goodNights", icon: "moon.stars.fill", tint: Theme.Palette.sleep, label: "Sleep scores of 80 or more", value: "\(r.count)", detail: "longest run \(r.longest) nights"))
        }
        if let r = runs({ d in self.intensity(on: d).map { $0 >= 30 } }) {
            out.append(Fact(id: "hardDays", icon: "bolt.heart.fill", tint: Theme.Palette.heart, label: "Days with 30 intensity minutes", value: "\(r.count)", detail: "longest run \(r.longest) days"))
        }
        return out
    }
}
