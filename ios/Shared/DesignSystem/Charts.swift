import Charts
import SwiftUI

// Chart components. Every chart in the app is one of these, so the chart look is changed here and nowhere else.

extension Theme {
    enum ChartStyle {
        static let lineWidth: CGFloat = 2.5
        /// Opacity at the top of the fill under the main line. It fades to clear.
        static let areaOpacity = 0.26
        static let gridOpacity = 0.55
        static let barWidth = 0.56 // share of the slot
        static let dimmedBarOpacity = 0.32
    }
}

/// One line, or one set of loose points, in a `TrendChart`.
struct TrendSeries: Identifiable {
    enum Style { case line, points }
    struct Point: Identifiable { let date: Date; let value: Double; var id: Date { date } }
    let name: String
    let color: Color
    var style: Style = .line
    let points: [Point]
    var id: String { name }
}

/// Values over time: soft fill under the first line, a marked latest point, a dashed goal line,
/// and a callout that follows the finger.
struct TrendChart: View {
    let series: [TrendSeries]
    var goal: (label: String, value: Double)? = nil
    /// Flips the axis so that better (lower) values sit higher, for pace.
    var lowerIsBetter = false
    var height: CGFloat = 210
    /// Formats a value for the axis and the callout.
    let format: (Double) -> String
    @State private var selection: Date?

    private var lines: [TrendSeries] { series.filter { $0.style == .line } }

    /// The value range to draw: the data with a little headroom, so the trend fills the plot instead of hugging one edge.
    private var domain: ClosedRange<Double> {
        let values = series.flatMap { $0.points.map(\.value) }
        guard let lo = values.min(), let hi = values.max() else { return 0...1 }
        let span = max(hi - lo, 1)
        var low = lo - span * 0.18, high = hi + span * 0.18
        if let g = shownGoal { low = min(low, g - span * 0.12); high = max(high, g + span * 0.12) }
        return low...high
    }

    /// The goal line is drawn only when it is near the data. A goal far away would squash the trend into a flat line,
    /// so then it is left to the text around the chart.
    private var shownGoal: Double? {
        let values = series.flatMap { $0.points.map(\.value) }
        guard let goal, let lo = values.min(), let hi = values.max() else { return nil }
        let reach = max(hi - lo, 1) * 1.5
        return (lo - reach...hi + reach).contains(goal.value) ? goal.value : nil
    }

    /// The point of each series closest to the finger.
    private var picked: [(series: TrendSeries, point: TrendSeries.Point)] {
        guard let selection else { return [] }
        return series.compactMap { s in
            s.points.min { abs($0.date.timeIntervalSince(selection)) < abs($1.date.timeIntervalSince(selection)) }.map { (s, $0) }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            if series.count > 1 {
                HStack(spacing: Theme.Space.m) {
                    ForEach(series) { s in
                        HStack(spacing: Theme.Space.xs) {
                            Circle().fill(s.color).frame(width: 7, height: 7)
                            Text(s.name).font(Theme.Typography.label).foregroundStyle(Theme.Palette.muted)
                        }
                    }
                }
            }
            chart
        }
    }

