import Foundation

// Wire models. Property names mirror the API's JSON keys exactly (snake_case for database rows,
// camelCase for values that come from program.js), so no CodingKeys or key strategies are needed.
// A key strategy would also rewrite dictionary keys such as exercise keys, which must stay as they are.

/// A value the API sends as either a number or a string.
struct Flex: Decodable, Hashable {
    let text: String
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) { text = s }
        else if let d = try? c.decode(Double.self) { text = Fmt.number(d) }
        else { text = "" }
    }
}

// MARK: Program (GET /api/program)

struct ProgramResponse: Decodable {
    let program: Program
    let settings: Settings
}

struct Program: Decodable {
    struct Body: Decodable { let goalWeightKg: Double }
    struct Nutrition: Decodable { let calories: Double; let proteinG: Double; let funBudgetWeekKcal: Double; let note: String? }
    struct Running: Decodable { let fiveKTargetSec: Double; let fiveKStretchSec: Double; let baselineNote: String?; let cadenceNote: String? }
    struct Zone: Decodable, Hashable { let name: String; let from: Int; let to: Int; let note: String? }
    struct HeartRate: Decodable { let maxBpm: Int; let thresholdBpm: Int; let zones: [Zone] }
    struct Item: Decodable, Hashable { let id: String; let text: String }
    struct Checklist: Decodable { let title: String; let minutes: Flex; let note: String?; let items: [Item] }
    struct Jumps: Decodable { let title: String; let minutes: Flex; let note: String?; let phaseNotes: [String: String]? }
    struct TestDef: Decodable, Hashable { let key: String; let name: String; let unit: String; let input: String }

    let name: String
    let body: Body
    let nutrition: Nutrition
    let running: Running
    let heartRate: HeartRate
    let stepsNote: String?
    let warmup: Checklist
    let jumps: Jumps
    let kneeRoutine: Checklist
    let exercises: [String: Exercise]
    let templates: [String: Template]
    let tests: [TestDef]

    /// Metadata for an exercise key, including custom ones typed in the app ("custom:name").
    func exercise(_ key: String) -> Exercise {
        if let e = exercises[key] { return e }
        let name = key.hasPrefix("custom:") ? key.dropFirst(7).replacingOccurrences(of: "_", with: " ").capitalizedFirst : key
        return Exercise(name: name, short: nil, fields: ["kg", "reps"], increment: 2.5, group: "other", e1rm: key.hasPrefix("custom:"), kgOptional: nil, hidden: nil, kgHint: nil)
    }
}

struct Exercise: Decodable, Hashable {
    let name: String
    let short: String?
    /// Which inputs a set row shows: kg, reps, seconds, meters.
    let fields: [String]
    let increment: Double?
    let group: String
    let e1rm: Bool?
    let kgOptional: Bool?
    let hidden: Bool?
    let kgHint: String?
    var shortName: String { short ?? name }
}

struct Template: Decodable, Hashable {
    struct Finisher: Decodable, Hashable { let title: String; let text: String; let minutes: Flex? }
    struct Intervals: Decodable, Hashable { let reps: Int; let workSec: Int; let restSec: Int }
    let key: String
    let name: String
    let kind: String
    let subtitle: String?
    let duration: String?
    let blocks: [String]?
    let tips: [String]?
    let finisher: Finisher?
    let detail: String?
    let pace: String?
    let intervals: Intervals?
    let timeTrial: Bool?
    let easy: Bool?
}

struct Jump: Decodable, Hashable { let id: String; let name: String; let sets: String; let note: String? }

/// One exercise in a session's plan. Sent back to the server unchanged when the plan is edited.
struct PlanEntry: Codable, Hashable {
    var key: String
    var sets: Int
    var reps: String?
    var repsMin: Int?
    var repsMax: Int?
    var note: String?
    var startKg: Double?
    var amrap: Bool?
    var seconds: Int?
    var meters: Int?
    var plannedSets: Int?
    var added: Bool?
    var replaces: String?
}

/// Key/value settings. Everything is stored as text on the server.
struct Settings: Decodable {
    var values: [String: String] = [:]
    private struct Key: CodingKey { var stringValue: String; var intValue: Int? { nil }; init?(stringValue: String) { self.stringValue = stringValue }; init?(intValue: Int) { nil } }
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        for k in c.allKeys { if let s = try? c.decode(Flex.self, forKey: k), !s.text.isEmpty { values[k.stringValue] = s.text } }
    }
    subscript(key: String) -> String? { values[key] }
    func number(_ key: String) -> Double? { values[key].flatMap(Fmt.parse) }
}

// MARK: Day (GET /api/day/:date)

