import Foundation

/// A platform the user can quick-flag a message from (rendered as a button in the
/// Quick Flag widget). Shared between the app (configuration) and the widget (display).
struct FlagPlatform: Codable, Identifiable, Equatable, Hashable {
    var name: String
    var icon: String   // SF Symbol name

    var id: String { name }
}

/// The menu of platforms the user can choose from, plus selection rules.
enum PlatformCatalog {
    static let maxSelection = 16

    /// Common messaging surfaces. SF Symbols are approximations — Apple ships no
    /// third-party brand glyphs — chosen to be visually distinct.
    static let all: [FlagPlatform] = [
        FlagPlatform(name: "WhatsApp",  icon: "phone.fill"),
        FlagPlatform(name: "Telegram",  icon: "paperplane.fill"),
        FlagPlatform(name: "Signal",    icon: "lock.shield.fill"),
        FlagPlatform(name: "Discord",   icon: "bubble.left.and.bubble.right.fill"),
        FlagPlatform(name: "Instagram", icon: "camera.fill"),
        FlagPlatform(name: "Messenger", icon: "message.fill"),
        // Apple's own messaging surfaces — the only ones a Shortcuts automation can auto-flag
        // on receipt (see CreateReminderIntent). Placed after the first five so the default
        // widget selection (prefix(5)) is unchanged.
        FlagPlatform(name: "Messages",  icon: "text.bubble.fill"),
        FlagPlatform(name: "Mail",      icon: "envelope.badge.fill"),
        FlagPlatform(name: "Snapchat",  icon: "bolt.fill"),
        FlagPlatform(name: "Slack",     icon: "number.square.fill"),
        FlagPlatform(name: "Teams",     icon: "person.2.fill"),
        FlagPlatform(name: "X",         icon: "at"),
        FlagPlatform(name: "TikTok",    icon: "music.note"),
        FlagPlatform(name: "Reddit",    icon: "antenna.radiowaves.left.and.right"),
        FlagPlatform(name: "LinkedIn",  icon: "briefcase.fill"),
        FlagPlatform(name: "Gmail",     icon: "envelope.fill"),
        FlagPlatform(name: "Facebook",  icon: "f.square.fill"),
        FlagPlatform(name: "Threads",   icon: "at.circle.fill"),
        FlagPlatform(name: "WeChat",    icon: "message.circle.fill"),
        FlagPlatform(name: "Line",      icon: "bubble.left.fill"),
        FlagPlatform(name: "Viber",     icon: "phone.circle.fill"),
        FlagPlatform(name: "KakaoTalk", icon: "ellipsis.bubble.fill"),
        FlagPlatform(name: "Mastodon",  icon: "number.circle.fill"),
        FlagPlatform(name: "YouTube",   icon: "play.rectangle.fill"),
        FlagPlatform(name: "Pinterest", icon: "pin.fill"),
        FlagPlatform(name: "Outlook",   icon: "envelope.circle.fill"),
        FlagPlatform(name: "Tumblr",    icon: "t.square.fill"),
        FlagPlatform(name: "Hinge",     icon: "heart.fill"),
        FlagPlatform(name: "Bumble",    icon: "heart.circle.fill"),
        FlagPlatform(name: "Tinder",    icon: "flame.fill"),
        FlagPlatform(name: "Grindr",    icon: "location.circle.fill"),
        FlagPlatform(name: "eBay",      icon: "tag.fill"),
        FlagPlatform(name: "Etsy",      icon: "cart.fill"),
        FlagPlatform(name: "Depop",     icon: "bag.fill"),
        FlagPlatform(name: "Airbnb",    icon: "house.circle.fill"),
        FlagPlatform(name: "Venmo",     icon: "dollarsign.circle.fill"),
        FlagPlatform(name: "PayPal",    icon: "p.circle.fill"),
        FlagPlatform(name: "Safari",     icon: "safari.fill"),
        FlagPlatform(name: "Chrome",     icon: "globe"),
        FlagPlatform(name: "Firefox",    icon: "globe.americas.fill"),
        FlagPlatform(name: "Edge",       icon: "globe.europe.africa.fill"),
        FlagPlatform(name: "Brave",      icon: "shield.lefthalf.filled"),
        FlagPlatform(name: "DuckDuckGo", icon: "magnifyingglass.circle.fill"),
        FlagPlatform(name: "Voicemail", icon: "recordingtape"),
    ]

