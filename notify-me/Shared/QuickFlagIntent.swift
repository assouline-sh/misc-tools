import AppIntents
import UserNotifications
import WidgetKit

struct QuickFlagIntent: AppIntent {
    static var title: LocalizedStringResource = "Quick Flag"
    static var description: IntentDescription = "Flag a message for reply"
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Source App")
    var sourceApp: String?

    init() {}

    init(sourceApp: String) {
        self.sourceApp = sourceApp
    }

    func perform() async throws -> some IntentResult {
        let interval = IntervalStore.interval(for: sourceApp)

        let reminder = PendingReminder(
            id: UUID(),
            messageText: "Flagged at \(Self.timeFormatter.string(from: Date()))",
            senderName: nil,
            sourceApp: sourceApp,
            createdAt: Date(),
            intervalMinutes: interval
        )

        try reminder.write()

        let content = UNMutableNotificationContent()
        let text = ReminderNotification.text(senderName: nil, sourceApp: sourceApp, messageText: reminder.messageText, createdAt: reminder.createdAt)
        content.title = text.title
        if let subtitle = text.subtitle { content.subtitle = String(subtitle.prefix(150)) }
        if let body = text.body { content.body = String(body.prefix(150)) }
        content.sound = .default
        content.categoryIdentifier = AppConstants.notificationCategoryID
        content.userInfo = ["reminderId": reminder.id.uuidString, "sourceApp": sourceApp ?? ""]
        content.threadIdentifier = ReminderNotification.threadIdentifier(sourceApp: sourceApp)
        content.interruptionLevel = StrengthStore.ignoresDoNotDisturb(for: sourceApp) ? .timeSensitive : .active

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: TimeInterval(interval * 60),
            repeats: true
        )
        let request = UNNotificationRequest(
            identifier: "reminder-\(reminder.id.uuidString)",
            content: content,
            trigger: trigger
        )

        try await UNUserNotificationCenter.current().add(request)

        // Record which app was just flagged so the widget can briefly flash it, then
        // refresh the timeline to show (and shortly after, clear) that confirmation.
        if let sourceApp {
            AppConstants.sharedDefaults.set(sourceApp, forKey: AppConstants.widgetFlashAppKey)
            AppConstants.sharedDefaults.set(Date(), forKey: AppConstants.widgetFlashDateKey)
        }
        WidgetCenter.shared.reloadAllTimelines()

        return .result()
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()
}
