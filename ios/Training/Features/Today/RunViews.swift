import Charts
import SwiftUI
import UniformTypeIdentifiers

/// Inside the session card on run days: what to do, heart rate targets, the interval timer, and the result fields.
struct RunBody: View {
    let model: DayModel
    @State private var distance = ""
    @State private var time = ""
    @State private var hr = ""
    @State private var importing = false
    @State private var activity: GarminActivity?
    private var runner: IntervalRunner { .shared }

    var body: some View {
        let t = model.template, p = model.program, zones = p.heartRate.zones
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            if let d = t.detail { Text(d).font(Theme.Typography.callout) }
            if t.easy == true, let easy = zones.first { Banner("Keep heart rate under \(easy.to). Pace is a guide only.", tone: .accent) }
            if t.timeTrial == true {
                let target = AppModel.shared.settings.number("five_k_target_sec") ?? p.running.fiveKTargetSec
                Banner("Target by week 16: under \(Fmt.time(target)) (\(Fmt.pace(target / 5))), stretch \(Fmt.time(p.running.fiveKStretchSec)).", tone: .accent)
            }
            if t.kind == "run" {
                HeartRateZones(heartRate: p.heartRate, highlight: t.easy == true ? [0] : t.intervals != nil ? [2, 3] : [])
                if let c = p.running.cadenceNote { Text(c).font(Theme.Typography.caption).foregroundStyle(Theme.Palette.muted) }
                timer(t, zones)
            }
            HStack(spacing: Theme.Space.s) {
                LabeledField(label: "Distance (km)") { TextField(t.timeTrial == true ? "5.00" : "km", text: $distance).keyboardType(.decimalPad) }
                LabeledField(label: "Time") { TextField("mm:ss", text: $time).keyboardType(.numbersAndPunctuation) }
                LabeledField(label: "Avg HR") { TextField("bpm", text: $hr).keyboardType(.numberPad) }
            }
            if let km = Fmt.parse(distance), km > 0, let s = Fmt.parseTime(time) { Text("Pace \(Fmt.pace(s / km))").font(Theme.Typography.caption).foregroundStyle(Theme.Palette.muted) }
            garmin
        }
        .onAppear {
            distance = Fmt.number(model.workout?.distance_km); time = Fmt.time(model.workout?.time_sec); hr = Fmt.number(model.workout?.avg_hr)
        }
        .onChange(of: [distance, time, hr]) { _, _ in model.setRun(distance: distance, time: time, hr: hr) }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.data], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { Task { await attach(urls) } }
        }
        .sheet(item: $activity) { ActivitySheet(id: $0.id) }
    }

    /// Start button, or the running phase with its countdown. Mirrored on the lock screen by the Live Activity.
    @ViewBuilder
    private func timer(_ t: Template, _ zones: [Program.Zone]) -> some View {
        if runner.isActive, runner.date == model.date {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                if let phase = runner.current, let end = runner.phaseEnds {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(phase.title).font(Theme.Typography.title)
                            Text(phase.detail).font(Theme.Typography.caption).foregroundStyle(Theme.Palette.muted)
                        }
                        Spacer()
                        Text(timerInterval: Date()...max(end, Date()), countsDown: true).font(Theme.Typography.timer).foregroundStyle(phase.kind == .work ? Theme.Palette.danger : Theme.Palette.ok)
                    }
                    if let target = phase.target { Label(target, systemImage: "heart.fill").font(Theme.Typography.caption).foregroundStyle(Theme.Palette.muted) }
                    if let next = runner.next { Text("Next: \(next.title) \(Fmt.time(Double(next.seconds)))").font(Theme.Typography.caption).foregroundStyle(Theme.Palette.muted) }
                } else if let started = runner.startedAt {
                    Text(started, style: .timer).font(Theme.Typography.timer)
                }
                HStack(spacing: Theme.Space.s) {
                    if runner.current != nil { Button("Skip to next") { runner.advance() }.buttonStyle(.tinted) }
                    Button("Stop") { runner.stop() }.buttonStyle(.tinted(.danger))
                }
            }
            .padding(Theme.Space.m)
            .background(Theme.Palette.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
        } else if model.isToday, model.workout?.status != "done" {
            let phases = IntervalRunner.phases(for: t, zones: zones)
            Button(phases.isEmpty ? "Start run timer" : "Start interval timer") {
                runner.start(name: t.name, date: model.date, phases: phases, steadyTarget: t.easy == true ? zones.first.map { "under \($0.to) bpm" } : nil)
            }
            .buttonStyle(.primary)
            if !phases.isEmpty {
                Text("Spoken cues and a Live Activity for the 10 min warm-up, each rep and recovery, and a 5 min cool-down.").font(Theme.Typography.caption).foregroundStyle(Theme.Palette.muted)
            }
        }
    }

    private var garmin: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            SectionTitle("Garmin")
            ForEach(model.workout?.activities ?? []) { a in
                ActionRow(title: [a.distance_m.map { String(format: "%.2f km", $0 / 1000) }, a.duration_s.map { Fmt.time($0) }, a.avg_pace_s_per_km.map { Fmt.pace($0) }].compactMap { $0 }.joined(separator: " · "),
                          subtitle: [a.avg_hr.map { "avg HR \(Int($0))" }, a.max_hr.map { "max \(Int($0))" }, a.best_5k_s.map { "best 5 km \(Fmt.time($0))" }].compactMap { $0 }.joined(separator: " · ")) { activity = a }
            }
            Button((model.workout?.activities ?? []).isEmpty ? "Attach the Garmin file for this run" : "Attach another file") { importing = true }.font(Theme.Typography.callout)
            Text("FIT, TCX, GPX or CSV").font(Theme.Typography.caption).foregroundStyle(Theme.Palette.muted)
        }
    }

    private func attach(_ urls: [URL]) async {
        if (model.workout?.id ?? 0) == 0 { await model.saveWorkout([:]) }
        var fields = ["date": model.date, "source": "garmin", "tz_offset_min": String(-TimeZone.current.secondsFromGMT() / 60)]
        if let id = model.workout?.id, id > 0 { fields["workout_id"] = String(id) }
        do {
            let r = try await API.shared.upload(files: urls, fields: fields)
            let failed = r.uploads.first { $0.status == "failed" }
            model.toast = failed.map { "Stored, but could not parse: \($0.error ?? "")" } ?? "Garmin file attached"
            await model.load()
        } catch { model.toast = error.localizedDescription }
    }
}

