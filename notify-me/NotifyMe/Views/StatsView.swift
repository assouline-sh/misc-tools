import SwiftUI
import SwiftData
import Charts

struct StatsView: View {
    @Query(sort: \ReminderItem.createdAt, order: .reverse)
    private var all: [ReminderItem]

    private let calendar = Calendar.current

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    streak
                    numbers
                    repliesChart
                    responseTimeChart
                }
                .padding()
            }
            .navigationTitle("stats")
            .screen()
        }
    }

    // MARK: - Streak

    private var streak: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("streak")
                .font(.caption)
                .foregroundStyle(Theme.dim)
            Text("\(streakDays)d")
                .font(.system(size: 44, weight: .bold, design: .monospaced))
                .foregroundStyle(streakDays > 0 ? Theme.accent : Theme.dim)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .panel()
    }

    // MARK: - Numbers

    private var numbers: some View {
        VStack(spacing: 0) {
            statLine("replied", "\(answered.count)")
            divider
            statLine("avg reply time", avgResponseLabel)
            divider
            statLine("beat the nag", beatNagLabel)
            divider
            statLine("bothered you", "\(totalNags)×")
            divider
            statLine("open now", "\(pending.count)")
        }
        .padding(.vertical, 4)
        .panel()
    }

    private func statLine(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(Theme.dim)
            Spacer()
            Text(value).foregroundStyle(Theme.text)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    private var divider: some View {
        Rectangle().fill(Theme.border).frame(height: 1).padding(.horizontal)
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
        chartSection("avg reply time / day (min)") {
            Chart(last7Days) { day in
                if let minutes = day.avgResponseMinutes {
                    LineMark(
                        x: .value("day", day.date, unit: .day),
                        y: .value("min", minutes)
                    )
                    .foregroundStyle(Theme.warn)
                    PointMark(
                        x: .value("day", day.date, unit: .day),
                        y: .value("min", minutes)
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

    /// Total nags fired across every reminder (until answered, or until now if still open).
    private var totalNags: Int {
        all.reduce(0) { sum, item in
            let end = item.answeredAt ?? Date()
            let elapsed = end.timeIntervalSince(item.createdAt)
            let interval = TimeInterval(item.notificationIntervalMinutes * 60)
            return sum + (interval > 0 ? max(0, Int(elapsed / interval)) : 0)
        }
    }

    private var responseTimes: [TimeInterval] {
        answered.compactMap { item in
            guard let answeredAt = item.answeredAt else { return nil }
            return answeredAt.timeIntervalSince(item.createdAt)
        }
    }

    private var avgResponseLabel: String {
        guard !responseTimes.isEmpty else { return "—" }
        let avg = responseTimes.reduce(0, +) / Double(responseTimes.count)
        return Self.durationLabel(avg)
    }

    private var beatNagLabel: String {
        guard !answered.isEmpty else { return "—" }
        let beat = answered.filter { item in
            guard let answeredAt = item.answeredAt else { return false }
            let elapsed = answeredAt.timeIntervalSince(item.createdAt)
            return elapsed < TimeInterval(item.notificationIntervalMinutes * 60)
        }.count
        return "\(Int((Double(beat) / Double(answered.count)) * 100))%"
    }

    /// Consecutive days, back through your active period, with nothing left unanswered.
    /// Today never breaks it; quiet days don't either.
    private var streakDays: Int {
        guard let earliest = all.map(\.createdAt).min() else { return 0 }
        let startDay = calendar.startOfDay(for: earliest)
        var day = calendar.startOfDay(for: Date())
        var count = 0

        while day >= startDay {
            let isToday = calendar.isDateInToday(day)
            let droppedBall = all.contains {
                calendar.isDate($0.createdAt, inSameDayAs: day) && !$0.isAnswered
            }
            if droppedBall && !isToday { break }
            count += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = prev
        }
        return count
    }

    private struct DayStat: Identifiable {
        let date: Date
        let replyCount: Int
        let avgResponseMinutes: Double?
        var id: Date { date }
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
            let avgMinutes = times.isEmpty ? nil : (times.reduce(0, +) / Double(times.count)) / 60
            return DayStat(date: day, replyCount: dayReplies.count, avgResponseMinutes: avgMinutes)
        }
    }

    private static func durationLabel(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let days = total / 86_400
        let hours = (total % 86_400) / 3_600
        let minutes = (total % 3_600) / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)m" }
        return "<1m"
    }
}
