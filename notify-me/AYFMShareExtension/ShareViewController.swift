import UIKit
import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

/// Share-sheet target: grabs a shared URL or text, infers which app/service it came from,
/// then shows a small editable form (app / who / about / interval). On submit it saves the
/// reply-reminder directly — writing it to the App Group and arming its repeating
/// notification right here, exactly like a widget quick-flag. The app imports the queued
/// reminder into its database the next time it opens (see `SharedDataManager`). It never
/// launches the app, so the sheet just dismisses when you're done.
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        extractShared { [weak self] url, text in
            DispatchQueue.main.async { self?.presentForm(url: url, text: text) }
        }
    }

    // MARK: - Hosting the edit form

    private func presentForm(url: URL?, text: String?) {
        let app = sourceApp(for: url)
        let about = (text ?? url?.absoluteString)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let form = ShareComposeView(
            initialApp: app,
            initialMessage: about,
            onSubmit: { [weak self] app, sender, message in
                ShareReminderStore.save(sourceApp: app, senderName: sender, messageText: message) {
                    self?.finish()
                }
            },
            onCancel: { [weak self] in self?.finish() }
        )

        let host = UIHostingController(rootView: form)
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
    }

    /// Dismiss the share sheet. Hopping to the main queue keeps us safe when called from a
    /// background notification-scheduling callback.
    private func finish() {
        DispatchQueue.main.async { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
        }
    }

    // MARK: - Extracting the shared content

    /// Pulls the first URL and/or plain-text attachment from the share, if any.
    private func extractShared(completion: @escaping (URL?, String?) -> Void) {
        guard let item = extensionContext?.inputItems.first as? NSExtensionItem,
              let provider = item.attachments?.first else {
            completion(nil, nil)
            return
        }

        let urlType = UTType.url.identifier
        let textType = UTType.plainText.identifier

        if provider.hasItemConformingToTypeIdentifier(urlType) {
            provider.loadItem(forTypeIdentifier: urlType, options: nil) { value, _ in
                if let url = value as? URL {
                    completion(url, nil)
                } else if let string = value as? String {
                    completion(URL(string: string), string)
                } else {
                    completion(nil, nil)
                }
            }
        } else if provider.hasItemConformingToTypeIdentifier(textType) {
            provider.loadItem(forTypeIdentifier: textType, options: nil) { value, _ in
                let string = value as? String
                completion(string.flatMap(URL.init(string:)), string)
            }
        } else {
            completion(nil, nil)
        }
    }

    // MARK: - Source-app detection

    /// Best-effort guess at which app the shared link is from. iOS never tells an extension
    /// which app invoked it, so we infer: a known service domain maps to its catalog name
    /// (matching the widget's app list, so per-app intervals/strength apply); any other web
    /// page is attributed to the browser it came from — defaulting to Safari, since iOS
    /// won't say which browser and the link itself is kept in the description; a share with
    /// no web URL stays nil.
    private func sourceApp(for url: URL?) -> String? {
        guard let url, let host = url.host?.lowercased() else { return nil }
        let domain = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host

        for (needle, name) in Self.domainMap where domain == needle || domain.hasSuffix(".\(needle)") {
            return name
        }
        let scheme = url.scheme?.lowercased()
        return (scheme == "http" || scheme == "https") ? "Safari" : nil
    }

    /// Registrable domains → the catalog app name they belong to. Subdomains match too
    /// (e.g. `m.youtube.com` → YouTube via the `.youtube.com` suffix check above).
    private static let domainMap: [(String, String)] = [
        ("youtube.com", "YouTube"), ("youtu.be", "YouTube"),
        ("twitter.com", "X"), ("x.com", "X"),
        ("reddit.com", "Reddit"),
        ("instagram.com", "Instagram"),
        ("tiktok.com", "TikTok"),
        ("facebook.com", "Facebook"), ("fb.com", "Facebook"), ("fb.watch", "Facebook"),
        ("messenger.com", "Messenger"),
        ("linkedin.com", "LinkedIn"),
        ("threads.net", "Threads"),
        ("t.me", "Telegram"),
        ("wa.me", "WhatsApp"), ("whatsapp.com", "WhatsApp"),
        ("discord.com", "Discord"), ("discord.gg", "Discord"),
        ("snapchat.com", "Snapchat"),
        ("twitch.tv", "Twitch"),
        ("pinterest.com", "Pinterest"),
        ("ebay.com", "eBay"),
        ("etsy.com", "Etsy"),
        ("airbnb.com", "Airbnb"),
        ("venmo.com", "Venmo"),
        ("paypal.com", "PayPal"),
    ]
}

// MARK: - Saving + scheduling

