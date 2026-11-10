import SwiftUI

/// The landing page: a grid of data cards from the watch and from training. Which cards show, in what order and
/// at what width, is set in Customize and saved on the phone.
struct HomeScreen: View {
    let openToday: () -> Void
    @State private var model = HomeModel()
    @State private var customizing = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Screen {
            Text(Day.label(model.today, year: true)).font(Theme.Typography.callout).foregroundStyle(Theme.Palette.muted).padding(.horizontal, Theme.Space.xs)
            if let error = model.error, model.dash == nil { ErrorCard(message: error) { await model.load() } }
            if model.loaded, !model.hasWatchData { waiting }
            ForEach(model.rows, id: \.self) { row in
                if row.count == 1, row[0].wide || row[0].kind.alwaysWide {
                    card(row[0], wide: true)
                } else {
                    HStack(alignment: .top, spacing: Theme.Space.m) {
                        ForEach(row) { card($0, wide: false) }
                        if row.count == 1 { Color.clear.frame(maxWidth: .infinity) }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            if !model.loaded { ProgressView().frame(maxWidth: .infinity).padding(.top, 60) }
        }
        .navigationTitle("Home")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationLink { SettingsScreen() } label: { Image(systemName: "gearshape") }.accessibilityLabel("Settings")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { customizing = true } label: { Image(systemName: "square.grid.2x2") }.accessibilityLabel("Customize dashboard")
            }
        }
        .sheet(isPresented: $customizing) { CustomizeSheet(model: model) }
        .task { await model.load() }
        .refreshable { await model.load() }
        .onChange(of: scenePhase) { _, phase in if phase == .active, model.loaded { Task { await model.load() } } }
    }

    /// Shown until the first import from Garmin has arrived.
    private var waiting: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            CardHeader(kind: .all, title: "Watch data")
            Text("Nothing from your watch yet. The server fetches about four months from Garmin on its first sync, then keeps up every 30 minutes.").font(Theme.Typography.callout)
            if let message = model.syncMessage { Text(message).font(Theme.Typography.caption).foregroundStyle(Theme.Palette.muted) }
            Button(model.syncing ? "Checking Garmin" : "Check Garmin now") { Task { await model.syncGarmin() } }.buttonStyle(.tinted).disabled(model.syncing)
        }
        .card()
    }

    @ViewBuilder
    private func card(_ setting: CardSetting, wide: Bool) -> some View {
        Group {
            switch setting.kind {
            case .today: TodayCard(model: model, open: openToday)
            case .week: WeekCard(model: model)
            case .weight: WeightCard(model: model, wide: wide)
            case .nutrition: NutritionCard(model: model)
            case .sleep: SleepCard(model: model, wide: wide)
            case .intensity: IntensityCard(model: model, wide: wide)
            case .facts: FactsCard(model: model)
            case .all: AllMetricsCard(model: model)
            default: if let spec = MetricSpec.all[setting.kind] { MetricCard(model: model, kind: setting.kind, spec: spec, wide: wide) }
            }
        }
        .padding(Theme.Space.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }
}

// MARK: Card pieces

/// Icon and title in the card's colour, with an optional note or view on the right.
private struct CardHeader<Trailing: View>: View {
    let kind: CardKind
    var title: String? = nil
    @ViewBuilder var trailing: Trailing
    var body: some View {
        HStack(spacing: Theme.Space.xs) {
            Image(systemName: kind.icon).font(.caption.weight(.semibold))
            Text((title ?? kind.title).uppercased()).font(Theme.Typography.label).lineLimit(1).minimumScaleFactor(0.7)
            Spacer(minLength: Theme.Space.xs)
            trailing
        }
        .frame(height: 24) // the same with or without a ring, so values line up across a row
        .foregroundStyle(kind.tint)
    }
}

extension CardHeader where Trailing == EmptyView {
    init(kind: CardKind, title: String? = nil) { self.kind = kind; self.title = title; self.trailing = EmptyView() }
}

/// Big number with a small unit after it.
private struct BigValue: View {
    let value: String
    var unit: String = ""
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(value).font(Theme.Typography.timer).lineLimit(1).minimumScaleFactor(0.5)
            if !unit.isEmpty { Text(unit).font(Theme.Typography.callout).foregroundStyle(Theme.Palette.muted) }
        }
    }
}

private struct Caption: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View { Text(text).font(Theme.Typography.caption).foregroundStyle(Theme.Palette.muted).fixedSize(horizontal: false, vertical: true) }
}

