import Foundation
import SwiftData

struct SharedDataManager {
    static func importPendingReminders(context: ModelContext) {
        let pending = PendingReminder.loadAll()

        for reminder in pending {
            let id = reminder.id
            let predicate = #Predicate<ReminderItem> { $0.id == id }
            let descriptor = FetchDescriptor(predicate: predicate)

            let exists = (try? context.fetchCount(descriptor)) ?? 0 > 0
            if !exists {
                let item = ReminderItem(from: reminder)
                context.insert(item)

                NotificationManager.shared.scheduleReminder(
                    id: item.id,
                    messageText: item.messageText,
                    senderName: item.senderName,
                    intervalMinutes: item.notificationIntervalMinutes
                )
            }

            PendingReminder.delete(id: reminder.id)
        }

        try? context.save()
    }

    static func rescheduleAll(context: ModelContext) {
        let predicate = #Predicate<ReminderItem> { !$0.isAnswered }
        let descriptor = FetchDescriptor(predicate: predicate)

        if let items = try? context.fetch(descriptor) {
            NotificationManager.shared.rescheduleAllActive(items: items)
        }
    }
}