struct DayResponse: Decodable {
    var day: DayInfo
    var workouts: [Workout]
    var active: Workout?
    var last: [String: LastSets]
    var body: BodyMetric?
    var tests: [TestResult]?
    var week: [WeekDay]
    var today: String
    /// Estimated days only: where the numbers would be if things go to plan.
    var projection: Projection? = nil
    /// Everything the watch recorded on this date, whichever session it is filed under.
    var recorded: [GarminActivity]? = nil
}

struct Projection: Decodable {
    struct Line: Decodable, Hashable { let label: String; let value: String; let basis: String? }
    let lines: [Line]
    let note: String?
}

struct DayInfo: Decodable {
    let date: String
    let defaultTemplateKey: String
    let moved: Bool
    let weekdayName: String
    let week: Int
    let beforeStart: Bool
    let beyondPlan: Bool
    let phase: Int
    let phaseName: String
    let deload: Bool
    let testWeek: Bool
    let templateKey: String
    let template: Template
    let plan: [PlanEntry]
    let jumps: [Jump]?
    let extras: [String]?
    let startDate: String
    /// concrete, estimate or none: how firm the plan is for this day. Absent on an older server.
    var horizon: String? = nil
    var concreteTo: String? = nil
    var estimateTo: String? = nil
}

struct WeekDay: Decodable, Identifiable {
    let date: String
    let templateKey: String
    let kind: String
    let name: String
    let moved: Bool
    let workouts: [Workout]
    var horizon: String? = nil
    var id: String { date }
}

/// A workout row. List endpoints send a subset, so most fields are optional.
struct Workout: Decodable, Identifiable, Hashable {
    var id: Int
    var date: String
    var template_key: String
    var kind: String
    var status: String
    var week_no: Int?
    var started_at: String?
    var finished_at: String?
    var duration_min: Double?
    var distance_km: Double?
    var time_sec: Double?
    var avg_hr: Double?
    var rpe: Double?
    var notes: String?
    var plan: [PlanEntry]?
    var checklist: [String: [String: Bool]]?
    var sets: [SetRow]?
    var activities: [GarminActivity]?
    var block_notes: [String: String]?
    var set_count: Int?
    var volume_kg: Double?
}

struct SetRow: Decodable, Hashable {
    var client_id: String
    var workout_id: Int?
    var exercise_key: String
    var set_index: Int
    var weight_kg: Double?
    var reps: Int?
    var seconds: Int?
    var distance_m: Double?
    var done: Int?
    var date: String?
    var isDone: Bool { (done ?? 1) != 0 }
}

struct LastSets: Decodable {
    let date: String
    let sets: [SetRow.Values]
    let note: String?
}

extension SetRow {
    struct Values: Decodable, Hashable {
        var set_index: Int?
        var weight_kg: Double?
        var reps: Int?
        var seconds: Int?
        var distance_m: Double?
    }
    var values: Values { Values(set_index: set_index, weight_kg: weight_kg, reps: reps, seconds: seconds, distance_m: distance_m) }
}

struct BodyMetric: Decodable, Hashable { var date: String; var weight_kg: Double?; var source: String? }
struct TestResult: Decodable, Hashable { var date: String; var test_key: String; var value: Double? }

/// The planning horizon: sessions are fixed about a month ahead, estimated for some months after, then empty.
enum Outlook {
    case concrete, estimate, none
    init(_ horizon: String?) { self = horizon == "estimate" ? .estimate : horizon == "none" ? .none : .concrete }
}

// MARK: Schedule (GET /api/schedule)

struct Schedule: Decodable {
    let today: String
    let days: [ScheduleDay]
    var concreteTo: String? = nil
    var estimateTo: String? = nil
}

struct ScheduleDay: Decodable, Identifiable, Hashable {
    let date: String
    let week: Int
    let templateKey: String
    let defaultTemplateKey: String
    let moved: Bool
    let kind: String
    let name: String
    let subtitle: String?
    let deload: Bool
    let testWeek: Bool
    let workouts: [Workout]
    var horizon: String? = nil
    var id: String { date }
    /// How firm the plan is: anything logged or moved is real, otherwise the server's planning horizon decides.
    var outlook: Outlook { main != nil || moved ? .concrete : Outlook(horizon) }
    /// The workout that represents the day: the planned one, else anything not skipped.
    var main: Workout? { workouts.first { $0.template_key == templateKey } ?? workouts.first { $0.status != "skipped" } ?? workouts.first }
}

// MARK: Garmin activities, uploads, reports