/// "today", "yesterday" or the date a value is from, when it is not today's.
private func dayNote(_ date: String, today: String) -> String? {
    date == today ? nil : date == Day.add(today, -1) ? "yesterday" : Day.short(date)
}

// MARK: Watch metrics

/// Generic card for one daily metric: latest value, caption, and a chart of the last two weeks (a month when wide).
private struct MetricCard: View {
    let model: HomeModel
    let kind: CardKind
    let spec: MetricSpec
    let wide: Bool

    private func show(_ v: Double) -> String { spec.digits == 0 ? Fmt.whole(v * spec.scale) : String(format: "%.\(spec.digits)f", v * spec.scale) }

    var body: some View {
        let latest = model.latest(spec.key)
        let goal = latest.flatMap { l in spec.goalKey.flatMap { model.value($0, on: l.date) } }
        let chart = Spark(values: model.series(spec.key, wide ? 30 : 14).map { $0.map { $0 * spec.scale } }, style: spec.style, color: spec.tint, goal: goal.map { $0 * spec.scale }, height: wide ? 72 : 44)
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            CardHeader(kind: kind) {
                if let latest, let goal, goal > 0 { ProgressRing(progress: latest.value / goal, color: spec.tint, size: 22) }
            }
            if wide {
                HStack(alignment: .bottom, spacing: Theme.Space.l) {
                    VStack(alignment: .leading, spacing: 2) { BigValue(value: latest.map { show($0.value) } ?? "–", unit: spec.unit); Caption(caption(latest, goal)) }
                    chart
                }
            } else {
                BigValue(value: latest.map { show($0.value) } ?? "–", unit: spec.unit)
                chart
                Caption(caption(latest, goal))
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func caption(_ latest: (date: String, value: Double)?, _ goal: Double?) -> String {
        var parts: [String] = []
        if let latest, let note = dayNote(latest.date, today: model.today) { parts.append(note) }
        if let goal, goal > 0 { parts.append("goal \(show(goal))") }
        if let avg = model.average(spec.key, 7) { parts.append("7-day avg \(show(avg))") }
        if let extra = spec.extra, let latest, let v = model.value(extra.key, on: latest.date) { parts.append("\(extra.label) \(show(v))") }
        if kind == .hrv, let status = model.latestText("hrv.status") { parts.append(status.lowercased()) }
        if kind == .stress, let q = model.latestText("stress.qualifier") { parts.append(q.replacingOccurrences(of: "_", with: " ")) }
        return parts.joined(separator: " · ")
    }
}

private struct SleepCard: View {
    let model: HomeModel
    let wide: Bool
    var body: some View {
        let night = model.latest("sleep.sleepTimeSeconds")
        let stage = { (key: String) -> Double in night.flatMap { model.value("sleep.\(key)", on: $0.date) } ?? 0 }
        let stages: [(String, Double, Color)] = [("Deep", stage("deepSleepSeconds"), Theme.Palette.sleep), ("Light", stage("lightSleepSeconds"), Theme.Palette.sleep.opacity(0.55)),
                                                 ("REM", stage("remSleepSeconds"), Theme.Palette.calm), ("Awake", stage("awakeSleepSeconds"), Theme.Palette.energy.opacity(0.8))]
        let score = night.flatMap { model.value("sleep.sleepScores.overall.value", on: $0.date) }
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            CardHeader(kind: .sleep) { if let score { Text("score \(Fmt.whole(score))").font(Theme.Typography.label) } }
            HStack(alignment: .bottom, spacing: Theme.Space.l) {
                VStack(alignment: .leading, spacing: 2) {
                    BigValue(value: night.map { Fmt.hours($0.value) } ?? "–")
                    Caption([night.flatMap { dayNote($0.date, today: model.today) } ?? "last night", model.average("sleep.sleepTimeSeconds", 7).map { "7-day avg \(Fmt.hours($0))" }].compactMap { $0 }.joined(separator: " · "))
                }
                if wide { Spark(values: model.series("sleep.sleepTimeSeconds", 14).map { $0.map { $0 / 3600 } }, style: .bars, color: Theme.Palette.sleep, height: 56) }
            }
            if stages.contains(where: { $0.1 > 0 }) {
                SegmentBar(parts: stages.map { ($0.1, $0.2) })
                HStack(spacing: Theme.Space.m) {
                    ForEach(stages.filter { $0.1 > 0 }, id: \.0) { s in
                        HStack(spacing: 3) { Circle().fill(s.2).frame(width: 6, height: 6); Text("\(s.0) \(Fmt.time(s.1 / 60))").font(Theme.Typography.label).foregroundStyle(Theme.Palette.muted) }
                    }
                }
                .lineLimit(1).minimumScaleFactor(0.6)
            }
        }
    }
}

/// Minutes this week towards Garmin's weekly goal, where a vigorous minute counts twice.
private struct IntensityCard: View {
    let model: HomeModel
    let wide: Bool
    var body: some View {
        let monday = Day.monday(of: model.today)
        let week = (0..<7).compactMap { model.intensity(on: Day.add(monday, $0)) }.reduce(0, +)
        let goal = model.latest("intensityMinutes.goal")?.value ?? 150
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            CardHeader(kind: .intensity) { ProgressRing(progress: week / max(goal, 1), color: CardKind.intensity.tint, size: 22) }
            BigValue(value: Fmt.whole(week), unit: "min")
            Spark(values: model.series(wide ? 30 : 14) { model.intensity(on: $0) }, style: .bars, color: CardKind.intensity.tint, height: wide ? 72 : 44)
            Caption("this week · goal \(Fmt.whole(goal))")
        }
    }
}

