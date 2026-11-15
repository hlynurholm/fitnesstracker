import SwiftUI

/// The page behind a Home widget: its number, a large chart over a range picked on the page, the figures that
/// matter for that measure, how it runs through the week, and whatever else the watch stores next to it.
/// Each widget has its own page below; they share the pieces at the end of this file.
struct WidgetDetailScreen: View {
    let model: HomeModel
    let kind: CardKind
    @State private var days = 30

    var body: some View {
        Screen {
            if kind != .week, kind != .facts {
                Picker("Range", selection: $days) { Text("1 week").tag(7); Text("1 month").tag(30); Text("3 months").tag(90); Text("6 months").tag(180) }.pickerStyle(.segmented)
            }
            page
        }
        .inlineTitle(kind.title)
    }

    @ViewBuilder
    private var page: some View {
        switch kind {
        case .steps: steps
        case .sleep: sleep
        case .hrv: hrv
        case .bodyBattery: bodyBattery
        case .stress: stress
        case .calories: calories
        case .intensity: intensity
        case .weight: weight
        case .nutrition: nutrition
        case .week: week
        case .facts: facts
        default: if let spec = MetricSpec.all[kind] { plain(spec) }
        }
    }

    // MARK: Days and groups

    /// Days are drawn one by one up to three months; six months are drawn as weekly averages.
    private var every: Int { days > 100 ? 7 : 1 }
    private var dates: [String] { (0..<days).map { Day.add(model.today, -(days - 1 - $0)) } }
    private var before: [String] { (0..<days).map { Day.add(model.today, -(2 * days - 1 - $0)) } }
    private var rangeName: String { days == 7 ? "week" : days == 30 ? "month" : days == 90 ? "3 months" : "6 months" }
    private var chartNote: String { every > 1 ? "weekly averages" : "each day" }

    /// The first day of each group of `every` days, counted back from today.
    private var slots: [String] { stride(from: dates.count, to: 0, by: -every).map { dates[max(0, $0 - every)] }.reversed() }
    /// A value per slot: the day's value, or the average of the group.
    private func grouped(_ value: (String) -> Double?) -> [Double?] {
        stride(from: dates.count, to: 0, by: -every).map { end -> Double? in
            let v = dates[max(0, end - every)..<end].compactMap(value)
            return v.isEmpty ? nil : v.reduce(0, +) / Double(v.count)
        }.reversed()
    }

    private func metric(_ spec: MetricSpec) -> Metric {
        Metric(name: spec.title, unit: spec.unit, color: spec.tint, digits: spec.digits, style: spec.style == .bars ? .bars : .line,
               sums: [.steps, .calories, .floors, .distance].contains(kind), lowerIsBetter: [.restingHR, .stress].contains(kind),
               goal: spec.goalKey.flatMap { model.latest($0)?.value }.map { $0 * spec.scale }) { model.value(spec.key, on: $0).map { $0 * spec.scale } }
    }

    // MARK: Pages

    /// A measure with nothing special about it: resting heart rate, floors, distance, sleep score, breathing, blood
    /// oxygen, body fat, lean mass.
    @ViewBuilder
    private func plain(_ spec: MetricSpec) -> some View {
        let m = metric(spec)
        hero(m)
        chart(m.name, [.init(id: m.name, color: m.color, style: m.style, values: grouped(m.value))], goal: m.goal, format: m.text)
        figures(m)
        if kind == .restingHR, let week = model.average(spec.key, 7), let month = model.average(spec.key, 30) {
            note("Your resting heart rate averaged \(Fmt.whole(week)) bpm over the last 7 days and \(Fmt.whole(month)) bpm over the last 30. " +
                 (week < month - 0.5 ? "It is coming down, which usually means fitness or recovery is improving." : week > month + 0.5 ? "It is running higher than usual, which can mean tiredness, stress or a cold on the way." : "It is holding steady."))
        }
        if kind == .distance { weeklyTotals(m, title: "Kilometres per week") }
        if kind == .sleepScore { note("\(count(m) { $0 >= 80 }) of the \(count(m) { _ in true }) nights in this range scored 80 or more.") }
        if ![.bodyFat, .leanMass].contains(kind) { weekdays(m) }
        siblings(of: spec.key)
    }

