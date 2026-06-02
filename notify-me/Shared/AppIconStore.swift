import Foundation

/// On-disk cache (in the shared App Group) for official app icons fetched at runtime
/// from Apple's public iTunes Search API. The app downloads them; both the app and the
/// widget read the cached PNGs. Nothing copyrighted is bundled in the project — icons
/// live only on-device, loaded from Apple's CDN, with an SF Symbol fallback.
enum AppIconStore {
    static var directory: URL {
        let url = AppConstants.sharedContainerURL.appendingPathComponent("Icons", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func fileURL(for name: String) -> URL {
        let safe = name.lowercased()
            .replacingOccurrences(of: "[^a-z0-9]", with: "-", options: .regularExpression)
        return directory.appendingPathComponent("\(safe).png")
    }

    static func cachedData(for name: String) -> Data? {
        let url = fileURL(for: name)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try? Data(contentsOf: url)
    }

    /// Curated App Store search terms to improve match accuracy for ambiguous names.
    /// Empty string = no App Store lookup (use the SF Symbol fallback).
    static let searchTerms: [String: String] = [
        "WhatsApp": "WhatsApp Messenger",
        "Telegram": "Telegram Messenger",
        "Signal": "Signal Private Messenger",
        "Discord": "Discord",
        "Instagram": "Instagram",
        "Messenger": "Messenger",
        "Snapchat": "Snapchat",
        "Slack": "Slack",
        "Teams": "Microsoft Teams",
        "X": "X formerly Twitter",
        "TikTok": "TikTok",
        "Reddit": "Reddit",
        "LinkedIn": "LinkedIn",
        "Gmail": "Gmail email by Google",
        "Hinge": "Hinge Dating App",
        "Bumble": "Bumble Dating",
        "Tinder": "Tinder Dating App",
        "Marketplace": "Facebook",
        "Voicemail": "",
    ]

    static func searchTerm(for name: String) -> String {
        searchTerms[name] ?? ""
    }
}
