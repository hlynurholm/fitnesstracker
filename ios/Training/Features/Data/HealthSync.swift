import HealthKit
import Observation

/// Reads from Apple Health and sends to the backend:
/// - daily nutrition totals (MyFitnessPal writes food to Health), through PUT /api/nutrition;
/// - body measurements from a connected scale: weight, body fat, lean mass, BMI and waist, through PUT /api/apple-health.
///   The first sync sends everything Health has, later ones the last month.
///
/// It only reads from Health. It never replaces richer data: a day imported from a MyFitnessPal CSV keeps its meal
/// breakdown, and the server keeps a weight typed in by hand ahead of the scale's.
@MainActor @Observable
final class HealthSync {
    static let shared = HealthSync()
    static var available: Bool { HKHealthStore.isHealthDataAvailable() }

    /// Turned on by "Connect Apple Health". Sync then runs whenever the app comes to the front.
    private(set) var enabled = UserDefaults.standard.bool(forKey: "healthSync") {
        didSet { UserDefaults.standard.set(enabled, forKey: "healthSync") }
    }
    private(set) var running = false
    /// What the last run did, for the Data tab.
    private(set) var status: String? = UserDefaults.standard.string(forKey: "healthSyncStatus") {
        didSet { UserDefaults.standard.set(status, forKey: "healthSyncStatus") }
    }

    private let store = HKHealthStore()

    /// Health quantity, its unit, and the API field it becomes.
    private static let nutrients: [(id: HKQuantityTypeIdentifier, unit: HKUnit, field: String)] = [
        (.dietaryEnergyConsumed, .kilocalorie(), "calories"),
        (.dietaryProtein, .gram(), "protein_g"),
        (.dietaryCarbohydrates, .gram(), "carbs_g"),
        (.dietaryFatTotal, .gram(), "fat_g"),
        (.dietaryFiber, .gram(), "fiber_g"),
        (.dietarySugar, .gram(), "sugar_g"),
        (.dietarySodium, .gramUnit(with: .milli), "sodium_mg"),
    ]

    /// Body measurement in Health, its unit and scale, and the name it is stored under ("body.<name>" on the server).
    /// Health has no type for visceral fat, muscle mass, bone mass or body water, so a scale cannot pass those on.
    private static let measurements: [(id: HKQuantityTypeIdentifier, unit: HKUnit, scale: Double, name: String)] = [
        (.bodyFatPercentage, .percent(), 100, "fatPercent"),
        (.leanBodyMass, .gramUnit(with: .kilo), 1, "leanMassKg"),
        (.bodyMassIndex, .count(), 1, "bmi"),
        (.waistCircumference, .meterUnit(with: .centi), 1, "waistCm"),
    ]

    private static var readTypes: Set<HKObjectType> {
        Set(nutrients.map { HKQuantityType($0.id) } + measurements.map { HKQuantityType($0.id) } + [HKQuantityType(.bodyMass)])
    }

    func connect() async {
        do {
            try await store.requestAuthorization(toShare: [], read: Self.readTypes)
            enabled = true
            await sync()
        } catch { status = "Could not ask for Health access: \(error.localizedDescription)" }
    }

    func disconnect() { enabled = false; status = nil }

    /// Sends what Health has and the backend lacks. Safe to run often.
    func sync(days: Int = 14) async {
        guard enabled, Self.available, API.shared.hasToken, !running else { return }
        running = true
        defer { running = false }
        do {
            // Asks only when a kind of data was added since access was first granted (body composition, for example).
            try? await store.requestAuthorization(toShare: [], read: Self.readTypes)
            let calendar = Calendar.current
            let start = calendar.date(byAdding: .day, value: -(days - 1), to: calendar.startOfDay(for: Date()))!
            let health = try await nutrition(from: start)
            let serverNutrition: [NutritionDay] = try await API.shared.get("/api/nutrition")
            let send = Self.plan(health: health, serverNutrition: serverNutrition)
            for day in send {
                var body: [String: Any?] = ["date": day]
                for (field, value) in health[day] ?? [:] { body[field] = (value * 10).rounded() / 10 }
                try await API.shared.send("PUT", "/api/nutrition", body)
            }

            // Body measurements: everything Health has the first time, then the last month.
            let firstTime = !UserDefaults.standard.bool(forKey: "healthBodyHistorySent")
            let bodyDays = try await bodyMeasurements(from: firstTime ? .distantPast : calendar.date(byAdding: .day, value: -30, to: start)!)
            let dates = bodyDays.keys.sorted()
            for chunk in stride(from: 0, to: dates.count, by: 300).map({ Array(dates[$0..<min($0 + 300, dates.count)]) }) {
                let payload: [[String: Any]] = chunk.map { date in
                    var day: [String: Any] = ["date": date]
                    if let kg = bodyDays[date]?["weight_kg"] { day["weight_kg"] = kg }
                    let metrics = (bodyDays[date] ?? [:]).filter { $0.key != "weight_kg" }
                    if !metrics.isEmpty { day["metrics"] = metrics }
                    return day
                }
                try await API.shared.send("PUT", "/api/apple-health", ["days": payload])
            }
            UserDefaults.standard.set(true, forKey: "healthBodyHistorySent")

            let time = Date().formatted(date: .omitted, time: .shortened)
            let weighIns = bodyDays.values.filter { $0["weight_kg"] != nil }.count
            let composition = bodyDays.values.filter { $0["fatPercent"] != nil || $0["leanMassKg"] != nil }.count
            if health.isEmpty && bodyDays.isEmpty {
                // Health never says whether read access was refused, so an empty result gets the likely causes.
                status = "Checked at \(time). Health returned no nutrition or body measurements. Check that your scale and MyFitnessPal share with Health, and that Training may read it (Settings, Health, Data Access)."
            } else {
                var parts: [String] = []
                parts.append(send.isEmpty ? "nutrition up to date" : "\(send.count) day\(send.count == 1 ? "" : "s") of nutrition")
                parts.append("\(weighIns) weigh-in\(weighIns == 1 ? "" : "s")" + (firstTime ? " from your whole Health history" : " from the last weeks"))
                if composition > 0 { parts.append("\(composition) with body fat or lean mass") }
                if let first = dates.first, firstTime, weighIns > 0 { parts.append("oldest \(Day.label(first, year: true))") }
                status = "Synced at \(time): " + parts.joined(separator: ", ") + "."
            }
        } catch {
            status = "Sync failed: \(error.localizedDescription)"
        }
    }

