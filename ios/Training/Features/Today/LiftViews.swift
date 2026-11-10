import SwiftUI

/// What the session holds, before it is started.
struct PlanCard: View {
    let model: DayModel
    var body: some View {
        let t = model.template, p = model.program, blocks = t.blocks ?? []
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            CardTitle("Plan", note: "\(model.plan.count) lifts")
            Divided {
                if blocks.contains("warmup") { Row(title: p.warmup.title, subtitle: "\(p.warmup.items.count) drills") { note("\(p.warmup.minutes.text) min") } }
                if blocks.contains("jumps"), let day = model.day {
                    Row(title: "\(p.jumps.title), phase \(day.phase)", subtitle: (day.jumps ?? []).map(\.name).joined(separator: ", ")) { note("\(p.jumps.minutes.text) min") }
                }
                ForEach(model.plan, id: \.key) { e in
                    let last = model.data?.last[e.key]
                    Row(p.exercise(e.key).name, subtitle: [target(e), last.map { "last \(p.describe(e.key, $0.sets))" } ?? e.startKg.map { "start around \(Fmt.number($0)) kg" }].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                }
                if blocks.contains("finisher"), let f = t.finisher { Row(title: f.title, subtitle: f.text) { note("\(f.minutes?.text ?? "") min") } }
            }
        }
        .card()
    }

    private func note(_ s: String) -> some View { Text(s).font(Theme.Typography.caption).foregroundStyle(Theme.Palette.muted) }
}

private func target(_ e: PlanEntry, long: Bool = false) -> String {
    guard e.sets > 0 else { return "" }
    let deload = e.plannedSets != nil && e.plannedSets != e.sets
    return "\(e.sets) × \(e.reps ?? "")" + (deload ? (long ? " (deload, normally \(e.plannedSets!))" : " (deload)") : "")
}

/// The logging screen: checklists, one card per lift, finisher.
struct LiftLog: View {
    let model: DayModel
    @State private var picker: PickerTarget?

    enum PickerTarget: Identifiable {
        case add, replace(String)
        var id: String { if case .replace(let k) = self { k } else { "add" } }
    }

    var body: some View {
        let t = model.template, p = model.program, blocks = t.blocks ?? []
        if blocks.contains("warmup") {
            ChecklistCard(model: model, block: "warmup", title: "\(p.warmup.title) (\(p.warmup.minutes.text) min)", note: p.warmup.note, items: p.warmup.items.map { .init(id: $0.id, text: $0.text) })
        }
        if blocks.contains("jumps"), let day = model.day {
            ChecklistCard(model: model, block: "jumps", title: "\(p.jumps.title), phase \(day.phase)", note: [p.jumps.note, p.jumps.phaseNotes?[String(day.phase)]].compactMap { $0 }.joined(separator: " "),
                          items: (day.jumps ?? []).map { .init(id: $0.id, text: "\($0.name): \($0.sets)", sub: $0.note) })
        }
        SectionTitle("Lifts")
        ForEach(model.plan, id: \.key) { e in
            ExerciseCard(model: model, entry: e) { picker = .replace(e.key) }
        }
        Button("+ Add an exercise") { picker = .add }.buttonStyle(.tinted)
            .sheet(item: $picker) { target in
                ExercisePicker(program: p, title: target.id == "add" ? "Add an exercise" : "Replace \(p.exercise(target.id).name) with") { key in
                    Task { if case .replace(let old) = target { await model.replaceExercise(old, with: key) } else { await model.addExercise(key) } }
                }
            }
        if blocks.contains("finisher"), let f = t.finisher {
            ChecklistCard(model: model, block: "finisher", title: f.title, items: [.init(id: "done", text: f.text)])
        }
        Text("Progression: once you hit the top of the rep range on every set with 1 to 2 reps left, add weight next time (2.5 kg for barbell, one dumbbell step).")
            .font(Theme.Typography.caption).foregroundStyle(Theme.Palette.muted).padding(.horizontal, Theme.Space.xs)
    }
}

private struct ExerciseCard: View {
    let model: DayModel
    let entry: PlanEntry
    let replace: () -> Void

