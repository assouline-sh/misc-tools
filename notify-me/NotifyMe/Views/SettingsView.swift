import SwiftUI
import UserNotifications

struct SettingsView: View {
    @AppStorage(AppConstants.defaultIntervalKey, store: AppConstants.sharedDefaults)
    private var intervalMinutes: Int = 60

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
            VStack(alignment: .leading, spacing: 0) {
                ScreenTitle("settings", accent: "settings")
                Form {
                Section {
                    VStack(alignment: .leading, spacing: 1) {
                        Picker("global interval", selection: $intervalMinutes) {
                            ForEach(intervalOptions, id: \.minutes) { option in
                                Text(option.label).tag(option.minutes)
                            }
                        }
                        .pickerStyle(.menu)

                        Text("default if not otherwise specified")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    NavigationLink {
                        AppIntervalConfigView(intervalOptions: intervalOptions)
                    } label: {
                        Label("app-specific intervals", systemImage: "clock")
                    }

                    NavigationLink {
                        PlatformConfigView()
                    } label: {
                        Label("widget configuration", systemImage: "square.grid.2x2")
                    }
                } header: {
                    sectionHeader("harassment schedule")
                }

                Section {
                    HStack {
                        Text("version")
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    sectionHeader("about")
                }
            }
            .scrollContentBackground(.hidden)
            }
            .background(Theme.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var selectedLabel: String {
        intervalOptions.first { $0.minutes == intervalMinutes }?.label ?? "\(intervalMinutes) min"
    }

    /// Section header in the app's monospaced font, with the grouped-list's default
    /// uppercasing turned off so it reads lowercase like the rest of the UI.
    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(.footnote, design: .monospaced))
            .textCase(nil)
            .frame(maxWidth: .infinity, alignment: .leading)
            // Outdent so the header aligns with the section box's left edge (and the
            // "settings" title) rather than the indented row content.
            .listRowInsets(EdgeInsets(top: 14, leading: 0, bottom: 6, trailing: 0))
    }
}
