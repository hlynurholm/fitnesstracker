import Charts
import SwiftUI

/// Targets, what MyFitnessPal says was eaten, how the scale responded, and the latest diet note. From GET /api/diet.
struct DietScreen: View {
    @State private var data: Diet?
    @State private var error: String?
    @State private var span = 42
    @State private var openDay: NutritionDay?

    var body: some View {
        Screen {
            if let d = data {
                tiles(d)
                targets(d)
                if d.nutrition.isEmpty {
                    VStack(alignment: .leading, spacing: Theme.Space.s) {
                        CardTitle("Nothing logged yet")
                        Text("Upload a MyFitnessPal export on the Data tab and the intake chart and weekly averages fill in here. Weigh-ins from the Today tab are used for the weight side.").font(Theme.Typography.callout).foregroundStyle(Theme.Palette.muted)
                    }.card()
                } else {
                    intake(d)
                    weeks(d)
                    days(d)
                }
                dayTemplate(d)
                if let r = d.report {
                    VStack(alignment: .leading, spacing: Theme.Space.s) {
                        CardTitle("Claude's diet notes", note: Day.short(r.date ?? String((r.created_at ?? "").prefix(10))))
                        Text(r.title).font(Theme.Typography.headline)
                        MarkdownText(r.body_md ?? "")
                    }.card()
                }
            } else if let error {
                ErrorCard(message: error) { await load() }
            } else {
                ProgressView().frame(maxWidth: .infinity).padding(.top, 80)
            }
        }
        .navigationTitle("Diet")
        .task { await load() }
        .refreshable { await load() }
        .sheet(item: $openDay) { n in dayDetail(n).presentationDetents([.medium, .large]) }
    }

    private func load() async {
        do { data = try await API.shared.get("/api/diet?days=120", cache: true); error = nil } catch { self.error = error.localizedDescription }
    }

    private func tiles(_ d: Diet) -> some View {
        let t = d.targets, today = Day.today()
        let todayRow = d.nutrition.first { $0.date == today }
        let last7 = d.nutrition.filter { $0.date > Day.add(today, -7) && $0.date <= today }
        let kcal = last7.isEmpty ? nil : last7.compactMap(\.calories).reduce(0, +) / Double(last7.count)
        let protein = last7.isEmpty ? nil : last7.compactMap(\.protein_g).reduce(0, +) / Double(last7.count)
        let lastChange = d.weeks.last { $0.weight_change != nil }?.weight_change
        return TileGrid {
            Tile(label: "Today", value: todayRow.map { "\(Fmt.whole($0.calories)) kcal" } ?? "–", detail: todayRow.map { "\(Fmt.whole($0.protein_g)) g protein · \(Fmt.signed(($0.calories ?? 0) - t.calories)) vs target" } ?? "no MyFitnessPal day yet")
            Tile(label: "7-day average", value: kcal.map { "\(Fmt.whole($0)) kcal" } ?? "–", detail: kcal.map { "\(Fmt.signed($0 - t.calories)) vs target · \(last7.count) of 7 days" } ?? "upload an export")
            Tile(label: "Protein, 7-day", value: protein.map { "\(Fmt.whole($0)) g" } ?? "–", detail: protein.map { "\(Fmt.signed($0 - t.protein_g)) g vs target" } ?? "target \(Fmt.whole(t.protein_g)) g", tone: (protein ?? .infinity) < t.protein_g - 20 ? .warn : nil)
            Tile(label: "Expected loss", value: "\(Fmt.number(t.loss_per_week_kg.first)) to \(Fmt.number(t.loss_per_week_kg.last)) kg", detail: lastChange.map { "a week. Last week \(Fmt.signed($0, digits: 1)) kg" } ?? "a week")
        }
    }

