import SwiftUI

/// Sessions that can be picked for a day. Same list as the web app.
let pickableTemplates = ["lift_a", "lift_b", "lift_c", "intervals_6x2", "intervals_5x3", "intervals_4x4", "time_trial_5k", "easy_run", "other", "rest_walk"]
private let shortNames = ["lift_a": "Lift A", "lift_b": "Lift B", "lift_c": "Lift C", "intervals_6x2": "Int", "intervals_5x3": "Int", "intervals_4x4": "Int", "time_trial_5k": "5 km", "easy_run": "Easy", "rest_walk": "Off", "rest_padel": "Padel", "other": "Other"]

/// Month grid of planned sessions, or a list of everything logged.
struct CalendarScreen: View {
    @State private var month = String(Day.today().prefix(7)) + "-01"
    @State private var schedule: Schedule?
    @State private var history: [Workout] = []
    @State private var error: String?
    @State private var showList = false
    @State private var openDay: String?

    var body: some View {
        Screen {
            Picker("View", selection: $showList) { Text("Month").tag(false); Text("List").tag(true) }.pickerStyle(.segmented)
            if let error { ErrorCard(message: error) { await load() } }
            if showList { list } else { grid }
        }
        .navigationTitle("Calendar")
        .navigationDestination(item: $openDay) { DayScreen(date: $0) }
        .task(id: "\(month)\(showList)") { await load() }
        .refreshable { await load() }
    }

    @ViewBuilder
    private var grid: some View {
        VStack(spacing: Theme.Space.m) {
            HStack {
                Button { month = Day.addMonths(month, -1) } label: { Image(systemName: "chevron.left") }.accessibilityLabel("Previous month")
                Spacer()
                Text(Day.month(month)).font(Theme.Typography.title)
                Spacer()
                Button { month = Day.addMonths(month, 1) } label: { Image(systemName: "chevron.right") }.accessibilityLabel("Next month")
            }
            let columns = Array(repeating: GridItem(.flexible(), spacing: Theme.Space.xs), count: 7)
            LazyVGrid(columns: columns, spacing: Theme.Space.xs) {
                ForEach(["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"], id: \.self) { Text($0).font(Theme.Typography.label).foregroundStyle(Theme.Palette.muted) }
                ForEach(schedule?.days ?? []) { d in
                    Button { openDay = d.date } label: { cell(d) }.buttonStyle(.plain)
                }
            }
            HStack(spacing: Theme.Space.m) {
                legend("Lift", Theme.Palette.lift); legend("Run", Theme.Palette.run); legend("Done", Theme.Palette.ok)
                Label("Moved", systemImage: "arrow.left.arrow.right").font(Theme.Typography.caption).foregroundStyle(Theme.Palette.muted)
            }
        }
        .card()
        if let days = schedule?.days.filter({ $0.date.hasPrefix(month.prefix(7)) && $0.kind != "rest" }) {
            let done = days.filter { $0.main?.status == "done" }.count
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                CardTitle(title: "This month") { Badge("\(done) of \(days.count) done", tone: done > 0 ? .ok : .neutral) }
                Text("\(days.filter { $0.kind == "lift" }.count) lifting days and \(days.filter { $0.kind == "run" }.count) runs planned. Extras like padel are not counted.")
                    .font(Theme.Typography.caption).foregroundStyle(Theme.Palette.muted)
            }
            .card()
        }
    }

    private func cell(_ d: ScheduleDay) -> some View {
        let status = d.main?.status
        let color = status == "done" ? Theme.Palette.ok : Theme.Palette.kind(d.kind)
        let isToday = d.date == Day.today()
        return VStack(spacing: 2) {
            Text(Day.dayNumber(d.date)).font(Theme.Typography.callout.weight(isToday ? .bold : .regular)).foregroundStyle(isToday ? Theme.Palette.accent : Theme.Palette.text)
            Text(shortNames[d.templateKey] ?? d.name).font(Theme.Typography.label).foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.7)
            Image(systemName: status == "done" ? "checkmark" : d.moved ? "arrow.left.arrow.right" : "circle.fill")
                .font(.system(size: 7, weight: .bold)).foregroundStyle(d.moved && status != "done" ? Theme.Palette.accent : color).opacity(status == nil && !d.moved ? 0 : 1)
        }
        .frame(maxWidth: .infinity).padding(.vertical, Theme.Space.s)
        .background(isToday ? Theme.Palette.accent.opacity(0.12) : Theme.Palette.fill.opacity(0.5), in: RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
        .opacity(d.date.hasPrefix(month.prefix(7)) ? (status == "skipped" ? 0.5 : 1) : 0.35)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Day.label(d.date)), \(d.name)\(status.map { ", \($0.replacingOccurrences(of: "_", with: " "))" } ?? "")")
    }

    private func legend(_ text: String, _ color: Color) -> some View {
        HStack(spacing: Theme.Space.xs) { Circle().fill(color).frame(width: 7, height: 7); Text(text) }.font(Theme.Typography.caption).foregroundStyle(Theme.Palette.muted)
    }

    @ViewBuilder
    private var list: some View {
        let program = AppModel.shared.program
        if history.isEmpty, error == nil { Text("Nothing logged yet.").foregroundStyle(Theme.Palette.muted).card() }
        ForEach(history) { w in
            Button { openDay = w.date } label: {
                Row(title: "\(Day.label(w.date)) · \(program?.templates[w.template_key]?.name ?? w.template_key)",
                    subtitle: [w.set_count.flatMap { $0 > 0 ? "\($0) sets" : nil }, w.volume_kg.flatMap { $0 > 0 ? "\(Fmt.whole($0)) kg" : nil }, w.distance_km.map { "\(Fmt.number($0)) km" }, w.time_sec.map { Fmt.time($0) }, w.notes].compactMap { $0 }.joined(separator: " · ")) {
                    Badge(w.status.replacingOccurrences(of: "_", with: " "), tone: w.status == "done" ? .ok : w.status == "skipped" ? .danger : .accent)
                }
            }
            .buttonStyle(.plain).card()
        }
    }

    private func load() async {
        do {
            if showList {
                history = try await API.shared.get("/api/workouts?limit=500")
            } else {
                let last = Day.add(Day.addMonths(month, 1), -1)
                schedule = try await API.shared.get("/api/schedule?from=\(Day.monday(of: month))&to=\(Day.add(Day.monday(of: last), 6))", cache: true)
            }
            error = nil
        } catch { self.error = error.localizedDescription }
    }
}