    var body: some View {
        let ex = model.program.exercise(entry.key)
        let fields = Array(ex.fields.prefix(2))
        let rows = model.rows[entry.key] ?? []
        let last = model.data?.last[entry.key]
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(ex.name).font(Theme.Typography.headline)
                    Text([target(entry, long: true), entry.note, ex.kgHint.map { "kg = \($0)" }].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(Theme.Typography.caption).foregroundStyle(Theme.Palette.muted)
                }
                Spacer()
                Menu {
                    Button("Replace with another exercise", action: replace)
                    Button("Remove from this session", role: .destructive) { Task { await model.removeExercise(entry.key) } }
                } label: {
                    Image(systemName: "ellipsis").padding(Theme.Space.s).contentShape(Rectangle())
                }
                .accessibilityLabel("Exercise options")
            }
            if let last {
                Text("Last time (\(Day.short(last.date))): \(model.program.describe(entry.key, last.sets))" + (last.note.map { "\n“\($0)”" } ?? ""))
                    .font(Theme.Typography.caption).foregroundStyle(Theme.Palette.muted)
            }
            if let hint = hint(ex, last) { Banner(hint, tone: .accent) }

            ForEach(Array(rows.enumerated()), id: \.element.id) { i, row in
                SetRowView(model: model, entry: entry, fields: fields, kgOptional: ex.kgOptional == true, index: i, row: row)
            }
            HStack {
                Button("+ Add set") { model.addSet(entry.key) }
                Spacer()
                if !rows.isEmpty { Button("Remove set") { Task { await model.removeLastSet(entry.key) } }.foregroundStyle(Theme.Palette.muted) }
            }
            .font(Theme.Typography.callout)
            NoteField(model: model, block: entry.key, prompt: "Note on \(ex.shortName)")
        }
        .card()
    }

    /// Suggests the next weight when every set last time reached the top of the rep range.
    private func hint(_ ex: Exercise, _ last: LastSets?) -> String? {
        guard let last else { return entry.startKg.map { "First session: start around \(Fmt.number($0)) kg." } }
        guard ex.fields.contains("kg"), ex.fields.contains("reps"), let top = entry.repsMax else { return nil }
        let sets = last.sets.filter { $0.reps != nil }
        guard sets.count >= max(1, entry.plannedSets ?? entry.sets), let kg = sets.compactMap(\.weight_kg).max(), kg > 0,
              sets.allSatisfy({ ($0.reps ?? 0) >= top && ($0.weight_kg ?? 0) >= kg }) else { return nil }
        return "Last time you hit \(top) on every set. Try \(Fmt.number(kg + (ex.increment ?? 2.5))) kg today."
    }
}

private struct SetRowView: View {
    let model: DayModel
    let entry: PlanEntry
    let fields: [String]
    let kgOptional: Bool
    let index: Int
    let row: DayModel.Row
    static let units = ["kg": "kg", "reps": "reps", "seconds": "sec", "meters": "m"]

