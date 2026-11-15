import SwiftUI

// The widgets on Home. Each comes in five sizes (see `WidgetSize`) and shows more as it grows: a name and a number
// at the smallest, a chart from ½ × ½ up, and the most at 1 × 1.

// MARK: The grid

struct WidgetSizeKey: LayoutValueKey { static let defaultValue = WidgetSize.square }

/// Two columns of quarter-height rows. A full-width widget starts below everything above it; a half-width one goes
/// into the shorter column, so short and tall widgets pack without holes where they can.
struct WidgetGrid: Layout {
    var spacing: CGFloat

    private func frames(width: CGFloat, _ subviews: Subviews) -> (rects: [CGRect], height: CGFloat) {
        let quarter = (width - 3 * spacing) / 4, half = (width - spacing) / 2
        var left: CGFloat = 0, right: CGFloat = 0
        let rects = subviews.map { view -> CGRect in
            let size = view[WidgetSizeKey.self]
            let height = CGFloat(size.rows) * quarter + CGFloat(size.rows - 1) * spacing
            if size.isWide {
                let y = max(left, right)
                left = y + height + spacing; right = left
                return CGRect(x: 0, y: y, width: width, height: height)
            }
            if left <= right {
                defer { left += height + spacing }
                return CGRect(x: 0, y: left, width: half, height: height)
            }
            defer { right += height + spacing }
            return CGRect(x: half + spacing, y: right, width: half, height: height)
        }
        return (rects, max(max(left, right) - spacing, 0))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        return CGSize(width: width, height: frames(width: width, subviews).height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (view, rect) in zip(subviews, frames(width: bounds.width, subviews).rects) {
            view.place(at: CGPoint(x: bounds.minX + rect.minX, y: bounds.minY + rect.minY), proposal: ProposedViewSize(rect.size))
        }
    }
}

// MARK: Pieces

/// Icon and title in the card's colour, with an optional note or view on the right. `compact` is the small form for
/// quarter-height widgets.
struct CardHeader<Trailing: View>: View {
    let kind: CardKind
    var title: String? = nil
    var compact = false
    @ViewBuilder var trailing: Trailing
    @Environment(\.onColor) private var onColor
    var body: some View {
        HStack(spacing: compact ? Theme.Space.xs : Theme.Space.s) {
            Image(systemName: kind.icon).font((compact ? Font.caption2 : .caption).weight(.bold))
            Text((title ?? kind.title).uppercased()).font(compact ? Theme.Typography.label : Theme.Typography.headline).lineLimit(1).minimumScaleFactor(0.6)
            Spacer(minLength: Theme.Space.xs)
            trailing
        }
        .frame(height: compact ? 16 : 26) // the same with or without a ring, so values line up across a row
        .foregroundStyle(onColor ? Theme.Palette.text : kind.tint)
    }
}

extension CardHeader where Trailing == EmptyView {
    init(kind: CardKind, title: String? = nil, compact: Bool = false) { self.kind = kind; self.title = title; self.compact = compact; self.trailing = EmptyView() }
}

/// Big number with a small unit after it.
struct BigValue: View {
    let value: String
    var unit: String = ""
    var compact = false
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(value).font(compact ? Theme.Typography.numeral : Theme.Typography.timer).lineLimit(1).minimumScaleFactor(0.5)
            if !unit.isEmpty { Text(unit).font(compact ? Theme.Typography.caption : Theme.Typography.callout).muted() }
        }
    }
}

struct Caption: View {
    let text: String
    var lines: Int? = nil
    init(_ text: String, lines: Int? = nil) { self.text = text; self.lines = lines }
    var body: some View { Text(text).font(Theme.Typography.caption).muted().lineLimit(lines).fixedSize(horizontal: false, vertical: lines == nil) }
}

/// The one line under a widget's chart: a few short facts, never wrapped, so every widget ends the same way.
struct ChartCaption: View {
    let parts: [String?]
    var trailing = false
    init(_ parts: [String?], trailing: Bool = false) { self.parts = parts; self.trailing = trailing }
    var body: some View {
        Text(parts.compactMap { $0 }.joined(separator: " · ")).font(Theme.Typography.caption).muted()
            .lineLimit(1).minimumScaleFactor(0.75).frame(maxWidth: .infinity, alignment: trailing ? .trailing : .leading)
    }
}

/// The two lines of a quarter-height widget: its name over its value, sitting in the middle of the row.
struct CompactLines<Trailing: View>: View {
    let kind: CardKind
    var title: String? = nil
    let value: String
    var unit = ""
    @ViewBuilder var trailing: Trailing
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            CardHeader(kind: kind, title: title, compact: true) { trailing }
            BigValue(value: value, unit: unit, compact: true)
        }
        .frame(maxHeight: .infinity)
    }
}

