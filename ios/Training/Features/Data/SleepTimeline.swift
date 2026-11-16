import HealthKit
import SwiftUI

/// One stretch of a night in one stage. Lanes run top to bottom: 0 awake, 1 REM, 2 light, 3 deep.
struct SleepStage: Hashable {
    let start: Date, end: Date, lane: Int
}

extension HealthSync {
    /// The stages of the night that ended on `date`, from Apple Health (Garmin Connect writes them there; Garmin's
    /// own service only hands out totals). Empty when Health is not connected or has no stages for that night.
    func sleepStages(endingOn date: String) async -> [SleepStage] {
        let p = date.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3, let noon = Calendar.current.date(from: DateComponents(year: p[0], month: p[1], day: p[2], hour: 12)) else { return [] }
        let evening = noon.addingTimeInterval(-18 * 3600)
        // TRAINING_SLEEP_DEMO=1 draws a made-up night, to look at the picture in the simulator.
        if ProcessInfo.processInfo.environment["TRAINING_SLEEP_DEMO"] != nil {
            let plan: [(Double, Int)] = [(12, 2), (25, 3), (18, 2), (6, 0), (30, 2), (40, 3), (22, 2), (35, 1), (45, 2), (28, 3), (20, 2), (8, 1), (50, 2), (30, 1), (4, 0), (25, 2)]
            var t = evening.addingTimeInterval(5.5 * 3600)
            return plan.map { minutes, lane in defer { t = t.addingTimeInterval(minutes * 60) }; return SleepStage(start: t, end: t.addingTimeInterval(minutes * 60), lane: lane) }
        }
        guard enabled, Self.available else { return [] }
        try? await store.requestAuthorization(toShare: [], read: Self.readTypes)
        let query = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: HKCategoryType(.sleepAnalysis), predicate: HKQuery.predicateForSamples(withStart: evening, end: noon))],
            sortDescriptors: [SortDescriptor(\.startDate)])
        let samples = (try? await query.result(for: store)) ?? []
        let lanes: [Int: Int] = [HKCategoryValueSleepAnalysis.awake.rawValue: 0, HKCategoryValueSleepAnalysis.asleepREM.rawValue: 1,
                                 HKCategoryValueSleepAnalysis.asleepCore.rawValue: 2, HKCategoryValueSleepAnalysis.asleepDeep.rawValue: 3]
        // Two devices can both write a night: keep the one that says the most.
        let bySource = Dictionary(grouping: samples.filter { lanes[$0.value] != nil }, by: { $0.sourceRevision.source.bundleIdentifier })
        let best = bySource.values.max { $0.count < $1.count } ?? []
        return best.map { SleepStage(start: $0.startDate, end: $0.endDate, lane: lanes[$0.value]!) }
    }
}

/// The night as a timeline: a block for every stretch of a stage, awake on top and deep at the bottom, joined where
/// one stage passes into the next. Falls back to the plain share-of-the-night bar when there is no timeline.
struct SleepTimeline: View {
    let date: String
    /// Deep, light, REM, awake.
    let colors: [Color]
    let fallback: [(value: Double, color: Color)]
    var height: CGFloat = 76
    /// The first and last clock time under the picture; off where the card already says them.
    var times = true
    @State private var stages: [SleepStage] = []

    var body: some View {
        Group {
            if let first = stages.first, let last = stages.last, last.end > first.start {
                let span = last.end.timeIntervalSince(first.start)
                let color = { (lane: Int) in colors[3 - lane] }
                VStack(spacing: 3) {
                    Canvas { context, size in
                        let row = size.height / 4, block = row - 4
                        let x = { (d: Date) in size.width * d.timeIntervalSince(first.start) / span }
                        let y = { (lane: Int) in CGFloat(lane) * row + 2 }
                        // Joins first, so the blocks sit on top of them.
                        for (a, b) in zip(stages, stages.dropFirst()) where a.lane != b.lane && b.start.timeIntervalSince(a.end) < 300 {
                            var join = Path()
                            join.move(to: CGPoint(x: x(b.start), y: y(min(a.lane, b.lane)) + block / 2))
                            join.addLine(to: CGPoint(x: x(b.start), y: y(max(a.lane, b.lane)) + block / 2))
                            context.stroke(join, with: .linearGradient(Gradient(colors: [color(min(a.lane, b.lane)), color(max(a.lane, b.lane))]),
                                                                       startPoint: CGPoint(x: 0, y: y(min(a.lane, b.lane))), endPoint: CGPoint(x: 0, y: y(max(a.lane, b.lane)) + block)),
                                           lineWidth: 1.5)
                        }
                        for s in stages {
                            let rect = CGRect(x: x(s.start), y: y(s.lane), width: max(x(s.end) - x(s.start), 2.5), height: block)
                            context.fill(Path(roundedRect: rect, cornerRadius: min(5, rect.width / 2), style: .continuous), with: .color(color(s.lane)))
                        }
                    }
                    .frame(height: height)
                    if times { HStack {
                        Text(first.start.formatted(date: .omitted, time: .shortened))
                        Spacer()
                        Text(last.end.formatted(date: .omitted, time: .shortened))
                    }
                    .font(Theme.Typography.label).opacity(0.7) }
                }
                .accessibilityHidden(true)
            } else {
                SegmentBar(parts: fallback, height: 10)
            }
        }
        .task(id: date) { stages = await HealthSync.shared.sleepStages(endingOn: date) }
    }
}
