import SwiftUI
import SwiftData
import UserNotifications

struct SettingsView: View {
    @AppStorage(AppConstants.defaultIntervalKey, store: AppConstants.sharedDefaults)
    private var intervalMinutes: Int = 60

    private let intervalOptions: [(label: String, minutes: Int)] = [
        ("30 min", 30),
        ("1 hour", 60),
        ("2 hours", 120),
        ("4 hours", 240),
        ("8 hours", 480),
        ("12 hours", 720),
        ("1 day", 1440),
        ("every other day", 2880),
    ]

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                ScreenTitle("settings", accent: "settings")
                Form {
                Section {
                    NavigationLink {
                        PlatformConfigView()
                    } label: {
                        Label("widget configuration", systemImage: "square.grid.2x2")
                    }
                } header: {
                    sectionHeader("harassment schedule")
                }

                Section {
                    Picker(selection: $intervalMinutes) {
                        ForEach(intervalOptions, id: \.minutes) { option in
                            Text(option.label).tag(option.minutes)
                        }
                    } label: {
                        Label("default interval", systemImage: "clock.fill")
                    }
                    .pickerStyle(.menu)

                    NavigationLink {
                        AppIntervalConfigView(intervalOptions: intervalOptions)
                    } label: {
                        Label("app-specific intervals", systemImage: "clock")
                    }
                }

                Section {
                    StrengthSection()

                    NavigationLink {
                        AppStrengthConfigView()
                    } label: {
                        Label("app-specific strength", systemImage: "bolt")
                    }

                    SnoozeSection()
                }

                Section {
                    NavigationLink {
                        FeedbackView()
                    } label: {
                        Label("send feedback", systemImage: "paperplane")
                    }
                } header: {
                    sectionHeader("got beef?")
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
            .listSectionSpacing(12)
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

// MARK: - Strength

/// Default notification strength: whether reminders break through Do Not Disturb / Focus.
/// On (the default) delivers them time-sensitive so they punch through; off lets them
/// respect Do Not Disturb. The toggle label states the current behaviour itself, so no
/// caption is needed. Flipping it reschedules active reminders so it takes effect now.
private struct StrengthSection: View {
    @Environment(\.modelContext) private var modelContext

    @AppStorage(AppConstants.defaultStrengthKey, store: AppConstants.sharedDefaults)
    private var ignoreDND: Bool = true

    var body: some View {
        Toggle(isOn: $ignoreDND) {
            Label(
                ignoreDND ? "ignore do not disturb" : "respect do not disturb",
                systemImage: "bolt.fill"
            )
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
        .tint(Theme.accent)
        .padding(.vertical, 2)
        .onChange(of: ignoreDND) { _, _ in
            SharedDataManager.rescheduleAll(context: modelContext)
        }
    }
}

// MARK: - Snooze

/// Positions on the "pause all" scale. `.active` is the off position (notifications
/// running); `.indefinitely` pauses until the user slides back down.
private enum SnoozeOption: Int, CaseIterable, Identifiable {
    case active, oneHour, eightHours, oneDay, indefinitely

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .active:       return "active"
        case .oneHour:      return "1 hour"
        case .eightHours:   return "8 hours"
        case .oneDay:       return "1 day"
        case .indefinitely: return "forever"
        }
    }

    /// Compact label for the slider's tick marks.
    var tick: String {
        switch self {
        case .active:       return "active"
        case .oneHour:      return "1h"
        case .eightHours:   return "8h"
        case .oneDay:       return "1d"
        case .indefinitely: return "∞"
        }
    }

    /// The instant the snooze should end, or nil when `.active` (not snoozing).
    /// `.indefinitely` returns `.distantFuture`.
    func snoozeUntil(from now: Date) -> Date? {
        switch self {
        case .active:       return nil
        case .oneHour:      return now.addingTimeInterval(3_600)
        case .eightHours:   return now.addingTimeInterval(8 * 3_600)
        case .oneDay:       return now.addingTimeInterval(24 * 3_600)
        case .indefinitely: return .distantFuture
        }
    }
}

/// Global-snooze control: a single discrete scale that runs "active" → "1 hour" →
/// "8 hours" → "1 day" → "forever", sitting on one line to the right of its label.
/// The slider snaps to each option and fires a selection haptic as it crosses one,
/// so you can feel the stops without looking. "active" is the off position.
private struct SnoozeSection: View {
    @Environment(\.modelContext) private var modelContext

    @AppStorage(AppConstants.globalSnoozeUntilKey, store: AppConstants.sharedDefaults)
    private var snoozeUntilTS: Double = 0

    @AppStorage(AppConstants.globalSnoozeOptionKey, store: AppConstants.sharedDefaults)
    private var snoozeOptionRaw: Int = SnoozeOption.active.rawValue

    private let haptics = UISelectionFeedbackGenerator()

    private var isSnoozing: Bool {
        snoozeUntilTS > 0 && Date(timeIntervalSince1970: snoozeUntilTS) > Date()
    }

    /// Where the slider currently sits. Falls back to `.active` whenever no snooze is
    /// running (including after a finite one quietly expires).
    private var currentIndex: Int {
        isSnoozing ? snoozeOptionRaw : SnoozeOption.active.rawValue
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 16) {
                Label("pause all", systemImage: "bell.slash")

                VStack(spacing: 2) {
                    Slider(
                        value: sliderBinding,
                        in: 0...Double(SnoozeOption.allCases.count - 1),
                        step: 1
                    )
                    .tint(Theme.accent)

                    // Tiny tick labels under each detent; the current one highlighted.
                    HStack(spacing: 0) {
                        ForEach(SnoozeOption.allCases) { option in
                            Text(option.tick)
                                // The ∞ glyph reads small at 9pt, so bump it up a little.
                                .font(.system(size: option == .indefinitely ? 14 : 9, design: .monospaced))
                                .foregroundStyle(option.rawValue == currentIndex ? Theme.accent : .secondary)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }

            Text(statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.vertical, 2)
        .onAppear { haptics.prepare() }
    }

    /// Slider position maps to a `SnoozeOption`. Moving it fires a haptic at each detent
    /// and applies that option — sliding to "active" resumes notifications.
    private var sliderBinding: Binding<Double> {
        Binding(
            get: { Double(currentIndex) },
            set: { newValue in
                let index = Int(newValue.rounded())
                guard index != currentIndex,
                      let option = SnoozeOption(rawValue: index) else { return }
                haptics.selectionChanged()
                haptics.prepare()
                apply(option)
            }
        )
    }

    private func apply(_ option: SnoozeOption) {
        snoozeOptionRaw = option.rawValue
        if let until = option.snoozeUntil(from: Date()) {
            snoozeUntilTS = until.timeIntervalSince1970
            NotificationManager.shared.setGlobalSnooze(until: until)
        } else {
            // "active" — lift the snooze and bring active reminders' notifications back.
            snoozeUntilTS = 0
            NotificationManager.shared.setGlobalSnooze(until: nil)
            SharedDataManager.rescheduleAll(context: modelContext)
        }
    }

    private var statusText: String {
        let until = Date(timeIntervalSince1970: snoozeUntilTS)
        let formatter = DateFormatter()
        formatter.dateFormat = Calendar.current.isDateInToday(until) ? "h:mm a" : "EEE h:mm a"
        let time = formatter.string(from: until)

        switch SnoozeOption(rawValue: currentIndex) ?? .active {
        case .active:       return "asking you to pls answer your f****** messages"
        case .oneHour:      return "take a break until \(time)"
        case .eightHours:   return "really focusing until \(time)"
        case .oneDay:       return "day off? until \(time)"
        case .indefinitely: return "stopped (for now). set active to resume"
        }
    }
}
