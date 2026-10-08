import Foundation
import Testing
@testable import FajrToIsha

private let tz = TimeZone(identifier: "Asia/Tashkent")!
private let today = Day(year: 2026, month: 10, day: 8)
private let sample = DayTimings(fajr: "04:58", sunrise: "06:19", dhuhr: "12:13",
                                asr: "16:20", maghrib: "18:05", isha: "19:21")

private func plan(now: Date, days: Int = NotificationPlanner.windowDays,
                  limit: Int = NotificationPlanner.defaultLimit,
                  completed: Set<String> = []) -> [PlannedNotification] {
    NotificationPlanner.plan(now: now, today: Day(now, in: tz), timeZone: tz, offsetMinutes: 15,
                             days: days, limit: limit,
                             timings: { _ in sample },
                             isCompleted: { name, day in completed.contains("\(day.key)_\(name)") })
}

private func at(_ hour: Int, _ minute: Int, on day: Day = today) -> Date {
    day.date(hour: hour, minute: minute, in: tz)!
}

struct NotificationPlannerTests {
    @Test func neverExceeds64() {
        let start = at(0, 0)
        for days in [1, 5, 6, 10, 30] {
            for limit in [10, 63, 64, 100, 1000] {
                let result = plan(now: start, days: days, limit: limit)
                #expect(result.count <= NotificationPlanner.systemLimit)
                #expect(result.count <= limit)
            }
        }
        #expect(plan(now: start, days: 30, limit: 1000).count == 64)
    }

    @Test func defaultWindowFitsWithTestSlot() {
        let result = plan(now: at(0, 0))
        #expect(result.count == NotificationPlanner.defaultLimit) // 5 days * 13 = 65 -> capped to 63
        #expect(result.count < NotificationPlanner.systemLimit)
    }

    @Test func fullDayHasThirteenEvents() {
        let result = plan(now: at(0, 0), days: 1)
        #expect(result.count == 13) // 5 warnings + 5 adhans + 2 Fajr-end + summary
        #expect(Set(result.map(\.id)).count == result.count)
    }

    @Test func onlyFutureAndSortedSoonestFirst() {
        let now = at(12, 0)
        let result = plan(now: now)
        #expect(result.allSatisfy { $0.fireDate > now })
        #expect(result.map(\.fireDate) == result.map(\.fireDate).sorted())
        #expect(result.first?.id == "2026-10-08_Dhuhr_exact")
        // Dhuhr warning (11:58) is already past.
        #expect(!result.contains { $0.id == "2026-10-08_Dhuhr_warning" })
    }

    @Test func identifiersAreStableAcrossRebuilds() {
        let a = plan(now: at(9, 0)).map(\.id)
        let b = plan(now: at(9, 0, on: today)).map(\.id)
        #expect(a == b)
        #expect(a.contains("2026-10-08_Asr_exact"))
        #expect(a.contains("2026-10-09_Sunrise_warning"))
        #expect(a.contains("2026-10-08_summary"))
    }

    @Test func fireTimesMatchTimingsAndOffset() {
        let result = plan(now: at(0, 0), days: 1)
        let byID = Dictionary(uniqueKeysWithValues: result.map { ($0.id, $0) })
        #expect(byID["2026-10-08_Asr_exact"]?.fireDate == at(16, 20))
        #expect(byID["2026-10-08_Asr_warning"]?.fireDate == at(16, 5))
        #expect(byID["2026-10-08_Sunrise_warning"]?.fireDate == at(6, 4))
        #expect(byID["2026-10-08_summary"]?.fireDate == at(21, 0))
        #expect(byID["2026-10-08_Asr_warning"]?.title == "Asr is approaching!")
        #expect(byID["2026-10-08_Asr_exact"]?.title == "It is time for Asr.")
        #expect(byID["2026-10-08_Sunrise_warning"]?.title == "Fajr ends in 15 minutes.")
    }

    @Test func completedPrayersGetNoAdhanAlert() {
        let result = plan(now: at(0, 0), days: 1, completed: ["2026-10-08_Fajr", "2026-10-08_Asr"])
        let ids = Set(result.map(\.id))
        #expect(!ids.contains("2026-10-08_Asr_exact"))
        #expect(!ids.contains("2026-10-08_Fajr_exact"))
        #expect(!ids.contains("2026-10-08_Sunrise_warning"))
        #expect(ids.contains("2026-10-08_Sunrise_exact"))
        #expect(ids.contains("2026-10-08_Dhuhr_exact"))
    }

    @Test func daysWithoutTimingsAreSkipped() {
        let result = NotificationPlanner.plan(now: at(0, 0), today: today, timeZone: tz, offsetMinutes: 15,
                                              timings: { $0 == today ? sample : nil },
                                              isCompleted: { _, _ in false })
        #expect(result.allSatisfy { $0.day == today })
    }

    @Test func summaryMentionsRecaps() {
        let thursday = NotificationPlanner.summaryBody(for: today)
        let sunday = NotificationPlanner.summaryBody(for: Day(year: 2026, month: 10, day: 11))
        let oct30 = NotificationPlanner.summaryBody(for: Day(year: 2026, month: 10, day: 30))
        let both = NotificationPlanner.summaryBody(for: Day(year: 2026, month: 5, day: 31)) // Sunday
        #expect(thursday == "Tap to see today's summary.")
        #expect(sunday.contains("weekly") && !sunday.contains("monthly"))
        #expect(oct30 == "Tap to see today's summary.")
        #expect(NotificationPlanner.summaryBody(for: Day(year: 2026, month: 10, day: 31)).contains("monthly"))
        #expect(both.contains("weekly and monthly"))
    }
}

struct AladhanParsingTests {
    @Test func parsesCalendarResponse() throws {
        let json = """
        {"code":200,"status":"OK","data":[
          {"timings":{"Fajr":"04:58 (+05)","Sunrise":"06:19 (+05)","Dhuhr":"12:13 (+05)","Asr":"16:20 (+05)",
                      "Sunset":"18:05 (+05)","Maghrib":"18:05 (+05)","Isha":"19:21 (+05)"},
           "date":{"gregorian":{"date":"01-10-2026"}},
           "meta":{"timezone":"Asia/Tashkent"}}
        ]}
        """
        let month = try AladhanClient.parse(Data(json.utf8))
        #expect(month.timezoneID == "Asia/Tashkent")
        #expect(month.days[Day(year: 2026, month: 10, day: 1)] == DayTimings(
            fajr: "04:58", sunrise: "06:19", dhuhr: "12:13", asr: "16:20", maghrib: "18:05", isha: "19:21"))
    }

    @Test func surfacesErrorMessage() {
        let json = #"{"code":400,"status":"BAD_REQUEST","data":"Unable to geocode address: X, Y"}"#
        #expect(throws: PrayerTimesError.self) { try AladhanClient.parse(Data(json.utf8)) }
    }

    @Test func buildsCalendarURLs() {
        let coords = AladhanClient.url(for: .coordinates(latitude: 41.3, longitude: 69.24), method: 14, school: 1,
                                       year: 2026, month: 10).absoluteString
        #expect(coords.hasPrefix("https://api.aladhan.com/v1/calendar/2026/10?"))
        #expect(coords.contains("method=14") && coords.contains("school=1") && coords.contains("latitude=41.3"))
        let city = AladhanClient.url(for: .city(name: "New York", country: "USA"), method: 2, school: 0,
                                     year: 2026, month: 11).absoluteString
        #expect(city.contains("/v1/calendarByCity/2026/11") && city.contains("city=New%20York"))
    }
}
