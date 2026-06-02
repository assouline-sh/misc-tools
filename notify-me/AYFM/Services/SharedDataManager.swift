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

                // The intent that wrote this pending reminder already scheduled its
                // notification, so only arm one if none exists (avoids resetting the timer).
                NotificationManager.shared.scheduleReminderIfNeeded(
                    id: item.id,
                    messageText: item.messageText,
                    senderName: item.senderName,
                    sourceApp: item.sourceApp,
                    intervalMinutes: item.notificationIntervalMinutes,
                    createdAt: item.createdAt
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

    /// Queue every active reminder to resume nagging when a finite pause ends, so the
    /// break self-lifts without the app having to be reopened. See `scheduleResume`.
    static func scheduleResume(context: ModelContext, at date: Date) {
        let predicate = #Predicate<ReminderItem> { !$0.isAnswered }
        let descriptor = FetchDescriptor(predicate: predicate)

        if let items = try? context.fetch(descriptor) {
            NotificationManager.shared.scheduleResume(items: items, at: date)
        }
    }
}
