import SwiftUI

/// One day: the planned session, logging, and everything around it. Used by the Today tab and pushed from the calendar.
///
/// Switching days never blanks the screen: the day on screen stays until the next one has loaded, then the content
/// under the week strip is swapped in one step.
struct DayScreen: View {
    @State var date: String
    /// The Today tab's own screen (shows the Settings gear), as opposed to a day pushed from the calendar.
    var isRoot = false
    @State private var model: DayModel?

    var body: some View {
        Group {
            if let model {
                DayContent(model: model, selected: date, isRoot: isRoot) { date = $0 }
            } else {
                Screen { ProgressView().frame(maxWidth: .infinity).padding(.top, 80) }
                    .navigationTitle(date == Day.today() ? "Today" : Day.label(date))
            }
        }
        .task(id: date) {
            if let model, model.date == date { await model.load(); return } // back on this screen: refresh in place
            let next = DayModel(date: date, program: AppModel.shared.program!)
            if model == nil {
                // Nothing on screen yet: show the saved copy of the day straight away.
                next.showCached()
                if next.data != nil { model = next }
            }
            await next.load()
            if !Task.isCancelled { model = next }
        }
    }
}

private struct DayContent: View {
    @Bindable var model: DayModel
    /// The day that was asked for. It can be one step ahead of `model.date` while that day loads.
    let selected: String
    let isRoot: Bool
    let go: (String) -> Void
    @State private var showChange = false
    @State private var showFinish = false
    @State private var confirmDelete = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Screen {
            if let day = model.day {
                // The week strip keeps its identity across days, so it never redraws from scratch.
                WeekStrip(week: model.data?.week ?? [], selected: selected, go: go)
                // Beyond the concrete planning window there is no session yet, only an outlook.
                if Outlook(day.horizon) != .concrete, !day.moved, (model.data?.workouts ?? []).isEmpty {
                    OutlookCard(day: day).id(model.date)
                    if let projection = model.data?.projection, !projection.lines.isEmpty { ProjectionCard(projection: projection) }
                } else {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    if API.shared.offline { Banner("Offline: showing the last saved copy of this day. New entries are saved on the phone and synced later.") }
                    header(day)
                    ForEach(model.data?.recorded ?? []) { RunCard(activity: $0) }
                    WeightCard(model: model)
                    session(day)
                    others
                    if day.testWeek { TestsCard(model: model) }
                    if model.template.kind != "lift" { ChecklistCard(model: model, block: "knee", title: model.program.kneeRoutine.title, note: (model.program.kneeRoutine.note ?? "") + (model.template.kind == "run" ? " Optional after the run." : ""), items: model.program.kneeRoutine.items.map { .init(id: $0.id, text: $0.text) }) }
                }
                .id(model.date) // per-day field state (typed weight, open notes) starts fresh for each day
                }
            } else if let error = model.error {
                ErrorCard(message: error) { await model.load() }
            }
        }
        .navigationTitle(selected == Day.today() ? "Today" : Day.label(selected))
        .toolbar {
            if isRoot {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink { SettingsScreen() } label: { Image(systemName: "gearshape") }.accessibilityLabel("Settings")
                }
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                if selected != Day.today() { Button("Today") { go(Day.today()) } }
                Button { go(Day.add(selected, -1)) } label: { Image(systemName: "chevron.left") }.accessibilityLabel("Previous day")
                Button { go(Day.add(selected, 1)) } label: { Image(systemName: "chevron.right") }.accessibilityLabel("Next day")
            }
        }
        .refreshable { await model.load() }
        .safeAreaInset(edge: .bottom) { if model.template.kind == "lift", model.mode == .log { TimerBar(model: model) } }
        .toast($model.toast)
        .sheet(isPresented: $showChange) { SessionChangeSheet(date: model.date) { await model.load() } }
        .sheet(isPresented: $showFinish) { FinishSheet(model: model).presentationDetents([.medium]) }
        .confirmationDialog("Delete this session and all its sets?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { Task { await model.delete() } }
        }
        // Keep the screen on while logging a lift.
        .onChange(of: model.mode == .log && model.template.kind == "lift", initial: true) { _, on in UIApplication.shared.isIdleTimerDisabled = on }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await API.shared.flush() } } }
    }

    private func header(_ day: DayInfo) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Space.s) {
                    if model.isToday { Badge(Day.label(day.date, year: true)) }
                    if day.week >= 1 { Badge("Week \(day.week)", tone: .accent) }
                    Badge("Phase \(day.phase): \(day.phaseName)")
                    if day.deload { Badge("Deload week", tone: .warn) }
                    if day.testWeek { Badge("Test week", tone: .warn) }
                    if day.moved { Badge("Moved from the plan", tone: .accent) }
                    if day.beyondPlan { Badge("Beyond the planned weeks") }
                }
            }
            if day.beforeStart { Banner("The plan starts Monday \(Day.short(day.startDate)). This shows the normal session for a \(day.weekdayName).", tone: .accent) }
            if day.deload { Banner("Deload: every 6th week all sets are cut in half. Keep the weight, do half the sets.") }
        }
    }

    @ViewBuilder
    private func session(_ day: DayInfo) -> some View {
        let t = model.template
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text([t.kind == "rest" ? "Rest" : t.kind.capitalizedFirst, t.duration].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ").uppercased())
                        .font(Theme.Typography.label).foregroundStyle(Theme.Palette.kind(t.kind))
                    Text(t.name).font(Theme.Typography.title)
                    if let s = t.subtitle { Text(s).font(Theme.Typography.caption).foregroundStyle(Theme.Palette.muted) }
                }
                Spacer()
                Badge(model.status.text, tone: model.status.tone)
            }
            if day.moved, model.templateKey == day.templateKey, let planned = model.program.templates[day.defaultTemplateKey] {
                Text("The plan has \(planned.name) today. You moved it.").font(Theme.Typography.caption).foregroundStyle(Theme.Palette.muted)
            }
            if model.templateKey == day.templateKey {
                ForEach(day.extras ?? [], id: \.self) { Text($0).font(Theme.Typography.caption).foregroundStyle(Theme.Palette.muted) }
            }
            switch t.kind {
            case "lift":
                if let tips = t.tips, !tips.isEmpty { Text(tips.joined(separator: " ")).font(Theme.Typography.callout).foregroundStyle(Theme.Palette.muted) }
                if model.mode == .overview {
                    Button("Start workout") { Task { await model.startWorkout() } }.buttonStyle(.primary).padding(.top, Theme.Space.xs)
                }
            case "run", "other":
                RunBody(model: model)
            default:
                if let d = t.detail { Text(d).font(Theme.Typography.callout) }
                if let s = model.program.stepsNote { Text(s).font(Theme.Typography.caption).foregroundStyle(Theme.Palette.muted) }
            }
        }
        .card()

        if t.kind == "lift" {
            switch model.mode {
            case .overview: PlanCard(model: model)
            case .log: LiftLog(model: model); notesAndFinish
            case .summary: LiftSummary(model: model)
            }
        } else {
            notesAndFinish
        }
        actions
    }

    private var notesAndFinish: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            LabeledField(label: "Notes") {
                TextField("How it felt, knees, anything for later", text: Binding(get: { model.workout?.notes ?? "" }, set: { model.setWorkoutNotes($0) }), axis: .vertical).lineLimit(2...6)
            }
            let kind = model.template.kind
            if model.workout?.status != "done" {
                Button(kind == "rest" ? "Mark day done" : kind == "lift" ? "Finish workout" : "Finish session") { showFinish = true }.buttonStyle(.primary)
            } else if kind == "lift" {
                Button("Done editing") { model.editing = false }.buttonStyle(.primary)
            } else {
                Button("Reopen session") { Task { await model.setStatus("in_progress") } }.buttonStyle(.tinted)
            }
        }
        .card()
    }

    private var actions: some View {
        Divided {
            ActionRow(title: "Move or change this session", subtitle: "Swap with another day, or do a different session today", tone: .accent) { showChange = true }
            if model.workout?.status == "skipped" {
                ActionRow(title: "Unskip") { Task { await model.setStatus("in_progress") } }
            } else {
                ActionRow(title: "Skip this session") { Task { await model.setStatus("skipped") } }
            }
            if (model.workout?.id ?? 0) > 0 {
                ActionRow(title: "Delete this session and its sets", tone: .danger) { confirmDelete = true }
            }
        }
        .card()
    }

    @ViewBuilder
    private var others: some View {
        let list = (model.data?.workouts ?? []).filter { $0.template_key != model.templateKey }
        if !list.isEmpty {
            SectionTitle("Also on this day")
            ForEach(list) { w in
                Button { model.open(w) } label: {
                    Row(title: model.program.templates[w.template_key]?.name ?? w.template_key,
                        subtitle: ["\(w.sets?.count ?? 0) sets", w.distance_km.map { "\(Fmt.number($0)) km" }, w.time_sec.map { Fmt.time($0) }].compactMap { $0 }.joined(separator: " · ") + ". Tap to open.") {
                        Badge(w.status.replacingOccurrences(of: "_", with: " "), tone: w.status == "done" ? .ok : w.status == "skipped" ? .danger : .neutral)
                    }
                }
                .buttonStyle(.plain).card()
            }
        }
    }
}

