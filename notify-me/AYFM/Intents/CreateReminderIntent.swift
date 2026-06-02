import AppIntents
import UserNotifications

/// The Shortcuts action behind the Messages/Mail auto-flag automations: every incoming
/// message runs this to start tracking a "reply to this" reminder. Built to be driven by a
/// Personal Automation with no UI, so it doesn't open the app.
///
/// Senders on the user's ignore list — a spam email account, 2FA shortcodes/bots — are
/// dropped silently (see `IgnoredSenderStore`), so routine noise never becomes a nag.
/// Honours the global "pause all" snooze: while paused the reminder is still tracked but no
/// notification is armed; it starts nagging when the pause lifts / the app next opens
/// (the import path arms anything not yet scheduled).
struct CreateReminderIntent: AppIntent {
    static var title: LocalizedStringResource = "Track a Reply Reminder"
    static var description = IntentDescription(
        "Track a received message so AYFM nags you until you reply. Drives the Messages/Mail auto-flag automations."
    )
    // No UI — automations run this in the background on each incoming message.
    static var openAppWhenRun: Bool = false

    @Parameter(title: "From who?")
    var senderName: String?

    @Parameter(title: "Which app?", default: "Messages")
    var sourceApp: String?

    @Parameter(title: "Message content?")
    var messageContent: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Track a reply to \(\.$senderName) on \(\.$sourceApp)") {
            \.$messageContent
        }
    }

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog {
        // Drop senders the user has chosen to ignore (spam account, 2FA bots, …).
        guard !IgnoredSenderStore.isIgnored(senderName) else {
            return .result(dialog: "Ignored — that sender is on your ignore list.")
        }

        let app = sourceApp?.trimmingCharacters(in: .whitespacesAndNewlines)
        let interval = IntervalStore.interval(for: app)

        let about = messageContent?.trimmingCharacters(in: .whitespacesAndNewlines)
        let reminder = PendingReminder(
            id: UUID(),
            messageText: (about?.isEmpty == false) ? about! : "Flagged at \(Self.timeFormatter.string(from: Date()))",
            senderName: senderName,
            sourceApp: app,
            createdAt: Date(),
            intervalMinutes: interval
        )
        try reminder.write()

        // Arm the repeating nag now — unless everything is globally paused, in which case the
        // reminder is still tracked above and will arm when the app next opens / the pause lifts.
        if !SnoozeStore.isSnoozed {
            let content = UNMutableNotificationContent()
            let text = ReminderNotification.text(
                senderName: senderName,
                sourceApp: app,
                messageText: reminder.messageText,
                createdAt: reminder.createdAt
            )
            content.title = text.title
            if let subtitle = text.subtitle { content.subtitle = String(subtitle.prefix(150)) }
            if let body = text.body { content.body = String(body.prefix(150)) }
            content.sound = .default
            content.categoryIdentifier = AppConstants.notificationCategoryID
            content.userInfo = ["reminderId": reminder.id.uuidString, "sourceApp": app ?? ""]
            content.threadIdentifier = ReminderNotification.threadIdentifier(sourceApp: app)
            content.interruptionLevel = StrengthStore.ignoresDoNotDisturb(for: app) ? .timeSensitive : .active

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
        }

        let who = (senderName?.trimmingCharacters(in: .whitespacesAndNewlines))
            .flatMap { $0.isEmpty ? nil : $0 } ?? "them"
        return .result(dialog: "Tracked — I'll nag you to reply to \(who).")
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()
}
