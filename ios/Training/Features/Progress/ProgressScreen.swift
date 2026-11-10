import Charts
import SwiftUI

/// Charts from GET /api/dashboard: body weight, lift progression, running, sessions per week and personal bests.
struct ProgressScreen: View {
    @State private var data: Dashboard?
    @State private var error: String?
    @State private var lift = ""

    var body: some View {
        Screen {
            if let d = data, let program = AppModel.shared.program {
                let m = Model(d, program)
                tiles(m, d, program)
                weight(m, d, program)
                sessions(m)
                lifts(m, program)
                running(m, d, program)
                bests(m, program)
            } else if let error {
                ErrorCard(message: error) { await load() }
            } else {
                ProgressView().frame(maxWidth: .infinity).padding(.top, 80)
            }
        }
        .navigationTitle("Progress")
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        do { data = try await API.shared.get("/api/dashboard", cache: true); error = nil } catch { self.error = error.localizedDescription }
    }

    // MARK: Derived data

    struct Point: Identifiable { let date: Date; let value: Double; var id: Date { date } }
    struct LiftSeries: Identifiable { let key: String; let sessions: [(date: String, top: Double?, e1rm: Double?, reps: Int, seconds: Int)]; var id: String { key } }

    struct Model {
        var weights: [Point] = []
        var rolling: [Point] = []
        var lifts: [LiftSeries] = []
        var runs: [(date: String, pace: Double, km: Double, easy: Bool)] = []
        var weeks: [(week: Int, done: Int)] = []

        init(_ d: Dashboard, _ program: Program) {
            // One weigh-in per day, manual entries win.
            var byDay: [String: Double] = [:]
            for b in d.body.sorted(by: { ($0.source == "manual" ? 1 : 0) < ($1.source == "manual" ? 1 : 0) }) { if let kg = b.weight_kg { byDay[b.date] = kg } }
            let days = byDay.sorted { $0.key < $1.key }
            weights = days.map { Point(date: Day.date($0.key), value: $0.value) }
            rolling = days.map { day in
                let window = days.filter { $0.key > Day.add(day.key, -7) && $0.key <= day.key }.map(\.value)
                return Point(date: Day.date(day.key), value: window.reduce(0, +) / Double(window.count))
            }

            lifts = Dictionary(grouping: d.sets, by: \.exercise_key).map { key, sets in
                let sessions = Dictionary(grouping: sets) { "\($0.date ?? "")#\($0.workout_id ?? 0)" }.values.map { s in
                    (date: s[0].date ?? "", top: s.compactMap(\.weight_kg).max(), e1rm: s.compactMap { Fmt.e1rm(kg: $0.weight_kg, reps: $0.reps) }.max(), reps: s.compactMap(\.reps).max() ?? 0, seconds: s.compactMap(\.seconds).max() ?? 0)
                }.sorted { $0.date < $1.date }
                return LiftSeries(key: key, sessions: sessions)
            }.sorted { ($0.sessions.count, program.exercise($1.key).name) > ($1.sessions.count, program.exercise($0.key).name) }

            runs = d.workouts.filter { $0.kind == "run" && $0.status != "skipped" }.compactMap { w in
                guard let km = w.distance_km, let s = w.time_sec, km > 0, s > 0 else { return nil }
                return (w.date, s / km, km, program.templates[w.template_key]?.easy == true)
            }

            if let start = d.settings["program_start_date"] {
                let monday = Day.monday(of: start)
                let done = d.workouts.filter { $0.status == "done" && $0.kind != "rest" }
                let current = max(1, Day.daysBetween(monday, Day.today()) / 7 + 1)
                weeks = (1...current).suffix(12).map { wk in
                    (wk, Set(done.filter { let n = Day.daysBetween(monday, $0.date); return n >= 0 && n / 7 + 1 == wk }.map(\.date)).count)
                }
            }
        }
    }

    // MARK: Cards

    private func tiles(_ m: Model, _ d: Dashboard, _ program: Program) -> some View {
        let goal = d.settings.number("goal_weight_kg") ?? program.body.goalWeightKg
        let latest = m.rolling.last?.value
        let thisWeek = m.weeks.last
        return TileGrid {
            Tile(label: "Weight, 7-day", value: latest.map { String(format: "%.1f kg", $0) } ?? "–", detail: latest.map { String(format: "%.1f kg to the %@ kg goal", $0 - goal, Fmt.number(goal)) } ?? "no weigh-ins yet")
            Tile(label: "This week", value: thisWeek.map { "\($0.done) done" } ?? "–", detail: thisWeek.map { "week \($0.week) of the plan" })
            Tile(label: "Sessions logged", value: "\(d.workouts.filter { $0.status == "done" && $0.kind != "rest" }.count)")
            Tile(label: "5 km", value: d.tests.last { $0.test_key == "five_k_sec" }.map { Fmt.time($0.value) } ?? "–", detail: "target \(Fmt.time(d.settings.number("five_k_target_sec") ?? program.running.fiveKTargetSec))")
        }
    }

