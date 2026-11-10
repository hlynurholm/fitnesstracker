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
        var runs: [(date: String, pace: Double, km: Double)] = []
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
                return (w.date, s / km, km)
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
            CardTitle("Body weight", note: "daily, 7-day average and goal")
            if m.weights.count < 2 {
                empty("Log your morning weight on the Today tab and the trend shows up here.")
            } else {
                Chart {
                    ForEach(m.weights) { PointMark(x: .value("Date", $0.date), y: .value("kg", $0.value)).foregroundStyle(Theme.Palette.muted).symbolSize(20) }
                    ForEach(m.rolling) { LineMark(x: .value("Date", $0.date), y: .value("kg", $0.value)).foregroundStyle(Theme.Palette.accent).interpolationMethod(.catmullRom) }
                    RuleMark(y: .value("Goal", goal)).foregroundStyle(Theme.Palette.ok).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .annotation(position: .top, alignment: .leading) { Text("Goal \(Fmt.number(goal)) kg").font(Theme.Typography.label).foregroundStyle(Theme.Palette.ok) }
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .frame(height: 200)
            }
        }
        .card()
    }

    private func sessions(_ m: Model) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            CardTitle("Sessions", note: "days trained per week")
            Chart(m.weeks, id: \.week) {
                BarMark(x: .value("Week", "W\($0.week)"), y: .value("Done", $0.done)).foregroundStyle(Theme.Palette.accent)
            }
            .chartYScale(domain: 0...7)
            .frame(height: 140)
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
                let weighted = series.sessions.contains { $0.top != nil }
                Chart(series.sessions, id: \.date) { s in
                    if weighted {
                        if let v = s.top { LineMark(x: .value("Date", Day.date(s.date)), y: .value("kg", v), series: .value("s", "Top set")).foregroundStyle(by: .value("s", "Top set")).symbol(.circle) }
                        if ex.e1rm == true, let v = s.e1rm { LineMark(x: .value("Date", Day.date(s.date)), y: .value("kg", v), series: .value("s", "Estimated 1RM")).foregroundStyle(by: .value("s", "Estimated 1RM")).symbol(.circle) }
                    } else {
                        LineMark(x: .value("Date", Day.date(s.date)), y: .value("Best", ex.fields.contains("seconds") ? s.seconds : s.reps)).foregroundStyle(Theme.Palette.accent).symbol(.circle)
                    }
                }
                .chartForegroundStyleScale(["Top set": Theme.Palette.series[0], "Estimated 1RM": Theme.Palette.series[1]])
                .chartYScale(domain: .automatic(includesZero: false))
                .frame(height: 200)
            }
        }
        .card()
    }

    @ViewBuilder
    private func running(_ m: Model, _ d: Dashboard, _ program: Program) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            CardTitle("Running", note: "pace per run, lower is faster")
            if m.runs.isEmpty {
                empty("Log a run with distance and time, or attach a Garmin file.")
            } else {
                Chart(m.runs, id: \.date) {
                    LineMark(x: .value("Date", Day.date($0.date)), y: .value("Pace", $0.pace)).foregroundStyle(Theme.Palette.run).symbol(.circle)
                }
                .chartYScale(domain: .automatic(includesZero: false, reversed: true))
                .chartYAxis { AxisMarks { v in AxisGridLine(); AxisValueLabel { if let s = v.as(Double.self) { Text(Fmt.time(s)) } } } }
                .frame(height: 180)
            }
            HeartRateZones(heartRate: program.heartRate)
        }
        .card()
    }

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
