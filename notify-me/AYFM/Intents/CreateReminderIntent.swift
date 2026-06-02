import AppIntents
import UserNotifications

struct CreateReminderIntent: AppIntent {
    static var title: LocalizedStringResource = "Create Reminder"
    static var description: IntentDescription = "Create a reminder to reply to a message"
    static var openAppWhenRun: Bool = false

    @Parameter(title: "From who?")
    var senderName: String?

    @Parameter(title: "Which app?")
    var sourceApp: String?

    @Parameter(title: "Message content?")
    var messageContent: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Create a reply reminder") {
            \.$senderName
            \.$sourceApp
            \.$messageContent
        }
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let intervalMinutes = AppConstants.sharedDefaults.integer(forKey: AppConstants.defaultIntervalKey)
        let interval = intervalMinutes > 0 ? intervalMinutes : 60

        let reminder = PendingReminder(
            id: UUID(),
            messageText: messageContent ?? "Message at \(Self.timeFormatter.string(from: Date()))",
            senderName: senderName,
            sourceApp: sourceApp,
            createdAt: Date(),
            intervalMinutes: interval
        )

        try reminder.write()

        // Schedule notification directly
        let content = UNMutableNotificationContent()
        let text = ReminderNotification.text(senderName: senderName, sourceApp: sourceApp, messageText: reminder.messageText, createdAt: reminder.createdAt)
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

        let name = senderName ?? "someone"
        return .result(dialog: "Reminder set — I'll poke you every \(interval) min to reply to \(name).")
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()
}