    @ViewBuilder
    private func weight(_ m: Model, _ d: Dashboard, _ program: Program) -> some View {
        let goal = d.settings.number("goal_weight_kg") ?? program.body.goalWeightKg
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            CardTitle("Body weight", note: "goal \(Fmt.number(goal)) kg")
            if m.weights.count < 2 {
                empty("Log your morning weight on the Today tab and the trend shows up here.")
            } else {
                if let first = m.rolling.first, let last = m.rolling.last {
                    let change = last.value - first.value
                    StatLine(value: kg(last.value), caption: "\(Fmt.signed(change, digits: 1)) kg since \(Day.short(Day.string(first.date)))", tone: change < 0 ? .ok : nil)
                }
                TrendChart(series: [
                    TrendSeries(name: "7-day average", color: Theme.Palette.accent, points: m.rolling.map { .init(date: $0.date, value: $0.value) }),
                    TrendSeries(name: "Weigh-in", color: Theme.Palette.muted, style: .points, points: m.weights.map { .init(date: $0.date, value: $0.value) }),
                ], goal: ("Goal \(Fmt.number(goal)) kg", goal), format: kg)
            }
        }
        .card()
    }

    private func sessions(_ m: Model) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            CardTitle("Sessions", note: "days trained per week")
            BarsChart(bars: m.weeks.map { .init(label: "W\($0.week)", value: Double($0.done)) }, highlight: m.weeks.last.map { "W\($0.week)" })
        }
        .card()
    }

    @ViewBuilder
    private func lifts(_ m: Model, _ program: Program) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            CardTitle("Lift progression", note: "one lift at a time")
            if m.lifts.isEmpty {
                empty("Log a lifting session and each lift gets its own curve.")
            } else {
                let series = m.lifts.first { $0.key == lift } ?? m.lifts[0]
                let ex = program.exercise(series.key)
                Picker("Lift", selection: Binding(get: { series.key }, set: { lift = $0 })) {
                    ForEach(m.lifts) { Text(program.exercise($0.key).shortName).tag($0.key) }
                }
                .pickerStyle(.menu).fieldStyle()
                let top = series.sessions.compactMap { s in s.top.map { TrendSeries.Point(date: Day.date(s.date), value: $0) } }
                if !top.isEmpty {
                    let change = top.last!.value - top.first!.value
                    StatLine(value: kg(top.last!.value), caption: top.count < 2 ? "top set" : change == 0 ? "top set, unchanged over \(top.count) sessions" : "top set, \(Fmt.signed(change, digits: change == change.rounded() ? 0 : 1)) kg over \(top.count) sessions", tone: change > 0 ? .ok : nil)
                    let estimate = series.sessions.compactMap { s in s.e1rm.map { TrendSeries.Point(date: Day.date(s.date), value: $0) } }
                    TrendChart(series: [TrendSeries(name: "Top set", color: Theme.Palette.series[0], points: top)]
                        + (ex.e1rm == true ? [TrendSeries(name: "Estimated 1RM", color: Theme.Palette.series[3], points: estimate)] : []), format: kg)
                } else {
                    let timed = ex.fields.contains("seconds")
                    let best = series.sessions.map { TrendSeries.Point(date: Day.date($0.date), value: Double(timed ? $0.seconds : $0.reps)) }
                    StatLine(value: "\(Int(best.last?.value ?? 0)) \(timed ? "s" : "reps")", caption: "best set, latest session")
                    TrendChart(series: [TrendSeries(name: timed ? "Best hold" : "Best set", color: Theme.Palette.series[0], points: best)], format: { "\(Int($0.rounded()))" })
                }
            }
        }
        .card()
    }

    @ViewBuilder
    private func running(_ m: Model, _ d: Dashboard, _ program: Program) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            CardTitle("Running", note: "pace per run, faster is higher")
            if m.runs.isEmpty {
                empty("Log a run with distance and time, or attach a Garmin file.")
            } else {
                if let last = m.runs.last { StatLine(value: Fmt.pace(last.pace), caption: "\(Fmt.number(last.km)) km on \(Day.short(last.date))") }
                // Easy runs and hard sessions are different paces on purpose, so each gets its own line.
                let hard = m.runs.filter { !$0.easy }.map { TrendSeries.Point(date: Day.date($0.date), value: $0.pace) }
                let easy = m.runs.filter { $0.easy }.map { TrendSeries.Point(date: Day.date($0.date), value: $0.pace) }
                TrendChart(series: (hard.isEmpty ? [] : [TrendSeries(name: "Intervals and tests", color: Theme.Palette.run, points: hard)])
                    + (easy.isEmpty ? [] : [TrendSeries(name: "Easy runs", color: Theme.Palette.ok, points: easy)]),
                           lowerIsBetter: true, height: 180, format: { Fmt.time($0) })
            }
            HeartRateZones(heartRate: program.heartRate)
        }
        .card()
    }

    private func kg(_ value: Double) -> String { Fmt.number((value * 10).rounded() / 10) + " kg" }

    @ViewBuilder
    private func bests(_ m: Model, _ program: Program) -> some View {
        let rows = m.lifts.compactMap { l -> (String, String)? in
            guard let top = l.sessions.compactMap(\.top).max(), top > 0 else { return nil }
            let e = l.sessions.compactMap(\.e1rm).max()
            return (program.exercise(l.key).name, "\(Fmt.number(top)) kg" + (program.exercise(l.key).e1rm == true ? e.map { " · e1RM \(Fmt.number($0.rounded()))" } ?? "" : ""))
        }
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                CardTitle("Personal bests", note: "heaviest set and best estimated 1RM")
                Divided { ForEach(rows, id: \.0) { r in Row(title: r.0) { Text(r.1).font(Theme.Typography.callout.monospacedDigit()).foregroundStyle(Theme.Palette.muted) } } }
            }
            .card()
        }
    }

    private func empty(_ text: String) -> some View { Text(text).font(Theme.Typography.callout).foregroundStyle(Theme.Palette.muted) }
}
