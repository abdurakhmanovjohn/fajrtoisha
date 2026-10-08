import Charts
import SwiftData
import SwiftUI

struct StatsView: View {
    @Environment(AppModel.self) private var model
    @Query private var logs: [PrayerLog]

    var body: some View {
        @Bindable var model = model
        let records = logs.compactMap(\.record)
        let today = model.today()

        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Picker("Section", selection: $model.statsSection) {
                        ForEach(StatsSection.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    switch model.statsSection {
                    case .reports: ReportsSection(records: records, today: today)
                    case .overview: OverviewSection(overview: StatsEngine.overview(records, today: today))
                    case .profile: ProfileSection(profile: StatsEngine.profile(records, today: today))
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Stats")
        }
    }
}

// MARK: - Reports

private enum ReportPeriod: String, CaseIterable, Identifiable {
    case today = "Today"
    case week = "7 Days"
    case month = "30 Days"
    var id: String { rawValue }
}

private struct ReportsSection: View {
    let records: [LogRecord]
    let today: Day
    @State private var period: ReportPeriod = .today

    var body: some View {
        VStack(spacing: 16) {
            Picker("Period", selection: $period) {
                ForEach(ReportPeriod.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            switch period {
            case .today:
                DailyReportCard(report: StatsEngine.dailyReport(records, day: today))
                // End-of-day summary extras, as in send_summary_report.
                if today.weekdayIndex == 6 {
                    RangeReportCard(report: StatsEngine.weeklyReport(records, today: today))
                }
                if today.isLastDayOfMonth {
                    RangeReportCard(report: StatsEngine.thirtyDayReport(records, today: today,
                                                                        title: "Monthly Report (last 30 days)"))
                }
            case .week:
                RangeReportCard(report: StatsEngine.weeklyReport(records, today: today))
            case .month:
                RangeReportCard(report: StatsEngine.thirtyDayReport(records, today: today))
            }
        }
    }
}

struct StatsCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct DailyReportCard: View {
    let report: StatsEngine.DailyReport

    var body: some View {
        StatsCard {
            Text("Daily Report — \(report.day.key)").font(.headline)
            ForEach(Prayers.fard, id: \.self) { name in
                let done = report.completed.contains(name)
                Label(name, systemImage: done ? "checkmark.circle.fill" : "xmark.circle")
                    .foregroundStyle(done ? Color.green : Color.red)
            }
            Divider()
            Text("\(report.count)/5 prayers completed.\(report.isPerfect ? " 🎉" : "")")
                .font(.subheadline.bold())
        }
    }
}

private struct RangeReportCard: View {
    let report: StatsEngine.RangeReport

    var body: some View {
        StatsCard {
            VStack(alignment: .leading, spacing: 2) {
                Text(report.title).font(.headline)
                Text("\(report.effectiveStart.key) → \(report.end.key) "
                     + "(\(StatsEngine.plural(report.numDays, "day", "days")) tracked)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                metric("Total", "\(report.total)/\(report.possible)", "\(report.rate)%")
                metric("Perfect days", "\(report.perfectDays)/\(report.numDays)", nil)
            }

            Text("By prayer").font(.subheadline.bold())
            Chart(report.perPrayer, id: \.name) { item in
                BarMark(x: .value("Completed", item.count), y: .value("Prayer", item.name))
                    .foregroundStyle(Color.accentColor)
                    .annotation(position: .trailing) {
                        Text("\(item.count)/\(report.numDays)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
            }
            .chartXScale(domain: 0...max(1, report.numDays))
            .chartXAxis(.hidden)
            .frame(height: 170)
            .accessibilityLabel(report.perPrayer.map { "\($0.name) \($0.count) of \(report.numDays)" }
                .joined(separator: ", "))

            outcome
        }
    }

    @ViewBuilder
    private var outcome: some View {
        switch report.outcome {
        case .noPrayers:
            Text("No prayers logged in this period yet.").foregroundStyle(.secondary)
        case let .mostMissed(prayers, times):
            Label {
                Text("Most missed: **\(prayers.joined(separator: ", "))** "
                     + "(\(StatsEngine.plural(times, "time", "times")))")
            } icon: {
                Image(systemName: "lightbulb.fill").foregroundStyle(Color.gold)
            }
        case .perfect:
            Text("🎉 No missed prayers — perfect period!").font(.subheadline.bold())
        }
    }

    private func metric(_ title: String, _ value: String, _ extra: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(value).font(.title3.bold().monospacedDigit())
                if let extra {
                    Text(extra).font(.subheadline.monospacedDigit()).foregroundStyle(Color.accentColor)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Overview

enum OverviewPalette {
    static func color(for count: Int) -> Color {
        switch count {
        case 5: Color(red: 0.13, green: 0.65, blue: 0.33)
        case 4: Color(red: 0.96, green: 0.78, blue: 0.10)
        case 3: Color(red: 0.97, green: 0.55, blue: 0.13)
        case 2: Color(red: 0.89, green: 0.25, blue: 0.22)
        case 1: Color(red: 0.55, green: 0.36, blue: 0.24)
        default: Color(.systemGray4)
        }
    }

    static let outside = Color(.systemGray6)
}

private struct OverviewSection: View {
    let overview: StatsEngine.Overview
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)

    var body: some View {
        StatsCard {
            Text("Last 30 Days").font(.headline)
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"], id: \.self) {
                    Text($0).font(.caption2.bold()).foregroundStyle(.secondary)
                }
                ForEach(Array(overview.weeks.joined().enumerated()), id: \.offset) { _, cell in
                    OverviewCellView(cell: cell)
                }
            }
            legend
            Divider()
            LabeledContent("Perfect days", value: "\(overview.perfectDays)/\(overview.trackedDays)")
            LabeledContent("Completion", value: "\(overview.rate)%")
            LabeledContent("Current streak",
                           value: "🔥 \(StatsEngine.plural(overview.currentStreak, "day", "days"))")
        }
    }

    private var legend: some View {
        HStack(spacing: 10) {
            ForEach([5, 4, 3, 2, 1, 0], id: \.self) { n in
                HStack(spacing: 3) {
                    RoundedRectangle(cornerRadius: 3).fill(OverviewPalette.color(for: n)).frame(width: 12, height: 12)
                    Text("\(n)").font(.caption2)
                }
            }
            HStack(spacing: 3) {
                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(Color.secondary.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [2]))
                    .background(OverviewPalette.outside, in: RoundedRectangle(cornerRadius: 3))
                    .frame(width: 12, height: 12)
                Text("outside").font(.caption2)
            }
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
    }
}

private struct OverviewCellView: View {
    let cell: StatsEngine.OverviewCell

    var body: some View {
        switch cell {
        case let .tracked(day, count):
            RoundedRectangle(cornerRadius: 6)
                .fill(OverviewPalette.color(for: count))
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    Text("\(day.day)").font(.caption2.bold())
                        .foregroundStyle(count == 0 ? Color.secondary : Color.white)
                }
                .accessibilityElement()
                .accessibilityLabel("\(day.key): \(count) of 5")
        case let .outside(day):
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color.secondary.opacity(day == nil ? 0 : 0.35), style: StrokeStyle(lineWidth: 1, dash: [3]))
                .background(day == nil ? Color.clear : OverviewPalette.outside, in: RoundedRectangle(cornerRadius: 6))
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    if let day { Text("\(day.day)").font(.caption2).foregroundStyle(.tertiary) }
                }
                .accessibilityHidden(day == nil)
                .accessibilityLabel(day.map { "\($0.key): outside tracked range" } ?? "")
        }
    }
}

// MARK: - Profile

private struct ProfileSection: View {
    let profile: StatsEngine.Profile

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                tile("Current streak", StatsEngine.plural(profile.currentStreak, "day", "days"), "flame.fill", .gold)
                tile("Longest streak", StatsEngine.plural(profile.longestStreak, "day", "days"), "trophy.fill", .gold)
            }
            if profile.currentStreak == 0 {
                Text("Complete all 5 today to start one!")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                tile("Prayers today", "\(profile.todayCount)/5", "checkmark.circle.fill", .green)
                tile("Lifetime prayers", "\(profile.lifetimeTotal)", "infinity", .accentColor)
            }
            Text("Keep up the good work!")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
    }

    private func tile(_ title: String, _ value: String, _ icon: String, _ color: Color) -> some View {
        StatsCard {
            Image(systemName: icon).font(.title2).foregroundStyle(color)
            Text(value).font(.title2.bold().monospacedDigit())
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
    }
}
