import SwiftUI
import WidgetKit

/// Per-app reminder intervals. Each selected widget app can either follow the global
/// interval or pick its own. Overrides persist to the shared App Group.
struct AppIntervalConfigView: View {
    let intervalOptions: [(label: String, minutes: Int)]

    /// The apps the user has put in their widget slots.
    private var platforms: [FlagPlatform] { PlatformStore.load() }

    /// Per-app overrides, mirrored in @State so the pickers update live. nil = use global.
    @State private var overrides: [String: Int] = IntervalStore.overrides()

    /// Sentinel tag for the "use global" picker option.
    private let useGlobalTag = -1

    var body: some View {
        Form {
            if platforms.isEmpty {
                Section {
                    Text("no apps configured yet. add some under “widget.”")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                Section("apps") {
                    ForEach(platforms) { platform in
                        Picker(platform.name, selection: binding(for: platform.name)) {
                            Text("global (\(globalLabel))").tag(useGlobalTag)
                            ForEach(intervalOptions, id: \.minutes) { option in
                                Text(option.label).tag(option.minutes)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("app-specific intervals")
        .navigationBarTitleDisplayMode(.inline)
        .tint(Theme.accent)
    }

    private var globalLabel: String {
        let minutes = IntervalStore.global
        return intervalOptions.first { $0.minutes == minutes }?.label ?? "\(minutes) min"
    }

    /// A binding that reads/writes an app's override, using `useGlobalTag` for "no override".
    private func binding(for app: String) -> Binding<Int> {
        Binding(
            get: { overrides[app] ?? useGlobalTag },
            set: { newValue in
                let minutes: Int? = newValue == useGlobalTag ? nil : newValue
                if let minutes { overrides[app] = minutes } else { overrides[app] = nil }
                IntervalStore.setOverride(minutes, for: app)
                WidgetCenter.shared.reloadAllTimelines()
            }
        )
    }
}
