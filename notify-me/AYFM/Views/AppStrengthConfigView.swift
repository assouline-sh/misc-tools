import SwiftUI
import SwiftData
import WidgetKit

/// Per-app notification strength. Each selected widget app can follow the default
/// strength or pick its own — ignore Do Not Disturb (time-sensitive) or respect it.
/// Overrides persist to the shared App Group.
struct AppStrengthConfigView: View {
    @Environment(\.modelContext) private var modelContext

    /// The apps the user has put in their widget slots.
    private var platforms: [FlagPlatform] { PlatformStore.load() }

    /// Per-app overrides, mirrored in @State so the pickers update live. nil = use default.
    @State private var overrides: [String: Bool] = StrengthStore.overrides()

    /// Picker tags. `useDefaultTag` means "no override, follow the default strength".
    private let useDefaultTag = 0
    private let ignoreTag = 1
    private let respectTag = 2

    var body: some View {
        Form {
            if platforms.isEmpty {
                Section {
                    Text("no apps configured yet. add some under “widget.”")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                Section {
                    ForEach(platforms) { platform in
                        Picker(platform.name.lowercased(), selection: binding(for: platform.name)) {
                            Text("default (\(defaultLabel))").tag(useDefaultTag)
                            Text("ignore dnd").tag(ignoreTag)
                            Text("respect dnd").tag(respectTag)
                        }
                        .pickerStyle(.menu)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .contentMargins(.top, 8, for: .scrollContent)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("app-specific respect")
        .navigationBarTitleDisplayMode(.inline)
        .tint(Theme.accent)
    }

    /// The default strength shown in the "default (…)" option.
    private var defaultLabel: String {
        StrengthStore.global ? "ignore dnd" : "respect dnd"
    }

    /// A binding that reads/writes an app's override, using `useDefaultTag` for "no override".
    private func binding(for app: String) -> Binding<Int> {
        Binding(
            get: {
                switch overrides[app] {
                case .some(true):  return ignoreTag
                case .some(false): return respectTag
                case .none:        return useDefaultTag
                }
            },
            set: { newValue in
                let ignore: Bool? = newValue == useDefaultTag ? nil : (newValue == ignoreTag)
                overrides[app] = ignore
                StrengthStore.setOverride(ignore, for: app)
                // Apply now so active reminders pick up the new strength, and refresh the
                // widget in case it surfaces this state.
                SharedDataManager.rescheduleAll(context: modelContext)
                WidgetCenter.shared.reloadAllTimelines()
            }
        )
    }
}
