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
    static let maxSelection = 8

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
        FlagPlatform(name: "Hinge",     icon: "heart.fill"),
        FlagPlatform(name: "Bumble",    icon: "heart.circle.fill"),
        FlagPlatform(name: "Tinder",    icon: "flame.fill"),
        FlagPlatform(name: "Marketplace", icon: "cart.fill"),
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