    @ViewBuilder
    private var steps: some View {
        if let spec = MetricSpec.all[.steps] {
            let m = metric(spec)
            hero(m)
            chart("Steps", [.init(id: "Steps", color: m.color, values: grouped(m.value))], goal: m.goal, format: m.text)
            figures(m)
            let goalDays = dates.map { d in model.value(spec.key, on: d).flatMap { v in model.value("movement.steps.goal", on: d).map { v >= $0 } } }
            let run = Self.streaks(goalDays)
            let km = dates.compactMap { model.value("movement.steps.distanceInMeters", on: $0) }.reduce(0, +) / 1000
            TileGrid {
                Tile(label: "Goal streak now", value: "\(run.current) days", detail: "longest in this range \(run.longest)")
                Tile(label: "10,000 step days", value: "\(count(m) { $0 >= 10000 })", detail: "of \(count(m) { _ in true })")
                if km > 0 { Tile(label: "Walked", value: "\(Fmt.whole(km)) km", detail: "in this \(rangeName)") }
                if let climbed = Optional(dates.compactMap({ model.value("movement.floorsAscended.value", on: $0) }).reduce(0, +)), climbed > 0 { Tile(label: "Floors climbed", value: Fmt.whole(climbed)) }
            }
            weekdays(m)
            siblings(of: spec.key)
        }
    }