struct GarminActivity: Decodable, Identifiable, Hashable {
    struct Split: Decodable, Hashable { let km: Flex?; let index: Flex?; let seconds: Double?; let duration_s: Double?; let pace_s_per_km: Double?; let avg_hr: Double?; let distance_m: Double?; let partial: Bool? }
    /// `edges` is the heart rate each zone starts at, zone 1 first.
    struct Zones: Decodable, Hashable { let max_hr_used: Double?; let edges: [Double]?; let seconds: [Double]? }
    /// One sample of the track: seconds from the start, km covered, heart rate, pace (s/km), altitude and position.
    struct Point: Decodable, Hashable { let t: Double?; let d: Double?; let hr: Double?; let pace: Double?; let alt: Double?; let lat: Double?; let lon: Double? }
    let id: Int
    let workout_id: Int?
    let start_time: String?
    let date: String?
    let sport: String?
    let name: String?
    let distance_m: Double?
    let duration_s: Double?
    let avg_hr: Double?
    let max_hr: Double?
    let avg_pace_s_per_km: Double?
    let best_5k_s: Double?
    let calories: Double?
    let elevation_gain_m: Double?
    var avg_cadence: Double? = nil
    var best_1k_s: Double? = nil
    let splits: [Split]?
    let laps: [Split]?
    let hr_zones: Zones?
    let track: [Point]?

    var isRun: Bool { (sport ?? "").lowercased().contains("run") || sport == nil }
    /// The calendar day of the activity.
    var day: String { date ?? String((start_time ?? "").prefix(10)) }
}

struct Upload: Decodable, Identifiable, Hashable {
    let id: Int
    let source: String
    let format: String
    let filename: String?
    let size_bytes: Double?
    let parse_status: String
    let parse_error: String?
    let uploaded_at: String
    let workout_date: String?
    let activity_count: Int?
}

struct UploadResponse: Decodable {
    struct Result: Decodable { let filename: String?; let status: String?; let error: String?; let nutrition_days: Int? }
    let uploads: [Result]
}

/// GET /api/garmin: whether the Worker's automatic Garmin import is set up, and how its last run went.
struct GarminStatus: Decodable {
    struct Run: Decodable { let at: String?; let ok: Bool?; let found: Int?; let imported: Int?; let already: Int?; let error: String? }
    let configured: Bool
    let last: Run?
}

/// POST /api/garmin/sync
struct GarminSyncResult: Decodable {
    struct Item: Decodable { let id: String?; let name: String?; let date: String? }
    let ok: Bool
    let found: Int
    let imported: [Item]
    let already: Int
    let error: String?
}

struct Report: Decodable, Identifiable, Hashable {
    let id: Int
    let title: String
    let date: String?
    let author: String?
    let section: String?
    let created_at: String?
    let preview: String?
    let body_md: String?
}

// MARK: Dashboard (GET /api/dashboard) and diet (GET /api/diet)

/// GET /api/metrics: daily health metrics from the watch. Each day is a flat set of Garmin field names to values.
struct MetricsResponse: Decodable {
    let days: [MetricDay]
}

struct MetricDay: Decodable {
    struct Value: Decodable {
        let number: Double?
        let text: String?
        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            number = try? c.decode(Double.self)
            text = number == nil ? try? c.decode(String.self) : nil
        }
    }
    let date: String
    let data: [String: Value]
}

struct Dashboard: Decodable {
    /// Today's planned session.
    var today: DayInfo? = nil
    let settings: Settings
    let workouts: [Workout]
    let sets: [SetRow]
    let body: [BodyMetric]
    let tests: [TestResult]
    let nutrition: [NutritionDay]
}

struct NutritionDay: Decodable, Identifiable, Hashable {
    struct Meal: Decodable, Hashable { let meal: String?; let calories: Double?; let protein_g: Double?; let note: String? }
    let date: String
    let calories: Double?
    let protein_g: Double?
    let carbs_g: Double?
    let fat_g: Double?
    let sugar_g: Double?
    let meals: [Meal]?
    /// myfitnesspal for a CSV import, manual for totals sent by the app (Apple Health sync).
    var source: String? = nil
    var id: String { date }
}

struct Diet: Decodable {
    struct Targets: Decodable { let calories: Double; let protein_g: Double; let fun_budget_week_kcal: Double; let maintenance_estimate: Double; let goal_weight_kg: Double; let loss_per_week_kg: [Double] }
    struct TemplateRow: Decodable, Hashable { let when: String; let what: String; let kcal: Double; let protein: Double? }
    struct Week: Decodable, Identifiable, Hashable {
        let week: Int; let monday: String; let days_logged: Int; let kcal_avg: Double?; let protein_avg: Double?; let weight_avg: Double?; let weigh_ins: Int; let weight_change: Double?
        var id: Int { week }
    }
    let targets: Targets
    let day_template: [TemplateRow]
    let nutrition: [NutritionDay]
    let body: [BodyMetric]
    let weeks: [Week]
    let report: Report?
}

extension StringProtocol {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
