import SwiftUI
import UserNotifications

struct SettingsView: View {
    @AppStorage(AppConstants.defaultIntervalKey, store: AppConstants.sharedDefaults)
    private var intervalMinutes: Int = 60

    @State private var notificationStatus: String = "Checking..."
    @State private var scheduledInfo: String = ""

    private let intervalOptions: [(label: String, minutes: Int)] = [
        ("1 min", 1),
        ("15 min", 15),
        ("30 min", 30),
        ("1 hour", 60),
        ("2 hours", 120),
        ("4 hours", 240),
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Reminder Interval") {
                    Picker("Default interval", selection: $intervalMinutes) {
                        ForEach(intervalOptions, id: \.minutes) { option in
                            Text(option.label).tag(option.minutes)
                        }
                    }
                    .pickerStyle(.menu)

                    Text("New reminders will notify you every \(selectedLabel).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Quick Flag") {
                    NavigationLink {
                        PlatformConfigView()
                    } label: {
                        Label("Configure widget buttons", systemImage: "square.grid.2x2")
                    }
                }

                Section("Notifications") {
                    HStack {
                        Text("Permission")
                        Spacer()
                        Text(notificationStatus)
                            .foregroundStyle(.secondary)
                    }

                    if notificationStatus == "Denied" {
                        Button("Open Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                    }
                }

                Section("Debug") {
                    Button("Send Test Notification (5 seconds)") {
                        let content = UNMutableNotificationContent()
                        content.title = "Test Notification"
                        content.body = "If you see this, notifications are working!"
                        content.sound = .default
                        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
                        let request = UNNotificationRequest(identifier: "test", content: content, trigger: trigger)
                        UNUserNotificationCenter.current().add(request)
                    }

                    Button("Check Scheduled Notifications") {
                        Task {
                            let pending = await UNUserNotificationCenter.current().pendingNotificationRequests()
                            scheduledInfo = "Scheduled: \(pending.count)\n"
                            for req in pending {
                                if let trigger = req.trigger as? UNTimeIntervalNotificationTrigger {
                                    scheduledInfo += "- \(req.identifier): every \(Int(trigger.timeInterval))s, repeats: \(trigger.repeats), next: \(trigger.nextTriggerDate()?.description ?? "none")\n"
                                } else {
                                    scheduledInfo += "- \(req.identifier): \(req.trigger?.description ?? "no trigger")\n"
                                }
                            }
                        }
                    }

                    if !scheduledInfo.isEmpty {
                        Text(scheduledInfo)
                            .font(.caption)
                            .monospaced()
                    }
                }

                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("settings")
            .screen()
            .task {
                await checkNotificationStatus()
            }
        }
    }

    private var selectedLabel: String {
        intervalOptions.first { $0.minutes == intervalMinutes }?.label ?? "\(intervalMinutes) min"
    }

    private func checkNotificationStatus() async {
        let status = await NotificationManager.shared.authorizationStatus()
        switch status {
        case .authorized: notificationStatus = "Authorized"
        case .denied: notificationStatus = "Denied"
        case .provisional: notificationStatus = "Provisional"
        case .notDetermined: notificationStatus = "Not Requested"
        case .ephemeral: notificationStatus = "Ephemeral"
        @unknown default: notificationStatus = "Unknown"
        }
    }
}
