import Foundation
import SwiftData

/// One month of timings from Aladhan's calendar endpoints.
nonisolated struct AladhanMonth: Sendable {
    let timezoneID: String
    let days: [Day: DayTimings]
}

nonisolated enum PrayerTimesError: LocalizedError {
    case badResponse(String)
    case noData

    var errorDescription: String? {
        switch self {
        case let .badResponse(message): message
        case .noData: "Prayer times are unavailable. Check your connection and try again."
        }
    }
}

/// Aladhan HTTP client (port of prayer_api.py, using the monthly calendar endpoints).
nonisolated enum AladhanClient {
    private struct Response: Decodable {
        struct Entry: Decodable {
            struct DateInfo: Decodable {
                struct Gregorian: Decodable { let date: String } // "DD-MM-YYYY"
                let gregorian: Gregorian
            }
            struct Meta: Decodable { let timezone: String }
            let timings: [String: String]
            let date: DateInfo
            let meta: Meta
        }
        let code: Int
        let data: [Entry]
    }

    private struct ErrorResponse: Decodable {
        let code: Int
        let data: String
    }

    static func url(for query: LocationQuery, method: Int, school: Int, year: Int, month: Int) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.aladhan.com"
        var items = [URLQueryItem(name: "method", value: String(method)),
                     URLQueryItem(name: "school", value: String(school))]
        switch query {
        case let .coordinates(lat, lon):
            components.path = "/v1/calendar/\(year)/\(month)"
            items += [URLQueryItem(name: "latitude", value: String(lat)),
                      URLQueryItem(name: "longitude", value: String(lon))]
        case let .city(name, country):
            components.path = "/v1/calendarByCity/\(year)/\(month)"
            items += [URLQueryItem(name: "city", value: name),
                      URLQueryItem(name: "country", value: country)]
        }
        components.queryItems = items
        return components.url!
    }

    static func parse(_ data: Data) throws -> AladhanMonth {
        let decoder = JSONDecoder()
        guard let response = try? decoder.decode(Response.self, from: data) else {
            if let error = try? decoder.decode(ErrorResponse.self, from: data) {
                throw PrayerTimesError.badResponse(error.data)
            }
            throw PrayerTimesError.noData
        }
        var days: [Day: DayTimings] = [:]
        var timezone: String?
        for entry in response.data {
            let p = entry.date.gregorian.date.split(separator: "-").compactMap { Int($0) }
            guard p.count == 3, let timings = DayTimings(aladhan: entry.timings) else { continue }
            days[Day(year: p[2], month: p[1], day: p[0])] = timings
            timezone = timezone ?? entry.meta.timezone
        }
        guard let timezone, !days.isEmpty else { throw PrayerTimesError.noData }
        return AladhanMonth(timezoneID: timezone, days: days)
    }

    static func fetchMonth(_ query: LocationQuery, method: Int, school: Int,
                           year: Int, month: Int, session: URLSession = .shared) async throws -> AladhanMonth {
        var request = URLRequest(url: url(for: query, method: method, school: school, year: year, month: month))
        request.timeoutInterval = 20
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            if let error = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
                throw PrayerTimesError.badResponse(error.data)
            }
            throw PrayerTimesError.badResponse("Aladhan API returned status \(http.statusCode).")
        }
        return try parse(data)
    }
}

/// A day's timings plus where they came from.
struct ResolvedTimings: Equatable {
    let day: Day
    let timings: DayTimings
    let timeZone: TimeZone
    /// True when using the last good data from another day because this day isn't cached.
    let isFallback: Bool
}

/// Fetches whole months from Aladhan and caches them per day in SwiftData.
final class PrayerTimesService {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    /// Fetches one month and stores it. Returns the month (with Aladhan's meta.timezone).
    @discardableResult
    func fetchAndStore(_ query: LocationQuery, method: Int, school: Int,
                       year: Int, month: Int) async throws -> AladhanMonth {
        let result = try await AladhanClient.fetchMonth(query, method: method, school: school,
                                                        year: year, month: month)
        let key = query.cacheKey(method: method, school: school)
        let existing = cachedRows(locationKey: key)
        let byDay = Dictionary(existing.map { ($0.day, $0) }, uniquingKeysWith: { a, _ in a })
        for (day, timings) in result.days {
            if let row = byDay[day.key] {
                row.update(timezoneID: result.timezoneID, timings: timings)
            } else {
                context.insert(CachedTimings(locationKey: key, day: day, timezoneID: result.timezoneID,
                                             timings: timings))
            }
        }
        try? context.save()
        return result
    }

    /// Makes sure every day in `today ... today + daysAhead` is cached, fetching the current
    /// and (when needed) next month. Failures are tolerated if cached data exists.
    /// - Returns: the timezone reported by Aladhan, if a fetch succeeded.
    @discardableResult
    func ensureCached(_ query: LocationQuery, method: Int, school: Int,
                      today: Day, daysAhead: Int = 7) async -> String? {
        let key = query.cacheKey(method: method, school: school)
        let cachedDays = Set(cachedRows(locationKey: key).map(\.day))
        let needed = Day.range(today, today.adding(days: daysAhead))
        var months: [(Int, Int)] = []
        for day in needed where !cachedDays.contains(day.key) {
            if !months.contains(where: { $0 == (day.year, day.month) }) { months.append((day.year, day.month)) }
        }

        var timezone: String?
        for (year, month) in months {
            do {
                let result = try await fetchAndStore(query, method: method, school: school, year: year, month: month)
                timezone = result.timezoneID
            } catch {
                print("Prayer times fetch failed for \(year)-\(month): \(error.localizedDescription)")
            }
        }
        // Only prune after a successful fetch so offline fallback data survives.
        if timezone != nil { pruneOldRows(before: today.adding(days: -60)) }
        return timezone
    }

    /// Cached timings for a day, falling back to the last good cached day for this location.
    func timings(for day: Day, query: LocationQuery, method: Int, school: Int) -> ResolvedTimings? {
        let key = query.cacheKey(method: method, school: school)
        let id = "\(key)#\(day.key)"
        var exact = FetchDescriptor<CachedTimings>(predicate: #Predicate { $0.id == id })
        exact.fetchLimit = 1
        if let row = try? context.fetch(exact).first, let tz = TimeZone(identifier: row.timezoneID) {
            return ResolvedTimings(day: day, timings: row.timings, timeZone: tz, isFallback: false)
        }

        // Fallback: closest earlier cached day, else the earliest later one.
        let rows = cachedRows(locationKey: key)
        let dayKey = day.key
        let candidate = rows.filter { $0.day < dayKey }.max { $0.day < $1.day }
            ?? rows.min { $0.day < $1.day }
        guard let row = candidate, let tz = TimeZone(identifier: row.timezoneID) else { return nil }
        return ResolvedTimings(day: day, timings: row.timings, timeZone: tz, isFallback: true)
    }

    func hasCache(for query: LocationQuery, method: Int, school: Int) -> Bool {
        !cachedRows(locationKey: query.cacheKey(method: method, school: school)).isEmpty
    }

    func deleteAll() {
        try? context.delete(model: CachedTimings.self)
        try? context.save()
    }

    private func cachedRows(locationKey: String) -> [CachedTimings] {
        let descriptor = FetchDescriptor<CachedTimings>(predicate: #Predicate { $0.locationKey == locationKey })
        return (try? context.fetch(descriptor)) ?? []
    }

    private func pruneOldRows(before day: Day) {
        let cutoff = day.key
        let all = (try? context.fetch(FetchDescriptor<CachedTimings>())) ?? []
        for row in all where row.day < cutoff { context.delete(row) }
        try? context.save()
    }
}