/// Heart rate zones from the program, with the zones that matter today highlighted.
struct HeartRateZones: View {
    let heartRate: Program.HeartRate
    var highlight: Set<Int> = []
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HStack {
                Text("HEART RATE").font(Theme.Typography.label).foregroundStyle(Theme.Palette.muted)
                Spacer()
                Text("max \(heartRate.maxBpm) · threshold \(heartRate.thresholdBpm)").font(Theme.Typography.caption).foregroundStyle(Theme.Palette.muted)
            }
            HStack(spacing: Theme.Space.xs) {
                ForEach(Array(heartRate.zones.enumerated()), id: \.offset) { i, z in
                    let on = highlight.contains(i)
                    VStack(spacing: 2) {
                        Text(z.name).font(Theme.Typography.label)
                        Text("\(z.from)–\(z.to)").font(Theme.Typography.callout.monospacedDigit())
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, Theme.Space.s)
                    .foregroundStyle(on ? .white : Theme.Palette.text)
                    .background(on ? Theme.Palette.run : Theme.Palette.fill, in: RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
                }
            }
        }
    }
}

/// Parsed Garmin activity: totals, heart rate over distance, splits and time in zones.
struct ActivitySheet: View {
    let id: Int
    @State private var activity: GarminActivity?
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Screen {
                if let a = activity {
                    TileGrid {
                        Tile(label: "Distance", value: a.distance_m.map { String(format: "%.2f km", $0 / 1000) } ?? "–")
                        Tile(label: "Time", value: Fmt.time(a.duration_s))
                        Tile(label: "Pace", value: Fmt.pace(a.avg_pace_s_per_km))
                        Tile(label: "Avg HR", value: a.avg_hr.map { "\(Int($0))" } ?? "–", detail: a.max_hr.map { "max \(Int($0))" })
                    }
                    let track = (a.track ?? []).filter { $0.d != nil && $0.hr != nil }
                    if track.count > 5 {
                        Chart(Array(track.enumerated()), id: \.offset) { _, p in
                            LineMark(x: .value("km", p.d!), y: .value("Heart rate", p.hr!)).foregroundStyle(Theme.Palette.danger)
                        }
                        .chartYScale(domain: .automatic(includesZero: false))
                        .frame(height: 180).card()
                    }
                    let splits = (a.splits ?? []).isEmpty ? (a.laps ?? []) : a.splits!
                    if !splits.isEmpty {
                        Grid(alignment: .trailing, horizontalSpacing: Theme.Space.l, verticalSpacing: Theme.Space.s) {
                            GridRow { Text("km").gridColumnAlignment(.leading); Text("time"); Text("pace"); Text("HR") }.font(Theme.Typography.label).foregroundStyle(Theme.Palette.muted)
                            ForEach(Array(splits.enumerated()), id: \.offset) { _, s in
                                GridRow {
                                    Text((s.km ?? s.index)?.text ?? "")
                                    Text(Fmt.time(s.seconds ?? s.duration_s))
                                    Text(Fmt.pace(s.pace_s_per_km))
                                    Text(s.avg_hr.map { "\(Int($0))" } ?? "")
                                }
                                .font(Theme.Typography.callout.monospacedDigit())
                            }
                        }
                        .card()
                    }
                    if let z = a.hr_zones?.seconds {
                        Text("Time in zones: " + z.enumerated().map { "Z\($0 + 1) \(Fmt.time($1))" }.joined(separator: " · ")).font(Theme.Typography.caption).foregroundStyle(Theme.Palette.muted)
                    }
                } else if let error {
                    ErrorCard(message: error) { await load() }
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 60)
                }
            }
            .navigationTitle("Garmin activity").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Close") { dismiss() } } }
            .task { await load() }
        }
    }

    private func load() async {
        do { activity = try await API.shared.get("/api/activities/\(id)"); error = nil } catch { self.error = error.localizedDescription }
    }
}
