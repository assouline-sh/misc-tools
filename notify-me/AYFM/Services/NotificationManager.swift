import Foundation
import UserNotifications
import SwiftData
import UIKit

final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    /// The app's live SwiftData container, set at launch. Notification actions write through
    /// this so changes (e.g. marking answered) appear immediately in the running app's
    /// `@Query` views, instead of through a separate container the UI never observes.
    var modelContainer: ModelContainer?

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

    // MARK: - Global snooze

    /// The instant until which every reminder is paused, or nil when not snoozing.
    /// Backed by `SnoozeStore` so the app, widget, and intents all read the same value.
    /// `.distantFuture` represents an indefinite snooze.
    var snoozeUntil: Date? { SnoozeStore.snoozeUntil }

    var isSnoozed: Bool { SnoozeStore.isSnoozed }

    /// Pause every reminder until `date` (pass `.distantFuture` for indefinitely), or pass
    /// nil to lift the snooze. Pausing immediately clears all pending notifications; lifting
    /// reschedules nothing here — the caller reschedules the active reminders.
    func setGlobalSnooze(until date: Date?) {
        let defaults = AppConstants.sharedDefaults
        let wasSnoozed = SnoozeStore.isSnoozed   // capture prior state before mutating
        if let date {
            defaults.set(date.timeIntervalSince1970, forKey: AppConstants.globalSnoozeUntilKey)
            UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
            // Log the pause window so the nag counter can exclude this paused time.
            SnoozeStore.beginPause(until: date, wasPaused: wasSnoozed)
        } else {
            defaults.removeObject(forKey: AppConstants.globalSnoozeUntilKey)
            if wasSnoozed { SnoozeStore.endPause(at: Date()) }
        }
    }

    /// For a *finite* pause, re-arm each active reminder so it stays silent for the whole
    /// pause and then resumes its repeating cadence on its own — no app reopen required.
    /// Each reminder gets a repeating notification whose first fire is no earlier than the
    /// pause's end (we use the longer of its interval and the time remaining), under the live
    /// `reminder-<id>` identifier so opening the app later cleanly replaces it. Indefinite
    /// pauses pass `date == .distantFuture` and are skipped — there's nothing to resume to.
    func scheduleResume(items: [ReminderItem], at date: Date) {
        let pauseRemaining = date.timeIntervalSinceNow
        guard pauseRemaining > 0, date < .distantFuture else { return }

        let center = UNUserNotificationCenter.current()
        for item in items where !item.isAnswered {
            let interval = TimeInterval(item.notificationIntervalMinutes * 60)
            guard interval > 0 else { continue }
            // Hold the first fire until the pause ends, then repeat. When the interval is
            // longer than the remaining pause, its own schedule already clears the pause.
            let firstInterval = max(interval, pauseRemaining)

            let text = ReminderNotification.text(
                senderName: item.senderName,
                sourceApp: item.sourceApp,
                messageText: item.messageText,
                createdAt: item.createdAt
            )
            let content = UNMutableNotificationContent()
            content.title = text.title
            if let subtitle = text.subtitle { content.subtitle = String(subtitle.prefix(150)) }
            if let body = text.body { content.body = String(body.prefix(150)) }
            content.sound = .default
            content.categoryIdentifier = AppConstants.notificationCategoryID
            content.userInfo = ["reminderId": item.id.uuidString, "sourceApp": item.sourceApp ?? ""]
            content.threadIdentifier = ReminderNotification.threadIdentifier(sourceApp: item.sourceApp)
            content.interruptionLevel = StrengthStore.ignoresDoNotDisturb(for: item.sourceApp) ? .timeSensitive : .active

            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: firstInterval, repeats: true)
            let request = UNNotificationRequest(
                identifier: "reminder-\(item.id.uuidString)",
                content: content,
                trigger: trigger
            )
            center.add(request)
        }
    }

    // MARK: - Scheduling

    func scheduleReminder(id: UUID, messageText: String, senderName: String?, sourceApp: String?, intervalMinutes: Int, createdAt: Date) {
        // Honour a global snooze — no new notifications fire while paused.
        guard !isSnoozed else { return }

        let content = UNMutableNotificationContent()
        let text = ReminderNotification.text(senderName: senderName, sourceApp: sourceApp, messageText: messageText, createdAt: createdAt)
        content.title = text.title
        if let subtitle = text.subtitle { content.subtitle = String(subtitle.prefix(150)) }
        if let body = text.body { content.body = String(body.prefix(150)) }
        content.sound = .default
        content.categoryIdentifier = AppConstants.notificationCategoryID
        content.userInfo = ["reminderId": id.uuidString, "sourceApp": sourceApp ?? ""]
        content.threadIdentifier = ReminderNotification.threadIdentifier(sourceApp: sourceApp)
        // Time-sensitive reminders punch through Do Not Disturb / Focus; "weak" ones respect it.
        content.interruptionLevel = StrengthStore.ignoresDoNotDisturb(for: sourceApp) ? .timeSensitive : .active

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

    /// Schedule a reminder only if one isn't already armed for it. Used by the import path:
    /// a widget/Shortcuts flag already scheduled its repeating notification, so re-scheduling
    /// on the next app launch would silently reset the countdown. This checks first and only
    /// schedules when nothing is pending (e.g. a flag made while paused that now needs arming).
    func scheduleReminderIfNeeded(id: UUID, messageText: String, senderName: String?, sourceApp: String?, intervalMinutes: Int, createdAt: Date) {
        let identifier = "reminder-\(id.uuidString)"
        UNUserNotificationCenter.current().getPendingNotificationRequests { [weak self] requests in
            guard !requests.contains(where: { $0.identifier == identifier }) else { return }
            self?.scheduleReminder(
                id: id,
                messageText: messageText,
                senderName: senderName,
                sourceApp: sourceApp,
                intervalMinutes: intervalMinutes,
                createdAt: createdAt
            )
        }
    }

    func cancelReminder(id: UUID) {
        // Clear both the repeating reminder and any one-hour "snooze" follow-up; otherwise
        // a snoozed notification keeps firing for a message you've already answered/edited.
        let identifiers = ["reminder-\(id.uuidString)", "snooze-\(id.uuidString)"]
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    func rescheduleAllActive(items: [ReminderItem]) {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()

        // While globally snoozed, leave everything cancelled — don't reschedule.
        guard !isSnoozed else { return }

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
            // If "pause all" is on, honour it — don't re-arm a 1-hour follow-up that would
            // fire while everything is supposed to be paused. (Reschedule happens on resume.)
            guard !isSnoozed else { break }
            // Reschedule with a 1-hour delay
            let content = response.notification.request.content
            let snoozeContent = UNMutableNotificationContent()
            snoozeContent.title = content.title
            snoozeContent.subtitle = content.subtitle
            snoozeContent.body = content.body
            snoozeContent.sound = content.sound
            snoozeContent.categoryIdentifier = content.categoryIdentifier
            snoozeContent.userInfo = content.userInfo
            snoozeContent.threadIdentifier = content.threadIdentifier
            snoozeContent.interruptionLevel = content.interruptionLevel

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
        // Prefer the app's live container so the change is observed by the UI; fall back to
        // opening the shared store directly if the app hasn't registered one yet.
        let container = modelContainer ?? (try? ModelContainer(
            for: ReminderItem.self,
            configurations: ModelConfiguration(
                url: AppConstants.sharedContainerURL.appendingPathComponent("AYFM.store")
            )
        ))
        guard let container else { return }

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
