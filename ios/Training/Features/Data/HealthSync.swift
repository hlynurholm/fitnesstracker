import HealthKit
import Observation

/// Reads daily nutrition totals and the first weigh-in of each day from Apple Health and sends them to the backend,
/// so MyFitnessPal (which writes food and weight to Health) no longer needs a manual CSV export.
///
/// It only reads from Health and only writes through the existing API: PUT /api/nutrition and PUT /api/body.
/// It never replaces richer data: a day imported from a MyFitnessPal CSV keeps its meal breakdown, and a weight typed
/// in by hand stays as typed.
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

    func connect() async {
        let types = Set(Self.nutrients.map { HKQuantityType($0.id) } + [HKQuantityType(.bodyMass)])
        do {
            try await store.requestAuthorization(toShare: [], read: types)
            enabled = true
            await sync()
        } catch { status = "Could not ask for Health access: \(error.localizedDescription)" }
    }

    func disconnect() { enabled = false; status = nil }

    /// Sends what Health has for the last `days` days and the backend lacks. Safe to run often.
    func sync(days: Int = 14) async {
        guard enabled, Self.available, API.shared.hasToken, !running else { return }
        running = true
        defer { running = false }
        do {
            let calendar = Calendar.current
            let start = calendar.date(byAdding: .day, value: -(days - 1), to: calendar.startOfDay(for: Date()))!
            let health = try await nutrition(from: start)
            let weights = try await firstWeights(from: start)
            let serverNutrition: [NutritionDay] = try await API.shared.get("/api/nutrition")
            let serverBody: [BodyMetric] = try await API.shared.get("/api/body")

            let plan = Self.plan(health: health, weights: weights, serverNutrition: serverNutrition, serverBody: serverBody)
            for day in plan.nutrition {
                var body: [String: Any?] = ["date": day]
                for (field, value) in health[day] ?? [:] { body[field] = (value * 10).rounded() / 10 }
                try await API.shared.send("PUT", "/api/nutrition", body)
            }
            for day in plan.weights {
                try await API.shared.send("PUT", "/api/body", ["date": day, "weight_kg": ((weights[day] ?? 0) * 10).rounded() / 10])
            }
            let time = Date().formatted(date: .omitted, time: .shortened)
            if health.isEmpty && weights.isEmpty {
                // Health never says whether read access was refused, so an empty result gets the likely causes.
                status = "Checked at \(time). Health returned no nutrition or weight for the last \(days) days. Check that MyFitnessPal shares with Health, and that Training may read it (Settings, Health, Data Access)."
            } else if plan.nutrition.isEmpty && plan.weights.isEmpty {
                status = "Checked at \(time). Everything in Health is already on the server."
            } else {
                status = "Synced at \(time): \(plan.nutrition.count) day\(plan.nutrition.count == 1 ? "" : "s") of nutrition, \(plan.weights.count) weigh-in\(plan.weights.count == 1 ? "" : "s")."
            }
        } catch {
            status = "Sync failed: \(error.localizedDescription)"
        }
    }

    /// Which days to send. Kept free of HealthKit and networking so it can be checked on its own.
    nonisolated static func plan(health: [String: [String: Double]], weights: [String: Double], serverNutrition: [NutritionDay], serverBody: [BodyMetric]) -> (nutrition: [String], weights: [String]) {
        let rows = Dictionary(serverNutrition.map { ($0.date, $0) }, uniquingKeysWith: { a, _ in a })
        let nutrition = health.keys.sorted().filter { day in
            guard let kcal = health[day]?["calories"], kcal > 0 else { return false }
            guard let row = rows[day] else { return true }
            // A CSV import has the meals; totals from Health would wipe them. Rows this sync wrote are "manual".
            guard row.source == "manual" else { return false }
            return abs((row.calories ?? 0) - kcal) >= 1 || abs((row.protein_g ?? 0) - (health[day]?["protein_g"] ?? 0)) >= 1
        }
        let typed = Set(serverBody.filter { $0.source == "manual" && $0.weight_kg != nil }.map(\.date))
        return (nutrition, weights.keys.sorted().filter { !typed.contains($0) && (weights[$0] ?? 0) > 0 })
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

    /// The first weigh-in of each local day, in kg: the morning weight.
    private func firstWeights(from start: Date) async throws -> [String: Double] {
        let query = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(.bodyMass), predicate: HKQuery.predicateForSamples(withStart: start, end: nil))],
            sortDescriptors: [SortDescriptor(\.startDate)])
        var out: [String: Double] = [:]
        for sample in try await query.result(for: store) {
            let day = Day.local(sample.startDate)
            if out[day] == nil { out[day] = sample.quantity.doubleValue(for: .gramUnit(with: .kilo)) }
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
        let body = [BodyMetric(date: "2026-11-01", weight_kg: 93, source: "manual"), BodyMetric(date: "2026-11-02", weight_kg: 93, source: "myfitnesspal")]
        let p = plan(health: health, weights: ["2026-11-01": 92.5, "2026-11-02": 92.4, "2026-11-03": 92.3], serverNutrition: server, serverBody: body)
        assert(p.nutrition == ["2026-11-01", "2026-11-04"], "nutrition plan: \(p.nutrition)")
        assert(p.weights == ["2026-11-02", "2026-11-03"], "weight plan: \(p.weights)") // the typed weight on the 1st stays
    }
    #endif
}