    /// Which days of nutrition to send. Kept free of HealthKit and networking so it can be checked on its own.
    nonisolated static func plan(health: [String: [String: Double]], serverNutrition: [NutritionDay]) -> [String] {
        let rows = Dictionary(serverNutrition.map { ($0.date, $0) }, uniquingKeysWith: { a, _ in a })
        return health.keys.sorted().filter { day in
            guard let kcal = health[day]?["calories"], kcal > 0 else { return false }
            guard let row = rows[day] else { return true }
            // A CSV import has the meals; totals from Health would wipe them. Rows this sync wrote are "manual".
            guard row.source == "manual" else { return false }
            return abs((row.calories ?? 0) - kcal) >= 1 || abs((row.protein_g ?? 0) - (health[day]?["protein_g"] ?? 0)) >= 1
        }
    }

    // MARK: Reading Health

    /// Daily totals per nutrient, as the Health app shows them, keyed by local day.
    private func nutrition(from start: Date) async throws -> [String: [String: Double]] {
        var out: [String: [String: Double]] = [:]
        let range = HKQuery.predicateForSamples(withStart: start, end: nil)
        for n in Self.nutrients {
            let query = HKStatisticsCollectionQueryDescriptor(
                predicate: .quantitySample(type: HKQuantityType(n.id), predicate: range),
                options: .cumulativeSum, anchorDate: start, intervalComponents: DateComponents(day: 1))
            let result = try await query.result(for: store)
            result.enumerateStatistics(from: start, to: Date()) { stats, _ in
                if let v = stats.sumQuantity()?.doubleValue(for: n.unit), v > 0 { out[Day.local(stats.startDate), default: [:]][n.field] = v }
            }
        }
        return out
    }

    /// The first reading of each local day (the morning one) for weight and each body measurement.
    /// Returns day to { "weight_kg": ..., "fatPercent": ..., ... }.
    private func bodyMeasurements(from start: Date) async throws -> [String: [String: Double]] {
        var out: [String: [String: Double]] = [:]
        let all = [(id: HKQuantityTypeIdentifier.bodyMass, unit: HKUnit.gramUnit(with: .kilo), scale: 1.0, name: "weight_kg")] + Self.measurements
        for m in all {
            let query = HKSampleQueryDescriptor(
                predicates: [.quantitySample(type: HKQuantityType(m.id), predicate: HKQuery.predicateForSamples(withStart: start, end: nil))],
                sortDescriptors: [SortDescriptor(\.startDate)])
            for sample in try await query.result(for: store) {
                let day = Day.local(sample.startDate)
                if out[day]?[m.name] == nil { out[day, default: [:]][m.name] = (sample.quantity.doubleValue(for: m.unit) * m.scale * 100).rounded() / 100 }
            }
        }
        return out
    }

    #if DEBUG
    /// One runnable check of the send-or-skip rules. Called at launch in debug builds.
    nonisolated static func selfCheck() {
        func day(_ date: String, _ kcal: Double, _ source: String) -> NutritionDay {
            NutritionDay(date: date, calories: kcal, protein_g: 100, carbs_g: nil, fat_g: nil, sugar_g: nil, meals: nil, source: source)
        }
        let health: [String: [String: Double]] = [
            "2026-11-01": ["calories": 2400, "protein_g": 150], // not on the server: send
            "2026-11-02": ["calories": 2400, "protein_g": 150], // CSV import on the server: keep the import
            "2026-11-03": ["calories": 2400, "protein_g": 100], // sent before, unchanged: skip
            "2026-11-04": ["calories": 2600, "protein_g": 100], // sent before, eaten more since: send again
            "2026-11-05": ["protein_g": 20],                   // no energy logged: skip
        ]
        let server = [day("2026-11-02", 2300, "myfitnesspal"), day("2026-11-03", 2400, "manual"), day("2026-11-04", 2400, "manual")]
        let p = plan(health: health, serverNutrition: server)
        assert(p == ["2026-11-01", "2026-11-04"], "nutrition plan: \(p)")
    }
    #endif
}