// MARK: Pieces

/// Projected weights, paces and body weight for an estimated day, each with what it is based on.
private struct ProjectionCard: View {
    let projection: Projection
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            CardTitle("If things go to plan", note: "projection")
            Divided {
                ForEach(projection.lines, id: \.self) { line in
                    Row(title: line.label, subtitle: line.basis) {
                        Text(line.value).font(Theme.Typography.callout.weight(.semibold).monospacedDigit()).multilineTextAlignment(.trailing)
                    }
                }
            }
            if let note = projection.note { Text(note).font(Theme.Typography.caption).foregroundStyle(Theme.Palette.muted) }
        }
        .card()
    }
}

/// A day past the concrete plan: the likely session type for an estimate, or nothing at all further out.
private struct OutlookCard: View {
    let day: DayInfo
    var body: some View {
        let estimate = Outlook(day.horizon) == .estimate
        let kind = day.template.kind
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text(estimate ? "ESTIMATE" : "NOT PLANNED YET").font(Theme.Typography.label).foregroundStyle(Theme.Palette.muted)
            Text(estimate ? day.template.name : "Nothing planned this far ahead").font(Theme.Typography.title)
            Text(estimate
                 ? "If the plan holds, this is \(kind == "rest" ? "a rest day" : kind == "lift" ? "a lifting day" : "a running day"). Sets, paces and targets are set closer to the time, from how training has gone by then."
                 : "Sessions this far out would only be the weekly template repeated, so the calendar leaves them empty.")
                .font(Theme.Typography.callout)
            if let fixed = day.concreteTo, let estimated = day.estimateTo {
                Text("The plan is fixed through \(Day.label(fixed, year: true)) and estimated through \(Day.label(estimated, year: true)). It moves forward on the 1st of each month.")
                    .font(Theme.Typography.caption).foregroundStyle(Theme.Palette.muted)
            }
        }
        .card()
    }
}

