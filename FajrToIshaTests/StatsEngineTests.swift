import Testing
@testable import FajrToIsha

private let today = Day(year: 2026, month: 10, day: 8) // a Thursday

private func d(_ offset: Int) -> Day { today.adding(days: offset) }

private func fard(_ day: Day, _ names: [String], completed: Bool = true) -> [LogRecord] {
    names.map { LogRecord(prayerName: $0, day: day, isCompleted: completed, category: .fard) }
}

private func perfect(_ day: Day) -> [LogRecord] { fard(day, Prayers.fard) }

struct StreakTests {
    @Test func emptyHasNoStreaks() {
        let result = StatsEngine.computeStreaks([], today: today)
        #expect(result.current == 0 && result.longest == 0)
    }

    @Test func gapsSplitRuns() {
        // -9 -8 -7 (run of 3), gap at -6, then -5 -4 (run of 2), gap, then -1 0.
        let days = [d(-9), d(-8), d(-7), d(-5), d(-4), d(-1), d(0)]
        let result = StatsEngine.computeStreaks(days, today: today)
        #expect(result.current == 2)
        #expect(result.longest == 3)
    }

    @Test func unfinishedTodayDoesNotBreakStreak() {
        let result = StatsEngine.computeStreaks([d(-3), d(-2), d(-1)], today: today)
        #expect(result.current == 3)
        #expect(result.longest == 3)
    }

    @Test func missingYesterdayBreaksStreak() {
        let result = StatsEngine.computeStreaks([d(-4), d(-3), d(-2)], today: today)
        #expect(result.current == 0)
        #expect(result.longest == 3)
    }

    @Test func duplicatesAndOrderDoNotMatter() {
        let result = StatsEngine.computeStreaks([d(0), d(-1), d(-1), d(-2)], today: today)
        #expect(result.current == 3)
        #expect(result.longest == 3)
    }

    @Test func streakCrossesMonthBoundary() {
        let start = Day(year: 2026, month: 2, day: 27)
        let days = (0..<4).map { start.adding(days: $0) } // Feb 27 – Mar 2
        #expect(days.last == Day(year: 2026, month: 3, day: 2))
        #expect(StatsEngine.computeStreaks(days, today: days.last!).current == 4)
    }

    @Test func profileUsesOnlyFullDaysAndIgnoresNafl() {
        let logs = perfect(d(-2)) + perfect(d(-1)) + fard(d(0), ["Fajr", "Dhuhr"])
            + [LogRecord(prayerName: "Duha", day: d(0), isCompleted: true, category: .nafl)]
            + fard(d(0), ["Asr"], completed: false)
        let profile = StatsEngine.profile(logs, today: today)
        #expect(profile.currentStreak == 2)
        #expect(profile.longestStreak == 2)
        #expect(profile.todayCount == 2)
        #expect(profile.lifetimeTotal == 12)
    }
}

struct RangeReportTests {
    @Test func noLogsCoversOneDay() {
        let report = StatsEngine.weeklyReport([], today: today)
        #expect(report.effectiveStart == today)
        #expect(report.numDays == 1)
        #expect(report.possible == 5)
        #expect(report.rate == 0)
        #expect(report.outcome == .noPrayers)
    }

    @Test func rangeStartingBeforeFirstLogIsScaled() {
        // Tracking started 2 days ago; a 7-day report only counts 3 days.
        let logs = perfect(d(-2)) + fard(d(-1), ["Fajr", "Dhuhr", "Asr"]) + fard(d(0), ["Fajr"])
        let report = StatsEngine.weeklyReport(logs, today: today)
        #expect(report.effectiveStart == d(-2))
        #expect(report.numDays == 3)
        #expect(report.total == 9)
        #expect(report.possible == 15)
        #expect(report.rate == 60)
        #expect(report.perfectDays == 1)
        #expect(report.perPrayer.map(\.count) == [3, 2, 2, 1, 1])
        #expect(report.outcome == .mostMissed(prayers: ["Maghrib", "Isha"], times: 2))
    }

    @Test func firstLogDateCountsUncompletedRows() {
        // Like the bot's MIN(prayer_date): an unmarked row still starts tracking.
        let logs = fard(d(-4), ["Fajr"], completed: false) + perfect(d(0))
        let report = StatsEngine.weeklyReport(logs, today: today)
        #expect(report.effectiveStart == d(-4))
        #expect(report.numDays == 5)
    }

    @Test func naflDoesNotStartTracking() {
        let logs = [LogRecord(prayerName: "Duha", day: d(-5), isCompleted: true, category: .nafl)] + perfect(d(0))
        let report = StatsEngine.weeklyReport(logs, today: today)
        #expect(report.effectiveStart == today)
        #expect(report.outcome == .perfect)
    }

