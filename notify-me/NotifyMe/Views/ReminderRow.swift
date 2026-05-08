import SwiftUI

struct ReminderRow: View {
    let item: ReminderItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                if let sender = item.senderName, !sender.isEmpty {
                    Text(sender)
                        .font(.headline)
                }
                Text(item.messageText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(item.createdAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Text("Every \(intervalLabel)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }

    private var intervalLabel: String {
        let mins = item.notificationIntervalMinutes
        if mins < 60 {
            return "\(mins)m"
        } else if mins % 60 == 0 {
            let hours = mins / 60
            return hours == 1 ? "1hr" : "\(hours)hrs"
        } else {
            return "\(mins)m"
        }
    }
}
