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
        FlagPlatform(name: "BeReal",    icon: "camera.aperture"),
        FlagPlatform(name: "Twitch",    icon: "gamecontroller.fill"),
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

/// Reminder intervals (in minutes). One global fallback plus optional per-app overrides,
/// stored in the shared App Group so the app, widget, and intents all resolve the same value.
enum IntervalStore {
    /// The fallback interval used by any app without its own override.
    static var global: Int {
        let stored = AppConstants.sharedDefaults.integer(forKey: AppConstants.defaultIntervalKey)
        return stored > 0 ? stored : 60
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
