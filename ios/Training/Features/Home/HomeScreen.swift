import SwiftUI

/// The landing page: a grid of data widgets from the watch and from training.
///
/// Normal mode: touch and hold a widget for its settings (width, range of days shown, remove).
/// Edit mode (the grid button): widgets can be dragged to a new place, resized with the handle in their bottom
/// right corner, removed with the minus in their top left corner, and added with the plus button.
/// The layout is saved on the phone.
struct HomeScreen: View {
    let openToday: () -> Void
    @State private var model = HomeModel()
    @State private var editing = false
    @State private var adding = false
    @State private var dragging: CardKind?
    /// "Use this range for all widgets" asks twice: first this dialog, then an alert.
    @State private var askApply: Int?
    @State private var confirmApply: Int?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Screen {
            Text(editing ? "Drag to move. Use the corner handle to resize." : Day.label(model.today, year: true))
                .font(Theme.Typography.callout).foregroundStyle(Theme.Palette.muted).padding(.horizontal, Theme.Space.xs)
            if let error = model.error, model.dash == nil { ErrorCard(message: error) { await model.load() } }
            if model.loaded, !model.hasWatchData, !editing { waiting }
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
                if editing {
                    Button("Done") { withAnimation(.snappy) { editing = false; dragging = nil } }.fontWeight(.semibold)
                } else {
                    NavigationLink { SettingsScreen() } label: { Image(systemName: "gearshape") }.accessibilityLabel("Settings")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                if editing {
                    Button { adding = true } label: { Image(systemName: "plus") }.accessibilityLabel("Add widget")
                } else {
                    Button { startEditing() } label: { Image(systemName: "square.grid.2x2") }.accessibilityLabel("Edit dashboard")
                }
            }
        }
        .sheet(isPresented: $adding) { AddWidgetSheet(model: model).presentationDetents([.medium, .large]) }
        .confirmationDialog("Use \(RangeOption.label(askApply ?? 0)) for all widgets?", isPresented: Binding(get: { askApply != nil }, set: { if !$0 { askApply = nil } }), titleVisibility: .visible, presenting: askApply) { days in
            Button("Apply to all widgets") {
                // Second check, shown once this dialog has closed.
                Task { try? await Task.sleep(for: .milliseconds(400)); confirmApply = days }
            }
        } message: { _ in Text("Every widget with a chart will show this range.") }
        .alert("Are you sure?", isPresented: Binding(get: { confirmApply != nil }, set: { if !$0 { confirmApply = nil } }), presenting: confirmApply) { days in
            Button("Yes, change all widgets", role: .destructive) { withAnimation { model.applyRangeToAll(days) } }
            Button("Cancel", role: .cancel) {}
        } message: { days in
            Text("This replaces the range on \(model.layout.filter { $0.kind.hasRange && !$0.hidden }.count) widgets with \(RangeOption.label(days)). Ranges you set one by one will be lost.")
        }
        .task { await model.load() }
        .refreshable { await model.load() }
        .onChange(of: scenePhase) { _, phase in if phase == .active, model.loaded { Task { await model.load() } } }
    }

    private func startEditing() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.snappy) { editing = true }
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

    // MARK: One widget

    @ViewBuilder
    private func card(_ setting: CardSetting, wide: Bool) -> some View {
        let surface = content(setting, wide: wide)
            .allowsHitTesting(!editing) // while editing, touches move and resize the widget instead
            .padding(Theme.Space.l)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .contentShape(.dragPreview, RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        if editing {
            surface
                .opacity(dragging == setting.kind ? 0.4 : 1)
                .overlay(alignment: .topLeading) { removeButton(setting) }
                .overlay(alignment: .bottomTrailing) { if !setting.kind.alwaysWide { resizeHandle(setting) } }
                .modifier(Wiggle())
                .onDrag { dragging = setting.kind; return NSItemProvider(object: setting.id as NSString) }
                .onDrop(of: [.text], delegate: ReorderDrop(target: setting.kind, model: model, dragging: $dragging))
        } else {
            surface.contextMenu { menu(setting) }
        }
    }

    @ViewBuilder
    private func content(_ setting: CardSetting, wide: Bool) -> some View {
        switch setting.kind {
        case .today: TodayCard(model: model, open: openToday)
        case .week: WeekCard(model: model)
        case .weight: WeightCard(model: model, setting: setting, wide: wide)
        case .nutrition: NutritionCard(model: model, setting: setting, wide: wide)
        case .sleep: SleepCard(model: model, setting: setting, wide: wide)
        case .intensity: IntensityCard(model: model, setting: setting, wide: wide)
        case .facts: FactsCard(model: model)
        case .all: AllMetricsCard(model: model)
        default: if let spec = MetricSpec.all[setting.kind] { MetricCard(model: model, setting: setting, spec: spec, wide: wide) }
        }
    }

    /// Minus in the top left corner: takes the widget off the dashboard. It can be added back with the plus button.
    private func removeButton(_ setting: CardSetting) -> some View {
        Button { withAnimation(.snappy) { model.update(setting.kind) { $0.hidden = true } } } label: {
            Image(systemName: "minus").font(.caption.weight(.heavy)).foregroundStyle(.white)
                .frame(width: 26, height: 26).background(Theme.Palette.rest, in: Circle())
                .overlay(Circle().stroke(Theme.Palette.background, lineWidth: 2))
                .padding(8).contentShape(Rectangle())
        }
        .buttonStyle(.plain).offset(x: -14, y: -14)
        .accessibilityLabel("Remove \(setting.kind.title)")
    }

    /// Handle in the bottom right corner: drag it outwards for full width, inwards for half, or tap to switch.
    private func resizeHandle(_ setting: CardSetting) -> some View {
        let set = { (wide: Bool) in
            guard wide != setting.wide else { return }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.snappy) { model.update(setting.kind) { $0.wide = wide } }
        }
        return Image(systemName: setting.wide ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
            .font(.caption.weight(.bold)).foregroundStyle(.white)
            .frame(width: 30, height: 30).background(Theme.Palette.accent, in: Circle())
            .overlay(Circle().stroke(Theme.Palette.background, lineWidth: 2))
            .padding(8).contentShape(Rectangle())
            .onTapGesture { set(!setting.wide) }
            .highPriorityGesture(DragGesture(minimumDistance: 12).onEnded { drag in
                if drag.translation.width > 24 { set(true) } else if drag.translation.width < -24 { set(false) }
            })
            .offset(x: 12, y: 12)
            .accessibilityLabel(setting.wide ? "Make \(setting.kind.title) half width" : "Make \(setting.kind.title) full width")
            .accessibilityAddTraits(.isButton)
    }

    /// Settings for one widget, on touch and hold.
    @ViewBuilder
    private func menu(_ setting: CardSetting) -> some View {
        if !setting.kind.alwaysWide {
            Picker("Width", selection: Binding(get: { setting.wide }, set: { wide in withAnimation(.snappy) { model.update(setting.kind) { $0.wide = wide } } })) {
                Label("Half width", systemImage: "rectangle.split.2x1").tag(false)
                Label("Full width", systemImage: "rectangle").tag(true)
            }
        }
        if setting.kind.hasRange {
            Menu {
                Picker("Range", selection: Binding(get: { setting.range }, set: { days in withAnimation { model.setRange(setting.kind, days) } })) {
                    Text("Default").tag(Int?.none)
                    ForEach(RangeOption.all) { Text("Last \($0.label)").tag(Int?.some($0.days)) }
                }
            } label: {
                Label("Range: \(setting.range.map { RangeOption.label($0) } ?? "default")", systemImage: "calendar")
            }
            Menu {
                Picker("Resolution", selection: Binding(get: { setting.resolution }, set: { days in withAnimation { model.update(setting.kind) { $0.resolution = days } } })) {
                    Text("Auto").tag(Int?.none)
                    ForEach(ResolutionOption.all) { Text($0.label).tag(Int?.some($0.days)) }
                }
            } label: {
                Label("Resolution: \(ResolutionOption.label(setting.resolution))", systemImage: "chart.bar.xaxis")
            }
            Menu {
                Picker("Chart", selection: Binding(get: { setting.chart }, set: { kind in withAnimation { model.update(setting.kind) { $0.chart = kind } } })) {
                    Text("Default").tag(String?.none)
                    Label("Bars", systemImage: "chart.bar.fill").tag(String?.some("bars"))
                    Label("Line", systemImage: "chart.xyaxis.line").tag(String?.some("line"))
                }
            } label: {
                Label("Chart: \(setting.chart ?? "default")", systemImage: setting.chart == "line" ? "chart.xyaxis.line" : "chart.bar.fill")
            }
            if let days = setting.range {
                Button { askApply = days } label: { Label("Use \(RangeOption.label(days)) for all widgets", systemImage: "square.on.square") }
            }
        }
        Divider()
        Button { startEditing() } label: { Label("Edit dashboard", systemImage: "square.grid.2x2") }
        Button(role: .destructive) { withAnimation(.snappy) { model.update(setting.kind) { $0.hidden = true } } } label: { Label("Remove widget", systemImage: "minus.circle") }
    }
}

