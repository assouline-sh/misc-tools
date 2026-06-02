import SwiftUI
import SwiftData
import Charts

struct StatsView: View {
    @Query(sort: \ReminderItem.createdAt, order: .reverse)
    private var all: [ReminderItem]

    private let calendar = Calendar.current

    var body: some View {
        // Compute every derived figure in a single pass so the subviews below don't each
        // re-filter/re-reduce the whole reminder list on every render.
        let stats = makeStats()
        VStack(alignment: .leading, spacing: 0) {
            ScreenTitle("stats for nerds", accent: "stats")
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    topBoxes(stats)
                    repliesChart(stats)
                    responseTimeChart(stats)
                    botheredBox(stats)
                }
                .padding()
            }
            .scrollContentBackground(.hidden)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.background.ignoresSafeArea())
    }

    // MARK: - Top boxes

    private func topBoxes(_ stats: Stats) -> some View {
        HStack(spacing: 12) {
            statBox("open", "\(stats.openCount)",
                    color: Theme.dim, width: 64)
            statBox("done today", "\(stats.repliedToday)",
                    color: stats.repliedToday > 0 ? Theme.accent : Theme.dim, width: 74)
            statBox("done this week", "\(stats.repliedThisWeek)",
                    color: stats.repliedThisWeek > 0 ? Theme.accent : Theme.dim)
        }
    }

    private func statBox(_ label: String, _ value: String, color: Color, width: CGFloat? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.dim)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(value)
                .font(.system(size: 44, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(width: width, alignment: .leading)
        .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
        .padding()
        .panel()
    }

    private func botheredBox(_ stats: Stats) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("asked you to please answer your f****** messages")
                .font(.caption)
                .foregroundStyle(Theme.dim)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text("\(stats.totalNags)")
                .font(.system(size: 44, weight: .bold, design: .monospaced))
                .foregroundStyle(stats.totalNags > 0 ? Theme.warn : Theme.dim)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .panel()
    }

    // MARK: - Charts

    private func repliesChart(_ stats: Stats) -> some View {
        chartSection("replies / day", domain: stats.weekDomain) {
            Chart(stats.days) { day in
                BarMark(
                    x: .value("day", day.date, unit: .day),
                    y: .value("replies", day.replyCount)
                )
                .foregroundStyle(Theme.accent)
            }
        }
    }

    private func responseTimeChart(_ stats: Stats) -> some View {
        chartSection("avg reply time / day (hours)", domain: stats.weekDomain) {
            Chart(stats.days) { day in
                if let hours = day.avgResponseHours {
                    LineMark(
                        x: .value("day", day.date, unit: .day),
                        y: .value("hr", hours)
                    )
                    .foregroundStyle(Theme.warn)
                    PointMark(
                        x: .value("day", day.date, unit: .day),
                        y: .value("hr", hours)
                    )
                    .foregroundStyle(Theme.warn)
                }
            }
        }
    }

    private func chartSection<Content: View>(
        _ title: String,
        domain: ClosedRange<Date>,
        @ViewBuilder _ chart: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption)
                .foregroundStyle(Theme.dim)
            chart()
                .chartXScale(domain: domain)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day)) { _ in
                        AxisValueLabel(format: .dateTime.weekday(.narrow))
                            .foregroundStyle(Theme.dim)
                    }
                }
                .chartYAxis {
                    AxisMarks { _ in
                        AxisValueLabel().foregroundStyle(Theme.dim)
                    }
                }
                .frame(height: 140)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .panel()
    }

    // MARK: - Derived data

    private struct DayStat: Identifiable {
        let date: Date
        let replyCount: Int
        let avgResponseHours: Double?
        var id: Date { date }
    }

    /// Everything the view shows, derived from `all` in one pass.
    private struct Stats {
        let openCount: Int
        let repliedToday: Int
        let repliedThisWeek: Int
        let totalNags: Int
        let days: [DayStat]
        /// Fixed 7-day X range [oldest day 00:00 ... tomorrow 00:00) so both charts always
        /// show all weekday labels, even on days with no data point.
        let weekDomain: ClosedRange<Date>
    }

    /// Single computation of all stats. "done today"/"done this week" are taken from the
    /// same rolling 7-day buckets the charts use, so the boxes and bars can't disagree.
    private func makeStats() -> Stats {
        let now = Date()
        let today = calendar.startOfDay(for: now)

        var openCount = 0
        var answered: [ReminderItem] = []
        var totalNags = 0

        for item in all {
            if item.isAnswered {
                if item.answeredAt != nil { answered.append(item) }
            } else {
                openCount += 1
            }
            // Nag count, excluding any time spent under a global "pause all".
            let end = item.answeredAt ?? now
            let paused = SnoozeStore.pausedSeconds(from: item.createdAt, to: end)
            let elapsed = end.timeIntervalSince(item.createdAt) - paused
            let interval = TimeInterval(item.notificationIntervalMinutes * 60)
            if interval > 0 { totalNags += max(0, Int(elapsed / interval)) }
        }

        var days: [DayStat] = []
        for offset in (0..<7).reversed() {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            let dayReplies = answered.filter { item in
                guard let answeredAt = item.answeredAt else { return false }
                return calendar.isDate(answeredAt, inSameDayAs: day)
            }
            let times = dayReplies.compactMap { item -> TimeInterval? in
                guard let answeredAt = item.answeredAt else { return nil }
                return answeredAt.timeIntervalSince(item.createdAt)
            }
            let avgHours = times.isEmpty ? nil : (times.reduce(0, +) / Double(times.count)) / 3_600
            days.append(DayStat(date: day, replyCount: dayReplies.count, avgResponseHours: avgHours))
        }

        let start = days.first?.date ?? today
        let lastDay = days.last?.date ?? start
        let domainEnd = calendar.date(byAdding: .day, value: 1, to: lastDay) ?? lastDay

        return Stats(
            openCount: openCount,
            repliedToday: days.last?.replyCount ?? 0,
            repliedThisWeek: days.reduce(0) { $0 + $1.replyCount },
            totalNags: totalNags,
            days: days,
            weekDomain: start...domainEnd
        )
    }
}