private struct WeekStrip: View {
    let week: [WeekDay]
    let selected: String
    let go: (String) -> Void
    var body: some View {
        HStack(spacing: Theme.Space.xs) {
            ForEach(week) { d in
                let w = d.workouts.first { $0.template_key == d.templateKey } ?? d.workouts.first { $0.status != "skipped" } ?? d.workouts.first
                Button { go(d.date) } label: {
                    VStack(spacing: 3) {
                        Text(Day.label(d.date).prefix(3)).font(Theme.Typography.label).foregroundStyle(Theme.Palette.muted)
                        Text(Day.dayNumber(d.date)).font(Theme.Typography.headline).foregroundStyle(d.date == Day.today() ? Theme.Palette.accent : Theme.Palette.text)
                        // Past the concrete plan the dot is grey (estimate) or absent, unless something is logged or moved.
                        let outlook = w != nil || d.moved ? Outlook.concrete : Outlook(d.horizon)
                        Circle().fill(w?.status == "done" ? Theme.Palette.ok : (outlook == .concrete ? Theme.Palette.kind(d.kind) : Theme.Palette.rest).opacity(w?.status == "skipped" ? 0.25 : 0.8))
                            .frame(width: 7, height: 7).opacity(outlook == .none ? 0 : 1)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, Theme.Space.s)
                    .background(d.date == selected ? Theme.Palette.fill : .clear, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(Day.label(d.date)), \(d.name)")
            }
        }
        .padding(Theme.Space.xs)
        .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }
}

private struct WeightCard: View {
    let model: DayModel
    @State private var text = ""
    @FocusState private var focused: Bool
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Morning weight").font(Theme.Typography.headline)
                Text("Three mornings a week is enough.").font(Theme.Typography.caption).foregroundStyle(Theme.Palette.muted)
            }
            Spacer()
            TextField("kg", text: $text).keyboardType(.decimalPad).multilineTextAlignment(.center).focused($focused).frame(width: 72).fieldStyle()
        }
        .card()
        .onAppear { text = Fmt.number(model.data?.body?.weight_kg) }
        .onChange(of: focused) { _, now in
            if !now, Fmt.parse(text) != model.data?.body?.weight_kg { Task { await model.saveWeight(text) } }
        }
        .toolbar { if focused { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { focused = false } } } }
    }
}

