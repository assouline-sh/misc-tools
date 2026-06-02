import AppIntents
import UserNotifications

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
        let intervalMinutes = AppConstants.sharedDefaults.integer(forKey: AppConstants.defaultIntervalKey)
        let interval = intervalMinutes > 0 ? intervalMinutes : 60

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
        content.title = "Reply to \(sourceApp ?? "message")"
        content.body = reminder.messageText
        content.sound = .default
        content.categoryIdentifier = AppConstants.notificationCategoryID
        content.userInfo = ["reminderId": reminder.id.uuidString, "sourceApp": sourceApp ?? ""]

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

        return .result()
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()
}
