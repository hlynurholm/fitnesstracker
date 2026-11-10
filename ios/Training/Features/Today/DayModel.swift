import Observation
import UIKit

/// Program and settings, loaded once from the Worker and shared by every screen.
@MainActor @Observable
final class AppModel {
    static let shared = AppModel()
    private(set) var program: Program?
    private(set) var settings = Settings()
    private(set) var error: String?

    func load() async {
        do {
            let r: ProgramResponse = try await API.shared.get("/api/program", cache: true)
            program = r.program; settings = r.settings; error = nil
        } catch { self.error = error.localizedDescription }
    }
}

/// State and persistence for one day: the session, its sets, checklists and notes.
/// Mirrors the web app's day view so both clients write the same shapes to the same endpoints.
@MainActor @Observable
final class DayModel {
    struct Row: Identifiable, Hashable {
        let id: String // client id, generated on the phone so a save can be replayed safely
        var index: Int
        var text: [String: String] = [:] // field (kg, reps, seconds, meters) to what is typed
        var saved = false // ticked
        var touched = false // sent to the server at least once
    }

    struct Countdown { let rowID: String; let key: String; let range: ClosedRange<Date> }
    enum Mode { case overview, log, summary }

    static let blockNames = ["warmup": "Warm-up", "jumps": "Jumps", "finisher": "Finisher", "knee": "Routine"]

    let date: String
    let program: Program
    private(set) var data: DayResponse?
    private(set) var error: String?
    private(set) var workout: Workout?
    private(set) var templateKey = ""
    private(set) var plan: [PlanEntry] = []
    private(set) var checklist: [String: [String: Bool]] = [:]
    private(set) var notes: [String: String] = [:]
    private(set) var rows: [String: [Row]] = [:]
    private(set) var lastTick: Date?
    private(set) var countdown: Countdown?
    var editing = false
    var toast: String?
    private var pending: [String: Task<Void, Never>] = [:]

    init(date: String, program: Program) { self.date = date; self.program = program }

    var day: DayInfo? { data?.day }
    var template: Template { program.templates[templateKey] ?? data?.day.template ?? program.templates["other"]! }
    var isToday: Bool { date == Day.today() }
    var doneSets: Int { rows.values.joined().filter(\.saved).count }

    /// overview: nothing started yet. log: started, or a finished workout opened for edits. summary: finished.
    var mode: Mode {
        guard let w = workout else { return .overview }
        if w.status == "done" { return editing ? .log : .summary }
        if w.started_at != nil || rows.values.joined().contains(where: \.touched) { return .log }
        return .overview
    }

    var status: (text: String, tone: Tone) {
        switch workout?.status {
        case "done": return ("Done", .ok)
        case "skipped": return ("Skipped", .danger)
        default:
            let started = template.kind == "lift" ? workout?.started_at != nil : (doneSets > 0 || workout?.time_sec != nil)
            return started ? ("In progress", .accent) : ("Not started", .neutral)
        }
    }

    // MARK: Loading

    func load() async {
        do {
            let d: DayResponse = try await API.shared.get("/api/day/\(date)", cache: true)
            let preferred = UserDefaults.standard.string(forKey: "active_\(date)")
            data = d
            error = nil
            open(d.workouts.first { $0.template_key == preferred } ?? d.active)
        } catch { self.error = error.localizedDescription }
    }

    /// Shows one of the day's workouts (or the planned session when nil).
    func open(_ w: Workout?) {
        guard let d = data else { return }
        workout = w
        templateKey = w?.template_key ?? d.day.templateKey
        plan = (w?.plan).flatMap { $0.isEmpty ? nil : $0 } ?? (templateKey == d.day.templateKey ? d.day.plan : [])
        checklist = w?.checklist ?? [:]
        notes = w?.block_notes ?? [:]
        buildRows(from: w?.sets ?? [])
        if let w { UserDefaults.standard.set(w.template_key, forKey: "active_\(date)") }
        updateLive()
    }

