import SwiftUI
import SwiftData
import Charts

struct StatsView: View {
    @Query(sort: \ReminderItem.createdAt, order: .reverse)
    private var all: [ReminderItem]

    private let calendar = Calendar.current

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScreenTitle("stats for nerds", accent: "stats")
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    topBoxes
                    repliesChart
                    responseTimeChart
                    botheredBox
                }
                .padding()
            }
            .scrollContentBackground(.hidden)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.background.ignoresSafeArea())
    }

    // MARK: - Top boxes

    private var topBoxes: some View {
        HStack(spacing: 12) {
            statBox("open", "\(pending.count)",
                    color: Theme.dim, width: 64)
            statBox("done today", "\(repliedToday)",
                    color: repliedToday > 0 ? Theme.accent : Theme.dim, width: 74)
            statBox("done this week", "\(repliedThisWeek)",
                    color: repliedThisWeek > 0 ? Theme.accent : Theme.dim)
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

    private var botheredBox: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("asked you to please answer your f****** messages")
                .font(.caption)
                .foregroundStyle(Theme.dim)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text("\(totalNags)")
                .font(.system(size: 44, weight: .bold, design: .monospaced))
                .foregroundStyle(totalNags > 0 ? Theme.warn : Theme.dim)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .panel()
    }

    // MARK: - Charts

    private var repliesChart: some View {
        chartSection("replies / day") {
            Chart(last7Days) { day in
                BarMark(
                    x: .value("day", day.date, unit: .day),
                    y: .value("replies", day.replyCount)
                )
                .foregroundStyle(Theme.accent)
            }
        }
    }

    private var responseTimeChart: some View {
        chartSection("avg reply time / day (hours)") {
            Chart(last7Days) { day in
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
        @ViewBuilder _ chart: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption)
                .foregroundStyle(Theme.dim)
            chart()
                .chartXScale(domain: weekDomain)
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

    private var answered: [ReminderItem] {
        all.filter { $0.isAnswered && $0.answeredAt != nil }
    }

    private var pending: [ReminderItem] {
        all.filter { !$0.isAnswered }
    }

    private var repliedToday: Int {
        let today = calendar.startOfDay(for: Date())
        return answered.filter {
            guard let answeredAt = $0.answeredAt else { return false }
            return calendar.isDate(answeredAt, inSameDayAs: today)
        }.count
    }

    private var repliedThisWeek: Int {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: Date()) else { return 0 }
        return answered.filter {
            guard let answeredAt = $0.answeredAt else { return false }
            return week.contains(answeredAt)
        }.count
    }

    /// Total reminders fired across every message (until answered, or until now if open).
    private var totalNags: Int {
        all.reduce(0) { sum, item in
            let end = item.answeredAt ?? Date()
            let elapsed = end.timeIntervalSince(item.createdAt)
            let interval = TimeInterval(item.notificationIntervalMinutes * 60)
            return sum + (interval > 0 ? max(0, Int(elapsed / interval)) : 0)
        }
    }

    private struct DayStat: Identifiable {
        let date: Date
        let replyCount: Int
        let avgResponseHours: Double?
        var id: Date { date }
    }

    /// Fixed 7-day X range [oldest day 00:00 ... tomorrow 00:00) so both charts always
    /// show all weekday labels, even on days with no data point.
    private var weekDomain: ClosedRange<Date> {
        let days = last7Days.map(\.date)
        let start = days.first ?? calendar.startOfDay(for: Date())
        let last = days.last ?? start
        let end = calendar.date(byAdding: .day, value: 1, to: last) ?? last
        return start...end
    }

    private var last7Days: [DayStat] {
        let today = calendar.startOfDay(for: Date())
        return (0..<7).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let dayReplies = answered.filter {
                guard let answeredAt = $0.answeredAt else { return false }
                return calendar.isDate(answeredAt, inSameDayAs: day)
            }
            let times = dayReplies.compactMap { item -> TimeInterval? in
                guard let answeredAt = item.answeredAt else { return nil }
                return answeredAt.timeIntervalSince(item.createdAt)
            }
            let avgHours = times.isEmpty ? nil : (times.reduce(0, +) / Double(times.count)) / 3_600
            return DayStat(date: day, replyCount: dayReplies.count, avgResponseHours: avgHours)
        }
    }
}