    @ViewBuilder
    private var sleep: some View {
        let m = Metric(name: "Sleep", color: Theme.Palette.sleep, hours: true) { model.value("sleep.sleepTimeSeconds", on: $0).map { $0 / 3600 } }
        let stage = { (key: String) in { (d: String) in model.value("sleep.\(key)", on: d).map { $0 / 3600 } } }
        let stages: [(name: String, key: String, color: Color)] = [("Deep", "deepSleepSeconds", Theme.Palette.sleep), ("Light", "lightSleepSeconds", Theme.Palette.sleep.opacity(0.5)),
                                                                   ("REM", "remSleepSeconds", Theme.Palette.calm), ("Awake", "awakeSleepSeconds", Theme.Palette.warn)]
        hero(m)
        // Each night split into its stages.
        chart("Nights", stages.map { .init(id: $0.name, color: $0.color, values: grouped(stage($0.key))) }, goal: nil, format: m.text)
        figures(m)
        if let night = model.latest("sleep.sleepTimeSeconds") {
            let parts = stages.map { s in (s.name, model.value("sleep.\(s.key)", on: night.date) ?? 0, s.color) }.filter { $0.1 > 0 }
            let total = max(parts.map(\.1).reduce(0, +), 1)
            if !parts.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    CardTitle("The night of \(Day.short(night.date))", note: model.value("sleep.sleepScores.overall.value", on: night.date).map { "score \(Fmt.whole($0))" })
                    SegmentBar(parts: parts.map { ($0.1, $0.2) }, height: 12)
                    ForEach(parts, id: \.0) { p in
                        HStack(spacing: Theme.Space.s) {
                            Circle().fill(p.2).frame(width: 8, height: 8)
                            Text(p.0).font(Theme.Typography.callout)
                            Spacer()
                            Text("\(Fmt.whole(p.1 / total * 100)) %").font(Theme.Typography.caption).muted()
                            Text(Fmt.hours(p.1)).font(Theme.Typography.callout.weight(.semibold).monospacedDigit()).frame(width: 96, alignment: .trailing)
                        }
                    }
                }
                .card()
            }
        }
        let score = Metric(name: "Sleep score", color: Theme.Palette.sleep, style: .line) { model.value("sleep.sleepScores.overall.value", on: $0) }
        if count(score, { _ in true }) > 1 {
            chart("Sleep score", [.init(id: "Score", color: score.color, style: .line, values: grouped(score.value))], goal: nil, height: 160, format: score.text)
        }
        note("\(count(m) { $0 >= 7 }) of the \(count(m) { _ in true }) nights in this range were 7 hours or longer.")
        weekdays(m)
        siblings(of: "sleep.sleepTimeSeconds")
    }

    @ViewBuilder
    private var hrv: some View {
        let weekly = Metric(name: "7 day average", unit: "ms", color: CardKind.hrv.tint, style: .line) { model.hrvWeekly(on: $0) }
        let nightly = Metric(name: "HRV", unit: "ms", color: CardKind.hrv.tint, style: .dots) { model.value("hrv.lastNightAvg", on: $0) }
        hero(weekly, label: "7 day average")
        chart("HRV", [.init(id: "Night", color: Theme.Palette.rest, style: .dots, values: grouped(nightly.value)),
                      .init(id: "7 day average", color: weekly.color, style: .line, values: grouped(weekly.value))],
              band: (grouped { model.value("hrv.baseline.balancedLow", on: $0) }, grouped { model.value("hrv.baseline.balancedUpper", on: $0) }), goal: nil, format: weekly.text)
        note("The line is your 7 day average, which is what Garmin's HRV status shows. The grey dots are single nights, which jump about much more. The green band is the range your watch calls balanced for you; it is meant for the average, not for one night.")
        figures(nightly)
        if let d = model.latest("hrv.lastNightAvg")?.date {
            TileGrid {
                if let lo = model.value("hrv.baseline.balancedLow", on: d), let hi = model.value("hrv.baseline.balancedUpper", on: d) { Tile(label: "Balanced range", value: "\(Fmt.whole(lo))–\(Fmt.whole(hi)) ms") }
                if let low = model.value("hrv.baseline.lowUpper", on: d) { Tile(label: "Low under", value: "\(Fmt.whole(low)) ms") }
                if let peak = model.value("hrv.lastNight5MinHigh", on: d) { Tile(label: "Highest 5 minutes", value: "\(Fmt.whole(peak)) ms", detail: "last night") }
                if let status = model.days[d]?["hrv.status"]?.text { Tile(label: "Garmin's status", value: status.replacingOccurrences(of: "_", with: " ").lowercased().capitalizedFirst) }
            }
        }
        weekdays(nightly)
    }

    @ViewBuilder
    private var bodyBattery: some View {
        let high = Metric(name: "Body Battery", color: Theme.Palette.ok, style: .line) { model.value("bodyBattery.maxValue", on: $0) }
        let low = Metric(name: "Lowest", color: Theme.Palette.rest, style: .line) { model.value("bodyBattery.minValue", on: $0) }
        hero(high, label: "Highest today")
        chart("Highest and lowest", [.init(id: "Highest", color: high.color, style: .line, values: grouped(high.value)), .init(id: "Lowest", color: low.color, style: .line, values: grouped(low.value))], goal: nil, format: high.text)
        note("The top line is how full you were at your best each day, usually on waking. The bottom line is how far you ran down. A wide gap is a day that cost a lot.")
        let spent = dates.compactMap { d in high.value(d).flatMap { h in low.value(d).map { h - $0 } } }
        TileGrid {
            if let a = average(high) { Tile(label: "Average high", value: Fmt.whole(a)) }
            if let a = average(low) { Tile(label: "Average low", value: Fmt.whole(a)) }
            if !spent.isEmpty { Tile(label: "Spent per day", value: Fmt.whole(spent.reduce(0, +) / Double(spent.count)), detail: "from high to low") }
            Tile(label: "Days starting above 80", value: "\(count(high) { $0 >= 80 })", detail: "of \(count(high) { _ in true })")
        }
        weekdays(high)
        siblings(of: "bodyBattery.maxValue")
    }

    @ViewBuilder
    private var stress: some View {
        let avg = Metric(name: "Stress", color: Theme.Palette.energy, style: .line, lowerIsBetter: true) { model.value("stress.avgLevel", on: $0) }
        let peak = Metric(name: "Peak", color: Theme.Palette.danger, style: .dots) { model.value("stress.maxLevel", on: $0) }
        hero(avg, label: "Average today")
        chart("Average and peak", [.init(id: "Peak", color: peak.color.opacity(0.6), style: .dots, values: grouped(peak.value)), .init(id: "Average", color: avg.color, style: .line, values: grouped(avg.value))], goal: nil, format: avg.text)
        note("Garmin scores stress from 0 to 100: under 26 is rest, 26 to 50 low, 51 to 75 medium, above that high.")
        figures(avg)
        TileGrid {
            Tile(label: "Restful days", value: "\(count(avg) { $0 <= 25 })", detail: "average of 25 or less")
            Tile(label: "Days peaking above 75", value: "\(count(peak) { $0 > 75 })", detail: "of \(count(peak) { _ in true })")
        }
        weekdays(avg)
        siblings(of: "stress.avgLevel")
    }

    @ViewBuilder
    private var calories: some View {
        let active = Metric(name: "Active calories", unit: "kcal", color: Theme.Palette.energy, sums: true) { model.value("calories.burnedActive", on: $0) }
        let total = Metric(name: "Total burned", unit: "kcal", color: Theme.Palette.rest, sums: true) { model.value("calories.burnedTotal", on: $0) }
        let resting = { (d: String) in total.value(d).flatMap { t in active.value(d).map { max(t - $0, 0) } } }
        hero(active)
        chart("Burned", [.init(id: "Active", color: active.color, values: grouped(active.value)), .init(id: "At rest", color: total.color.opacity(0.5), values: grouped(resting))], goal: nil, format: active.text)
        figures(active)
        TileGrid {
            if let a = average(total) { Tile(label: "Total per day", value: "\(Fmt.whole(a)) kcal", detail: "moving and at rest") }
            if let a = average(active), let t = average(total), t > 0 { Tile(label: "Share from moving", value: "\(Fmt.whole(a / t * 100)) %") }
        }
        if let target = model.dash?.settings.number("calorie_target") ?? AppModel.shared.program?.nutrition.calories, let t = average(total) {
            note("You burn about \(Fmt.whole(t)) kcal a day on average in this range. Your eating target is \(Fmt.whole(target)) kcal, which leaves a gap of \(Fmt.whole(t - target)) kcal a day.")
        }
        weekdays(active)
        siblings(of: "calories.burnedActive")
    }

    @ViewBuilder
    private var intensity: some View {
        let m = Metric(name: "Intensity minutes", unit: "min", color: CardKind.intensity.tint, sums: true) { model.intensity(on: $0) }
        let goal = model.latest("intensityMinutes.goal")?.value ?? 150
        hero(m, label: "Today")
        chart("Per day", [.init(id: "Moderate", color: Theme.Palette.energy, values: grouped { model.value("intensityMinutes.moderate", on: $0) }),
                          .init(id: "Vigorous, counted twice", color: Theme.Palette.heart, values: grouped { model.value("intensityMinutes.vigorous", on: $0).map { $0 * 2 } })], goal: nil, format: m.text)
        weeklyTotals(m, title: "Minutes per week", goal: goal)
        figures(m)
        note("Garmin counts a vigorous minute twice towards the weekly goal of \(Fmt.whole(goal)).")
        weekdays(m)
        siblings(of: "intensityMinutes.moderate")
    }

    @ViewBuilder
    private var weight: some View {
        let byDay = Dictionary((model.dash?.body ?? []).compactMap { b in b.weight_kg.map { (b.date, $0) } }, uniquingKeysWith: { a, _ in a })
        let m = Metric(name: "Weight", unit: "kg", color: CardKind.weight.tint, digits: 1, style: .dots, lowerIsBetter: true) { byDay[$0] }
        /// The average of the weigh-ins in the week ending on a day.
        let smooth = { (d: String) -> Double? in
            let v = (0..<7).compactMap { byDay[Day.add(d, -$0)] }
            return v.isEmpty ? nil : v.reduce(0, +) / Double(v.count)
        }
        let goal = model.dash?.settings.number("goal_weight_kg") ?? AppModel.shared.program?.body.goalWeightKg
        hero(m)
        chart("Weigh-ins and 7 day average", [.init(id: "Weigh-in", color: Theme.Palette.rest, style: .dots, values: grouped(m.value)), .init(id: "7 day average", color: m.color, style: .line, values: grouped(smooth))],
              goal: goal.flatMap { g in (byDay.values.min() ?? g) - g < 6 ? g : nil }, format: m.text)
        let first = dates.lazy.compactMap(smooth).first, last = smooth(model.today) ?? dates.reversed().lazy.compactMap(smooth).first
        let weighDays = dates.filter { byDay[$0] != nil }
        TileGrid {
            if let first, let last {
                Tile(label: "Change in this \(rangeName)", value: "\(Fmt.signed(last - first, digits: 1)) kg", tone: last <= first ? .ok : .warn)
                if let a = weighDays.first, let b = weighDays.last, Day.daysBetween(a, b) >= 7 {
                    let perWeek = (last - first) / Double(Day.daysBetween(a, b)) * 7
                    Tile(label: "Per week", value: "\(Fmt.signed(perWeek, digits: 2)) kg")
                    if let goal, perWeek < -0.05, last > goal {
                        Tile(label: "Goal of \(Fmt.number(goal)) kg", value: Day.short(Day.add(model.today, Int(((last - goal) / -perWeek * 7).rounded()))), detail: "at this rate")
                    }
                }
            }
            if let goal, let last { Tile(label: "To goal", value: "\(Fmt.number(((last - goal) * 10).rounded() / 10)) kg") }
            Tile(label: "Weigh-ins", value: "\(weighDays.count)", detail: "in this \(rangeName)")
        }
        figures(m)
    }

    @ViewBuilder
    private var nutrition: some View {
        let rows = Dictionary((model.dash?.nutrition ?? []).map { ($0.date, $0) }, uniquingKeysWith: { a, _ in a })
        let program = AppModel.shared.program
        let kcalTarget = model.dash?.settings.number("calorie_target") ?? program?.nutrition.calories
        let proteinTarget = model.dash?.settings.number("protein_target") ?? program?.nutrition.proteinG
        let kcal = Metric(name: "Calories", unit: "kcal", color: CardKind.nutrition.tint, goal: kcalTarget) { rows[$0]?.calories }
        let protein = Metric(name: "Protein", unit: "g", color: Theme.Palette.accent, goal: proteinTarget) { rows[$0]?.protein_g }
        hero(kcal)
        chart("Calories", [.init(id: "Calories", color: kcal.color, values: grouped(kcal.value))], goal: kcalTarget, format: kcal.text)
        figures(kcal)
        chart("Protein", [.init(id: "Protein", color: protein.color, values: grouped(protein.value))], goal: proteinTarget, height: 170, format: protein.text)
        TileGrid {
            if let a = average(protein) { Tile(label: "Protein per day", value: "\(Fmt.whole(a)) g", detail: proteinTarget.map { "target \(Fmt.whole($0)) g" }) }
            if let proteinTarget { Tile(label: "Protein target reached", value: "\(count(protein) { $0 >= proteinTarget })", detail: "of \(count(protein) { _ in true }) logged days") }
            if let kcalTarget { Tile(label: "Within 10 % of target", value: "\(count(kcal) { abs($0 - kcalTarget) <= kcalTarget * 0.1 })", detail: "of \(count(kcal) { _ in true }) logged days") }
            Tile(label: "Days logged", value: "\(count(kcal) { _ in true })", detail: "of \(days)")
        }
        weekdays(kcal)
    }

    /// Sessions done per week over the last twelve weeks, and this week day by day.
    @ViewBuilder
    private var week: some View {
        let done = (model.dash?.workouts ?? []).filter { $0.status == "done" && $0.kind != "rest" }
        let monday = Day.monday(of: model.today)
        let mondays = (0..<12).map { Day.add(monday, -7 * (11 - $0)) }
        let inWeek = { (m: String, kind: String?) in Double(Set(done.filter { $0.date >= m && $0.date <= Day.add(m, 6) && (kind == nil || $0.kind == kind) }.map(\.date)).count) }
        let perWeek = mondays.map { inWeek($0, nil) }
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            CardTitle("Days trained per week", note: "last 12 weeks")
            SeriesChart(slots: mondays, series: [.init(id: "Lifting", color: Theme.Palette.lift, values: mondays.map { inWeek($0, "lift") }),
                                                 .init(id: "Running", color: Theme.Palette.run, values: mondays.map { inWeek($0, "run") }),
                                                 .init(id: "Other", color: Theme.Palette.test, values: mondays.map { m in max(inWeek(m, nil) - inWeek(m, "lift") - inWeek(m, "run"), 0) })],
                        label: { Day.short($0) }, format: { Fmt.whole($0) })
        }
        .card()
        TileGrid {
            Tile(label: "This week", value: "\(Int(perWeek.last ?? 0)) days")
            Tile(label: "Average", value: String(format: "%.1f days", perWeek.reduce(0, +) / Double(perWeek.count)), detail: "a week, last 12 weeks")
            Tile(label: "Best week", value: "\(Int(perWeek.max() ?? 0)) days", detail: zip(mondays, perWeek).max { $0.1 < $1.1 }.map { "week of \(Day.short($0.0))" })
            Tile(label: "Sessions done", value: "\(done.filter { $0.date >= mondays[0] }.count)", detail: "last 12 weeks")
        }
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            CardTitle("This week")
            ForEach(0..<7, id: \.self) { i in
                let date = Day.add(monday, i), sessions = done.filter { $0.date == date }
                HStack {
                    Text(Day.label(date)).font(Theme.Typography.callout).foregroundStyle(date == model.today ? Theme.Palette.text : Theme.Palette.muted)
                    Spacer(minLength: Theme.Space.s)
                    Text(sessions.isEmpty ? (date > model.today ? "" : "nothing logged") : sessions.map { AppModel.shared.program?.templates[$0.template_key]?.name ?? $0.template_key }.joined(separator: ", "))
                        .font(Theme.Typography.callout.weight(sessions.isEmpty ? .regular : .semibold)).foregroundStyle(sessions.isEmpty ? Theme.Palette.muted : Theme.Palette.text).lineLimit(1)
                }
            }
        }
        .card()
    }

    /// Every theme of facts at once. The widget shows one a day.
    @ViewBuilder
    private var facts: some View {
        ForEach(model.factThemes, id: \.title) { theme in
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                CardTitle(theme.title)
                ForEach(theme.facts) { FactLine(fact: $0) }
            }
            .card()
        }
    }

    // MARK: Shared pieces

    /// A measure a page is about.
    private struct Metric {
        var name: String
        var unit = ""
        var color: Color
        var digits = 0
        var style: SeriesChart.Style = .bars
        /// Adding days up makes sense (steps), as opposed to a level (heart rate).
        var sums = false
        var lowerIsBetter = false
        /// The value is hours, written as "7 h 42 min".
        var hours = false
        var goal: Double? = nil
        let value: (String) -> Double?

        func text(_ v: Double) -> String { hours ? Fmt.hours(v * 3600) : digits == 0 ? Fmt.whole(v) : String(format: "%.\(digits)f", v) }
        func show(_ v: Double) -> String { text(v) + (unit.isEmpty ? "" : " \(unit)") }
    }

    private func points(_ m: Metric, in list: [String]? = nil) -> [(date: String, value: Double)] { (list ?? dates).compactMap { d in m.value(d).map { (d, $0) } } }
    private func average(_ m: Metric, in list: [String]? = nil) -> Double? {
        let v = points(m, in: list).map(\.value)
        return v.isEmpty ? nil : v.reduce(0, +) / Double(v.count)
    }
    private func count(_ m: Metric, _ pass: (Double) -> Bool) -> Int { points(m).filter { pass($0.value) }.count }

    /// The latest value, large, with the day it is from and how the range compares with the one before it.
    @ViewBuilder
    private func hero(_ m: Metric, label: String? = nil) -> some View {
        let latest = (0..<60).lazy.compactMap { back -> (date: String, value: Double)? in let d = Day.add(model.today, -back); return m.value(d).map { (d, $0) } }.first
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text(([label ?? "Latest"] + [latest.flatMap { dayNote($0.date, today: model.today) } ?? (latest == nil ? nil : "today")].compactMap { $0 }).joined(separator: " · ").uppercased())
                .font(Theme.Typography.label).foregroundStyle(m.color)
            BigValue(value: latest.map { m.text($0.value) } ?? "–", unit: m.hours ? "" : m.unit)
            if let now = average(m), let then = average(m, in: before), then != 0 {
                let change = (now - then) / then * 100
                Text(abs(change) < 1 ? "About the same as the \(rangeName) before." : "\(change > 0 ? "Up" : "Down") \(Fmt.whole(abs(change))) % on the \(rangeName) before.")
                    .font(Theme.Typography.caption).foregroundStyle(abs(change) < 1 ? Theme.Palette.muted : ((change < 0) == m.lowerIsBetter ? Theme.Palette.ok : Theme.Palette.warn))
            }
        }
        .padding(.horizontal, Theme.Space.xs).padding(.top, Theme.Space.xs)
    }

    private func chart(_ title: String, _ series: [SeriesChart.Series], band: (low: [Double?], high: [Double?])? = nil, goal: Double?, height: CGFloat = 230, format: @escaping (Double) -> String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            CardTitle(title, note: [chartNote, goal.map { "goal \(format($0))" }].compactMap { $0 }.joined(separator: " · "))
            SeriesChart(slots: slots, series: series, band: band, goal: goal, height: height, label: { Day.short($0) }, format: format)
            if series.count > 1 {
                HStack(spacing: Theme.Space.m) {
                    ForEach(series) { s in
                        HStack(spacing: Theme.Space.xs) { Circle().fill(s.color).frame(width: 7, height: 7); Text(s.id).font(Theme.Typography.caption).muted() }
                    }
                }
                .lineLimit(1).minimumScaleFactor(0.7)
            }
        }
        .card()
    }

    /// Average, total, best and worst day, and days on goal.
    @ViewBuilder
    private func figures(_ m: Metric) -> some View {
        let all = points(m)
        if let avg = average(m), let low = all.min(by: { $0.value < $1.value }), let high = all.max(by: { $0.value < $1.value }) {
            TileGrid {
                Tile(label: "Average", value: m.show(avg), detail: "this \(rangeName)")
                if m.sums { Tile(label: "Total", value: m.hours ? "\(Fmt.whole(all.map(\.value).reduce(0, +))) h" : m.show(all.map(\.value).reduce(0, +)), detail: "\(all.count) days") }
                Tile(label: "Highest", value: m.show(high.value), detail: Day.label(high.date), tone: m.lowerIsBetter ? nil : .ok)
                Tile(label: "Lowest", value: m.show(low.value), detail: Day.label(low.date), tone: m.lowerIsBetter ? .ok : nil)
                if let goal = m.goal, goal > 0 { Tile(label: "Goal reached", value: "\(all.filter { $0.value >= goal }.count) days", detail: "of \(all.count)") }
            }
        }
    }

    /// The average for each day of the week over the range.
    @ViewBuilder
    private func weekdays(_ m: Metric) -> some View {
        let names = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        let groups = Dictionary(grouping: points(m), by: { Day.weekday($0.date) })
        let values = (1...7).map { day -> Double? in groups[day].map { g in g.map(\.value).reduce(0, +) / Double(g.count) } }
        if days >= 14, values.compactMap({ $0 }).count >= 5 {
            let ranked = zip(names, values).compactMap { n, v in v.map { (n, $0) } }
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                CardTitle("Through the week", note: (m.lowerIsBetter ? ranked.min { $0.1 < $1.1 } : ranked.max { $0.1 < $1.1 }).map { "best on \($0.0)" })
                SeriesChart(slots: names, series: [.init(id: m.name, color: m.color, values: values)], height: 140, label: { $0 }, format: m.text)
            }
            .card()
        }
    }

    /// Totals for each of the last eight weeks, against a weekly goal if there is one.
    private func weeklyTotals(_ m: Metric, title: String, goal: Double? = nil) -> some View {
        let monday = Day.monday(of: model.today)
        let mondays = (0..<8).map { Day.add(monday, -7 * (7 - $0)) }
        let totals = mondays.map { start -> Double? in
            let v = (0..<7).compactMap { m.value(Day.add(start, $0)) }
            return v.isEmpty ? nil : v.reduce(0, +)
        }
        return VStack(alignment: .leading, spacing: Theme.Space.m) {
            CardTitle(title, note: goal.map { "goal \(m.text($0))" } ?? "last 8 weeks")
            SeriesChart(slots: mondays, series: [.init(id: m.name, color: m.color, values: totals)], goal: goal, height: 160, label: { Day.short($0) }, format: m.text)
        }
        .card()
    }

    private func note(_ text: String) -> some View {
        Text(text).font(Theme.Typography.caption).muted().padding(.horizontal, Theme.Space.xs)
    }

    /// Everything else the watch stored in the same group for the latest day, by Garmin's own names.
    @ViewBuilder
    private func siblings(of key: String) -> some View {
        let group = String(key.prefix { $0 != "." }) + "."
        if let date = model.latest(key)?.date {
            let rows = (model.days[date] ?? [:]).filter { $0.key.hasPrefix(group) && $0.key != key }.sorted { $0.key < $1.key }
            if !rows.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    CardTitle("More from your watch", note: Day.label(date))
                    ForEach(rows, id: \.key) { key, value in
                        HStack(alignment: .firstTextBaseline) {
                            Text(Fmt.metricName(String(key.dropFirst(group.count)))).font(Theme.Typography.caption).muted()
                            Spacer(minLength: Theme.Space.m)
                            Text(value.number.map { $0 == $0.rounded() ? Fmt.whole($0) : String(format: "%.1f", $0) } ?? value.text?.replacingOccurrences(of: "_", with: " ").lowercased() ?? "")
                                .font(Theme.Typography.caption.weight(.semibold).monospacedDigit())
                        }
                    }
                }
                .card()
            }
        }
    }

    /// The current and the longest run of days that pass. A day without a reading ends a run; today cannot.
    private static func streaks(_ days: [Bool?]) -> (current: Int, longest: Int) {
        var longest = 0, run = 0
        for (i, ok) in days.enumerated() {
            if ok == true { run += 1; longest = max(longest, run) } else if i < days.count - 1 { run = 0 }
        }
        return (run, longest)
    }
}