/// Writes a reply-reminder to the App Group and arms its repeating notification, mirroring
/// the widget quick-flag path so the app, widget, and share extension all behave the same.
enum ShareReminderStore {
    /// - Parameters are already trimmed by the form. `completion` runs once the notification
    ///   is registered, so the host can complete the share request without the system tearing
    ///   the extension down before scheduling lands.
    static func save(sourceApp app: String?, senderName: String?, messageText: String, completion: @escaping () -> Void) {
        let message = messageText.isEmpty
            ? "Flagged at \(timeFormatter.string(from: Date()))"
            : messageText
        let interval = IntervalStore.interval(for: app)

        let reminder = PendingReminder(
            id: UUID(),
            messageText: message,
            senderName: senderName,
            sourceApp: app,
            createdAt: Date(),
            intervalMinutes: interval
        )
        // Queue it for the app to import into its database on next launch.
        try? reminder.write()

        let content = UNMutableNotificationContent()
        let copy = ReminderNotification.text(senderName: senderName, sourceApp: app, messageText: message, createdAt: reminder.createdAt)
        content.title = copy.title
        if let subtitle = copy.subtitle { content.subtitle = String(subtitle.prefix(150)) }
        if let body = copy.body { content.body = String(body.prefix(150)) }
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
        UNUserNotificationCenter.current().add(request) { _ in completion() }
    }

    fileprivate static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()
}

// MARK: - The edit form

/// A compact, self-contained version of the app's compose form, styled to match (dark,
/// monospaced, amber accent) but with no SwiftData / app-target dependencies so it can live
/// inside the extension. Pre-filled from the share; lets you fix the app, add who/about,
/// and pick a cadence before saving.
private struct ShareComposeView: View {
    let initialApp: String?
    let initialMessage: String
    let onSubmit: (_ app: String?, _ sender: String?, _ message: String) -> Void
    let onCancel: () -> Void

    @State private var sourceApp: String?
    @State private var senderName = ""
    @State private var messageText = ""
    @State private var intervalMinutes: Int
    @State private var saving = false

    private let nameLimit = 25
    private let aboutLimit = 100

    // Pulled from Theme (which lives in the app target) so the extension matches the app.
    private let accent = Color(red: 0.961, green: 0.651, blue: 0.137)
    private let background = Color(red: 0.043, green: 0.043, blue: 0.051)

    init(
        initialApp: String?,
        initialMessage: String,
        onSubmit: @escaping (String?, String?, String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.initialApp = initialApp
        self.initialMessage = initialMessage
        self.onSubmit = onSubmit
        self.onCancel = onCancel
        _sourceApp = State(initialValue: initialApp)
        _messageText = State(initialValue: initialMessage)
        _intervalMinutes = State(initialValue: IntervalStore.normalized(IntervalStore.interval(for: initialApp)))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    // Custom layout: the selected app name sits prominently on the left, with
                    // the small "app" label + chevron on the right (a plain Picker puts them the
                    // other way round).
                    Menu {
                        Picker("app", selection: $sourceApp) {
                            Text("none").tag(String?.none)
                            ForEach(appChoices, id: \.self) { app in
                                Text(app).tag(Optional(app))
                            }
                        }
                    } label: {
                        HStack {
                            Text(sourceApp ?? "none")
                                .textCase(.lowercase)
                                .foregroundStyle(Color.primary)
                            Spacer()
                            Text("app")
                                .foregroundStyle(accent)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.footnote)
                                .foregroundStyle(accent)
                        }
                    }
                    .onChange(of: sourceApp) { _, newApp in
                        intervalMinutes = IntervalStore.normalized(IntervalStore.interval(for: newApp))
                    }
                } header: {
                    header("from which app?")
                }

                Section {
                    TextField("name", text: $senderName)
                        .textInputAutocapitalization(.words)
                        .onChange(of: senderName) { _, value in
                            let cleaned = String(value.replacingOccurrences(of: "\n", with: " ").prefix(nameLimit))
                            if cleaned != value { senderName = cleaned }
                        }
                } header: {
                    header("from who?")
                }

                Section {
                    TextField("message", text: $messageText, axis: .vertical)
                        .lineLimit(2...5)
                        .onChange(of: messageText) { _, value in
                            if value.count > aboutLimit { messageText = String(value.prefix(aboutLimit)) }
                        }
                } header: {
                    header("about what?")
                }

                Section {
                    Picker("interval", selection: $intervalMinutes) {
                        ForEach(IntervalStore.options, id: \.minutes) { option in
                            Text(option.label).tag(option.minutes)
                        }
                    }
                    .pickerStyle(.menu)
                } header: {
                    header("remind me every")
                }
            }
            .scrollContentBackground(.hidden)
            .background(background.ignoresSafeArea())
            .navigationTitle("new notification")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("submit", action: submit).fontWeight(.bold).disabled(saving)
                }
            }
        }
        .tint(accent)
        .fontDesign(.monospaced)
        .preferredColorScheme(.dark)
    }

    private func header(_ text: String) -> some View {
        Text(text)
            .font(.system(.footnote, design: .monospaced))
            .textCase(nil)
    }

    /// Apps offered in the picker: the full catalog plus the user's custom apps, plus the
    /// detected one if it isn't otherwise listed, sorted case-insensitively.
    private var appChoices: [String] {
        var names = PlatformCatalog.all.map(\.name)
        names.append(contentsOf: CustomAppStore.load().map(\.name))
        if let sourceApp { names.append(sourceApp) }
        return Array(Set(names)).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private func submit() {
        saving = true
        let message = String(messageText.prefix(aboutLimit))
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let sender = String(senderName.prefix(nameLimit))
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        onSubmit(sourceApp, sender.isEmpty ? nil : sender, message)
    }
}