    private var chart: some View {
        Chart {
            if let goal, shownGoal != nil {
                RuleMark(y: .value("Goal", goal.value))
                    .foregroundStyle(Theme.Palette.ok.opacity(0.8))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))
                    .annotation(position: .top, alignment: .trailing, spacing: 2) {
                        Text(goal.label).font(Theme.Typography.label).foregroundStyle(Theme.Palette.ok)
                    }
            }
            ForEach(series) { s in
                ForEach(s.points) { p in
                    if s.style == .points {
                        PointMark(x: .value("Date", p.date), y: .value("Value", p.value))
                            .symbolSize(16).foregroundStyle(s.color.opacity(0.5))
                    } else {
                        if s.id == lines.first?.id, !lowerIsBetter {
                            AreaMark(x: .value("Date", p.date), yStart: .value("Base", domain.lowerBound), yEnd: .value("Value", p.value))
                                .foregroundStyle(LinearGradient(colors: [s.color.opacity(Theme.ChartStyle.areaOpacity), s.color.opacity(0)], startPoint: .top, endPoint: .bottom))
                                .interpolationMethod(.monotone)
                        }
                        LineMark(x: .value("Date", p.date), y: .value("Value", p.value), series: .value("Series", s.name))
                            .foregroundStyle(s.color)
                            .lineStyle(StrokeStyle(lineWidth: Theme.ChartStyle.lineWidth, lineCap: .round, lineJoin: .round))
                            .interpolationMethod(.monotone)
                    }
                }
                // The latest value of each line gets a ringed dot.
                if s.style == .line, let last = s.points.last, selection == nil {
                    PointMark(x: .value("Date", last.date), y: .value("Value", last.value)).symbolSize(90).foregroundStyle(s.color)
                    PointMark(x: .value("Date", last.date), y: .value("Value", last.value)).symbolSize(26).foregroundStyle(Theme.Palette.surface)
                }
            }
            if let anchor = picked.first(where: { $0.series.style == .line }) ?? picked.first {
                RuleMark(x: .value("Date", anchor.point.date))
                    .foregroundStyle(Theme.Palette.muted.opacity(0.45))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .annotation(position: .top, spacing: Theme.Space.xs, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) { callout(anchor.point.date) }
                ForEach(picked.filter { $0.series.style == .line }, id: \.series.id) { item in
                    PointMark(x: .value("Date", item.point.date), y: .value("Value", item.point.value)).symbolSize(90).foregroundStyle(item.series.color)
                    PointMark(x: .value("Date", item.point.date), y: .value("Value", item.point.value)).symbolSize(26).foregroundStyle(Theme.Palette.surface)
                }
            }
        }
        .modifier(YScale(domain: domain, reversed: lowerIsBetter))
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Theme.Palette.separator.opacity(Theme.ChartStyle.gridOpacity))
                AxisValueLabel {
                    if let v = value.as(Double.self) { Text(format(v)).font(Theme.Typography.label).foregroundStyle(Theme.Palette.muted) }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisValueLabel(format: .dateTime.day().month(.abbreviated)).font(Theme.Typography.label).foregroundStyle(Theme.Palette.muted)
            }
        }
        .chartLegend(.hidden)
        .chartXScale(range: .plotDimension(startPadding: 2, endPadding: 10)) // room for the latest-point ring
        .chartXSelection(value: $selection)
        .environment(\.timeZone, .gmt) // days are plotted at UTC midnight
        .frame(height: height)
    }

    private func callout(_ date: Date) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(date.formatted(Date.FormatStyle(timeZone: .gmt).weekday(.abbreviated).day().month(.abbreviated)))
                .font(Theme.Typography.label).foregroundStyle(Theme.Palette.muted)
            // Only values from the same day as the anchor belong in the callout.
            ForEach(picked.filter { $0.point.date == date }, id: \.series.id) { item in
                HStack(spacing: Theme.Space.xs) {
                    Circle().fill(item.series.color).frame(width: 7, height: 7)
                    Text(format(item.point.value)).font(Theme.Typography.callout.weight(.semibold).monospacedDigit())
                    if series.count > 1 { Text(item.series.name).font(Theme.Typography.label).foregroundStyle(Theme.Palette.muted) }
                }
            }
        }
        .padding(.horizontal, Theme.Space.s).padding(.vertical, Theme.Space.xs)
        .background(Theme.Palette.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
    }
}

/// A fixed range for normal charts. A flipped axis can only be had from the automatic range.
private struct YScale: ViewModifier {
    let domain: ClosedRange<Double>
    let reversed: Bool
    func body(content: Content) -> some View {
        if reversed {
            content.chartYScale(domain: .automatic(includesZero: false, reversed: true))
        } else {
            content.chartYScale(domain: domain)
        }
    }
}

/// A few labelled bars with their values on top and one bar picked out, for counts per week.
struct BarsChart: View {
    struct Bar: Identifiable { let label: String; let value: Double; var id: String { label } }
    let bars: [Bar]
    /// Label of the bar drawn at full strength (the current week).
    var highlight: String? = nil
    var color: Color = Theme.Palette.accent
    var height: CGFloat = 150

    var body: some View {
        Chart(bars) { bar in
            BarMark(x: .value("Label", bar.label), y: .value("Value", bar.value), width: .ratio(Theme.ChartStyle.barWidth))
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
                .foregroundStyle(bar.label == highlight ? color : color.opacity(Theme.ChartStyle.dimmedBarOpacity))
                .annotation(position: .top, spacing: 3) {
                    Text(bar.value.formatted(.number.precision(.fractionLength(0)))).font(Theme.Typography.label)
                        .foregroundStyle(bar.label == highlight ? Theme.Palette.text : Theme.Palette.muted)
                }
        }
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks { _ in AxisValueLabel().font(Theme.Typography.label).foregroundStyle(Theme.Palette.muted) }
        }
        .frame(height: height)
    }
}