    private func buildRows(from sets: [SetRow]) {
        var out: [String: [Row]] = [:]
        // Sets logged for exercises that are no longer in the plan stay visible.
        for s in sets where !plan.contains(where: { $0.key == s.exercise_key }) {
            plan.append(PlanEntry(key: s.exercise_key, sets: 0, reps: "", added: true))
        }
        for e in plan {
            var r = sets.filter { $0.exercise_key == e.key }.sorted { $0.set_index < $1.set_index }.map { s in
                Row(id: s.client_id, index: s.set_index, text: Self.text(s.values), saved: s.isDone, touched: true)
            }
            while r.count < e.sets { r.append(Row(id: Self.newID(), index: r.count)) }
            out[e.key] = r
        }
        rows = out
    }

    private static func text(_ v: SetRow.Values) -> [String: String] {
        var t: [String: String] = [:]
        if let x = v.weight_kg { t["kg"] = Fmt.number(x) }
        if let x = v.reps { t["reps"] = String(x) }
        if let x = v.seconds { t["seconds"] = String(x) }
        if let x = v.distance_m { t["meters"] = Fmt.number(x) }
        return t
    }

    private static func newID() -> String { String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(24)).lowercased() }

    private func debounce(_ key: String, seconds: Double = 0.7, _ work: @escaping () async -> Void) {
        pending[key]?.cancel()
        pending[key] = Task {
            try? await Task.sleep(for: .seconds(seconds))
            if !Task.isCancelled { await work() }
        }
    }

    // MARK: Workout

    /// Applies a change to the workout now and sends it. When offline it is queued and the local copy stands.
    @discardableResult
    func saveWorkout(_ patch: [String: Any?]) async -> Bool {
        var w = workout ?? Workout(id: 0, date: date, template_key: templateKey, kind: template.kind, status: "in_progress")
        if let v = patch["status"] as? String { w.status = v }
        if patch.keys.contains("started_at") { w.started_at = patch["started_at"] as? String }
        if patch.keys.contains("finished_at") { w.finished_at = patch["finished_at"] as? String }
        if patch.keys.contains("notes") { w.notes = patch["notes"] as? String }
        if patch.keys.contains("rpe") { w.rpe = patch["rpe"] as? Double }
        if patch.keys.contains("duration_min") { w.duration_min = patch["duration_min"] as? Double }
        if patch.keys.contains("distance_km") { w.distance_km = patch["distance_km"] as? Double }
        if patch.keys.contains("time_sec") { w.time_sec = patch["time_sec"] as? Double }
        if patch.keys.contains("avg_hr") { w.avg_hr = patch["avg_hr"] as? Double }
        workout = w
        UserDefaults.standard.set(templateKey, forKey: "active_\(date)")
        var body = patch
        body["template_key"] = templateKey
        do {
            let saved: Workout? = try await API.shared.write("PUT", "/api/day/\(date)/workout", body, key: "workout:\(date):\(templateKey):\(patch.keys.sorted().joined(separator: ","))")
            if let saved { workout?.id = saved.id; workout?.activities = saved.activities }
            return true
        } catch {
            toast = error.localizedDescription
            return false
        }
    }

    func startWorkout() async {
        await saveWorkout(["status": "in_progress", "started_at": Fmt.isoNow()])
        updateLive()
    }

    func finish(rpe: Int?) async {
        var patch: [String: Any?] = ["status": "done"]
        if let rpe { patch["rpe"] = Double(rpe) }
        if let started = Fmt.timestamp(workout?.started_at), workout?.status != "done" {
            patch["finished_at"] = Fmt.isoNow()
            patch["duration_min"] = max(1, (Date().timeIntervalSince(started) / 60).rounded())
        }
        editing = false
        await saveWorkout(patch)
        // A timed 5 km also counts as the 5 km test.
        if template.timeTrial == true, let t = workout?.time_sec, let km = workout?.distance_km, (4.9...5.3).contains(km) {
            await saveTest("five_k_sec", value: t)
        }
        LiveWorkout.end()
        if IntervalRunner.shared.isActive { IntervalRunner.shared.stop() }
        toast = "Session done"
    }

    func setStatus(_ status: String) async {
        await saveWorkout(["status": status])
        updateLive()
    }

    func delete() async {
        guard let id = workout?.id, id > 0 else { return }
        do {
            try await API.shared.send("DELETE", "/api/workouts/\(id)")
            UserDefaults.standard.removeObject(forKey: "active_\(date)")
            LiveWorkout.end()
            await load()
        } catch { toast = error.localizedDescription }
    }

    func setWorkoutNotes(_ text: String) {
        workout?.notes = text
        debounce("notes") { await self.saveWorkout(["notes": text]) }
    }

    func setRun(distance: String, time: String, hr: String) {
        // Opening a run day must not create a workout: only save what actually changed.
        guard Fmt.parse(distance) != workout?.distance_km || Fmt.parseTime(time) != workout?.time_sec || Fmt.parse(hr) != workout?.avg_hr else { return }
        debounce("run") { await self.saveWorkout(["distance_km": Fmt.parse(distance), "time_sec": Fmt.parseTime(time), "avg_hr": Fmt.parse(hr)]) }
    }

    // MARK: Checklists and notes

    func isChecked(_ block: String, _ item: String) -> Bool { checklist[block]?[item] ?? false }

    func toggle(_ block: String, _ item: String) {
        checklist[block, default: [:]][item] = !isChecked(block, item)
        let snapshot = checklist
        debounce("checklist") { await self.saveWorkout(["checklist": snapshot]) }
    }

    /// Note on one exercise or block (warmup, jumps, finisher). An empty note deletes it on the server.
    func setNote(_ block: String, _ text: String) {
        notes[block] = text
        let body: [String: Any?] = ["template_key": templateKey, "block": block, "note": text]
        debounce("note:\(block)") {
            do {
                let _: NoteSaved? = try await API.shared.write("PUT", "/api/day/\(self.date)/notes", body, key: "note:\(self.date):\(self.templateKey):\(block)")
            } catch { self.toast = error.localizedDescription }
        }
    }

    // MARK: Sets

    func text(_ key: String, _ id: String, _ field: String) -> String {
        rows[key]?.first { $0.id == id }?.text[field] ?? ""
    }

    func setText(_ key: String, _ id: String, _ field: String, _ value: String) {
        guard let i = rows[key]?.firstIndex(where: { $0.id == id }), rows[key]![i].text[field] != value else { return }
        rows[key]![i].text[field] = value.isEmpty ? nil : value
        debounce("set:\(id)") { await self.saveSet(key, id) }
    }

    /// What the field would hold if left empty: the set above, else last time, else the plan's starting point.
    func placeholder(_ entry: PlanEntry, _ index: Int, _ field: String) -> String {
        let r = rows[entry.key] ?? []
        if index > 0, index <= r.count, let prev = r[index - 1].text[field] { return prev }
        if let last = data?.last[entry.key], !last.sets.isEmpty {
            let s = last.sets[min(index, last.sets.count - 1)]
            switch field {
            case "kg": if let v = s.weight_kg { return Fmt.number(v) }
            case "reps": if let v = s.reps { return String(v) }
            case "seconds": if let v = s.seconds { return String(v) }
            default: if let v = s.distance_m { return Fmt.number(v) }
            }
        }
        switch field {
        case "kg": return entry.startKg.map { Fmt.number($0) } ?? ""
        case "reps": return entry.repsMin.map(String.init) ?? ""
        case "seconds": return entry.seconds.map(String.init) ?? ""
        default: return entry.meters.map(String.init) ?? ""
        }
    }

    /// Tick or untick a set. Ticking fills empty fields from their placeholders first.
    func tick(_ entry: PlanEntry, _ id: String) {
        let key = entry.key
        guard let i = rows[key]?.firstIndex(where: { $0.id == id }) else { return }
        if rows[key]![i].saved {
            rows[key]![i].saved = false // keep the numbers, mark the set as not done
        } else {
            let ex = program.exercise(key)
            for f in ex.fields.prefix(2) where rows[key]![i].text[f] == nil {
                let p = placeholder(entry, i, f)
                if !p.isEmpty { rows[key]![i].text[f] = p }
            }
            guard !rows[key]![i].text.isEmpty else { toast = "Type the numbers first"; return }
            rows[key]![i].saved = true
            lastTick = Date()
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
        pending["set:\(id)"]?.cancel()
        Task { await saveSet(key, id) }
        updateLive()
    }

    private func saveSet(_ key: String, _ id: String) async {
        guard let i = rows[key]?.firstIndex(where: { $0.id == id }), !rows[key]![i].text.isEmpty else { return }
        rows[key]![i].touched = true
        let row = rows[key]![i]
        let body: [String: Any?] = [
            "date": date, "template_key": templateKey, "exercise_key": key, "set_index": row.index,
            "weight_kg": row.text["kg"].flatMap(Fmt.parse), "reps": row.text["reps"].flatMap(Fmt.parse),
            "seconds": row.text["seconds"].flatMap(Fmt.parse), "distance_m": row.text["meters"].flatMap(Fmt.parse),
            "done": row.saved ? 1 : 0,
        ]
        do {
            let r: SetSaved? = try await API.shared.write("PUT", "/api/sets/\(id)", body, key: "set:\(id)")
            if workout == nil || workout?.id == 0, let wid = r?.workout_id {
                if workout == nil { workout = Workout(id: wid, date: date, template_key: templateKey, kind: template.kind, status: "in_progress") }
                workout?.id = wid
            }
        } catch { toast = error.localizedDescription }
    }

    func addSet(_ key: String) {
        rows[key, default: []].append(Row(id: Self.newID(), index: rows[key]?.count ?? 0))
        updateLive()
    }

    func removeLastSet(_ key: String) async {
        guard let row = rows[key]?.popLast() else { return }
        updateLive()
        guard row.touched else { return }
        do { try await API.shared.send("DELETE", "/api/sets/\(row.id)") } catch { toast = error.localizedDescription }
    }

    // MARK: Set countdown (planks, marches)

    func toggleCountdown(_ entry: PlanEntry, _ id: String) {
        if let c = countdown {
            // Stopped early: keep the seconds actually held.
            let held = Int(Date().timeIntervalSince(c.range.lowerBound).rounded())
            countdown = nil
            pending["countdown"]?.cancel()
            setText(c.key, c.rowID, "seconds", String(held))
            toast = "Stopped at \(held) s"
            updateLive()
            if c.rowID == id { return }
        }
        guard let i = rows[entry.key]?.firstIndex(where: { $0.id == id }) else { return }
        let target = Int(Fmt.parse(rows[entry.key]![i].text["seconds"] ?? placeholder(entry, i, "seconds")) ?? 0)
        guard target > 0 else { toast = "Type the seconds first"; return }
        let c = Countdown(rowID: id, key: entry.key, range: Date()...Date().addingTimeInterval(TimeInterval(target)))
        countdown = c
        updateLive()
        pending["countdown"]?.cancel()
        pending["countdown"] = Task {
            try? await Task.sleep(for: .seconds(target))
            guard !Task.isCancelled, self.countdown?.rowID == id else { return }
            self.countdown = nil
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            if let i = self.rows[entry.key]?.firstIndex(where: { $0.id == id }) {
                self.rows[entry.key]![i].text["seconds"] = String(target)
                self.rows[entry.key]![i].saved = false
            }
            self.tick(entry, id)
        }
    }

    // MARK: Plan edits (this session only)

    func addExercise(_ key: String) async {
        let timed = program.exercise(key).fields.contains("seconds")
        plan.append(PlanEntry(key: key, sets: 3, reps: timed ? "30 s" : "8 to 10", repsMin: 8, repsMax: 10, added: true))
        await savePlan()
    }

    func replaceExercise(_ old: String, with key: String) async {
        guard let i = plan.firstIndex(where: { $0.key == old }) else { return }
        plan[i].key = key; plan[i].startKg = nil; plan[i].replaces = old
        await savePlan()
    }

    func removeExercise(_ key: String) async {
        plan.removeAll { $0.key == key }
        await savePlan()
    }

    private func savePlan() async {
        let sets = rows.flatMap { key, r in
            r.filter { $0.saved || $0.touched }.map { SetRow(client_id: $0.id, exercise_key: key, set_index: $0.index, weight_kg: $0.text["kg"].flatMap(Fmt.parse), reps: $0.text["reps"].flatMap(Fmt.parse).map { Int($0) }, seconds: $0.text["seconds"].flatMap(Fmt.parse).map { Int($0) }, distance_m: $0.text["meters"].flatMap(Fmt.parse), done: $0.saved ? 1 : 0) }
        }
        let keep = Set(plan.map(\.key))
        buildRows(from: sets.filter { keep.contains($0.exercise_key) })
        await saveWorkout(["plan": plan.jsonObject])
        updateLive()
    }

    // MARK: Body weight, tests, schedule

    func saveWeight(_ text: String) async {
        let kg = Fmt.parse(text)
        do {
            let _: BodyMetric? = try await API.shared.write("PUT", "/api/body", ["date": date, "weight_kg": kg], key: "body:\(date)")
            data?.body = kg.map { BodyMetric(date: date, weight_kg: $0) }
            toast = kg == nil ? "Weigh-in removed" : "Weight saved"
        } catch { toast = error.localizedDescription }
    }

    func saveTest(_ key: String, value: Double?) async {
        let on = data?.tests?.first { $0.test_key == key }?.date ?? date
        do {
            let _: TestResult? = try await API.shared.write("PUT", "/api/tests", ["date": on, "test_key": key, "value": value], key: "test:\(on):\(key)")
        } catch { toast = error.localizedDescription }
    }

    // MARK: Live Activity

    /// Keeps the lock screen on the next set, with the rest timer running from the last tick.
    func updateLive() {
        guard isToday, template.kind == "lift" else { return }
        guard let w = workout, w.status == "in_progress", let started = Fmt.timestamp(w.started_at) else {
            if !IntervalRunner.shared.isActive { LiveWorkout.end() }
            return
        }
        let total = plan.reduce(0) { $0 + (rows[$1.key]?.count ?? 0) }
        var title = "All sets logged", detail = "Finish the workout in the app"
        let current = countdown.flatMap { c in plan.first { $0.key == c.key } } ?? plan.first { e in rows[e.key]?.contains { !$0.saved } ?? false }
        let countingID = countdown?.rowID
        if let e = current, let r = rows[e.key], let i = r.firstIndex(where: { row in countingID.map { $0 == row.id } ?? !row.saved }) {
            let ex = program.exercise(e.key)
            let units = ["kg": " kg", "reps": " reps", "seconds": " s", "meters": " m"]
            let target = ex.fields.prefix(2).compactMap { f -> String? in
                let v = r[i].text[f] ?? placeholder(e, i, f)
                return v.isEmpty ? nil : v + units[f]!
            }.joined(separator: " × ")
            title = ex.shortName
            detail = ["Set \(i + 1) of \(r.count)", target].filter { !$0.isEmpty }.joined(separator: " · ")
        }
        LiveWorkout.show(name: template.name, isRun: false, startedAt: started, state: .init(phase: .lift, title: title, detail: detail, progress: "\(doneSets) of \(total) sets", target: nil, restSince: lastTick, countdown: countdown?.range))
    }

    private struct SetSaved: Decodable { let workout_id: Int? }
    private struct NoteSaved: Decodable { let workout_id: Int? }
}