// MARK: Training cards

private struct TodayCard: View {
    let model: HomeModel
    let open: () -> Void
    var body: some View {
        if let day = model.dash?.today {
            let t = day.template
            let workout = model.dash?.workouts.first { $0.date == day.date && $0.template_key == day.templateKey }
            Button(action: open) {
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    CardHeader(kind: .today) {
                        Badge(workout?.status == "done" ? "Done" : workout?.status == "skipped" ? "Skipped" : workout?.started_at != nil ? "In progress" : "Week \(max(day.week, 1))",
                              tone: workout?.status == "done" ? .ok : workout?.status == "skipped" ? .danger : .accent)
                    }
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(t.name).font(Theme.Typography.title).foregroundStyle(Theme.Palette.text)
                            if let s = t.subtitle { Caption(s) }
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.Palette.muted)
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }
}

/// Monday to Sunday with a dot for each day trained.
private struct WeekCard: View {
    let model: HomeModel
    var body: some View {
        let monday = Day.monday(of: model.today)
        let done = (model.dash?.workouts ?? []).filter { $0.status == "done" && $0.kind != "rest" }
        let count = Set(done.filter { $0.date >= monday && $0.date <= Day.add(monday, 6) }.map(\.date)).count
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            CardHeader(kind: .week) { Text("\(count) session\(count == 1 ? "" : "s") done").font(Theme.Typography.label) }
            HStack(spacing: Theme.Space.xs) {
                ForEach(0..<7, id: \.self) { i in
                    let date = Day.add(monday, i)
                    let kind = done.first { $0.date == date }?.kind
                    VStack(spacing: Theme.Space.xs) {
                        ZStack {
                            Circle().fill(kind.map { Theme.Palette.kind($0) } ?? Theme.Palette.fill)
                            if kind != nil { Image(systemName: "checkmark").font(.caption2.weight(.bold)).foregroundStyle(.white) }
                        }
                        .frame(width: 28, height: 28)
                        .overlay { if date == model.today { Circle().stroke(Theme.Palette.accent, lineWidth: 2).padding(-3) } }
                        Text(Day.label(date).prefix(3)).font(Theme.Typography.label).foregroundStyle(date == model.today ? Theme.Palette.text : Theme.Palette.muted)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

private struct WeightCard: View {
    let model: HomeModel
    let wide: Bool
    var body: some View {
        let byDay = Dictionary((model.dash?.body ?? []).compactMap { b in b.weight_kg.map { (b.date, $0) } }, uniquingKeysWith: { a, _ in a })
        let recent = (0..<7).compactMap { byDay[Day.add(model.today, -$0)] }
        let latestDate = byDay.keys.max()
        let avg = recent.isEmpty ? latestDate.flatMap { byDay[$0] } : recent.reduce(0, +) / Double(recent.count)
        let goal = model.dash?.settings.number("goal_weight_kg") ?? AppModel.shared.program?.body.goalWeightKg
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            CardHeader(kind: .weight)
            BigValue(value: avg.map { String(format: "%.1f", $0) } ?? "–", unit: "kg")
            Spark(values: model.series(wide ? 60 : 30) { byDay[$0] }, style: .line, color: CardKind.weight.tint, height: wide ? 72 : 44)
            Caption([recent.isEmpty ? latestDate.map { "last weighed \(Day.short($0))" } : "7-day avg", goal.flatMap { g in avg.map { String(format: "%.1f kg to goal", $0 - g) } }].compactMap { $0 }.joined(separator: " · "))
        }
    }
}

private struct NutritionCard: View {
    let model: HomeModel
    var body: some View {
        let program = AppModel.shared.program
        let day = model.dash?.nutrition.last { $0.date <= model.today }
        let kcalTarget = model.dash?.settings.number("calorie_target") ?? program?.nutrition.calories ?? 0
        let proteinTarget = model.dash?.settings.number("protein_target") ?? program?.nutrition.proteinG ?? 0
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            CardHeader(kind: .nutrition) { if let kcal = day?.calories, kcalTarget > 0 { ProgressRing(progress: kcal / kcalTarget, color: CardKind.nutrition.tint, size: 22) } }
            BigValue(value: Fmt.whole(day?.calories), unit: "kcal")
            Caption([day.flatMap { dayNote($0.date, today: model.today) }, kcalTarget > 0 ? "target \(Fmt.whole(kcalTarget))" : nil,
                     day?.protein_g.map { "protein \(Fmt.whole($0)) of \(Fmt.whole(proteinTarget)) g" }].compactMap { $0 }.joined(separator: " · "))
        }
    }
}

// MARK: Fun facts and the full list

private struct FactsCard: View {
    let model: HomeModel
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            CardHeader(kind: .facts)
            ForEach(Array(model.facts.enumerated()), id: \.offset) { _, fact in
                HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                    Image(systemName: fact.icon).font(.footnote).foregroundStyle(CardKind.facts.tint).frame(width: 20)
                    Text(fact.text).font(Theme.Typography.callout).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// Every metric stored for the latest day, including the ones that have no card of their own.
private struct AllMetricsCard: View {
    let model: HomeModel
    @State private var open = false
    var body: some View {
        let date = model.days.keys.max() ?? model.today
        let rows = (model.days[date] ?? [:]).sorted { $0.key < $1.key }
        DisclosureGroup(isExpanded: $open) {
            VStack(spacing: 0) {
                ForEach(rows, id: \.key) { key, value in
                    HStack(alignment: .firstTextBaseline) {
                        Text(Fmt.metricName(key)).font(Theme.Typography.caption).foregroundStyle(Theme.Palette.muted)
                        Spacer(minLength: Theme.Space.m)
                        Text(value.number.map { $0 == $0.rounded() ? Fmt.whole($0) : String(format: "%.1f", $0) } ?? value.text ?? "").font(Theme.Typography.caption.monospacedDigit())
                    }
                    .padding(.vertical, 3)
                }
            }
            .padding(.top, Theme.Space.s)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                CardHeader(kind: .all)
                Caption("\(rows.count) values for \(Day.label(date)), \(model.days.count) days stored")
            }
        }
        .tint(Theme.Palette.muted)
    }
}

// MARK: Customize

/// Reorder the cards, set each to half or full width, or hide it.
private struct CustomizeSheet: View {
    @Bindable var model: HomeModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach($model.layout) { $card in
                        HStack(spacing: Theme.Space.m) {
                            Image(systemName: card.kind.icon).foregroundStyle(card.kind.tint).frame(width: 24)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(card.kind.title).font(Theme.Typography.body).foregroundStyle(card.hidden ? Theme.Palette.muted : Theme.Palette.text)
                                if !model.hasData(card.kind) { Text("no data yet").font(Theme.Typography.caption).foregroundStyle(Theme.Palette.muted) }
                            }
                            Spacer(minLength: 0)
                            if !card.kind.alwaysWide {
                                Picker("Width", selection: $card.wide) { Text("Half").tag(false); Text("Full").tag(true) }.pickerStyle(.segmented).frame(width: 112)
                            }
                            Button { card.hidden.toggle() } label: {
                                Image(systemName: card.hidden ? "eye.slash" : "eye").font(.body.weight(.medium))
                                    .foregroundStyle(card.hidden ? Theme.Palette.muted : Theme.Palette.accent).frame(width: 36, height: 32)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel(card.hidden ? "Show \(card.kind.title)" : "Hide \(card.kind.title)")
                        }
                    }
                    .onMove { model.layout.move(fromOffsets: $0, toOffset: $1) }
                } footer: {
                    Text("Hold a card and drag to reorder. Two half-width cards in a row sit side by side. Cards without data stay hidden until your watch has some.")
                }
                Section { Button("Reset to the default layout", role: .destructive) { model.layout = CardSetting.defaults } }
            }
            .navigationTitle("Customize").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