    private func targets(_ d: Diet) -> some View {
        let t = d.targets
        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            CardTitle("Targets", note: "from the plan")
            Divided {
                value("Calories", "\(Fmt.whole(t.calories)) kcal a day", "about \(Fmt.whole(t.maintenance_estimate - t.calories)) under the \(Fmt.whole(t.maintenance_estimate)) kcal maintenance estimate")
                value("Protein", "\(Fmt.whole(t.protein_g)) g a day", "spread over 3 to 4 meals, 40 to 50 g each")
                value("Fun budget", "\(Fmt.whole(t.fun_budget_week_kcal)) kcal a week", "already inside the daily target")
                value("Weight", "\(Fmt.number(t.loss_per_week_kg.first)) to \(Fmt.number(t.loss_per_week_kg.last)) kg a week", "goal \(Fmt.number(t.goal_weight_kg)) kg. Read only the weekly average")
            }
            if let note = AppModel.shared.program?.nutrition.note { Text(note).font(Theme.Typography.caption).foregroundStyle(Theme.Palette.muted) }
        }
        .card()
    }

    private func value(_ title: String, _ value: String, _ sub: String) -> some View {
        Row(title: title, subtitle: sub) { Text(value).font(Theme.Typography.callout).multilineTextAlignment(.trailing) }
    }

    private func intake(_ d: Diet) -> some View {
        let t = d.targets
        let rows = d.nutrition.suffix(span)
        return VStack(alignment: .leading, spacing: Theme.Space.m) {
            CardTitle("Intake", note: "kcal per day")
            Picker("Span", selection: $span) { Text("6 weeks").tag(42); Text("12 weeks").tag(84); Text("All").tag(120) }.pickerStyle(.segmented)
            Chart {
                ForEach(rows) { n in
                    BarMark(x: .value("Date", Day.date(n.date), unit: .day), y: .value("kcal", n.calories ?? 0))
                        .foregroundStyle((n.calories ?? 0) > t.calories + 150 ? Theme.Palette.danger.opacity(0.7) : Theme.Palette.warn.opacity(0.75))
                }
                RuleMark(y: .value("Target", t.calories)).foregroundStyle(Theme.Palette.muted).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .annotation(position: .top, alignment: .leading) { Text("target \(Fmt.whole(t.calories))").font(Theme.Typography.label).foregroundStyle(Theme.Palette.muted) }
            }
            .frame(height: 180)
            Text("Protein, g per day").font(Theme.Typography.caption).foregroundStyle(Theme.Palette.muted)
            Chart {
                ForEach(rows) { n in
                    if let p = n.protein_g { LineMark(x: .value("Date", Day.date(n.date)), y: .value("g", p)).foregroundStyle(Theme.Palette.ok) }
                }
                RuleMark(y: .value("Target", t.protein_g)).foregroundStyle(Theme.Palette.muted).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .frame(height: 120)
        }
        .card()
    }

    private func weeks(_ d: Diet) -> some View {
        let t = d.targets
        return VStack(alignment: .leading, spacing: Theme.Space.m) {
            CardTitle("Weeks", note: "averages and the scale")
            Grid(alignment: .trailing, horizontalSpacing: Theme.Space.m, verticalSpacing: Theme.Space.s) {
                GridRow { Text("Week").gridColumnAlignment(.leading); Text("Days"); Text("kcal"); Text("Protein"); Text("Weight"); Text("±") }
                    .font(Theme.Typography.label).foregroundStyle(Theme.Palette.muted)
                ForEach(d.weeks.filter { $0.days_logged > 0 || $0.weigh_ins > 0 }.suffix(10).reversed()) { w in
                    GridRow {
                        Text(w.week >= 1 ? "Wk \(w.week)" : "Before")
                        Text("\(w.days_logged)")
                        Text(w.kcal_avg.map { Fmt.whole($0) } ?? "–").foregroundStyle((w.kcal_avg ?? 0) > t.calories + 150 ? Theme.Palette.danger : Theme.Palette.text)
                        Text(w.protein_avg.map { "\(Fmt.whole($0)) g" } ?? "–").foregroundStyle((w.protein_avg ?? .infinity) < t.protein_g - 20 ? Theme.Palette.warn : Theme.Palette.text)
                        Text(w.weight_avg.map { String(format: "%.1f", $0) } ?? "–")
                        Text(w.weight_change.map { Fmt.signed($0, digits: 1) } ?? "–").foregroundStyle((w.weight_change ?? 0) <= -0.3 ? Theme.Palette.ok : (w.weight_change ?? 0) > 0.2 ? Theme.Palette.danger : Theme.Palette.text)
                    }
                    .font(Theme.Typography.callout.monospacedDigit())
                }
            }
            Text("Red kcal: more than 150 over target. Orange protein: more than 20 g under.").font(Theme.Typography.caption).foregroundStyle(Theme.Palette.muted)
        }
        .card()
    }

    private func days(_ d: Diet) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            CardTitle("Last 14 days", note: "tap a day for its meals")
            Divided {
                ForEach(d.nutrition.suffix(14).reversed()) { n in
                    let over = (n.calories ?? 0) - d.targets.calories
                    Button { openDay = n } label: {
                        Row(title: Day.label(n.date), subtitle: "\(Fmt.whole(n.protein_g)) g protein · \(Fmt.whole(n.carbs_g)) g carbs · \(Fmt.whole(n.fat_g)) g fat") {
                            VStack(alignment: .trailing) {
                                Text("\(Fmt.whole(n.calories)) kcal").font(Theme.Typography.callout)
                                Text(Fmt.signed(over)).font(Theme.Typography.caption).foregroundStyle(over > 150 ? Theme.Palette.danger : over < -300 ? Theme.Palette.warn : Theme.Palette.muted)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .card()
    }

    private func dayDetail(_ n: NutritionDay) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                Text(Day.label(n.date, year: true)).font(Theme.Typography.title)
                Text("\(Fmt.whole(n.calories)) kcal of \(Fmt.whole(data?.targets.calories)) · \(Fmt.whole(n.protein_g)) g protein of \(Fmt.whole(data?.targets.protein_g))").font(Theme.Typography.callout).foregroundStyle(Theme.Palette.muted)
                if let meals = n.meals, !meals.isEmpty {
                    Divided {
                        ForEach(Array(meals.enumerated()), id: \.offset) { _, m in
                            Row(title: m.meal ?? "Meal", subtitle: m.note) { Text("\(Fmt.whole(m.calories ?? 0)) kcal · \(Fmt.whole(m.protein_g ?? 0)) g").font(Theme.Typography.callout.monospacedDigit()) }
                        }
                    }
                } else {
                    Text("No meal breakdown in this export, only the day totals.").font(Theme.Typography.callout).foregroundStyle(Theme.Palette.muted)
                }
            }
            .padding(Theme.Space.xl)
        }
    }

    private func dayTemplate(_ d: Diet) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            CardTitle("A day that hits the numbers", note: "from the plan")
            Divided {
                ForEach(d.day_template, id: \.self) { r in
                    Row(title: r.when, subtitle: r.what) { Text("\(Fmt.whole(r.kcal)) kcal" + ((r.protein ?? 0) > 0 ? "\n\(Fmt.whole(r.protein)) g" : "")).font(Theme.Typography.callout.monospacedDigit()).multilineTextAlignment(.trailing) }
                }
                Row(title: "Total") { Text("\(Fmt.whole(d.day_template.map(\.kcal).reduce(0, +))) kcal · \(Fmt.whole(d.day_template.compactMap(\.protein).reduce(0, +))) g").font(Theme.Typography.callout.monospacedDigit()) }
            }
        }
        .card()
    }
}

/// Small Markdown renderer for reports: headings, bullets and inline styles. Tables and HTML show as plain text.
struct MarkdownText: View {
    let source: String
    init(_ source: String) { self.source = source }
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            ForEach(Array(source.components(separatedBy: "\n").enumerated()), id: \.offset) { _, raw in
                let line = raw.trimmingCharacters(in: .whitespaces)
                let level = line.prefix { $0 == "#" }.count
                if line.isEmpty {
                    EmptyView()
                } else if level > 0 {
                    inline(String(line.dropFirst(level))).font(level == 1 ? Theme.Typography.title : Theme.Typography.headline).padding(.top, Theme.Space.xs)
                } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                    HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) { Text("•"); inline(String(line.dropFirst(2))) }.font(Theme.Typography.callout)
                } else {
                    inline(line).font(Theme.Typography.callout)
                }
            }
        }
    }

    private func inline(_ s: String) -> Text {
        Text((try? AttributedString(markdown: s.trimmingCharacters(in: .whitespaces), options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s))
    }
}