    var body: some View {
        let counting = model.countdown?.rowID == row.id
        HStack(spacing: Theme.Space.s) {
            Text("\(index + 1)").font(Theme.Typography.label).foregroundStyle(Theme.Palette.muted).frame(width: 18)
            ForEach(fields, id: \.self) { f in
                HStack(spacing: Theme.Space.xs) {
                    if counting, f == "seconds", let range = model.countdown?.range {
                        Text(timerInterval: range, countsDown: true).font(Theme.Typography.numeral).foregroundStyle(Theme.Palette.accent).frame(maxWidth: .infinity)
                    } else {
                        TextField(model.placeholder(entry, index, f), text: Binding(get: { model.text(entry.key, row.id, f) }, set: { model.setText(entry.key, row.id, f, $0) }))
                            .keyboardType(f == "kg" ? .decimalPad : .numberPad)
                            .font(Theme.Typography.numeral).multilineTextAlignment(.center)
                    }
                    if f == "seconds" {
                        Button { model.toggleCountdown(entry, row.id) } label: { Image(systemName: counting ? "stop.fill" : "play.fill") }
                            .accessibilityLabel(counting ? "Stop countdown" : "Start countdown")
                    } else {
                        Text(Self.units[f]! + (f == "kg" && kgOptional ? " (opt.)" : "")).font(Theme.Typography.caption).foregroundStyle(Theme.Palette.muted)
                    }
                }
                .fieldStyle()
            }
            Button { model.tick(entry, row.id) } label: {
                Image(systemName: "checkmark").font(.headline)
                    .foregroundStyle(row.saved ? .white : Theme.Palette.muted)
                    .frame(width: 44, height: 44)
                    .background(row.saved ? Theme.Palette.ok : Theme.Palette.fill, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(row.saved ? "Set \(index + 1) logged" : "Log set \(index + 1)")
        }
    }
}

/// Pinned above the tab bar while logging: workout time, rest since the last tick, and a running countdown.
struct TimerBar: View {
    let model: DayModel
    var body: some View {
        HStack {
            item("WORKOUT") {
                if let s = Fmt.timestamp(model.workout?.started_at), model.workout?.status != "done" { Text(s, style: .timer) } else { Text("done") }
            }
            item("REST") { if let t = model.lastTick { Text(t, style: .timer) } else { Text("–") } }
            if let c = model.countdown {
                item(model.program.exercise(c.key).shortName.uppercased()) { Text(timerInterval: c.range, countsDown: true).foregroundStyle(Theme.Palette.accent) }
            }
        }
        .padding(.vertical, Theme.Space.s)
        .background(.bar)
    }

    private func item(_ label: String, @ViewBuilder value: () -> some View) -> some View {
        VStack(spacing: 0) {
            Text(label).font(Theme.Typography.label).foregroundStyle(Theme.Palette.muted).lineLimit(1)
            value().font(Theme.Typography.numeral)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Finished workout: results per lift, and a way back in to fix mistakes.
struct LiftSummary: View {
    let model: DayModel

    private var minutes: Double? {
        if let m = model.workout?.duration_min { return m }
        guard let a = Fmt.timestamp(model.workout?.started_at), let b = Fmt.timestamp(model.workout?.finished_at), b > a else { return nil }
        return max(1, (b.timeIntervalSince(a) / 60).rounded())
    }

    var body: some View {
        let w = model.workout
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            CardTitle("Results", note: [minutes.map { "\(Int($0)) min" }, w?.rpe.map { "RPE \(Int($0))" }].compactMap { $0 }.joined(separator: " · "))
            Divided {
                ForEach(model.plan, id: \.key) { e in
                    let sets = (model.rows[e.key] ?? []).filter(\.saved)
                    let values = sets.map { r in SetRow.Values(weight_kg: r.text["kg"].flatMap(Fmt.parse), reps: r.text["reps"].flatMap(Fmt.parse).map { Int($0) }, seconds: r.text["seconds"].flatMap(Fmt.parse).map { Int($0) }, distance_m: r.text["meters"].flatMap(Fmt.parse)) }
                    Row(title: model.program.exercise(e.key).name, subtitle: [sets.isEmpty ? "not logged" : model.program.describe(e.key, values), model.notes[e.key]].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n")) {
                        Badge("\(sets.count)" + (e.sets > 0 ? "/\(e.sets)" : ""), tone: sets.isEmpty ? .neutral : .ok)
                    }
                }
            }
            ForEach(["warmup", "jumps", "finisher"], id: \.self) { b in
                if (model.template.blocks ?? []).contains(b), let ticked = model.checklist[b] {
                    Text("\(DayModel.blockNames[b]!): \(ticked.values.filter { $0 }.count) ticked" + (model.notes[b].map { ". \($0)" } ?? ""))
                        .font(Theme.Typography.caption).foregroundStyle(Theme.Palette.muted)
                }
            }
            if let notes = w?.notes, !notes.isEmpty { Text(notes).font(Theme.Typography.callout) }
            Button("Edit workout") { model.editing = true }.buttonStyle(.tinted).padding(.top, Theme.Space.xs)
        }
        .card()
    }
}

/// Search the exercise list, or type a new name to add a custom exercise.
struct ExercisePicker: View {
    let program: Program
    let title: String
    let pick: (String) -> Void
    @State private var query = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let matches = program.exercises.filter { $0.value.hidden != true && (q.isEmpty || $0.value.name.lowercased().contains(q) || $0.value.group.contains(q)) }.sorted { $0.value.name < $1.value.name }
        NavigationStack {
            List {
                ForEach(matches, id: \.key) { key, ex in
                    Button { pick(key); dismiss() } label: { Row(ex.name, subtitle: "\(ex.group) · \(ex.fields.joined(separator: " + "))") }
                }
                if !q.isEmpty, !matches.contains(where: { $0.value.name.lowercased() == q }) {
                    let key = "custom:" + q.replacingOccurrences(of: "[^a-z0-9]+", with: "_", options: .regularExpression).trimmingCharacters(in: CharacterSet(charactersIn: "_"))
                    Button { pick(key); dismiss() } label: { Row("Add \"\(query.trimmingCharacters(in: .whitespaces))\"", subtitle: "custom exercise, kg + reps") }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search, or type a new name")
            .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}
