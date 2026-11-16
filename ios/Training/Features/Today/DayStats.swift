import SwiftUI

/// The watch's and the scale's numbers for the last months, shared by every day page so they are fetched once.
/// It is the Home model, so a tile on a day can open the same detail page as the widget on Home.
@MainActor @Observable
final class DayStatsStore {
    static let shared = DayStatsStore()
    let home = HomeModel()
    private var loadedAt: Date?
    var days: [String: [String: MetricDay.Value]] { home.days }

    /// Fetches again when the last fetch is more than a few minutes old.
    func load() async {
        if let loadedAt, Date().timeIntervalSince(loadedAt) < 300 { return }
        loadedAt = Date()
        await home.load()
    }
}

/// How one day went, from the watch and the scale. Every number is set against his own last 30 days, a headline
/// names what stood out, and the night, the energy, the movement and the heart are drawn, not listed. Each tile
/// opens that measure's detail page. A tile shows only when the day has something for it.
struct DayStats: View {
    let date: String
    /// The weight logged that day, typed in or from the scale.
    var weight: Double? = nil
    @State private var more = false
    private var store: DayStatsStore { .shared }
    private var day: [String: MetricDay.Value] { store.days[date] ?? [:] }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            if !day.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text(date == Day.today() ? "THE DAY SO FAR" : "THE DAY").font(Theme.Typography.label).foregroundStyle(Theme.Palette.muted)
                    Text(headline).font(Theme.Typography.headline).fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, Theme.Space.xs).padding(.top, Theme.Space.s)
                DayClock(date: date, bedtime: {
                    let next = Day.add(date, 1), offset = Double(TimeZone.current.secondsFromGMT()) / 60
                    return n("sleep.bedMinutesLocal", on: next) ?? n("sleep.bedMinutesGMT", on: next).map { ($0 + offset + 1440).truncatingRemainder(dividingBy: 1440) }
                }())
                night
                movement
                energy
                heart
                bodyTile
                extras
            }
        }
        .task { await store.load() }
    }

    // MARK: Numbers

    private func n(_ key: String, on d: String? = nil) -> Double? { store.days[d ?? date]?[key]?.number }
    private func intensity(on d: String? = nil) -> Double? {
        let m = n("intensityMinutes.moderate", on: d), v = n("intensityMinutes.vigorous", on: d)
        return m == nil && v == nil ? nil : (m ?? 0) + 2 * (v ?? 0) // Garmin counts a vigorous minute twice
    }

    /// His normal for a measure: the average over the 30 days before this one. nil with fewer than five days to go on.
    private func usual(_ value: (String) -> Double?) -> Double? {
        let v = (1...30).compactMap { value(Day.add(date, -$0)) }
        return v.count >= 5 ? v.reduce(0, +) / Double(v.count) : nil
    }
    private func usual(_ key: String) -> Double? { usual { n(key, on: $0) } }

    /// The seven days ending on this one, for a small line.
    private func week(_ key: String) -> [Double?] { (0..<7).map { n(key, on: Day.add(date, -(6 - $0))) } }

    /// How many days back one has to go to find a higher value.
    private func highestIn(_ key: String) -> Int? {
        guard let today = n(key) else { return nil }
        for back in 1...60 { if let v = n(key, on: Day.add(date, -back)), v >= today { return back - 1 } }
        return nil
    }

    // MARK: Headline

    /// One sentence on what stood out against his normal.
    private var headline: String {
        struct Note { let text: String; let size: Double; let good: Bool }
        var notes: [Note] = []
        func compare(_ name: String, _ value: Double?, _ normal: Double?, higherIsGood: Bool, unit: String? = nil) {
            guard let value, let normal, normal > 0 else { return }
            let change = (value - normal) / normal
            guard abs(change) >= 0.1 else { return }
            let amount = unit.map { "\(Fmt.whole(abs(value - normal))) \($0)" } ?? "\(Fmt.whole(abs(change) * 100)) %"
            notes.append(Note(text: "\(name) \(amount) \(change > 0 ? "above" : "below") usual", size: abs(change), good: (change > 0) == higherIsGood))
        }
        if let run = highestIn("movement.steps.value"), run >= 7, let steps = n("movement.steps.value") {
            notes.append(Note(text: "most steps in \(run >= 14 ? "\(run / 7) weeks" : "\(run) days") (\(Fmt.whole(steps)))", size: 1, good: true))
        } else {
            compare("steps", n("movement.steps.value"), usual("movement.steps.value"), higherIsGood: true)
        }
        compare("sleep", n("sleep.sleepTimeSeconds").map { $0 / 60 }, usual("sleep.sleepTimeSeconds").map { $0 / 60 }, higherIsGood: true, unit: "min")
        compare("resting heart rate", n("heartRate.restingValue"), usual("heartRate.restingValue"), higherIsGood: false, unit: "bpm")
        compare("HRV", n("hrv.lastNightAvg"), usual("hrv.lastNightAvg"), higherIsGood: true)
        compare("intensity minutes", intensity(), usual { intensity(on: $0) }, higherIsGood: true)
        compare("stress", n("stress.avgLevel"), usual("stress.avgLevel"), higherIsGood: false)
        let top = notes.sorted { $0.size > $1.size }.prefix(2)
        guard !top.isEmpty else { return "A normal day: nothing far from your usual." }
        let good = top.filter(\.good).count
        let lead = good == top.count ? "Strong day" : good == 0 ? "Tough day" : "Mixed day"
        return "\(lead): " + top.map(\.text).joined(separator: ", ") + "."
    }

    // MARK: Tiles

    /// The night on a clock from 20:00 to 12:00, split into its stages.
    @ViewBuilder
    private var night: some View {
        if let slept = n("sleep.sleepTimeSeconds") {
            let offset = Double(TimeZone.current.secondsFromGMT()) / 60
            let clock = { (name: String) in n("sleep.\(name)MinutesLocal") ?? n("sleep.\(name)MinutesGMT").map { $0 + offset } }
            let bed = clock("bed").map(Self.evening)
            let wake = clock("wake").map(Self.evening) ?? bed.map { $0 + (slept + (n("sleep.awakeSleepSeconds") ?? 0)) / 60 }
            let stages: [(Double, Color)] = [(n("sleep.deepSleepSeconds") ?? 0, Theme.Palette.text), (n("sleep.lightSleepSeconds") ?? 0, Theme.Palette.text.opacity(0.5)),
                                             (n("sleep.remSleepSeconds") ?? 0, Theme.Palette.calm), (n("sleep.awakeSleepSeconds") ?? 0, Theme.Palette.warn)]
            tile(.sleep, fill: Theme.Palette.dusk) {
                HStack(alignment: .firstTextBaseline) {
                    Label("NIGHT BEFORE", systemImage: "moon.zzz.fill").font(Theme.Typography.label)
                    Spacer()
                    if let score = n("sleep.sleepScores.overall.value") { Text("SCORE \(Fmt.whole(score))").font(Theme.Typography.label) }
                }
                HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                    Text(Fmt.hours(slept)).font(Theme.Typography.timer)
                    Delta(value: slept / 60, usual: usual("sleep.sleepTimeSeconds").map { $0 / 60 }, unit: "min")
                }
                if let bed, let wake, wake > bed {
                    HStack(alignment: .top) {
                        small("Fell asleep", Self.clock(bed))
                        small("Woke up", Self.clock(wake))
                    }
                }
                // How the night was shared out: one bar, and each stage named with its time under it.
                let named = Array(zip(["Deep", "Light", "REM", "Awake"], stages)).filter { $0.1.0 > 0 }
                if !named.isEmpty {
                    SleepTimeline(date: date, colors: stages.map(\.1), fallback: named.map(\.1))
                    HStack(alignment: .top, spacing: Theme.Space.s) {
                        ForEach(named, id: \.0) { name, stage in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 4) { Circle().fill(stage.1).frame(width: 8, height: 8); Text(name).font(Theme.Typography.caption) }
                                Text("\(Int(stage.0) / 3600) h \(Int(stage.0) % 3600 / 60) m").font(Theme.Typography.caption.weight(.semibold))
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
        }
    }

    /// Steps and intensity as rings toward their goals, with distance and calories beside them.
    @ViewBuilder
    private var movement: some View {
        if let steps = n("movement.steps.value") {
            let goal = n("movement.steps.goal") ?? 0
            let minutes = intensity()
            tile(.steps, fill: Theme.Palette.butter) {
                Label("MOVEMENT", systemImage: "figure.walk").font(Theme.Typography.label)
                HStack(alignment: .center, spacing: Theme.Space.l) {
                    ProgressRing(progress: goal > 0 ? steps / goal : 0, color: Theme.Palette.text, size: 64)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Fmt.whole(steps)).font(Theme.Typography.timer)
                        HStack(spacing: Theme.Space.s) {
                            Text(goal > 0 ? "steps of \(Fmt.whole(goal))" : "steps").font(Theme.Typography.caption).muted()
                            Delta(value: steps, usual: usual("movement.steps.value"))
                        }
                    }
                }
                HStack(alignment: .top, spacing: Theme.Space.m) {
                    if let km = n("movement.steps.distanceInMeters") { small("On foot", String(format: "%.1f km", km / 1000)) }
                    if let minutes { small("Intensity", "\(Fmt.whole(minutes)) min", delta: Delta(value: minutes, usual: usual { intensity(on: $0) })) }
                    if let kcal = n("calories.burnedActive") { small("Active", "\(Fmt.whole(kcal)) kcal") }
                }
            }
        }
    }

    /// Body Battery as the stretch between the day's low and high on a 0 to 100 track, and stress.
    @ViewBuilder
    private var energy: some View {
        if let high = n("bodyBattery.maxValue"), let low = n("bodyBattery.minValue") {
            tile(.bodyBattery) {
                HStack(alignment: .firstTextBaseline) {
                    Label("BODY BATTERY", systemImage: "battery.75percent").font(Theme.Typography.label).foregroundStyle(Theme.Palette.ok)
                    Spacer()
                    Text("SPENT \(Fmt.whole(high - low))").font(Theme.Typography.label).foregroundStyle(Theme.Palette.muted)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.Palette.fill)
                        Capsule().fill(LinearGradient(colors: [Theme.Palette.ok, Theme.Palette.warn], startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(geo.size.width * (high - low) / 100, 10)).offset(x: geo.size.width * (100 - high) / 100) // 100 on the left, 0 on the right
                    }
                }
                .frame(height: 14)
                HStack(alignment: .top) {
                    small("Highest", Fmt.whole(high), delta: Delta(value: high, usual: usual("bodyBattery.maxValue")), note: "usually on waking")
                    small("Lowest", Fmt.whole(low))
                    if let stress = n("stress.avgLevel") { small("Stress", Fmt.whole(stress), delta: Delta(value: stress, usual: usual("stress.avgLevel"), lowerIsGood: true), note: n("stress.maxLevel").map { "peak \(Fmt.whole($0))" }) }
                }
            }
        }
    }

    /// Resting heart rate and HRV, each with the week leading up to the day.
    @ViewBuilder
    private var heart: some View {
        let resting = n("heartRate.restingValue"), hrv = n("hrv.lastNightAvg")
        if resting != nil || hrv != nil {
            HStack(alignment: .top, spacing: Theme.Space.m) {
                if let resting {
                    tile(.restingHR) {
                        Label("RESTING HR", systemImage: "heart.fill").font(Theme.Typography.label).foregroundStyle(Theme.Palette.heart)
                        HStack(alignment: .firstTextBaseline, spacing: 3) { Text(Fmt.whole(resting)).font(Theme.Typography.timer); Text("bpm").font(Theme.Typography.caption).muted() }
                        Spark(values: week("heartRate.restingValue"), style: .line, color: Theme.Palette.heart, relative: true, height: 34)
                        Delta(value: resting, usual: usual("heartRate.restingValue"), unit: "bpm", lowerIsGood: true)
                    }
                }
                if let hrv {
                    tile(.hrv) {
                        Label("HRV", systemImage: "waveform.path.ecg").font(Theme.Typography.label).foregroundStyle(CardKind.hrv.tint)
                        HStack(alignment: .firstTextBaseline, spacing: 3) { Text(Fmt.whole(hrv)).font(Theme.Typography.timer); Text("ms").font(Theme.Typography.caption).muted() }
                        Spark(values: week("hrv.lastNightAvg"), style: .line, color: CardKind.hrv.tint, relative: true, height: 34)
                        Delta(value: hrv, usual: usual("hrv.lastNightAvg"))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var bodyTile: some View {
        let items: [(String, String?)] = [("Weight", weight.map { String(format: "%.1f kg", $0) }), ("Body fat", n("body.fatPercent").map { String(format: "%.1f %%", $0) }),
                                          ("Lean mass", n("body.leanMassKg").map { String(format: "%.1f kg", $0) }), ("BMI", n("body.bmi").map { String(format: "%.1f", $0) })]
        let shown = items.filter { $0.1 != nil }
        if !shown.isEmpty {
            tile(.weight) {
                Label("BODY", systemImage: "scalemass").font(Theme.Typography.label).foregroundStyle(Theme.Palette.calm)
                HStack(alignment: .top) { ForEach(shown, id: \.0) { small($0.0, $0.1!) } }
            }
        }
    }

    /// The numbers that rarely matter, folded away.
    @ViewBuilder
    private var extras: some View {
        let items: [(String, String?)] = [("Breathing", n("respiration.avgValue").map { String(format: "%.1f /min", $0) }), ("Blood oxygen", n("pulseOx.avgValue").map { "\(Fmt.whole($0)) %" }),
                                          ("Floors", n("movement.floorsAscended.value").map { Fmt.whole($0) }), ("Total calories", n("calories.burnedTotal").map { "\(Fmt.whole($0)) kcal" }),
                                          ("Waist", n("body.waistCm").map { String(format: "%.1f cm", $0) })]
        let shown = items.filter { $0.1 != nil }
        if !shown.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Button { withAnimation(.snappy) { more.toggle() } } label: {
                    Label(more ? "Less" : "More from the day", systemImage: more ? "chevron.up" : "chevron.down").font(Theme.Typography.label).foregroundStyle(Theme.Palette.muted)
                }
                .buttonStyle(.plain)
                if more {
                    ForEach(shown, id: \.0) { item in
                        HStack { Text(item.0).font(Theme.Typography.callout).foregroundStyle(Theme.Palette.muted); Spacer(); Text(item.1!).font(Theme.Typography.callout.weight(.semibold).monospacedDigit()) }
                    }
                }
            }
            .padding(.horizontal, Theme.Space.xs)
        }
    }

    // MARK: Pieces

    /// A tile that opens the detail page of its measure: glass, or a grainy card of colour when given a fill.
    private func tile(_ kind: CardKind, fill: [Color]? = nil, @ViewBuilder content: () -> some View) -> some View {
        NavigationLink { WidgetDetailScreen(model: store.home, kind: kind) } label: {
            VStack(alignment: .leading, spacing: Theme.Space.s) { content() }
                .foregroundStyle(Theme.Palette.text)
                .padding(Theme.Space.l)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .cardSurface(fill: fill, lightFill: fill.map { Theme.Palette.isLight($0[0]) } ?? false)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func small(_ label: String, _ value: String, delta: Delta? = nil, note: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(Theme.Typography.caption).muted()
            Text(value).font(Theme.Typography.numeral).lineLimit(1).minimumScaleFactor(0.6)
            if let delta { delta }
            if let note { Text(note).font(Theme.Typography.caption).muted().lineLimit(1).minimumScaleFactor(0.8) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Minutes after midnight as minutes after 18:00, so a night stays in one piece.
    private static func evening(_ minutes: Double) -> Double {
        let m = (minutes - 18 * 60).truncatingRemainder(dividingBy: 1440)
        return m < 0 ? m + 1440 : m
    }
    private static func clock(_ evening: Double) -> String {
        let m = (Int(evening.rounded()) + 18 * 60) % 1440
        return String(format: "%02d:%02d", m / 60, m % 60)
    }
}

/// How a number sits against his usual: an arrow and the gap, green when that is the good direction. On a card of
/// colour it is drawn in the text colour, since green or amber would not read there.
struct Delta: View {
    let value: Double
    let usual: Double?
    /// Shows the gap in this unit ("12 min"). Without one it is a percentage.
    var unit: String? = nil
    var lowerIsGood = false
    @Environment(\.onColor) private var onColor

    var body: some View {
        if let usual, usual > 0 {
            let gap = value - usual, share = gap / usual
            if abs(share) < 0.03 {
                Text("as usual").font(Theme.Typography.caption).muted()
            } else {
                let good = (gap > 0) != lowerIsGood
                Label(unit.map { "\(Fmt.whole(abs(gap))) \($0)" } ?? "\(Fmt.whole(abs(share) * 100)) %", systemImage: gap > 0 ? "arrow.up" : "arrow.down")
                    .labelStyle(.titleAndIcon).font(Theme.Typography.caption.weight(.semibold))
                    .foregroundStyle(onColor ? Theme.Palette.text : good ? Theme.Palette.ok : Theme.Palette.warn)
                    .lineLimit(1).fixedSize()
                    .accessibilityLabel("\(Fmt.whole(abs(share) * 100)) percent \(gap > 0 ? "above" : "below") usual")
            }
        }
    }
}

/// GET /api/timeline/<date>: one day hour by hour. Moments are epoch milliseconds.
struct DayTimeline: Decodable {
    struct Event: Decodable, Hashable { let type: String; let start: Double; let end: Double; let impact: Double? }
    struct Recorded: Decodable, Hashable { let id: Int; let start_time: String?; let duration_s: Double?; let sport: String?; let name: String? }
    let hr: [[Double]]
    let battery: [[Double]]
    let events: [Event]
    var charged: Double? = nil
    var drained: Double? = nil
    var activities: [Recorded]? = nil
    var error: String? = nil
}

/// The day from midnight to midnight: heart rate and Body Battery as lines, with the hours asleep and the activities
/// shaded behind them. Shows nothing for a day Garmin has no such readings for.
struct DayClock: View {
    let date: String
    /// When he went to bed that evening, in minutes after midnight, from the next day's sleep.
    var bedtime: Double? = nil
    @State private var timeline: DayTimeline?

    /// Local midnight at the start of the day, in epoch milliseconds.
    private var midnight: Double {
        var parts = DateComponents()
        let p = date.split(separator: "-").compactMap { Int($0) }
        (parts.year, parts.month, parts.day) = (p.first, p.dropFirst().first, p.last)
        return (Calendar.current.date(from: parts) ?? Date()).timeIntervalSince1970 * 1000
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            if let t = timeline, t.hr.count > 3 || t.battery.count > 3 {
                var spans = Self.spans(t, midnight: midnight)
                // Garmin files a night under the morning it ends, so the evening's bedtime comes from the next day.
                let _ = { if let bedtime, bedtime >= 720, !spans.contains(where: { $0.sleep && $0.start > midnight + 43_200_000 }) {
                    spans.append(Span(start: midnight + bedtime * 60_000, end: midnight + 86_400_000, sleep: true)) } }()
                CardTitle("Through the day", note: [t.charged.map { "+\(Fmt.whole($0)) charged" }, t.drained.map { "-\(Fmt.whole($0)) drained" }].compactMap { $0 }.joined(separator: " · "))
                let beats = t.hr.compactMap { $0.count > 1 ? $0[1] : nil }.sorted()
                // At rest: within a quarter of the day's low heart rate. Garmin keeps its stress readings to itself.
                let rest = (beats.isEmpty ? 60 : beats[beats.count / 10]) * 1.25
                Canvas { context, size in
                    let x = { (ms: Double) in CGFloat(min(max((ms - midnight) / 86_400_000, 0), 1)) * size.width }
                    for level in stride(from: 25.0, through: 100, by: 25) {
                        let y = size.height * (1 - level / 100)
                        var line = Path(); line.move(to: CGPoint(x: 0, y: y)); line.addLine(to: CGPoint(x: size.width, y: y))
                        context.stroke(line, with: .color(Theme.Palette.separator.opacity(0.6)), lineWidth: 0.5)
                        context.draw(Text(Fmt.whole(level)).font(Theme.Typography.label).foregroundStyle(Theme.Palette.muted), at: CGPoint(x: 2, y: y + 2), anchor: .topLeading)
                    }
                    // Body Battery as a filled shape behind everything.
                    let points = Self.quarters(t.battery).map { CGPoint(x: x($0[0]), y: size.height * (1 - $0[1] / 100)) }
                    let line = Self.curve(points)
                    if let first = points.first, let last = points.last {
                        var area = line
                        area.addLine(to: CGPoint(x: last.x, y: size.height)); area.addLine(to: CGPoint(x: first.x, y: size.height)); area.closeSubpath()
                        context.fill(area, with: .linearGradient(Gradient(colors: [Theme.Palette.text.opacity(0.38), Theme.Palette.text.opacity(0.04)]), startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
                    }
                    // Heart rate as bars from the floor: blue at rest, orange when raised, grey during an activity.
                    if let high = beats.last {
                        let bar = size.width / 288 + 0.5 // a hair wider than its slot, so no gaps show between bars
                        let hr = t.hr.filter { $0.count > 1 }
                        for (i, p) in hr.enumerated() {
                            let active = spans.contains { !$0.sleep && p[0] >= $0.start && p[0] <= $0.end }
                            // Height eased with the neighbours on either side; the colour keeps the reading itself.
                            let near = [i > 0 ? hr[i - 1] : p, p, p, i + 1 < hr.count ? hr[i + 1] : p].filter { abs($0[0] - p[0]) < 900_000 }
                            let eased = active ? p[1] : near.map { $0[1] }.reduce(0, +) / Double(near.count)
                            let h = size.height * 0.9 * CGFloat(max(eased - 35, 2) / max(high - 35, 1))
                            context.fill(Path(CGRect(x: x(p[0]), y: size.height - h, width: bar, height: h)),
                                         with: .color(active ? Theme.Palette.muted : p[1] <= rest ? Theme.Palette.calm : Theme.Palette.energy))
                        }
                    }
                    context.stroke(line, with: .color(Theme.Palette.text), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                }
                .frame(height: 190)
                // Under the chart: where sleep began and ended, and each activity.
                GeometryReader { geo in
                    let x = { (ms: Double) in CGFloat(min(max((ms - midnight) / 86_400_000, 0), 1)) * geo.size.width }
                    ForEach(Array(spans.enumerated()), id: \.offset) { _, span in
                        if span.sleep {
                            if span.start >= midnight { mark("moon.zzz.fill", Theme.Palette.calm).position(x: x(span.start), y: 10) }
                            if span.end < midnight + 86_400_000 { mark("alarm.fill", Theme.Palette.calm).position(x: x(span.end), y: 10) }
                        } else {
                            mark("figure.run", Theme.Palette.ok).position(x: x((span.start + span.end) / 2), y: 10)
                        }
                    }
                }
                .frame(height: 20)
                HStack { Text("00"); Spacer(); Text("04"); Spacer(); Text("08"); Spacer(); Text("12"); Spacer(); Text("16"); Spacer(); Text("20"); Spacer(); Text("00") }
                    .font(Theme.Typography.label).foregroundStyle(Theme.Palette.muted)
                HStack(spacing: Theme.Space.m) {
                    key("Body Battery", Theme.Palette.text, line: true)
                    key("Heart at rest", Theme.Palette.calm, line: false)
                    key("Raised", Theme.Palette.energy, line: false)
                    if spans.contains(where: { !$0.sleep }) { key("Active", Theme.Palette.muted, line: false) }
                }
                .lineLimit(1).minimumScaleFactor(0.7)
                let notes = [spans.first { $0.sleep && $0.end > midnight }.map { "up \(Self.time($0.end))" },
                             spans.last { $0.sleep && $0.start > midnight + 12 * 3_600_000 }.map { "asleep \(Self.time($0.start))" },
                             beats.first.flatMap { lo in beats.last.map { "heart \(Fmt.whole(lo)) to \(Fmt.whole($0)) bpm" } }].compactMap { $0 }
                if !notes.isEmpty { Text(notes.joined(separator: " · ")).font(Theme.Typography.caption).foregroundStyle(Theme.Palette.muted) }
            }
        }
        .modifier(CardWhen(shown: (timeline?.hr.count ?? 0) > 3 || (timeline?.battery.count ?? 0) > 3))
        .task(id: date) { timeline = try? await API.shared.get("/api/timeline/\(date)", cache: true) }
    }

    private func mark(_ symbol: String, _ color: Color) -> some View {
        Image(systemName: symbol).font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.Palette.on(color))
            .frame(width: 20, height: 20).background(color, in: Circle())
    }

    private func key(_ name: String, _ color: Color, line: Bool) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 12, height: line ? 3 : 10)
            Text(name).font(Theme.Typography.caption).foregroundStyle(Theme.Palette.muted)
        }
    }

    /// Body Battery as one level per quarter hour (Garmin sends each interval's low and high).
    private static func quarters(_ rows: [[Double]]) -> [[Double]] {
        var sums: [Double: (Double, Double)] = [:]
        for r in rows where r.count > 1 { let k = (r[0] / 900_000).rounded(.down); sums[k] = ((sums[k]?.0 ?? 0) + r[1], (sums[k]?.1 ?? 0) + 1) }
        return sums.keys.sorted().map { [$0 * 900_000 + 450_000, sums[$0]!.0 / sums[$0]!.1] }
    }

    /// A curve through the points: each stretch bends through the midpoints, which rounds the corners off.
    private static func curve(_ points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for (a, b) in zip(points, points.dropFirst()) { path.addQuadCurve(to: CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2), control: a) }
        if let last = points.last { path.addLine(to: last) }
        return path
    }

    private struct Span { let start: Double; let end: Double; let sleep: Bool }

    /// The stretches to shade: Garmin's sleep and nap events, and the activities (Garmin's, or the recorded ones).
    private static func spans(_ t: DayTimeline, midnight: Double) -> [Span] {
        var out = t.events.filter { ["sleep", "nap", "activity"].contains($0.type) }.map { Span(start: $0.start, end: $0.end, sleep: $0.type != "activity") }
        if !out.contains(where: { !$0.sleep }) {
            out += (t.activities ?? []).compactMap { a in
                guard let start = Fmt.timestamp(a.start_time)?.timeIntervalSince1970, let length = a.duration_s else { return nil }
                return Span(start: start * 1000, end: (start + length) * 1000, sleep: false)
            }
        }
        return out.filter { $0.end > midnight && $0.start < midnight + 86_400_000 }.sorted { $0.start < $1.start }
    }

    /// A line through the points, broken where the watch has a gap of more than half an hour.
    private static func draw(_ points: [[Double]], low: Double, high: Double, color: Color, width: CGFloat, x: (Double) -> CGFloat, size: CGSize, in context: inout GraphicsContext) {
        var path = Path(), last: Double?
        for p in points where p.count > 1 {
            let point = CGPoint(x: x(p[0]), y: size.height * (1 - CGFloat((p[1] - low) / max(high - low, 1))))
            if let last, p[0] - last < 1_800_000 { path.addLine(to: point) } else { path.move(to: point) }
            last = p[0]
        }
        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
    }

    private static func time(_ ms: Double) -> String { Date(timeIntervalSince1970: ms / 1000).formatted(date: .omitted, time: .shortened) }
}

private struct CardWhen: ViewModifier {
    let shown: Bool
    func body(content: Content) -> some View { if shown { content.card() } else { content } }
}