/// A 1 × ¼ widget: name and value on the left; on the right a note over the caption, on the same two lines, and
/// then room for a small picture.
struct StripLines<Note: View, Picture: View>: View {
    let kind: CardKind
    var title: String? = nil
    let value: String
    var unit = ""
    let caption: [String?]
    @ViewBuilder var note: Note
    @ViewBuilder var picture: Picture
    var body: some View {
        HStack(alignment: .center, spacing: Theme.Space.m) {
            CompactLines(kind: kind, title: title, value: value, unit: unit) { EmptyView() }.fixedSize(horizontal: true, vertical: false)
            VStack(alignment: .trailing, spacing: Theme.Space.xs) {
                note.frame(height: 16)
                ChartCaption(caption, trailing: true).frame(height: 28, alignment: .bottom)
            }
            picture
        }
        .frame(maxHeight: .infinity)
    }
}

/// A few named numbers side by side, for the largest size.
struct StatRow: View {
    let items: [(label: String, value: String)]
    var body: some View {
        HStack(spacing: Theme.Space.s) {
            ForEach(items, id: \.label) { item in
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.label.uppercased()).font(Theme.Typography.label).muted()
                    Text(item.value).font(Theme.Typography.numeral).lineLimit(1).minimumScaleFactor(0.6)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// "yesterday" or the date a value is from, when it is not today's.
func dayNote(_ date: String, today: String) -> String? {
    date == today ? nil : date == Day.add(today, -1) ? "yesterday" : Day.short(date)
}

/// The shared build of a widget made of a number and a chart, at each of the five sizes:
/// ½ × ¼ name and number; 1 × ¼ the same with the caption beside it; ½ × ½ and 1 × ½ add the chart; 1 × 1 gives the
/// chart most of the card and adds `more` under it.
struct MetricWidget<Trailing: View, Chart: View, More: View>: View {
    let kind: CardKind
    let size: WidgetSize
    let value: String
    var unit = ""
    let caption: [String?]
    /// The chart has too many points to share a row with the number.
    var long = false
    @ViewBuilder var trailing: Trailing
    @ViewBuilder var chart: Chart
    @ViewBuilder var more: More

    var body: some View {
        switch size {
        case .small:
            CompactLines(kind: kind, value: value, unit: unit) { trailing }
        case .strip:
            StripLines(kind: kind, value: value, unit: unit, caption: caption) { trailing } picture: { EmptyView() }
        case .square:
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                CardHeader(kind: kind) { trailing }
                BigValue(value: value, unit: unit)
                chart.frame(maxHeight: .infinity)
                ChartCaption(caption)
            }
        case .wide:
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                CardHeader(kind: kind) { trailing }
                if long {
                    BigValue(value: value, unit: unit)
                    chart.frame(maxHeight: .infinity)
                } else {
                    HStack(alignment: .bottom, spacing: Theme.Space.l) { BigValue(value: value, unit: unit).fixedSize(); chart.frame(maxHeight: .infinity) }
                }
                ChartCaption(caption)
            }
        case .large:
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                CardHeader(kind: kind) { trailing }
                BigValue(value: value, unit: unit)
                chart.frame(maxHeight: .infinity)
                more
                ChartCaption(caption)
            }
        }
    }
}

// MARK: Watch metrics

/// Generic widget for one daily metric: latest value, a chart over its range and a caption.
struct MetricCard: View {
    let model: HomeModel
    let setting: CardSetting
    let spec: MetricSpec
    let size: WidgetSize
    @Environment(\.onColor) private var onColor
    private var kind: CardKind { setting.kind }
    private var tint: Color { onColor ? Theme.Palette.text.opacity(0.85) : spec.tint }
    /// Days the caption's average covers: the widget's range once one is chosen, a week until then.
    private var days: Int { setting.range ?? 7 }

    private func show(_ v: Double) -> String { spec.digits == 0 ? Fmt.whole(v * spec.scale) : String(format: "%.\(spec.digits)f", v * spec.scale) }