extension Program {
    /// "75 kg × 5, 5, 5" style summary of logged sets.
    func describe(_ key: String, _ sets: [SetRow.Values]) -> String {
        guard !sets.isEmpty else { return "" }
        let f = exercise(key).fields
        if f.first == "reps" { return sets.map { "\($0.reps ?? 0)" + (($0.weight_kg ?? 0) > 0 ? " (+\(Fmt.number($0.weight_kg)) kg)" : "") }.joined(separator: ", ") }
        if f.contains("kg"), f.contains("reps") {
            let same = sets.allSatisfy { $0.weight_kg == sets[0].weight_kg }
            return same ? "\(Fmt.number(sets[0].weight_kg ?? 0)) kg × " + sets.map { "\($0.reps ?? 0)" }.joined(separator: ", ")
                : sets.map { "\(Fmt.number($0.weight_kg ?? 0))×\($0.reps ?? 0)" }.joined(separator: ", ")
        }
        if f.contains("seconds") { return sets.map { "\($0.seconds ?? 0) s" }.joined(separator: ", ") }
        if f.contains("meters") { return sets.map { "\(Fmt.number($0.weight_kg ?? 0)) kg × \(Fmt.number($0.distance_m ?? 0)) m" }.joined(separator: ", ") }
        return ""
    }
}
