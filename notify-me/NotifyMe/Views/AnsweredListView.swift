import SwiftUI
import SwiftData

struct AnsweredListView: View {
    @Query(
        filter: #Predicate<ReminderItem> { $0.isAnswered },
        sort: \ReminderItem.answeredAt,
        order: .reverse
    )
    private var reminders: [ReminderItem]

    @Environment(\.modelContext) private var context

    var body: some View {
        NavigationStack {
            Group {
                if reminders.isEmpty {
                    ContentUnavailableView(
                        "No Answered Messages",
                        systemImage: "checkmark.circle",
                        description: Text("Messages you mark as answered will appear here.")
                    )
                } else {
                    List {
                        ForEach(reminders) { item in
                            VStack(alignment: .leading, spacing: 4) {
                                if let sender = item.senderName, !sender.isEmpty {
                                    Text(sender)
                                        .font(.headline)
                                }
                                Text(item.messageText)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                if let answered = item.answeredAt {
                                    Text("Answered \(answered, style: .relative) ago")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .onDelete(perform: deleteItems)
                    }
                }
            }
            .navigationTitle("Answered")
        }
    }

    private func deleteItems(at offsets: IndexSet) {
        for index in offsets {
            context.delete(reminders[index])
        }
        try? context.save()
    }
}