struct ChecklistItem: Identifiable, Hashable { let id: String; let text: String; var sub: String? = nil }

/// Collapsible checklist with a done count and a note. Used for the warm-up, jumps, finisher and knee routine.
struct ChecklistCard: View {
    let model: DayModel
    let block: String
    let title: String
    var note: String? = nil
    let items: [ChecklistItem]
    @State private var open = false

    var body: some View {
        let done = items.filter { model.isChecked(block, $0.id) }.count
        DisclosureGroup(isExpanded: $open) {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                if let note, !note.isEmpty { Text(note).font(Theme.Typography.caption).foregroundStyle(Theme.Palette.muted) }
                ForEach(items) { item in
                    let on = model.isChecked(block, item.id)
                    Button { model.toggle(block, item.id) } label: {
                        HStack(alignment: .top, spacing: Theme.Space.m) {
                            Image(systemName: on ? "checkmark.circle.fill" : "circle").font(.title3).foregroundStyle(on ? Theme.Palette.ok : Theme.Palette.muted)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.text).font(Theme.Typography.body).strikethrough(on).foregroundStyle(on ? Theme.Palette.muted : Theme.Palette.text).multilineTextAlignment(.leading)
                                if let sub = item.sub, !sub.isEmpty { Text(sub).font(Theme.Typography.caption).foregroundStyle(Theme.Palette.muted).multilineTextAlignment(.leading) }
                            }
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                NoteField(model: model, block: block, prompt: "Note on the \((DayModel.blockNames[block] ?? title).lowercased())")
            }
            .padding(.top, Theme.Space.s)
        } label: {
            HStack {
                Text(title).font(Theme.Typography.headline).foregroundStyle(Theme.Palette.text)
                Spacer()
                Badge("\(done)/\(items.count)", tone: done == items.count ? .ok : .neutral)
            }
        }
        .card()
        .onAppear { open = done > 0 && done < items.count }
    }
}

