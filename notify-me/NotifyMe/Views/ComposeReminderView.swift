import SwiftUI
import SwiftData
import UIKit

/// Pre-filled "new reminder" form shown when you tap an app in the widget. Lets you
/// record who messaged, what they said, and how often to be nagged before saving.
struct ComposeReminderView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    /// The app tapped in the widget (nil if launched without one). Editable, so you can
    /// fix it when the wrong app — or none — was picked up from the tap.
    @State private var sourceApp: String?

    @State private var senderName = ""
    @State private var messageText = ""
    @State private var intervalMinutes: Int

    /// Input caps so the notification title/subtitle stay legible and don't get truncated.
    private let nameLimit = 25
    private let aboutLimit = 100

    /// Drives the tapped-app badge's pop-in, so opening the form clearly confirms which
    /// app you tapped in the widget.
    @State private var badgeIn = false

    /// Reminder cadence choices, in minutes. The value pulled from Settings is always
    /// included so the pre-filled interval is selectable even when it isn't a standard
    /// choice (e.g. a 1-minute global default).
    private var intervalOptions: [Int] {
        Set([15, 30, 60, 120, 240, 480, 1440]).union([intervalMinutes]).sorted()
    }

    init(sourceApp: String?) {
        _sourceApp = State(initialValue: sourceApp)
        // Default to this app's own interval if it has one, else the global interval.
        _intervalMinutes = State(initialValue: IntervalStore.interval(for: sourceApp))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Menu {
                        Picker("app", selection: $sourceApp) {
                            ForEach(appChoices, id: \.self) { app in
                                Text(app).tag(Optional(app))
                            }
                        }
                    } label: {
                        appBadge(sourceApp)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .onChange(of: sourceApp) { _, newApp in
                        // Follow the newly chosen app's configured interval.
                        intervalMinutes = IntervalStore.interval(for: newApp)
                    }
                }
                .listRowBackground(Color.clear)

                Section {
                    TextField("name", text: $senderName)
                        .textInputAutocapitalization(.words)
                        .onChange(of: senderName) { _, value in
                            let cleaned = String(value.replacingOccurrences(of: "\n", with: " ").prefix(nameLimit))
                            if cleaned != value { senderName = cleaned }
                        }
                } header: {
                    sectionHeader("from who?")
                }

                Section {
                    TextField("message", text: $messageText, axis: .vertical)
                        .lineLimit(2...5)
                        .onChange(of: messageText) { _, value in
                            if value.count > aboutLimit { messageText = String(value.prefix(aboutLimit)) }
                        }
                } header: {
                    sectionHeader("about what?")
                }

                Section {
                    Picker("interval", selection: $intervalMinutes) {
                        ForEach(intervalOptions, id: \.self) { minutes in
                            Text(label(forMinutes: minutes)).tag(minutes)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(Theme.accent)
                } header: {
                    sectionHeader("remind me every")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("new notification")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("submit", action: save).fontWeight(.bold)
                }
            }
        }
        .tint(Theme.accent)
        .fontDesign(.monospaced)
        .preferredColorScheme(.dark)
        .onAppear(perform: playOpenHaptic)
    }

    /// A single tap of haptic feedback as the form opens, reinforcing the tap that
    /// launched it.
    private func playOpenHaptic() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare()
        generator.impactOccurred()
    }

    /// A large badge for the tapped app — its icon (or a brand-coloured initial) plus its
    /// name — that pops in when the form appears, confirming which app you selected.
    @ViewBuilder
    private func appBadge(_ app: String?) -> some View {
        let icon = app.flatMap(iconImage(for:))
        let brand = Theme.brand(for: app)

        VStack(spacing: 8) {
            ZStack {
                if let icon {
                    Image(uiImage: icon).resizable().scaledToFill()
                } else {
                    brand
                    Text(app.map { String($0.prefix(1)).uppercased() } ?? "?")
                        .font(.system(size: 34, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 78, height: 78)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: brand.opacity(0.5), radius: 12)

            Text(app ?? "choose app")
                .font(.system(size: 17, weight: .bold, design: .monospaced))
                .foregroundStyle(Theme.accent)

            Label("tap to change", systemImage: "chevron.up.chevron.down")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .scaleEffect(badgeIn ? 1 : 0.5)
        .opacity(badgeIn ? 1 : 0)
        .onAppear {
            badgeIn = false
            withAnimation(.spring(response: 0.5, dampingFraction: 0.55).delay(0.1)) {
                badgeIn = true
            }
        }
    }

    /// The cached icon for an app (in-memory, then on-disk), if we have one.
    private func iconImage(for app: String) -> UIImage? {
        AppIconCache.shared.images[app]
            ?? AppIconStore.cachedData(for: app).flatMap { UIImage(data: $0) }
    }

    /// Apps offered in the picker: the full catalog, plus the current one if it's custom.
    private var appChoices: [String] {
        var names = PlatformCatalog.all.map(\.name)
        if let sourceApp, !names.contains(sourceApp) { names.insert(sourceApp, at: 0) }
        return names
    }

    /// Section header in the app's monospaced font, left-aligned with the section box's
    /// edge (outdented from the default row-content inset) and not uppercased.
    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(.footnote, design: .monospaced))
            .textCase(nil)
            .frame(maxWidth: .infinity, alignment: .leading)
            .listRowInsets(EdgeInsets(top: 14, leading: 0, bottom: 6, trailing: 0))
    }

    private func label(forMinutes minutes: Int) -> String {
        switch minutes {
        case ..<60:  return "\(minutes) min"
        case 60:     return "1 hour"
        case 1440:   return "1 day"
        default:     return "\(minutes / 60) hours"
        }
    }

    private func save() {
        let trimmedMessage = String(messageText.prefix(aboutLimit))
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSender = String(senderName.prefix(nameLimit))
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let item = ReminderItem(
            messageText: trimmedMessage.isEmpty
                ? "Flagged at \(Self.timeFormatter.string(from: Date()))"
                : trimmedMessage,
            senderName: trimmedSender.isEmpty ? nil : trimmedSender,
            sourceApp: sourceApp,
            intervalMinutes: intervalMinutes
        )
        context.insert(item)
        try? context.save()

        NotificationManager.shared.scheduleReminder(
            id: item.id,
            messageText: item.messageText,
            senderName: item.senderName,
            sourceApp: item.sourceApp,
            intervalMinutes: item.notificationIntervalMinutes,
            createdAt: item.createdAt
        )

        dismiss()
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()
}