    /// Sensible starting set before the user customizes anything.
    static let defaultSelection: [FlagPlatform] = Array(all.prefix(5))
}

/// Reads/writes the user's chosen platforms to the shared App Group so the app and
/// widget always agree. Stored as JSON under `selectedPlatformsKey`.
enum PlatformStore {
    static func load() -> [FlagPlatform] {
        guard let data = AppConstants.sharedDefaults.data(forKey: AppConstants.selectedPlatformsKey),
              let list = try? JSONDecoder().decode([FlagPlatform].self, from: data),
              !list.isEmpty
        else { return PlatformCatalog.defaultSelection }
        return list
    }

    static func save(_ platforms: [FlagPlatform]) {
        let trimmed = Array(platforms.prefix(PlatformCatalog.maxSelection))
        guard let data = try? JSONEncoder().encode(trimmed) else { return }
        AppConstants.sharedDefaults.set(data, forKey: AppConstants.selectedPlatformsKey)
    }
}

/// User-added apps that aren't in the catalog. Persisted on their own (separate from the
/// chosen widget slots) so they stick around in the palette even when not slotted.
enum CustomAppStore {
    static func load() -> [FlagPlatform] {
        guard let data = AppConstants.sharedDefaults.data(forKey: AppConstants.customPlatformsKey),
              let list = try? JSONDecoder().decode([FlagPlatform].self, from: data)
        else { return [] }
        return list
    }

    static func save(_ apps: [FlagPlatform]) {
        guard let data = try? JSONEncoder().encode(apps) else { return }
        AppConstants.sharedDefaults.set(data, forKey: AppConstants.customPlatformsKey)
    }
}

/// Senders whose auto-flagged Messages/Mail should be dropped — e.g. a spam email account,
/// or the shortcodes/bots that send 2FA codes. Consulted by `CreateReminderIntent` (the
/// Shortcuts auto-flag path) before it tracks anything: a match is silently ignored, so no
/// reminder is created and nothing nags. Stored as a JSON list of patterns in the shared
/// App Group — the app edits the list, the intent reads it.
///
/// A pattern matches a sender when:
/// - it starts with "@" — an email domain, matching any address containing it
///   (e.g. "@spam.com" ignores "deals@spam.com");
/// - it otherwise contains "@" — a full email address, matched case-insensitively;
/// - it looks like a phone number/shortcode (only digits and `+()-. `) — matched on digits
///   only, ignoring formatting, where either side's digits end with the other's (so
///   "+1 (555) 123-4567" and "5551234567" are the same, and a shortcode matches itself);
/// - otherwise — a sender name, matched case-insensitively in full.
enum IgnoredSenderStore {
    static func load() -> [String] {
        guard let data = AppConstants.sharedDefaults.data(forKey: AppConstants.ignoredSendersKey),
              let list = try? JSONDecoder().decode([String].self, from: data)
        else { return [] }
        return list
    }

    static func save(_ patterns: [String]) {
        // Trim, drop blanks, and de-duplicate (case-insensitively) so the list stays tidy.
        var seen = Set<String>()
        let cleaned = patterns
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
        guard let data = try? JSONEncoder().encode(cleaned) else { return }
        AppConstants.sharedDefaults.set(data, forKey: AppConstants.ignoredSendersKey)
    }

    /// Whether `sender` matches any ignore pattern and should be dropped.
    static func isIgnored(_ sender: String?) -> Bool {
        guard let raw = sender?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !raw.isEmpty else { return false }
        let senderDigits = raw.filter(\.isNumber)

        return load().contains { pattern in
            let p = pattern.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !p.isEmpty else { return false }

            if p.contains("@") {                  // email domain ("@x.com") or full address
                return raw.contains(p)
            }
            // Phone number or shortcode? (only digits and common separators)
            let pDigits = p.filter(\.isNumber)
            let phoneLike = !pDigits.isEmpty && p.allSatisfy { $0.isNumber || "+()-. ".contains($0) }
            if phoneLike, pDigits.count >= 4, !senderDigits.isEmpty {
                return senderDigits.hasSuffix(pDigits) || pDigits.hasSuffix(senderDigits)
            }
            return raw == p                       // sender name (exact, case-insensitive)
        }
    }
}

