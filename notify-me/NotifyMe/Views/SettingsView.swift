import SwiftUI

struct SettingsView: View {
    @AppStorage(AppConstants.defaultIntervalKey, store: AppConstants.sharedDefaults)
    private var intervalMinutes: Int = 60

    @State private var notificationStatus: String = "Checking..."

    private let intervalOptions: [(label: String, minutes: Int)] = [
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

                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
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
