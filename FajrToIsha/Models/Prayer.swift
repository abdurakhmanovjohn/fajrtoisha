import Foundation

/// App-wide constants, mirroring the module-level constants in the bot's main.py.
nonisolated enum AppConfig {
    /// Display format for all times. Equivalent of `TIME_FMT` in the bot.
    /// Set to "h:mm a" for 12-hour AM/PM.
    static let timeFormat = "HH:mm"

    static let offsetOptions = [5, 10, 15, 20, 30]
    static let defaultOffset = 15
    static let defaultAsrSchool = 1   // 1 = Hanafi, 0 = Standard (Shafi'i)
    static let defaultCalcMethod = 14
    static let summaryHour = 21

    static let backgroundRefreshID = "com.abdurakhmanovjohn.fajrtoisha.refresh"

    /// Weeks start on Monday (the bot uses calendar.MONDAY).
    static let firstWeekday = 2
}

nonisolated enum Prayers {
    static let fard = ["Fajr", "Dhuhr", "Asr", "Maghrib", "Isha"]
    static let nafl = ["Tahajjud", "Duha", "Ishraq", "Awwabin", "Tarawih"]
    static let qaza = ["Fajr", "Dhuhr", "Asr", "Maghrib", "Isha", "Witr"]
    /// The six timings shown and cached (Sunrise marks the end of Fajr).
    static let timingNames = ["Fajr", "Sunrise", "Dhuhr", "Asr", "Maghrib", "Isha"]
}

nonisolated enum LogCategory: String, Codable, Sendable {
    case fard
    case nafl
}

/// Aladhan calculation methods offered in Settings.
nonisolated struct CalcMethod: Identifiable, Hashable, Sendable {
    let id: Int
    let name: String

    static let all: [CalcMethod] = [
        .init(id: 14, name: "Spiritual Administration of Muslims of Russia"),
        .init(id: 3, name: "Muslim World League"),
        .init(id: 2, name: "ISNA (North America)"),
        .init(id: 1, name: "University of Islamic Sciences, Karachi"),
        .init(id: 4, name: "Umm al-Qura, Makkah"),
        .init(id: 5, name: "Egyptian General Authority of Survey"),
        .init(id: 13, name: "Diyanet İşleri Başkanlığı, Turkey"),
        .init(id: 8, name: "Gulf Region"),
        .init(id: 9, name: "Kuwait"),
        .init(id: 10, name: "Qatar"),
        .init(id: 16, name: "Dubai"),
        .init(id: 11, name: "Majlis Ugama Islam Singapura"),
        .init(id: 17, name: "JAKIM, Malaysia"),
        .init(id: 20, name: "KEMENAG, Indonesia"),
        .init(id: 12, name: "UOIF, France"),
        .init(id: 15, name: "Moonsighting Committee Worldwide"),
        .init(id: 7, name: "Institute of Geophysics, Tehran"),
        .init(id: 0, name: "Jafari / Shia Ithna-Ashari"),
        .init(id: 18, name: "Tunisia"),
        .init(id: 19, name: "Algeria"),
        .init(id: 21, name: "Morocco"),
        .init(id: 22, name: "Comunidade Islamica de Lisboa"),
        .init(id: 23, name: "Jordan"),
    ]

    static func name(for id: Int) -> String {
        all.first { $0.id == id }?.name ?? "Method \(id)"
    }
}

/// One day's timings as "HH:mm" strings in the location's timezone.
nonisolated struct DayTimings: Codable, Hashable, Sendable {
    var fajr: String
    var sunrise: String
    var dhuhr: String
    var asr: String
    var maghrib: String
    var isha: String

    subscript(name: String) -> String? {
        switch name {
        case "Fajr": fajr
        case "Sunrise": sunrise
        case "Dhuhr": dhuhr
        case "Asr": asr
        case "Maghrib": maghrib
        case "Isha": isha
        default: nil
        }
    }

    /// Builds timings from Aladhan's map, stripping suffixes like " (+05)".
    init?(aladhan raw: [String: String]) {
        func clean(_ key: String) -> String? {
            guard let value = raw[key] else { return nil }
            return TimeOfDay.clean(value)
        }
        guard let f = clean("Fajr"), let s = clean("Sunrise"), let d = clean("Dhuhr"),
              let a = clean("Asr"), let m = clean("Maghrib"), let i = clean("Isha") else { return nil }
        self.init(fajr: f, sunrise: s, dhuhr: d, asr: a, maghrib: m, isha: i)
    }

    init(fajr: String, sunrise: String, dhuhr: String, asr: String, maghrib: String, isha: String) {
        self.fajr = fajr
        self.sunrise = sunrise
        self.dhuhr = dhuhr
        self.asr = asr
        self.maghrib = maghrib
        self.isha = isha
    }

    /// Absolute moment of a timing on `day` in `timeZone`.
    func date(of name: String, on day: Day, in timeZone: TimeZone) -> Date? {
        guard let value = self[name], let (h, m) = TimeOfDay.parse(value) else { return nil }
        return day.date(hour: h, minute: m, in: timeZone)
    }
}

nonisolated enum TimeOfDay {
    /// "04:58 (+05)" -> "04:58". Returns nil if the result isn't a valid HH:mm.
    static func clean(_ raw: String) -> String? {
        guard let first = raw.split(separator: " ").first else { return nil }
        let value = String(first)
        return parse(value) == nil ? nil : value
    }

    static func parse(_ hhmm: String) -> (Int, Int)? {
        let parts = hhmm.split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]),
              (0..<24).contains(h), (0..<60).contains(m) else { return nil }
        return (h, m)
    }

    /// Formats a date using `AppConfig.timeFormat` in the given timezone (fmt_dt).
    static func format(_ date: Date, in timeZone: TimeZone) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = AppConfig.timeFormat
        return f.string(from: date)
    }

    /// Formats an "HH:mm" string using `AppConfig.timeFormat` (fmt_time).
    static func format(_ hhmm: String) -> String {
        guard let (h, m) = parse(hhmm) else { return hhmm }
        var comps = DateComponents()
        comps.hour = h
        comps.minute = m
        let utc = TimeZone(identifier: "UTC")!
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = utc
        guard let date = cal.date(from: comps) else { return hhmm }
        return format(date, in: utc)
    }
}