/// "+ Note" that opens a text field; open from the start when a note exists.
struct NoteField: View {
    let model: DayModel
    let block: String
    let prompt: String
    @State private var open = false
    var body: some View {
        if open || !(model.notes[block] ?? "").isEmpty {
            TextField(prompt, text: Binding(get: { model.notes[block] ?? "" }, set: { model.setNote(block, $0) }), axis: .vertical)
                .font(Theme.Typography.callout).fieldStyle()
        } else {
            Button("+ Note") { open = true }.font(Theme.Typography.callout)
        }
    }
}

private struct TestsCard: View {
    let model: DayModel
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            CardTitle(title: "Test week \(model.day?.week ?? 0)") { Badge("Fill in during the week", tone: .warn) }
            Text("5 km on Tuesday, jumps and shuttle after a warm-up, 3RMs on the lifting days. One leg hopping less than 90% of the other is the warning sign.")
                .font(Theme.Typography.caption).foregroundStyle(Theme.Palette.muted)
            ForEach(model.program.tests, id: \.key) { def in
                let existing = model.data?.tests?.first { $0.test_key == def.key }?.value
                TestField(def: def, initial: def.input == "time" ? Fmt.time(existing) : Fmt.number(existing)) { text in
                    Task { await model.saveTest(def.key, value: def.input == "time" ? Fmt.parseTime(text) : Fmt.parse(text)); model.toast = "Test saved" }
                }
            }
        }
        .card()
    }
}

private struct TestField: View {
    let def: Program.TestDef
    let initial: String
    let save: (String) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool
    var body: some View {
        LabeledField(label: "\(def.name) (\(def.unit))") {
            TextField(def.input == "time" ? "mm:ss" : def.unit, text: $text).keyboardType(.numbersAndPunctuation).focused($focused)
        }
        .onAppear { text = initial }
        .onChange(of: focused) { _, now in if !now, text != initial { save(text) } }
    }
}

private struct FinishSheet: View {
    let model: DayModel
    @State private var rpe: Int?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            Text(model.template.kind == "lift" ? "Finish workout" : "Finish session").font(Theme.Typography.title)
            if model.template.kind == "lift" { Text("\(model.doneSets) set\(model.doneSets == 1 ? "" : "s") logged.").foregroundStyle(Theme.Palette.muted) }
            Text("How hard was it? (1 easy, 10 all out)").font(Theme.Typography.caption).foregroundStyle(Theme.Palette.muted)
            HStack(spacing: Theme.Space.xs) {
                ForEach(1...10, id: \.self) { i in
                    Button("\(i)") { rpe = i }
                        .font(Theme.Typography.headline).frame(maxWidth: .infinity).padding(.vertical, Theme.Space.s)
                        .foregroundStyle(rpe == i ? .white : Theme.Palette.text)
                        .background(rpe == i ? Theme.Palette.accent : Theme.Palette.fill, in: RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
                        .buttonStyle(.plain)
                }
            }
            Button("Done") { Task { await model.finish(rpe: rpe) }; dismiss() }.buttonStyle(.primary)
            Spacer()
        }
        .padding(Theme.Space.xl)
        .onAppear { rpe = model.workout?.rpe.map { Int($0) } }
    }
}

struct ErrorCard: View {
    let message: String
    let retry: () async -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text("Could not load").font(Theme.Typography.headline)
            Text(message).font(Theme.Typography.callout).foregroundStyle(Theme.Palette.muted)
            Button("Retry") { Task { await retry() } }.buttonStyle(.tinted)
        }
        .card()
    }
}

// MARK: Toast

private struct ToastModifier: ViewModifier {
    @Binding var message: String?
    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if let message {
                Text(message).font(Theme.Typography.callout).padding(.horizontal, Theme.Space.l).padding(.vertical, Theme.Space.s)
                    .background(.regularMaterial, in: Capsule()).padding(.top, Theme.Space.s)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .task(id: message) { try? await Task.sleep(for: .seconds(2)); self.message = nil }
            }
        }
        .animation(.snappy, value: message)
    }
}

extension View {
    func toast(_ message: Binding<String?>) -> some View { modifier(ToastModifier(message: message)) }
}