/// Swap a day with another day, change its session, or return it to the plan. Opened from the day itself.
struct SessionChangeSheet: View {
    let date: String
    let done: () async -> Void
    @State private var schedule: Schedule?
    @State private var error: String?
    @State private var swapWith: ScheduleDay?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let day = schedule?.days.first { $0.date == date }
        let templates = AppModel.shared.program?.templates ?? [:]
        NavigationStack {
            List {
                if let error { Text(error).foregroundStyle(Theme.Palette.danger) }
                if let day {
                    Section {
                        Row(title: day.name, subtitle: [day.subtitle, day.deload ? "deload week" : nil, day.testWeek ? "test week" : nil, day.moved ? "moved, the plan has \(templates[day.defaultTemplateKey]?.name ?? "")" : nil].compactMap { $0 }.joined(separator: " · ")) {
                            if let s = day.main?.status { Badge(s.replacingOccurrences(of: "_", with: " "), tone: s == "done" ? .ok : s == "skipped" ? .danger : .accent) }
                        }
                        if day.moved { Button("Back to the plan: \(templates[day.defaultTemplateKey]?.name ?? "")") { apply { try await API.shared.send("PUT", "/api/schedule/\(date)", ["template_key": nil]) } } }
                    }
                    Section {
                        ForEach((schedule?.days ?? []).filter { $0.date != date }) { d in
                            Button { swapWith = d } label: {
                                Row(Day.label(d.date) + (d.date == schedule?.today ? " (today)" : ""), subtitle: [d.name, d.main?.status.replacingOccurrences(of: "_", with: " "), d.moved ? "moved" : nil].compactMap { $0 }.joined(separator: " · "))
                            }
                        }
                    } header: { Text("Swap with another day") } footer: { Text("Days are interchangeable. Avoid two lifting days back to back, and keep jump days 48 hours apart.") }
                    Section("Or do a different session this day") {
                        ForEach(pickableTemplates.compactMap { templates[$0] }, id: \.key) { t in
                            Button { if t.key == day.templateKey { dismiss() } else { apply { try await API.shared.send("PUT", "/api/schedule/\(date)", ["template_key": t.key]) } } } label: {
                                Row(title: t.name, subtitle: t.subtitle, titleColor: Theme.Palette.kind(t.kind)) {
                                    if t.key == day.defaultTemplateKey { Badge("planned") } else if t.key == day.templateKey { Badge("current", tone: .accent) }
                                }
                            }
                        }
                    }
                } else if error == nil {
                    ProgressView()
                }
            }
            .navigationTitle(Day.label(date, year: true)).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .confirmationDialog("Swap these two days?", isPresented: Binding(get: { swapWith != nil }, set: { if !$0 { swapWith = nil } }), titleVisibility: .visible, presenting: swapWith) { other in
                Button("Swap") { apply { try await API.shared.send("POST", "/api/schedule/swap", ["a": date, "b": other.date]) } }
            } message: { other in
                Text("\(Day.label(date)) becomes \(other.name). \(Day.label(other.date)) becomes \(day?.name ?? ""). Anything already logged stays on its day.")
            }
            .task {
                let monday = Day.monday(of: date)
                do { schedule = try await API.shared.get("/api/schedule?from=\(monday)&to=\(Day.add(monday, 13))") } catch { self.error = error.localizedDescription }
            }
        }
    }

    private func apply(_ change: @escaping () async throws -> Void) {
        Task {
            do {
                try await change()
                UserDefaults.standard.removeObject(forKey: "active_\(date)")
                await done()
                dismiss()
            } catch { self.error = error.localizedDescription }
        }
    }
}