    var body: some View {
        let latest = model.latest(spec.key)
        let goal = latest.flatMap { l in spec.goalKey.flatMap { model.value($0, on: l.date) } }
        let values = model.chart(setting.span(wide: size.isWide), every: setting.every(wide: size.isWide)) { day in model.value(spec.key, on: day).map { $0 * spec.scale } }
        MetricWidget(kind: kind, size: size, value: latest.map { show($0.value) } ?? "–", unit: spec.unit,
                     caption: [latest.flatMap { dayNote($0.date, today: model.today) }, goal.flatMap { $0 > 0 ? "goal \(show($0))" : nil }, model.average(spec.key, days).map { "\(RangeOption.short(days)) avg \(show($0))" }],
                     long: values.count > 45) {
            if let latest, let goal, goal > 0 { ProgressRing(progress: latest.value / goal, color: tint, size: size.rows == 1 ? 16 : 22) }
        } chart: {
            Spark(values: values, style: setting.chartStyle, color: tint, goal: goal.map { $0 * spec.scale }, height: nil)
        } more: {
            if let s = model.spread(values) {
                let text = { (v: Double) in spec.digits == 0 ? Fmt.whole(v) : String(format: "%.\(spec.digits)f", v) }
                StatRow(items: [("Lowest", text(s.low)), ("Average", text(s.average)), ("Highest", text(s.high))])
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Overnight heart rate variability as dots on a line, over the range the watch calls balanced for him, so one look
/// says whether it is where it should be.
struct HRVCard: View {
    let model: HomeModel
    let setting: CardSetting
    let size: WidgetSize

    var body: some View {
        let span = setting.span(wide: size.isWide), every = setting.every(wide: size.isWide)
        let latest = model.latest("hrv.lastNightAvg")
        let values = model.chart(span, every: every) { model.value("hrv.lastNightAvg", on: $0) }
        // The watch's own balanced range for each night. Without one (an older import), the middle of his own nights.
        let watchLow = model.chart(span, every: every) { model.value("hrv.baseline.balancedLow", on: $0) }
        let watchHigh = model.chart(span, every: every) { model.value("hrv.baseline.balancedUpper", on: $0) }
        let own = watchLow.allSatisfy { $0 == nil } ? HRVCard.usual(model.series("hrv.lastNightAvg", 28).compactMap { $0 }) : nil
        let low = own.map { r in values.map { _ in Optional(r.low) } } ?? watchLow, high = own.map { r in values.map { _ in Optional(r.high) } } ?? watchHigh
        let range = own ?? latest.flatMap { l in model.value("hrv.baseline.balancedLow", on: l.date).flatMap { lo in model.value("hrv.baseline.balancedUpper", on: l.date).map { (low: lo, high: $0) } } }
        let floor = latest.flatMap { model.value("hrv.baseline.lowUpper", on: $0.date) }
        let state: (text: String, color: Color)? = latest.flatMap { l in range.map { r in
            l.value < (floor ?? -1) ? ("Low", Theme.Palette.danger) : l.value < r.low ? ("Below range", Theme.Palette.warn) : l.value > r.high ? ("Above range", Theme.Palette.warn) : ("In range", Theme.Palette.ok)
        } }
        MetricWidget(kind: .hrv, size: size, value: latest.map { Fmt.whole($0.value) } ?? "–", unit: "ms",
                     caption: [latest.flatMap { dayNote($0.date, today: model.today) }, range.map { "\(own == nil ? "healthy" : "usual") \(Fmt.whole($0.low))–\(Fmt.whole($0.high))" },
                               model.average("hrv.lastNightAvg", setting.range ?? 7).map { "\(RangeOption.short(setting.range ?? 7)) avg \(Fmt.whole($0))" }],
                     long: values.count > 45) {
            if let state { Text(state.text).font(Theme.Typography.label).foregroundStyle(state.color).lineLimit(1) }
        } chart: {
            BandSpark(values: values, low: low, high: high, floor: floor, color: CardKind.hrv.tint, height: nil)
        } more: {
            if let s = model.spread(values) { StatRow(items: [("Lowest", Fmt.whole(s.low)), ("Average", Fmt.whole(s.average)), ("Highest", Fmt.whole(s.high))]) }
        }
        .accessibilityElement(children: .combine)
    }

    /// The middle half of a set of nights: from the 25th to the 75th percentile.
    static func usual(_ nights: [Double]) -> (low: Double, high: Double)? {
        guard nights.count >= 7 else { return nil }
        let sorted = nights.sorted()
        return (sorted[sorted.count / 4], sorted[sorted.count * 3 / 4])
    }
}

struct SleepCard: View {
    let model: HomeModel
    let setting: CardSetting
    let size: WidgetSize
    @Environment(\.onColor) private var onColor

    var body: some View {
        let night = model.latest("sleep.sleepTimeSeconds")
        let stage = { (key: String) -> Double in night.flatMap { model.value("sleep.\(key)", on: $0.date) } ?? 0 }
        let base = onColor ? Theme.Palette.text : Theme.Palette.sleep
        let stages: [(String, Double, Color)] = [("Deep", stage("deepSleepSeconds"), base), ("Light", stage("lightSleepSeconds"), base.opacity(0.5)),
                                                 ("REM", stage("remSleepSeconds"), Theme.Palette.calm), ("Awake", stage("awakeSleepSeconds"), Theme.Palette.warn)].filter { $0.1 > 0 }
        let score = night.flatMap { model.value("sleep.sleepScores.overall.value", on: $0.date) }
        let hours = model.chart(setting.span(wide: size.isWide), every: setting.every(wide: size.isWide)) { day in model.value("sleep.sleepTimeSeconds", on: day).map { $0 / 3600 } }
        let days = setting.range ?? 7
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            MetricWidget(kind: .sleep, size: size, value: night.map { Fmt.hours($0.value) } ?? "–",
                         caption: [night.flatMap { dayNote($0.date, today: model.today) }, model.average("sleep.sleepTimeSeconds", days).map { "\(RangeOption.short(days)) avg \(Fmt.hours($0))" }],
                         long: hours.count > 45) {
                if let score { Text("score \(Fmt.whole(score))").font(Theme.Typography.label).lineLimit(1) }
            } chart: {
                Spark(values: hours, style: setting.chartStyle, color: onColor ? Theme.Palette.text.opacity(0.85) : Theme.Palette.sleep, height: nil)
            } more: {
                if let s = model.spread(hours) { StatRow(items: [("Shortest", Fmt.hours(s.low * 3600)), ("Average", Fmt.hours(s.average * 3600)), ("Longest", Fmt.hours(s.high * 3600))]) }
            }
            // The night in stages: a bar from 1 × ½ up, with the times spelled out at 1 × 1.
            if !stages.isEmpty, size == .wide || size == .large {
                SegmentBar(parts: stages.map { ($0.1, $0.2) })
                if size == .large {
                    HStack(spacing: 0) {
                        ForEach(Array(stages.enumerated()), id: \.offset) { i, s in
                            if i > 0 { Spacer(minLength: Theme.Space.xs) }
                            HStack(spacing: Theme.Space.xs) {
                                Circle().fill(s.2).frame(width: 7, height: 7)
                                Text(s.0).font(Theme.Typography.caption).muted()
                                Text(Fmt.time(s.1 / 60)).font(Theme.Typography.caption.weight(.semibold).monospacedDigit())
                            }
                            .lineLimit(1).minimumScaleFactor(0.7)
                        }
                    }
                }
            }
        }
    }
}

/// Minutes this week towards Garmin's weekly goal, where a vigorous minute counts twice.
struct IntensityCard: View {
    let model: HomeModel
    let setting: CardSetting
    let size: WidgetSize
    @Environment(\.onColor) private var onColor
    var body: some View {
        let monday = Day.monday(of: model.today)
        let week = (0..<7).compactMap { model.intensity(on: Day.add(monday, $0)) }.reduce(0, +)
        let goal = model.latest("intensityMinutes.goal")?.value ?? 150
        let values = model.chart(setting.span(wide: size.isWide), every: setting.every(wide: size.isWide)) { model.intensity(on: $0) }
        let tint = onColor ? Theme.Palette.text.opacity(0.85) : CardKind.intensity.tint
        MetricWidget(kind: .intensity, size: size, value: Fmt.whole(week), unit: "min", caption: ["this week", "goal \(Fmt.whole(goal))"], long: values.count > 45) {
            ProgressRing(progress: week / max(goal, 1), color: tint, size: size.rows == 1 ? 16 : 22)
        } chart: {
            Spark(values: values, style: setting.chartStyle, color: tint, height: nil)
        } more: {
            if let s = model.spread(values) { StatRow(items: [("Easiest day", Fmt.whole(s.low)), ("Average", Fmt.whole(s.average)), ("Hardest day", Fmt.whole(s.high))]) }
        }
    }
}

// MARK: Training

/// The session to do next: today's until it is done, then tomorrow's. At 1 × 1 it lists what the session holds.
struct SessionCard: View {
    let model: HomeModel
    let size: WidgetSize
    let open: (String) -> Void

    var body: some View {
        if let s = model.nextSession {
            let t = s.day.template
            let title = s.isTomorrow ? "Tomorrow" : "Today"
            let badge = Badge(s.isTomorrow ? "Today done" : s.status == "done" ? "Done" : s.status == "skipped" ? "Skipped" : s.started ? "In progress" : "Week \(max(s.day.week, 1))",
                              tone: s.isTomorrow || s.status == "done" ? .ok : s.status == "skipped" ? .danger : .accent)
            let about = [s.isTomorrow ? Day.label(s.day.date) : nil, t.subtitle, size == .large ? t.duration : nil].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
            Button { open(s.day.date) } label: {
                Group {
                    switch size {
                    case .small:
                        CompactLines(kind: .today, title: title, value: t.name) { EmptyView() }
                    case .strip:
                        StripLines(kind: .today, title: "\(title)'s session", value: t.name, caption: [about]) { badge.fixedSize() } picture: { EmptyView() }
                    case .square:
                        VStack(alignment: .leading, spacing: Theme.Space.s) {
                            CardHeader(kind: .today, title: title)
                            BigValue(value: t.name)
                            Caption(about, lines: 2)
                            Spacer(minLength: 0)
                            badge
                        }
                    case .wide:
                        VStack(alignment: .leading, spacing: Theme.Space.s) {
                            CardHeader(kind: .today, title: "\(title)'s session") { badge }
                            BigValue(value: t.name)
                            Caption(about, lines: 2)
                            Spacer(minLength: 0)
                            Caption(t.duration ?? "", lines: 1)
                        }
                    case .large:
                        VStack(alignment: .leading, spacing: Theme.Space.s) {
                            CardHeader(kind: .today, title: "\(title)'s session") { badge }
                            BigValue(value: t.name)
                            Caption(about, lines: 1)
                            summary(s.day).frame(maxHeight: .infinity, alignment: .top)
                        }
                    }
                }
                .foregroundStyle(Theme.Palette.text)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    /// What the session holds: the lifts with their sets, or what the run or the rest day asks for.
    @ViewBuilder
    private func summary(_ day: DayInfo) -> some View {
        let lifts = day.plan.filter { $0.sets > 0 }
        if day.template.kind == "lift", !lifts.isEmpty {
            VStack(spacing: Theme.Space.xs) {
                ForEach(Array(lifts.prefix(7).enumerated()), id: \.offset) { _, e in
                    HStack {
                        Text(AppModel.shared.program?.exercise(e.key).name ?? e.key).font(Theme.Typography.callout).lineLimit(1)
                        Spacer(minLength: Theme.Space.s)
                        Text("\(e.sets) × \(e.reps ?? "")").font(Theme.Typography.callout.weight(.semibold).monospacedDigit()).fixedSize()
                    }
                }
                if lifts.count > 7 { Caption("and \(lifts.count - 7) more", lines: 1).frame(maxWidth: .infinity, alignment: .leading) }
            }
            .padding(.top, Theme.Space.xs)
        } else {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                if let detail = day.template.detail { Text(detail).font(Theme.Typography.callout) }
                if let pace = day.template.pace { Text(pace).font(Theme.Typography.callout).muted() }
                ForEach(day.extras ?? [], id: \.self) { Text($0).font(Theme.Typography.caption).muted() }
            }
            .padding(.top, Theme.Space.xs)
        }
    }
}

/// The latest run. Its route is a small sketch at the middle sizes and the whole map at 1 × 1.
struct LastRunCard: View {
    let model: HomeModel
    let size: WidgetSize
    let open: (Int) -> Void

    var body: some View {
        if let run = model.lastRun {
            let route = RunRoute(run.track ?? [])
            let km = run.distance_m.map { String(format: "%.2f", $0 / 1000) } ?? "–"
            let facts = [run.duration_s.map { Fmt.time($0) }, run.avg_pace_s_per_km.map { Fmt.pace($0) }, run.avg_hr.map { "\(Int($0)) bpm" }]
            if size == .large {
                // The map takes touches of its own, so only the heading opens the run.
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    Button { open(run.id) } label: {
                        CardHeader(kind: .lastRun) { Text(Day.label(run.day)).font(Theme.Typography.label) }.contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if route.isEmpty {
                        BigValue(value: km, unit: "km")
                        ChartCaption(facts)
                    } else {
                        RouteMap(route: route, activity: run, fixed: true, height: nil)
                    }
                }
            } else {
                Button { open(run.id) } label: {
                    Group {
                        switch size {
                        case .small:
                            CompactLines(kind: .lastRun, value: km, unit: "km") { EmptyView() }
                        case .strip:
                            StripLines(kind: .lastRun, value: km, unit: "km", caption: facts.prefix(2).map { $0 }) { Text(Day.label(run.day)).font(Theme.Typography.label).muted() } picture: {
                                if !route.isEmpty { RouteSketch(route: route, lineWidth: 2.5).frame(width: 64, height: 44) }
                            }
                        case .square:
                            VStack(alignment: .leading, spacing: Theme.Space.s) {
                                CardHeader(kind: .lastRun)
                                if !route.isEmpty { RouteSketch(route: route, lineWidth: 3).frame(maxWidth: .infinity, maxHeight: .infinity) } else { Spacer(minLength: 0) }
                                BigValue(value: km, unit: "km", compact: true)
                                ChartCaption(facts.prefix(2).map { $0 })
                            }
                        default:
                            VStack(alignment: .leading, spacing: Theme.Space.s) {
                                CardHeader(kind: .lastRun) { Text(Day.label(run.day)).font(Theme.Typography.label) }
                                HStack(alignment: .center, spacing: Theme.Space.l) {
                                    VStack(alignment: .leading, spacing: 2) { BigValue(value: km, unit: "km"); ChartCaption(facts) }
                                    if !route.isEmpty { RouteSketch(route: route).frame(width: 130).frame(maxHeight: .infinity) }
                                }
                                .frame(maxHeight: .infinity)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Monday to Sunday with a mark for each day trained. At 1 × 1 the week is listed day by day.
struct WeekCard: View {
    let model: HomeModel
    let size: WidgetSize

    var body: some View {
        let monday = Day.monday(of: model.today)
        let done = (model.dash?.workouts ?? []).filter { $0.status == "done" && $0.kind != "rest" && $0.date >= monday && $0.date <= Day.add(monday, 6) }
        let count = Set(done.map(\.date)).count
        let text = "\(count) session\(count == 1 ? "" : "s") done"
        switch size {
        case .small:
            CompactLines(kind: .week, value: "\(count)", unit: "done") { EmptyView() }
        case .strip:
            HStack(spacing: Theme.Space.m) {
                CompactLines(kind: .week, value: "\(count)", unit: "done") { EmptyView() }.fixedSize(horizontal: true, vertical: false)
                days(monday, done, circle: 24, labels: true)
            }
        case .square:
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                CardHeader(kind: .week)
                BigValue(value: "\(count)", unit: count == 1 ? "session" : "sessions")
                Spacer(minLength: 0)
                days(monday, done, circle: 14, labels: false)
                ChartCaption(["Monday to Sunday"])
            }
        case .wide:
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                CardHeader(kind: .week) { Text(text).font(Theme.Typography.label) }
                Spacer(minLength: 0)
                days(monday, done, circle: 32, labels: true)
                Spacer(minLength: 0)
            }
        case .large:
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                CardHeader(kind: .week) { Text(text).font(Theme.Typography.label) }
                days(monday, done, circle: 30, labels: true)
                VStack(spacing: Theme.Space.xs) {
                    ForEach(0..<7, id: \.self) { i in
                        let date = Day.add(monday, i), sessions = done.filter { $0.date == date }
                        HStack {
                            Text(Day.label(date)).font(Theme.Typography.callout).foregroundStyle(date == model.today ? Theme.Palette.text : Theme.Palette.muted)
                            Spacer(minLength: Theme.Space.s)
                            Text(sessions.isEmpty ? (date > model.today ? "" : "nothing logged") : sessions.map { AppModel.shared.program?.templates[$0.template_key]?.name ?? $0.template_key }.joined(separator: ", "))
                                .font(Theme.Typography.callout.weight(sessions.isEmpty ? .regular : .semibold)).foregroundStyle(sessions.isEmpty ? Theme.Palette.muted : Theme.Palette.text).lineLimit(1)
                        }
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
    }

    private func days(_ monday: String, _ done: [Workout], circle: CGFloat, labels: Bool) -> some View {
        HStack(spacing: Theme.Space.xs) {
            ForEach(0..<7, id: \.self) { i in
                let date = Day.add(monday, i)
                let kind = done.first { $0.date == date }?.kind
                VStack(spacing: Theme.Space.xs) {
                    ZStack {
                        Circle().fill(kind.map { Theme.Palette.kind($0) } ?? Theme.Palette.fill)
                        if let kind, circle >= 20 { Image(systemName: "checkmark").font(.caption2.weight(.bold)).foregroundStyle(Theme.Palette.on(Theme.Palette.kind(kind))) }
                    }
                    .frame(width: circle, height: circle)
                    .overlay { if date == model.today { Circle().stroke(Theme.Palette.accent, lineWidth: 2).padding(-3) } }
                    if labels { Text(Day.label(date).prefix(circle >= 28 ? 3 : 1)).font(Theme.Typography.label).foregroundStyle(date == model.today ? Theme.Palette.text : Theme.Palette.muted) }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

struct WeightWidget: View {
    let model: HomeModel
    let setting: CardSetting
    let size: WidgetSize
    var body: some View {
        let byDay = Dictionary((model.dash?.body ?? []).compactMap { b in b.weight_kg.map { (b.date, $0) } }, uniquingKeysWith: { a, _ in a })
        let recent = (0..<7).compactMap { byDay[Day.add(model.today, -$0)] }
        let latestDate = byDay.keys.max()
        let avg = recent.isEmpty ? latestDate.flatMap { byDay[$0] } : recent.reduce(0, +) / Double(recent.count)
        let goal = model.dash?.settings.number("goal_weight_kg") ?? AppModel.shared.program?.body.goalWeightKg
        let values = model.chart(setting.span(wide: size.isWide), every: setting.every(wide: size.isWide)) { byDay[$0] }
        MetricWidget(kind: .weight, size: size, value: avg.map { String(format: "%.1f", $0) } ?? "–", unit: "kg",
                     caption: [recent.isEmpty ? latestDate.map { Day.short($0) } : "7d avg", goal.flatMap { g in avg.map { String(format: "%.1f kg to goal", $0 - g) } }], long: values.count > 45) {
            EmptyView()
        } chart: {
            Spark(values: values, style: setting.chartStyle, color: CardKind.weight.tint, height: nil)
        } more: {
            if let s = model.spread(values) {
                StatRow(items: [("Lightest", String(format: "%.1f", s.low)), ("Heaviest", String(format: "%.1f", s.high)), ("Goal", goal.map { String(format: "%.1f", $0) } ?? "–")])
            }
        }
    }
}

struct NutritionCard: View {
    let model: HomeModel
    let setting: CardSetting
    let size: WidgetSize
    var body: some View {
        let program = AppModel.shared.program
        let day = model.dash?.nutrition.last { $0.date <= model.today }
        let byDay = Dictionary((model.dash?.nutrition ?? []).compactMap { n in n.calories.map { (n.date, $0) } }, uniquingKeysWith: { a, _ in a })
        let kcalTarget = model.dash?.settings.number("calorie_target") ?? program?.nutrition.calories ?? 0
        let proteinTarget = model.dash?.settings.number("protein_target") ?? program?.nutrition.proteinG ?? 0
        let values = model.chart(setting.span(wide: size.isWide), every: setting.every(wide: size.isWide)) { date in byDay[date] }
        MetricWidget(kind: .nutrition, size: size, value: Fmt.whole(day?.calories), unit: "kcal",
                     caption: [day.flatMap { dayNote($0.date, today: model.today) }, kcalTarget > 0 ? "goal \(Fmt.whole(kcalTarget))" : nil, day?.protein_g.map { "protein \(Fmt.whole($0))/\(Fmt.whole(proteinTarget)) g" }],
                     long: values.count > 45) {
            if let kcal = day?.calories, kcalTarget > 0 { ProgressRing(progress: kcal / kcalTarget, color: CardKind.nutrition.tint, size: size.rows == 1 ? 16 : 22) }
        } chart: {
            Spark(values: values, style: setting.chartStyle, color: CardKind.nutrition.tint, goal: kcalTarget > 0 ? kcalTarget : nil, height: nil)
        } more: {
            if let s = model.spread(values) { StatRow(items: [("Lowest", Fmt.whole(s.low)), ("Average", Fmt.whole(s.average)), ("Highest", Fmt.whole(s.high))]) }
        }
    }
}

// MARK: Fun facts and the full list

/// The day's facts: all of them at 1 × 1, the first row at 1 × ½, one fact below that.
struct FactsCard: View {
    let model: HomeModel
    let size: WidgetSize
    var body: some View {
        if let sheet = model.factSheet, let first = sheet.facts.first {
            switch size {
            case .small:
                CompactLines(kind: .facts, title: first.label, value: first.value, unit: first.unit) { EmptyView() }
            case .strip:
                FactLine(fact: first).frame(maxHeight: .infinity)
            case .square:
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    CardHeader(kind: .facts)
                    FactTile(fact: first, wide: false, paint: .wash)
                }
            case .wide:
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    CardHeader(kind: .facts) { Text(sheet.title).font(Theme.Typography.label) }
                    HStack(spacing: Theme.Space.s) {
                        ForEach(sheet.facts.prefix(2)) { FactTile(fact: $0, wide: false, paint: sheet.look == .lines ? .outline : .wash) }
                    }
                }
            case .large:
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    CardHeader(kind: .facts) { Text(sheet.title).font(Theme.Typography.label) }
                    ForEach(Array(sheet.rows.enumerated()), id: \.offset) { _, row in
                        if sheet.layout == .list {
                            FactLine(fact: row[0]).frame(maxHeight: .infinity)
                        } else if row.count == 1 {
                            FactTile(fact: row[0], wide: true, paint: sheet.look == .bold ? .solid : .wash)
                        } else {
                            HStack(spacing: Theme.Space.s) {
                                ForEach(row) { FactTile(fact: $0, wide: false, paint: sheet.look == .lines ? .outline : .wash) }
                            }
                        }
                    }
                }
            }
        }
    }
}

/// One fact as a tile: its name, a big number and a line about it. A wide tile carries its icon on the right,
/// inside a ring when the fact measures progress along something.
struct FactTile: View {
    enum Paint { case wash, solid, outline }
    let fact: Fact
    let wide: Bool
    let paint: Paint

    var body: some View {
        let solid = paint == .solid
        let ink = Theme.Palette.on(fact.tint) // what reads on the solid tile: black or white
        let accent = solid ? ink : fact.tint
        HStack(spacing: Theme.Space.m) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Theme.Space.xs) {
                    if !wide { Image(systemName: fact.icon).font(.caption.weight(.semibold)) }
                    Text(fact.label.uppercased()).font(Theme.Typography.label).lineLimit(1).minimumScaleFactor(0.6)
                }
                .foregroundStyle(accent.opacity(solid ? 0.85 : 1))
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(fact.value).font(wide ? Theme.Typography.timer : Theme.Typography.numeral).lineLimit(1).minimumScaleFactor(0.5).foregroundStyle(solid ? ink : Theme.Palette.text)
                    if !fact.unit.isEmpty { Text(fact.unit).font(Theme.Typography.callout).foregroundStyle(solid ? ink.opacity(0.8) : Theme.Palette.muted) }
                }
                if !fact.detail.isEmpty {
                    Text(fact.detail).font(Theme.Typography.caption).foregroundStyle(solid ? ink.opacity(0.85) : Theme.Palette.muted).fixedSize(horizontal: false, vertical: true)
                }
            }
            if wide {
                Spacer(minLength: 0)
                ZStack {
                    if let progress = fact.progress { ProgressRing(progress: progress, color: accent, size: 58) } else { Circle().fill(accent.opacity(solid ? 0.2 : 0.15)).frame(width: 58, height: 58) }
                    Image(systemName: fact.icon).font(.title3.weight(.semibold)).foregroundStyle(accent)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(Theme.Space.m)
        .background {
            let shape = RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
            switch paint {
            case .wash: shape.fill(fact.tint.opacity(0.12))
            case .solid: GrainyGradient(colors: [fact.tint, fact.tint.opacity(0.6)]).clipShape(shape)
            case .outline: shape.strokeBorder(fact.tint.opacity(0.5), lineWidth: 1.5)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// One fact as a line of a list: icon, name and note on the left, the number on the right.
struct FactLine: View {
    let fact: Fact
    var body: some View {
        HStack(spacing: Theme.Space.m) {
            Image(systemName: fact.icon).font(.footnote.weight(.semibold)).foregroundStyle(fact.tint)
                .frame(width: 34, height: 34).background(fact.tint.opacity(0.14), in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(fact.label).font(Theme.Typography.callout.weight(.medium)).lineLimit(1).minimumScaleFactor(0.8)
                if !fact.detail.isEmpty { Text(fact.detail).font(Theme.Typography.caption).foregroundStyle(Theme.Palette.muted).lineLimit(1).minimumScaleFactor(0.8) }
            }
            Spacer(minLength: Theme.Space.s)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(fact.value).font(Theme.Typography.numeral).foregroundStyle(fact.tint)
                if !fact.unit.isEmpty { Text(fact.unit).font(Theme.Typography.caption).foregroundStyle(Theme.Palette.muted) }
            }
            .lineLimit(1).layoutPriority(1)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

/// A way in to every metric stored for the latest day, including the ones without a widget of their own.
struct AllMetricsCard: View {
    let model: HomeModel
    let size: WidgetSize
    var body: some View {
        let date = model.days.keys.max() ?? model.today
        let count = model.days[date]?.count ?? 0
        NavigationLink { AllMetricsScreen(model: model) } label: {
            Group {
                switch size {
                case .small: CompactLines(kind: .all, title: "Watch data", value: "\(count)", unit: "values") { EmptyView() }
                case .strip: StripLines(kind: .all, title: "Watch data", value: "\(count)", unit: "values", caption: [Day.label(date), "\(model.days.count) days stored"]) { EmptyView() } picture: { EmptyView() }
                default:
                    VStack(alignment: .leading, spacing: Theme.Space.s) {
                        CardHeader(kind: .all, title: size.isWide ? nil : "Watch data")
                        BigValue(value: "\(count)", unit: "values")
                        Spacer(minLength: 0)
                        ChartCaption([Day.label(date), "\(model.days.count) days stored"])
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Every metric the watch gave for the latest day, by Garmin's own names.
struct AllMetricsScreen: View {
    let model: HomeModel
    var body: some View {
        let date = model.days.keys.max() ?? model.today
        let rows = (model.days[date] ?? [:]).sorted { $0.key < $1.key }
        Screen {
            VStack(spacing: 0) {
                ForEach(rows, id: \.key) { key, value in
                    HStack(alignment: .firstTextBaseline) {
                        Text(Fmt.metricName(key)).font(Theme.Typography.caption).muted()
                        Spacer(minLength: Theme.Space.m)
                        Text(value.number.map { $0 == $0.rounded() ? Fmt.whole($0) : String(format: "%.1f", $0) } ?? value.text ?? "").font(Theme.Typography.caption.monospacedDigit())
                    }
                    .padding(.vertical, 3)
                }
            }
            .card()
        }
        .inlineTitle(Day.label(date))
    }
}
