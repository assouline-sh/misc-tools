import Foundation
import UserNotifications
import SwiftData
import UIKit

final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    private override init() {
        super.init()
    }

    func setup() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self

        let markAnswered = UNNotificationAction(
            identifier: AppConstants.markAnsweredActionID,
            title: "Mark as Answered",
            options: .destructive
        )
        let snooze = UNNotificationAction(
            identifier: AppConstants.snoozeActionID,
            title: "Snooze 1 Hour",
            options: []
        )
        let category = UNNotificationCategory(
            identifier: AppConstants.notificationCategoryID,
            actions: [markAnswered, snooze],
            intentIdentifiers: []
        )
        center.setNotificationCategories([category])
    }

    func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus
    }

    // MARK: - Scheduling

    func scheduleReminder(id: UUID, messageText: String, senderName: String?, sourceApp: String?, intervalMinutes: Int, createdAt: Date) {
        let content = UNMutableNotificationContent()
        let text = ReminderNotification.text(senderName: senderName, sourceApp: sourceApp, messageText: messageText, createdAt: createdAt)
        content.title = text.title
        if let subtitle = text.subtitle { content.subtitle = String(subtitle.prefix(150)) }
        if let body = text.body { content.body = String(body.prefix(150)) }
        content.sound = .default
        content.categoryIdentifier = AppConstants.notificationCategoryID
        content.userInfo = ["reminderId": id.uuidString, "sourceApp": sourceApp ?? ""]

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: TimeInterval(intervalMinutes * 60),
            repeats: true
        )

        let request = UNNotificationRequest(
            identifier: "reminder-\(id.uuidString)",
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request)
    }

    func cancelReminder(id: UUID) {
        let identifier = "reminder-\(id.uuidString)"
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }

    func rescheduleAllActive(items: [ReminderItem]) {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()

        for item in items where !item.isAnswered {
            scheduleReminder(
                id: item.id,
                messageText: item.messageText,
                senderName: item.senderName,
                sourceApp: item.sourceApp,
                intervalMinutes: item.notificationIntervalMinutes,
                createdAt: item.createdAt
            )
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard let reminderIdString = response.notification.request.content.userInfo["reminderId"] as? String,
              let reminderId = UUID(uuidString: reminderIdString) else { return }

        switch response.actionIdentifier {
        case AppConstants.markAnsweredActionID:
            cancelReminder(id: reminderId)
            await markAsAnswered(id: reminderId)

        case AppConstants.snoozeActionID:
            cancelReminder(id: reminderId)
            // Reschedule with a 1-hour delay
            let content = response.notification.request.content
            let snoozeContent = UNMutableNotificationContent()
            snoozeContent.title = content.title
            snoozeContent.subtitle = content.subtitle
            snoozeContent.body = content.body
            snoozeContent.sound = content.sound
            snoozeContent.categoryIdentifier = content.categoryIdentifier
            snoozeContent.userInfo = content.userInfo

            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 3600, repeats: false)
            let request = UNNotificationRequest(
                identifier: "snooze-\(reminderId.uuidString)",
                content: snoozeContent,
                trigger: trigger
            )
            try? await UNUserNotificationCenter.current().add(request)

        default:
            // Tapping the notification opens the source app so you can reply right away.
            let sourceApp = response.notification.request.content.userInfo["sourceApp"] as? String
            if let url = AppLinks.url(for: sourceApp) {
                await UIApplication.shared.open(url)
            }
            NotificationCenter.default.post(
                name: .reminderTapped,
                object: nil,
                userInfo: ["reminderId": reminderId]
            )
        }
    }

    @MainActor
    private func markAsAnswered(id: UUID) async {
        guard let container = try? ModelContainer(
            for: ReminderItem.self,
            configurations: ModelConfiguration(
                url: AppConstants.sharedContainerURL.appendingPathComponent("AYFM.store")
            )
        ) else { return }

        let context = container.mainContext
        let predicate = #Predicate<ReminderItem> { $0.id == id }
        let descriptor = FetchDescriptor(predicate: predicate)

        if let item = try? context.fetch(descriptor).first {
            item.isAnswered = true
            item.answeredAt = Date()
            try? context.save()
        }
    }
}

extension Notification.Name {
    static let reminderTapped = Notification.Name("reminderTapped")
}
