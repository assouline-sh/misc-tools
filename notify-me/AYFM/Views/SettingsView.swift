import SwiftUI
import SwiftData
import UserNotifications

struct SettingsView: View {
    @AppStorage(AppConstants.defaultIntervalKey, store: AppConstants.sharedDefaults)
    private var intervalMinutes: Int = IntervalStore.defaultMinutes

    private let intervalOptions = IntervalStore.options

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
                        Label("app-specific respect", systemImage: "bolt")
                    }

                    SnoozeSection()
                }

                Section {
                    NavigationLink {
                        AutoFlagSetupView()
                    } label: {
                        Label("set it up", systemImage: "wand.and.stars")
                    }

                    NavigationLink {
                        IgnoredSendersView()
                    } label: {
                        Label("ignored senders", systemImage: "nosign")
                    }
                } header: {
                    sectionHeader("auto-flag imessage & mail")
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

    /// Bumped on a timer so the slider re-evaluates `isSnoozing` and snaps back to "active"
    /// on its own the moment a finite pause's end time passes while this screen is open.
    @State private var refreshTick = Date()

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
        .onReceive(Timer.publish(every: 20, on: .main, in: .common).autoconnect()) { now in
            // Re-render so the slider returns to "active" once a finite pause expires,
            // without the user having to leave and reopen the screen.
            refreshTick = now
        }
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
            // Queue active reminders to start nagging again the instant a finite break
            // ends, so the pause self-lifts without needing the app reopened.
            SharedDataManager.scheduleResume(context: modelContext, at: until)
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

// MARK: - Ignored senders

/// An editable list of senders the auto-flag intent drops (a spam email account, the
/// shortcodes/bots that send 2FA codes, etc.). Backed by `IgnoredSenderStore` in the shared
/// App Group, so `CreateReminderIntent` reads the same list when an automation fires.
private struct IgnoredSendersView: View {
    @State private var entries: [String] = IgnoredSenderStore.load()
    @State private var newEntry: String = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        Form {
            Section {
                HStack {
                    TextField("number, email, @domain, or name", text: $newEntry)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($fieldFocused)
                        .onSubmit(add)
                    Button(action: add) {
                        Image(systemName: "plus.circle.fill")
                    }
                    .disabled(newEntry.trimmingCharacters(in: .whitespaces).isEmpty)
                    .tint(Theme.accent)
                }
            } footer: {
                Text("auto-flagged messages from these are dropped — nothing gets tracked or nags you. matches a phone number/shortcode (ignoring formatting), a full email, an @domain, or an exact sender name.")
                    .font(.footnote)
            }

            if !entries.isEmpty {
                Section {
                    ForEach(entries, id: \.self) { entry in
                        Text(entry)
                            .font(.system(.body, design: .monospaced))
                    }
                    .onDelete(perform: delete)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .contentMargins(.top, 8, for: .scrollContent)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("ignored senders")
        .navigationBarTitleDisplayMode(.inline)
        .tint(Theme.accent)
        .toolbar { EditButton().tint(Theme.accent) }
    }

    private func add() {
        let trimmed = newEntry.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !entries.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame })
        else { newEntry = ""; return }
        entries.append(trimmed)
        IgnoredSenderStore.save(entries)
        // Re-read so the stored, de-duplicated/trimmed form is what's shown.
        entries = IgnoredSenderStore.load()
        newEntry = ""
        fieldFocused = false
    }

    private func delete(at offsets: IndexSet) {
        entries.remove(atOffsets: offsets)
        IgnoredSenderStore.save(entries)
    }
}

// MARK: - Auto-flag setup instructions

/// Walks the user through creating the two iOS Personal Automations that drive auto-flagging.
/// The app can't install automations itself, so this explains the steps and offers a button
/// to jump to the Shortcuts app.
private struct AutoFlagSetupView: View {
    var body: some View {
        Form {
            Section {
                Text("ios can auto-track messages for apple's own apps only — imessage/sms and mail. everything else you flag yourself from the widget or share sheet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                step(1, "open the shortcuts app → automation tab → + → create personal automation.")
                step(2, "pick “message” (or “email”). for mail, point it at the account(s) you want — leave your spam account out.")
                step(3, "choose “run immediately”, then add action → search “track a reply reminder”.")
                step(4, "set which app to “messages” (or “mail”), and pass the sender in as “from who?”.")
                step(5, "done. exclude 2fa bots and other noise under “ignored senders”.")
            } header: {
                sectionHeader("set up the automation")
            }

            Section {
                Link(destination: URL(string: "shortcuts://")!) {
                    Label("open shortcuts", systemImage: "arrow.up.forward.app")
                }
                .tint(Theme.accent)
            }
        }
        .scrollContentBackground(.hidden)
        .contentMargins(.top, 8, for: .scrollContent)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("auto-flag setup")
        .navigationBarTitleDisplayMode(.inline)
        .tint(Theme.accent)
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number)")
                .font(.system(.footnote, design: .monospaced).bold())
                .foregroundStyle(Theme.accent)
            Text(text)
                .font(.footnote)
        }
        .padding(.vertical, 2)
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(.footnote, design: .monospaced))
            .textCase(nil)
    }
}