/// Reminder intervals (in minutes). One global fallback plus optional per-app overrides,
/// stored in the shared App Group so the app, widget, and intents all resolve the same value.
enum IntervalStore {
    /// The interval choices offered everywhere (in minutes), in order. The single source of
    /// truth for the pickers in Settings, app-specific intervals, and the compose form.
    static let options: [(label: String, minutes: Int)] = [
        ("30 min", 30),
        ("1 hour", 60),
        ("2 hours", 120),
        ("4 hours", 240),
        ("8 hours", 480),
        ("12 hours", 720),
        ("1 day", 1440),
        ("every other day", 2880),
        ("every 3 days", 4320),
        ("every week", 10080),
    ]

    /// The default interval used when nothing is stored yet.
    static let defaultMinutes = 30

    /// The fallback interval used by any app without its own override.
    static var global: Int {
        let stored = AppConstants.sharedDefaults.integer(forKey: AppConstants.defaultIntervalKey)
        return stored > 0 ? stored : defaultMinutes
    }

    /// Snaps a value to a valid option, mapping any retired/unknown interval (e.g. an old
    /// 1- or 15-minute reminder) to the default so pickers always have a real selection.
    static func normalized(_ minutes: Int) -> Int {
        options.contains { $0.minutes == minutes } ? minutes : defaultMinutes
    }

    /// The label for a given interval, falling back to a sensible derived string for any
    /// value that isn't one of the standard options.
    static func label(for minutes: Int) -> String {
        if let match = options.first(where: { $0.minutes == minutes }) { return match.label }
        if minutes < 60 { return "\(minutes) min" }
        if minutes % 1440 == 0 { return "\(minutes / 1440) days" }
        return "\(minutes / 60) hours"
    }

    /// One-time cleanup of stale values left by older builds (e.g. the retired 1-minute and
    /// 15-minute choices) so the pickers never show a blank or no-longer-offered selection.
    /// Resets an invalid global default to `defaultMinutes` and drops invalid per-app overrides.
    static func sanitize() {
        let valid = Set(options.map(\.minutes))
        let defaults = AppConstants.sharedDefaults

        let storedGlobal = defaults.integer(forKey: AppConstants.defaultIntervalKey)
        if storedGlobal > 0 && !valid.contains(storedGlobal) {
            defaults.set(defaultMinutes, forKey: AppConstants.defaultIntervalKey)
        }

        let current = overrides()
        let cleaned = current.filter { valid.contains($0.value) }
        if cleaned.count != current.count, let data = try? JSONEncoder().encode(cleaned) {
            defaults.set(data, forKey: AppConstants.appIntervalsKey)
        }
    }

    /// Per-app overrides, keyed by app name. Apps absent here use the global interval.
    static func overrides() -> [String: Int] {
        guard let data = AppConstants.sharedDefaults.data(forKey: AppConstants.appIntervalsKey),
              let dict = try? JSONDecoder().decode([String: Int].self, from: data)
        else { return [:] }
        return dict
    }

    /// The interval to use for an app: its override if set, otherwise the global interval.
    static func interval(for app: String?) -> Int {
        if let app, let value = overrides()[app] { return value }
        return global
    }

    /// Sets (or, with nil, clears) an app's override.
    static func setOverride(_ minutes: Int?, for app: String) {
        var all = overrides()
        if let minutes { all[app] = minutes } else { all.removeValue(forKey: app) }
        guard let data = try? JSONEncoder().encode(all) else { return }
        AppConstants.sharedDefaults.set(data, forKey: AppConstants.appIntervalsKey)
    }
}

/// Notification "strength": whether a reminder breaks through Do Not Disturb / Focus
/// (delivered time-sensitive) or quietly respects it. One default plus optional per-app
/// overrides, stored in the shared App Group so the app, widget, and intents all resolve
/// the same value. `true` = ignore Do Not Disturb, which is the app's default.
enum StrengthStore {
    /// The default strength used by any app without its own override. Defaults to `true`
    /// (ignore Do Not Disturb) until the user turns it off.
    static var global: Bool {
        AppConstants.sharedDefaults.object(forKey: AppConstants.defaultStrengthKey) as? Bool ?? true
    }

    /// Per-app overrides, keyed by app name. Apps absent here use the default strength.
    static func overrides() -> [String: Bool] {
        guard let data = AppConstants.sharedDefaults.data(forKey: AppConstants.appStrengthsKey),
              let dict = try? JSONDecoder().decode([String: Bool].self, from: data)
        else { return [:] }
        return dict
    }

    /// Whether reminders for an app should ignore Do Not Disturb: its override if set,
    /// otherwise the default strength.
    static func ignoresDoNotDisturb(for app: String?) -> Bool {
        if let app, let value = overrides()[app] { return value }
        return global
    }

