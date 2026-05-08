import SwiftUI
import SwiftData

struct ReminderListView: View {
    @Query(
        filter: #Predicate<ReminderItem> { !$0.isAnswered },
        sort: \ReminderItem.createdAt,
        order: .reverse
    )
    private var reminders: [ReminderItem]

    @Environment(\.modelContext) private var context

    var body: some View {
        NavigationStack {
            Group {
                if reminders.isEmpty {
                    ContentUnavailableView(
                        "No Pending Reminders",
                        systemImage: "bell.slash",
                        description: Text("Share a message from any app to get started.")
                    )
                } else {
                    List {
                        ForEach(reminders) { item in
                            ReminderRow(item: item)
                                .swipeActions(edge: .trailing) {
                                    Button("Answered") {
                                        markAnswered(item)
                                    }
                                    .tint(.green)
                                }
                        }
                        .onDelete(perform: deleteItems)
                    }
                }
            }
            .navigationTitle("Pending")
        }
    }

    private func markAnswered(_ item: ReminderItem) {
        item.isAnswered = true
        item.answeredAt = Date()
        NotificationManager.shared.cancelReminder(id: item.id)
        try? context.save()
    }

    private func deleteItems(at offsets: IndexSet) {
        for index in offsets {
            let item = reminders[index]
            NotificationManager.shared.cancelReminder(id: item.id)
            context.delete(item)
        }
        try? context.save()
    }
}