/// The headline number above a chart, with what it means next to it.
struct StatLine: View {
    let value: String
    var caption: String? = nil
    var tone: Tone? = nil
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
            Text(value).font(Theme.Typography.numeral)
            if let caption { Text(caption).font(Theme.Typography.caption).foregroundStyle(tone?.color ?? Theme.Palette.muted) }
        }
    }
}

/// A value along the distance of a run (pace, heart rate, elevation): a line with a soft fill, a dashed average,
/// and a callout that follows the finger.
struct ProfileChart: View {
    struct Sample: Identifiable { let x: Double; let y: Double; var id: Double { x } }
    let samples: [Sample]
    var color: Color = Theme.Palette.accent
    /// Flips the axis so that better (lower) values sit higher, for pace.
    var lowerIsBetter = false
    var height: CGFloat = 150
    var average: Double? = nil
    /// Colours the line by value instead of with `color`: each band starts at `from` and runs up to the next one,
    /// lowest first. For heart rate zones. Not for `lowerIsBetter` charts.
    var bands: [(from: Double, color: Color)] = []
    let format: (Double) -> String
    @State private var selection: Double?

    /// The bands as a bottom-to-top gradient with hard edges, laid over the plot area.
    private func banded(opacity: Double) -> LinearGradient {
        let span = domain.upperBound - domain.lowerBound
        let place = { (v: Double) in min(max((v - domain.lowerBound) / span, 0), 1) }
        let stops = bands.indices.flatMap { i in
            [Gradient.Stop(color: bands[i].color.opacity(opacity), location: i == 0 ? 0 : place(bands[i].from)),
             Gradient.Stop(color: bands[i].color.opacity(opacity), location: i == bands.count - 1 ? 1 : place(bands[i + 1].from))]
        }
        return LinearGradient(stops: stops, startPoint: .bottom, endPoint: .top)
    }

    private var domain: ClosedRange<Double> {
        let ys = samples.map(\.y)
        guard let lo = ys.min(), let hi = ys.max() else { return 0...1 }
        let pad = max((hi - lo) * 0.12, 0.5)
        return (lo - pad)...(hi + pad)
    }

    var body: some View {
        let picked = selection.flatMap { x in samples.min { abs($0.x - x) < abs($1.x - x) } }
        Chart {
            ForEach(samples) { s in
                if !bands.isEmpty {
                    AreaMark(x: .value("km", s.x), yStart: .value("Base", domain.lowerBound), yEnd: .value("Value", s.y))
                        .foregroundStyle(banded(opacity: Theme.ChartStyle.areaOpacity * 0.6)).alignsMarkStylesWithPlotArea()
                        .interpolationMethod(.monotone)
                    LineMark(x: .value("km", s.x), y: .value("Value", s.y))
                        .foregroundStyle(banded(opacity: 1)).alignsMarkStylesWithPlotArea()
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)).interpolationMethod(.monotone)
                } else {
                    if !lowerIsBetter {
                        AreaMark(x: .value("km", s.x), yStart: .value("Base", domain.lowerBound), yEnd: .value("Value", s.y))
                            .foregroundStyle(LinearGradient(colors: [color.opacity(Theme.ChartStyle.areaOpacity), color.opacity(0)], startPoint: .top, endPoint: .bottom))
                            .interpolationMethod(.monotone)
                    }
                    LineMark(x: .value("km", s.x), y: .value("Value", s.y))
                        .foregroundStyle(color).lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)).interpolationMethod(.monotone)
                }
            }
            if let average {
                RuleMark(y: .value("Average", average)).foregroundStyle(color.opacity(0.55)).lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))
            }
            if let picked {
                RuleMark(x: .value("km", picked.x)).foregroundStyle(Theme.Palette.muted.opacity(0.45)).lineStyle(StrokeStyle(lineWidth: 1))
                    .annotation(position: .top, spacing: Theme.Space.xs, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(String(format: "%.2f km", picked.x)).font(Theme.Typography.label).foregroundStyle(Theme.Palette.muted)
                            Text(format(picked.y)).font(Theme.Typography.callout.weight(.semibold).monospacedDigit())
                        }
                        .padding(.horizontal, Theme.Space.s).padding(.vertical, Theme.Space.xs)
                        .background(Theme.Palette.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
                    }
                PointMark(x: .value("km", picked.x), y: .value("Value", picked.y)).symbolSize(70).foregroundStyle(color)
            }
        }
        .modifier(YScale(domain: domain, reversed: lowerIsBetter))
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Theme.Palette.separator.opacity(Theme.ChartStyle.gridOpacity))
                AxisValueLabel { if let v = value.as(Double.self) { Text(format(v)).font(Theme.Typography.label).foregroundStyle(Theme.Palette.muted) } }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { value in
                AxisValueLabel { if let v = value.as(Double.self) { Text("\(ChartLabel.km(v)) km").font(Theme.Typography.label).foregroundStyle(Theme.Palette.muted) } }
            }
        }
        .chartXSelection(value: $selection)
        .frame(height: height)
    }
}