    /// Sets (or, with nil, clears) an app's override.
    static func setOverride(_ ignore: Bool?, for app: String) {
        var all = overrides()
        if let ignore { all[app] = ignore } else { all.removeValue(forKey: app) }
        guard let data = try? JSONEncoder().encode(all) else { return }
        AppConstants.sharedDefaults.set(data, forKey: AppConstants.appStrengthsKey)
    }
}

/// Global "pause all" snooze, stored as a timestamp in the shared App Group so the app,
/// widget, and intents all honour the same pause. `.distantFuture` means paused
/// indefinitely. This is the single source of truth that everything scheduling a
/// notification consults before doing so.
enum SnoozeStore {
    /// The instant until which every reminder is paused, or nil when not snoozing
    /// (including after a finite snooze has quietly expired).
    static var snoozeUntil: Date? {
        let timestamp = AppConstants.sharedDefaults.double(forKey: AppConstants.globalSnoozeUntilKey)
        guard timestamp > 0 else { return nil }
        let until = Date(timeIntervalSince1970: timestamp)
        return until > Date() ? until : nil
    }

    /// Whether reminders are currently paused.
    static var isSnoozed: Bool { snoozeUntil != nil }

    /// Remove a finished finite-pause timestamp so it doesn't linger in shared defaults.
    /// `snoozeUntil` already treats a past timestamp as "not snoozing"; this just tidies up.
    /// `.distantFuture` (indefinite pause) is left alone.
    static func clearExpiredSnooze() {
        let ts = AppConstants.sharedDefaults.double(forKey: AppConstants.globalSnoozeUntilKey)
        if ts > 0, Date(timeIntervalSince1970: ts) <= Date() {
            AppConstants.sharedDefaults.removeObject(forKey: AppConstants.globalSnoozeUntilKey)
        }
    }

    // MARK: - Pause history (for the nag counter)

    /// A single past or ongoing "pause all" interval, in unix timestamps. Recorded so the
    /// "bothered you" counter can exclude time the user was paused — nothing nags during a
    /// pause, so that time shouldn't count toward how often a reminder bothered them.
    private struct PauseWindow: Codable { var start: Double; var end: Double }

    private static func pauseWindows() -> [PauseWindow] {
        guard let data = AppConstants.sharedDefaults.data(forKey: AppConstants.pauseWindowsKey),
              let list = try? JSONDecoder().decode([PauseWindow].self, from: data)
        else { return [] }
        return list
    }

    private static func savePauseWindows(_ list: [PauseWindow]) {
        // Bound the ledger; pauses are user-initiated and infrequent, so this is plenty.
        let trimmed = Array(list.suffix(200))
        guard let data = try? JSONEncoder().encode(trimmed) else { return }
        AppConstants.sharedDefaults.set(data, forKey: AppConstants.pauseWindowsKey)
    }

    /// Record the start of a pause that's planned to run until `end`. When the user adjusts
    /// the duration of a pause that's already running (`wasPaused`), we extend the current
    /// window's end instead of opening a new one.
    static func beginPause(until end: Date, wasPaused: Bool) {
        var list = pauseWindows()
        let endTS = end.timeIntervalSince1970
        if wasPaused, var last = list.last {
            last.end = endTS
            list[list.count - 1] = last
        } else {
            list.append(PauseWindow(start: Date().timeIntervalSince1970, end: endTS))
        }
        savePauseWindows(list)
    }

    /// Close the current pause early (slider slid back to "active"), capping its end at now.
    static func endPause(at date: Date) {
        var list = pauseWindows()
        guard var last = list.last else { return }
        last.end = min(last.end, date.timeIntervalSince1970)
        list[list.count - 1] = last
        savePauseWindows(list)
    }

    /// Total seconds within `[start, end]` that fell inside a pause window. A finite pause
    /// that ran its course keeps its planned end; an ongoing pause overlaps only up to `end`
    /// (typically "now"), so the counter freezes for the duration of the pause.
    static func pausedSeconds(from start: Date, to end: Date) -> TimeInterval {
        let lo0 = start.timeIntervalSince1970
        let hi0 = end.timeIntervalSince1970
        guard hi0 > lo0 else { return 0 }
        return pauseWindows().reduce(0) { total, window in
            let lo = max(lo0, window.start)
            let hi = min(hi0, window.end)
            return hi > lo ? total + (hi - lo) : total
        }
    }
}
