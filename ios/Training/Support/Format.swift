import Foundation

/// Calendar days travel as "YYYY-MM-DD" strings, exactly as the API stores them, so there are no timezone surprises.
enum Day {
    private static let utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
    private static let iso: DateFormatter = formatter("yyyy-MM-dd")
    private static let labelFormat = formatter("EEE d MMM")
    private static let labelYearFormat = formatter("EEE d MMM yyyy")
    private static let shortFormat = formatter("d MMM")
    private static let monthFormat = formatter("MMMM yyyy")

    private static func formatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.calendar = utc; f.timeZone = utc.timeZone; f.locale = Locale(identifier: "en_GB"); f.dateFormat = format
        return f
    }

    static func today() -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }
    static func date(_ day: String) -> Date { iso.date(from: String(day.prefix(10))) ?? Date() }
    static func string(_ date: Date) -> String { iso.string(from: date) }
    static func add(_ day: String, _ days: Int) -> String { string(utc.date(byAdding: .day, value: days, to: date(day))!) }
    static func addMonths(_ day: String, _ months: Int) -> String { string(utc.date(byAdding: .month, value: months, to: date(day))!) }
    /// 1 = Monday ... 7 = Sunday
    static func weekday(_ day: String) -> Int { (utc.component(.weekday, from: date(day)) + 5) % 7 + 1 }
    static func monday(of day: String) -> String { add(day, -(weekday(day) - 1)) }
    static func daysBetween(_ a: String, _ b: String) -> Int { utc.dateComponents([.day], from: date(a), to: date(b)).day ?? 0 }
    static func label(_ day: String, year: Bool = false) -> String { (year ? labelYearFormat : labelFormat).string(from: date(day)) }
    static func short(_ day: String) -> String { shortFormat.string(from: date(day)) }
    static func month(_ day: String) -> String { monthFormat.string(from: date(day)) }
    static func dayNumber(_ day: String) -> String { String(Int(day.suffix(2)) ?? 0) }
}

enum Fmt {
    /// Seconds as m:ss or h:mm:ss.
    static func time(_ seconds: Double?) -> String {
        guard let seconds, seconds.isFinite else { return "" }
        let s = Int(seconds.rounded())
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
    }

    /// "25:37", "1:02:11" or "25.5" (minutes) to seconds.
    static func parseTime(_ text: String) -> Double? {
        let t = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard !t.isEmpty else { return nil }
        let parts = t.split(separator: ":", omittingEmptySubsequences: false).map { Double($0) }
        guard !parts.contains(where: { $0 == nil }) else { return nil }
        switch parts.count {
        case 1: return (parts[0]! * 60).rounded()
        case 2: return (parts[0]! * 60 + parts[1]!).rounded()
        case 3: return (parts[0]! * 3600 + parts[1]! * 60 + parts[2]!).rounded()
        default: return nil
        }
    }

    static func pace(_ secondsPerKm: Double?) -> String {
        guard let secondsPerKm, secondsPerKm.isFinite, secondsPerKm > 0 else { return "" }
        return time(secondsPerKm) + "/km"
    }

    /// Up to two decimals, no trailing zeros: 75, 72.5.
    static func number(_ value: Double?) -> String {
        guard let value else { return "" }
        let rounded = (value * 100).rounded() / 100
        return rounded == rounded.rounded() ? String(Int(rounded)) : String(rounded)
    }

    static func whole(_ value: Double?) -> String {
        guard let value else { return "–" }
        return Int(value.rounded()).formatted(.number.locale(Locale(identifier: "en_US")))
    }

    static func signed(_ value: Double, digits: Int = 0) -> String {
        (value >= 0 ? "+" : "") + String(format: "%.\(digits)f", value)
    }

    /// Typed number. Accepts a comma as the decimal separator (Icelandic keyboards offer only a comma).
    static func parse(_ text: String) -> Double? {
        Double(text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
    }

    /// Server timestamps are ISO strings or SQLite "YYYY-MM-DD HH:MM:SS" in UTC.
    static func timestamp(_ text: String?) -> Date? {
        guard let text else { return nil }
        let iso = text.contains("T") ? text : text.replacingOccurrences(of: " ", with: "T") + "Z"
        let f = ISO8601DateFormatter()
        f.formatOptions = iso.contains(".") ? [.withInternetDateTime, .withFractionalSeconds] : [.withInternetDateTime]
        return f.date(from: iso)
    }

    static func isoNow() -> String { ISO8601DateFormatter().string(from: Date()) }

    /// Epley estimated one-rep max.
    static func e1rm(kg: Double?, reps: Int?) -> Double? {
        guard let kg, let reps, kg > 0, reps >= 1 else { return nil }
        return reps == 1 ? kg : kg * (1 + Double(reps) / 30)
    }
}