    @Test func oldLogsClampToRangeStart() {
        let logs = perfect(d(-60)) + perfect(d(0))
        let report = StatsEngine.thirtyDayReport(logs, today: today)
        #expect(report.effectiveStart == d(-29))
        #expect(report.numDays == 30)
        #expect(report.total == 5)
        #expect(report.perfectDays == 1)
    }

    @Test func mostMissedTiesAreAllListedInPrayerOrder() {
        let logs = fard(d(-1), ["Dhuhr", "Asr", "Maghrib"]) + fard(d(0), ["Dhuhr", "Asr", "Maghrib"])
        let report = StatsEngine.rangeReport(logs, start: d(-1), end: today, title: "T")
        #expect(report.outcome == .mostMissed(prayers: ["Fajr", "Isha"], times: 2))
    }

    @Test func singleMissIsReported() {
        let logs = perfect(d(-1)) + fard(d(0), ["Fajr", "Dhuhr", "Asr", "Maghrib"])
        let report = StatsEngine.rangeReport(logs, start: d(-1), end: today, title: "T")
        #expect(report.outcome == .mostMissed(prayers: ["Isha"], times: 1))
        #expect(report.rate == 90)
    }

    @Test func perfectPeriod() {
        let report = StatsEngine.weeklyReport(perfect(d(-1)) + perfect(d(0)), today: today)
        #expect(report.outcome == .perfect)
        #expect(report.rate == 100)
        #expect(report.perfectDays == 2)
    }

    @Test func rateRoundsHalfToEvenLikePython() {
        // 1 / 40 = 2.5% -> Python round() gives 2.
        let logs = fard(d(-7), ["Fajr"]) + fard(d(0), ["Fajr"], completed: false)
        let report = StatsEngine.rangeReport(logs, start: d(-7), end: today, title: "T")
        #expect(report.possible == 40)
        #expect(report.rate == 2)
        #expect(StatsEngine.pyRound(3.5) == 4)
    }

    @Test func dailyReportCountsOnlyCompletedFard() {
        let logs = fard(d(0), ["Fajr", "Asr"]) + fard(d(0), ["Isha"], completed: false) + perfect(d(-1))
        let report = StatsEngine.dailyReport(logs, day: today)
        #expect(report.completed == ["Fajr", "Asr"])
        #expect(!report.isPerfect)
    }
}

struct OverviewTests {
    @Test func gridIsMondayAlignedAndPadded() {
        let overview = StatsEngine.overview(perfect(d(0)), today: today)
        let first = overview.weeks.first!.first!
        guard case let .outside(day?) = first else { Issue.record("expected outside day"); return }
        #expect(day.weekdayIndex == 0)
        #expect(overview.weeks.allSatisfy { $0.count == 7 })
        // Today (Thursday) is followed by Fri/Sat/Sun padding.
        let last = overview.weeks.last!
        #expect(last[3] == .tracked(today, count: 5))
        #expect(last[4] == .outside(nil) && last[6] == .outside(nil))
    }

    @Test func daysBeforeTrackingAreOutsideNotMisses() {
        let logs = fard(d(-3), ["Fajr"]) + perfect(d(-1)) + perfect(d(0))
        let overview = StatsEngine.overview(logs, today: today)
        let cells = overview.weeks.joined()
        let tracked = cells.filter { if case .tracked = $0 { return true } else { return false } }
        #expect(tracked.count == 4)
        #expect(cells.contains(.tracked(d(-2), count: 0)))
        #expect(cells.contains(.outside(d(-4))))
        #expect(overview.trackedDays == 4)
        #expect(overview.perfectDays == 2)
        #expect(overview.rate == 55) // 11 / 20
        #expect(overview.currentStreak == 2)
    }

    @Test func noLogsTracksOnlyToday() {
        let overview = StatsEngine.overview([], today: today)
        #expect(overview.trackedDays == 1)
        #expect(overview.rate == 0)
        #expect(overview.weeks.joined().contains(.tracked(today, count: 0)))
    }
}

struct DayTests {
    @Test func keyRoundTrip() {
        #expect(Day(key: "2026-10-08") == today)
        #expect(today.key == "2026-10-08")
        #expect(Day(key: "2026-02-31") == nil)
        #expect(Day(key: "garbage") == nil)
    }

    @Test func weekdayMatchesPython() {
        #expect(today.weekdayIndex == 3)                              // Thursday
        #expect(Day(year: 2026, month: 10, day: 11).weekdayIndex == 6) // Sunday
    }

    @Test func lastDayOfMonth() {
        #expect(Day(year: 2026, month: 10, day: 31).isLastDayOfMonth)
        #expect(Day(year: 2028, month: 2, day: 29).isLastDayOfMonth)
        #expect(!today.isLastDayOfMonth)
    }

    @Test func stripsAladhanSuffix() {
        #expect(TimeOfDay.clean("04:58 (+05)") == "04:58")
        #expect(TimeOfDay.clean("19:21") == "19:21")
        #expect(TimeOfDay.clean("bad") == nil)
    }
}