/// Moves the dragged widget to the place of the widget it is dragged over.
private struct ReorderDrop: DropDelegate {
    let target: CardKind
    let model: HomeModel
    @Binding var dragging: CardKind?

    func dropEntered(info: DropInfo) {
        guard let dragging, dragging != target,
              let from = model.layout.firstIndex(where: { $0.kind == dragging }), let to = model.layout.firstIndex(where: { $0.kind == target }) else { return }
        withAnimation(.snappy) { model.layout.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to) }
    }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
    func performDrop(info: DropInfo) -> Bool { dragging = nil; return true }
}

/// The small rocking motion of widgets in edit mode.
private struct Wiggle: ViewModifier {
    @State private var on = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(reduceMotion ? 0 : on ? 0.45 : -0.45))
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.16).repeatForever(autoreverses: true), value: on)
            .onAppear { on = true }
    }
}

/// The widgets that are not on the dashboard, to add back.
private struct AddWidgetSheet: View {
    let model: HomeModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        let hidden = model.layout.filter(\.hidden)
        NavigationStack {
            ScrollView {
                if hidden.isEmpty {
                    Text("Every widget is already on your dashboard.").font(Theme.Typography.callout).foregroundStyle(Theme.Palette.muted).padding(.top, 40)
                }
                LazyVGrid(columns: [GridItem(.flexible(), spacing: Theme.Space.m), GridItem(.flexible())], spacing: Theme.Space.m) {
                    ForEach(hidden) { card in
                        Button { withAnimation(.snappy) { model.add(card.kind) } } label: {
                            VStack(alignment: .leading, spacing: Theme.Space.s) {
                                HStack {
                                    Image(systemName: card.kind.icon).font(.title3).foregroundStyle(card.kind.tint)
                                    Spacer()
                                    Image(systemName: "plus.circle.fill").font(.title3).foregroundStyle(Theme.Palette.ok)
                                }
                                Text(card.kind.title).font(Theme.Typography.headline).foregroundStyle(Theme.Palette.text).multilineTextAlignment(.leading)
                                Text(model.hasData(card.kind) ? " " : "no data yet").font(Theme.Typography.caption).foregroundStyle(Theme.Palette.muted)
                            }
                            .padding(Theme.Space.m).frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Add \(card.kind.title)")
                    }
                }
                .padding(Theme.Space.l)
            }
            .screenBackground()
            .navigationTitle("Add widgets").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
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
    let setting: CardSetting
    let spec: MetricSpec
    let wide: Bool
    private var kind: CardKind { setting.kind }

    private func show(_ v: Double) -> String { spec.digits == 0 ? Fmt.whole(v * spec.scale) : String(format: "%.\(spec.digits)f", v * spec.scale) }

    var body: some View {
        let latest = model.latest(spec.key)
        let goal = latest.flatMap { l in spec.goalKey.flatMap { model.value($0, on: l.date) } }
        let sparse = kind == .bodyFat || kind == .leanMass // weighed now and then, so show a longer stretch
        let span = setting.range ?? (sparse ? (wide ? 120 : 60) : wide ? 30 : 14)
        let chart = Spark(values: model.chart(span, wide: wide, every: setting.resolution) { day in model.value(spec.key, on: day).map { $0 * spec.scale } }, style: setting.style ?? spec.style, color: spec.tint, goal: goal.map { $0 * spec.scale }, height: wide ? 72 : 44)
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            CardHeader(kind: kind) {
                if let latest, let goal, goal > 0 { ProgressRing(progress: latest.value / goal, color: spec.tint, size: 22) }
            }
            if wide, chart.values.count > 45 {
                // A chart with many points needs the whole width of the widget, so it goes under the value.
                HStack(alignment: .firstTextBaseline, spacing: Theme.Space.m) { BigValue(value: latest.map { show($0.value) } ?? "–", unit: spec.unit); Caption(caption(latest, goal)) }
                chart
            } else if wide {
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
        if kind == .bodyFat || kind == .leanMass { parts.append("from your scale") } else if let avg = model.average(spec.key, setting.range ?? 7) { parts.append("\(setting.range.map { RangeOption.label($0) } ?? "7-day") avg \(show(avg))") }
        if let extra = spec.extra, let latest, let v = model.value(extra.key, on: latest.date) { parts.append("\(extra.label) \(show(v))") }
        if kind == .hrv, let status = model.latestText("hrv.status") { parts.append(status.lowercased()) }
        if kind == .stress, let q = model.latestText("stress.qualifier") { parts.append(q.replacingOccurrences(of: "_", with: " ")) }
        return parts.joined(separator: " · ")
    }
}

private struct SleepCard: View {
    let model: HomeModel
    let setting: CardSetting
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
                    Caption([night.flatMap { dayNote($0.date, today: model.today) } ?? "last night", model.average("sleep.sleepTimeSeconds", setting.range ?? 7).map { "\(setting.range.map { RangeOption.label($0) } ?? "7-day") avg \(Fmt.hours($0))" }].compactMap { $0 }.joined(separator: " · "))
                }
                if wide, !longDaily { nights(56) }
            }
            if !wide || longDaily { nights(wide ? 64 : 44) } // a long night-by-night chart gets the full width
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
    /// More nights than fit beside the value, each drawn on its own.
    private var longDaily: Bool { wide && model.chart(setting.range ?? 14, wide: wide, every: setting.resolution) { _ in nil }.count > 45 }

    /// Hours slept per night over the widget's range (weekly averages when there are too many nights to draw).
    private func nights(_ height: CGFloat) -> some View {
        Spark(values: model.chart(setting.range ?? 14, wide: wide, every: setting.resolution) { day in model.value("sleep.sleepTimeSeconds", on: day).map { $0 / 3600 } }, style: setting.style ?? .bars, color: Theme.Palette.sleep, height: height)
    }
}

/// Minutes this week towards Garmin's weekly goal, where a vigorous minute counts twice.
private struct IntensityCard: View {
    let model: HomeModel
    let setting: CardSetting
    let wide: Bool
    var body: some View {
        let monday = Day.monday(of: model.today)
        let week = (0..<7).compactMap { model.intensity(on: Day.add(monday, $0)) }.reduce(0, +)
        let goal = model.latest("intensityMinutes.goal")?.value ?? 150
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            CardHeader(kind: .intensity) { ProgressRing(progress: week / max(goal, 1), color: CardKind.intensity.tint, size: 22) }
            BigValue(value: Fmt.whole(week), unit: "min")
            Spark(values: model.chart(setting.range ?? (wide ? 30 : 14), wide: wide, every: setting.resolution) { model.intensity(on: $0) }, style: setting.style ?? .bars, color: CardKind.intensity.tint, height: wide ? 72 : 44)
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
    let setting: CardSetting
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
            Spark(values: model.chart(setting.range ?? (wide ? 60 : 30), wide: wide, every: setting.resolution) { byDay[$0] }, style: setting.style ?? .line, color: CardKind.weight.tint, height: wide ? 72 : 44)
            Caption([recent.isEmpty ? latestDate.map { "last weighed \(Day.short($0))" } : "7-day avg", goal.flatMap { g in avg.map { String(format: "%.1f kg to goal", $0 - g) } }].compactMap { $0 }.joined(separator: " · "))
        }
    }
}

private struct NutritionCard: View {
    let model: HomeModel
    let setting: CardSetting
    let wide: Bool
    var body: some View {
        let program = AppModel.shared.program
        let day = model.dash?.nutrition.last { $0.date <= model.today }
        let byDay = Dictionary((model.dash?.nutrition ?? []).compactMap { n in n.calories.map { (n.date, $0) } }, uniquingKeysWith: { a, _ in a })
        let kcalTarget = model.dash?.settings.number("calorie_target") ?? program?.nutrition.calories ?? 0
        let proteinTarget = model.dash?.settings.number("protein_target") ?? program?.nutrition.proteinG ?? 0
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            CardHeader(kind: .nutrition) { if let kcal = day?.calories, kcalTarget > 0 { ProgressRing(progress: kcal / kcalTarget, color: CardKind.nutrition.tint, size: 22) } }
            BigValue(value: Fmt.whole(day?.calories), unit: "kcal")
            Spark(values: model.chart(setting.range ?? (wide ? 30 : 14), wide: wide, every: setting.resolution) { date in byDay[date] }, style: setting.style ?? .bars, color: CardKind.nutrition.tint, goal: kcalTarget > 0 ? kcalTarget : nil, height: wide ? 72 : 44)
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