/// Number formatting the design system needs on its own (the app's `Fmt` is not part of the widget extension).
enum ChartLabel {
    static func km(_ v: Double) -> String { v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v) }
}

/// Tiny axis-free chart for dashboard cards: bars or a filled line, with gaps where a day has no value.
struct Spark: View {
    enum Style { case bars, line }
    let values: [Double?]
    var style: Style = .bars
    var color: Color = Theme.Palette.accent
    /// Dashed reference line, for a daily goal.
    var goal: Double? = nil
    var height: CGFloat = 44

    var body: some View {
        // One slot per day, named by its position, so a day without a value leaves a gap instead of closing up.
        let slots = values.indices.map(String.init)
        let points = Array(values.enumerated()).compactMap { i, v in v.map { (slot: String(i), index: i, value: $0) } }
        let lo = points.map(\.value).min() ?? 0, hi = max(points.map(\.value).max() ?? 1, goal ?? 0)
        let pad = max((hi - lo) * 0.15, 0.5)
        Chart {
            ForEach(points, id: \.index) { p in
                if style == .bars {
                    // Many bars: fill the slot and drop the rounding, so thin bars read as one shape, not as dots.
                    BarMark(x: .value("Day", p.slot), y: .value("Value", p.value), width: .ratio(values.count > 60 ? 0.9 : 0.72))
                        .clipShape(RoundedRectangle(cornerRadius: values.count > 60 ? 0 : 2, style: .continuous))
                        .foregroundStyle(p.index == values.count - 1 ? color : color.opacity(Theme.ChartStyle.dimmedBarOpacity + 0.1))
                } else {
                    AreaMark(x: .value("Day", p.slot), yStart: .value("Base", lo - pad), yEnd: .value("Value", p.value))
                        .foregroundStyle(LinearGradient(colors: [color.opacity(Theme.ChartStyle.areaOpacity), color.opacity(0)], startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.monotone)
                    LineMark(x: .value("Day", p.slot), y: .value("Value", p.value))
                        .foregroundStyle(color).lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)).interpolationMethod(.monotone)
                }
            }
            if style == .line, let last = points.last {
                PointMark(x: .value("Day", last.slot), y: .value("Value", last.value)).symbolSize(40).foregroundStyle(color)
            }
            if let goal {
                RuleMark(y: .value("Goal", goal)).foregroundStyle(color.opacity(0.5)).lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
            }
        }
        .chartXAxis(.hidden).chartYAxis(.hidden).chartLegend(.hidden)
        .chartXScale(domain: slots)
        .chartYScale(domain: (style == .bars ? 0 : lo - pad)...(hi + pad))
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

/// Ring that fills towards a goal.
struct ProgressRing: View {
    let progress: Double
    var color: Color = Theme.Palette.accent
    var size: CGFloat = 34
    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.18), lineWidth: size * 0.14)
            Circle().trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(color, style: StrokeStyle(lineWidth: size * 0.14, lineCap: .round)).rotationEffect(.degrees(-90))
            if progress >= 1 { Image(systemName: "checkmark").font(.system(size: size * 0.36, weight: .bold)).foregroundStyle(color) }
        }
        .frame(width: size, height: size)
        .accessibilityLabel("\(Int((progress * 100).rounded())) percent of goal")
    }
}

/// Horizontal bar split into coloured parts, for sleep stages.
struct SegmentBar: View {
    let parts: [(value: Double, color: Color)]
    var height: CGFloat = 10
    var body: some View {
        let total = max(parts.reduce(0) { $0 + $1.value }, 1)
        GeometryReader { geo in
            HStack(spacing: 2) {
                ForEach(Array(parts.enumerated()), id: \.offset) { _, p in
                    RoundedRectangle(cornerRadius: height / 2, style: .continuous).fill(p.color)
                        .frame(width: max(0, (geo.size.width - CGFloat(parts.count - 1) * 2) * p.value / total))
                }
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}
