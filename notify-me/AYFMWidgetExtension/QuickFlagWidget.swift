import WidgetKit
import SwiftUI
import AppIntents

struct QuickFlagWidget: Widget {
    let kind = "QuickFlagWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: QuickFlagTimelineProvider()) { entry in
            QuickFlagWidgetView(entry: entry)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Quick Flag")
        .description("Flag messages for reply reminders")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct QuickFlagEntry: TimelineEntry {
    let date: Date
}

struct QuickFlagTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuickFlagEntry {
        QuickFlagEntry(date: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping (QuickFlagEntry) -> Void) {
        completion(QuickFlagEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<QuickFlagEntry>) -> Void) {
        completion(Timeline(entries: [QuickFlagEntry(date: .now)], policy: .never))
    }
}

struct QuickFlagWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: QuickFlagEntry

    // The user's chosen platforms, configured in the app and shared via the App Group.
    // iMessage/Mail are handled automatically elsewhere, so they aren't listed here.
    private var platforms: [FlagPlatform] { PlatformStore.load() }

    /// Columns of apps for the current family.
    private var columnCount: Int {
        family == .systemSmall ? 2 : 5
    }

    /// Rows of apps per page. Both families use two rows — square: 2×2 = 4 per page,
    /// medium: 5×2 = 10 per page.
    private var rowCount: Int { 2 }

    /// Apps shown per page for the current family.
    private var pageSize: Int { columnCount * rowCount }

    /// Number of pages needed to show every selected app at the current page size. Either
    /// family paginates once its apps overflow a page; the medium widget only does so when
    /// more than ten apps are selected, which the picker currently caps below.
    private var pageCount: Int {
        max(1, Int(ceil(Double(platforms.count) / Double(pageSize))))
    }

    /// Current page, clamped in case the selection shrank since it was last set.
    private var currentPage: Int {
        let stored = AppConstants.sharedDefaults.integer(forKey: AppConstants.widgetPageKey)
        return min(max(0, stored), pageCount - 1)
    }

    /// The slice of apps to show for the current family/page.
    private var shown: [FlagPlatform] {
        let start = currentPage * pageSize
        guard start < platforms.count else { return [] }
        return Array(platforms[start..<min(start + pageSize, platforms.count)])
    }

    /// The app's own brand accent — amber (#F5A623) — used for every app's outline.
    private let accent = Color(red: 0.961, green: 0.651, blue: 0.137)

    /// A soft warm off-white (#F4ECDE) for the logo art — gentler than pure white against
    /// the amber frame.
    private let logoTint = Color(red: 0.957, green: 0.925, blue: 0.871)

    var body: some View {
        // The square widget spreads its two columns wider apart; medium keeps five snug.
        let columnSpacing: CGFloat = family == .systemSmall ? 26 : 14
        let columns = Array(
            repeating: GridItem(.flexible(), spacing: columnSpacing),
            count: columnCount
        )

        VStack(spacing: 6) {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(shown) { platform in
                    Button(intent: ComposeReminderIntent(sourceApp: platform.name)) {
                        appCell(platform)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxHeight: .infinity)

            if pageCount > 1 {
                pageDots
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, family == .systemSmall ? 14 : 12)
        // Pin the "next page" arrow into the widget's bottom-right corner, clear of the
        // centred page dots.
        .overlay(alignment: .bottomTrailing) {
            if pageCount > 1 {
                pageArrow
                    .padding(.trailing, 2)
                    .padding(.bottom, 4)
            }
        }
    }

    /// One app: its logo, framed by an amber border floating just outside it (a small
    /// gap, so it never overlaps the logo).
    private func appCell(_ platform: FlagPlatform) -> some View {
        let iconRadius = iconSize * 0.28
        let gap: CGFloat = 5
        let interiorRadius = iconRadius + gap

        return platformIcon(platform)
            .frame(width: iconSize, height: iconSize)
            .padding(gap)
            .overlay(
                RoundedRectangle(cornerRadius: interiorRadius, style: .continuous)
                    .strokeBorder(accent, lineWidth: 2.5)
            )
    }

    /// Page-position dots, centred along the bottom (shown only while paging is active).
    private var pageDots: some View {
        HStack(spacing: 5) {
            ForEach(0..<pageCount, id: \.self) { index in
                Circle()
                    .fill(index == currentPage ? Color.primary : Color.secondary.opacity(0.35))
                    .frame(width: 6, height: 6)
            }
        }
    }

    /// "Next page" button, pinned to the widget's bottom-right corner by the caller.
    /// Kept compact so it tucks into the corner without overlapping the last app icon.
    private var pageArrow: some View {
        Button(intent: QuickFlagPageIntent(forward: true)) {
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 26, height: 18)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.secondary.opacity(0.18))
                )
        }
        .buttonStyle(.plain)
    }

    /// Icon edge length: square uses a moderate size so the outline reads as UI rather
    /// than a real app icon; medium stays compact so two rows of five fit comfortably.
    private var iconSize: CGFloat {
        family == .systemSmall ? 44 : 36
    }

    /// The app's logo, drawn in a soft off-white from its real brand silhouette (Snapchat's
    /// ghost, WhatsApp's bubble, X's mark…). We render our own monochrome version instead of
    /// the genuine multicolour app icon: it's recognisable as *that* app yet clearly part of
    /// *this* app — not a tappable shortcut into the real one. The amber comes from the
    /// surrounding frame in `appCell`. Apps we have no bundled logo for fall back to a
    /// tinted SF Symbol. Clipping/badge come from `appCell`.
    @ViewBuilder
    private func platformIcon(_ platform: FlagPlatform) -> some View {
        if let logo = BrandLogo.logo(for: platform.name) {
            let shape = BrandLogoShape(pathData: logo.pathData, viewBox: logo.viewBox)
            Group {
                switch logo.style {
                case .filled:
                    shape.fill(logoTint)
                case .stroked:
                    // Line-art logos (e.g. Bumble, Hinge) are drawn, not filled.
                    shape.stroke(
                        logoTint,
                        style: StrokeStyle(lineWidth: iconSize * 0.05, lineCap: .round, lineJoin: .round)
                    )
                }
            }
            .frame(width: iconSize * 0.62, height: iconSize * 0.62)
            .frame(width: iconSize, height: iconSize)
        } else {
            Image(systemName: outlineSymbol(for: platform))
                .font(.system(size: iconSize * 0.5, weight: .regular))
                .foregroundStyle(logoTint)
                .frame(width: iconSize, height: iconSize)
        }
    }

    /// The non-filled (outline) variant of the platform's SF Symbol, used for apps with
    /// no bundled brand logo so the glyph reads as line art rather than a solid shape.
    private func outlineSymbol(for platform: FlagPlatform) -> String {
        platform.icon.hasSuffix(".fill") ? String(platform.icon.dropLast(5)) : platform.icon
    }
}

// MARK: - Brand logos

/// Brand logos for the Quick Flag widget, drawn monochrome (tinted by the caller, never
/// the real multicolour artwork) so they read as part of this app. Two sources:
/// • filled silhouettes from Simple Icons (CC0 1.0, https://simpleicons.org), 24×24;
/// • line-art outlines from Arcticons (https://arcticons.com) for apps Simple Icons
///   lacks (Bumble, Hinge), 48×48, meant to be stroked rather than filled.
enum BrandLogo {
    /// How a logo is rendered: a solid silhouette, or a stroked line drawing.
    enum Style { case filled, stroked }

    struct Logo {
        let pathData: String
        let viewBox: CGFloat
        let style: Style
    }

    /// The logo for a platform name, or nil if we have none (those fall back to an SF
    /// Symbol). Keys match `FlagPlatform.name`.
    static func logo(for name: String) -> Logo? {
        if let d = filledPaths[name] { return Logo(pathData: d, viewBox: 24, style: .filled) }
        if let d = strokedPaths[name] { return Logo(pathData: d, viewBox: 48, style: .stroked) }
        return nil
    }

    /// Line-art logos meant to be stroked, not filled (48×48 viewBox).
    private static let strokedPaths: [String: String] = [
        "Bumble": "M12.65 24h22.7m-18.52-7.67h14.34M19.06 31.67h9.88 M32.75 5.84h-17.5a3 3 0 0 0-2.6 1.51L3.9 22.5a3 3 0 0 0 0 3l8.75 15.15a3 3 0 0 0 2.6 1.51h17.5a3 3 0 0 0 2.6-1.51L44.1 25.5a3 3 0 0 0 0-3L35.35 7.35a3 3 0 0 0-2.6-1.51Z",
        "Hinge": "M38.5 5.5h-29c-2.2 0-4 1.8-4 4v29c0 2.2 1.8 4 4 4h29c2.2 0 4-1.8 4-4v-29c0-2.2-1.8-4-4-4m-23.996 6v25m15.743-25v25 M14.504 28.318c2.912-5.75 5.59-4.886 15.743-4.897c4.353-.005 6.02-.455 7.849-3.287",
    ]

    /// Filled silhouette logos (24×24 viewBox).
    private static let filledPaths: [String: String] = [
        "WhatsApp": "M17.472 14.382c-.297-.149-1.758-.867-2.03-.967-.273-.099-.471-.148-.67.15-.197.297-.767.966-.94 1.164-.173.199-.347.223-.644.075-.297-.15-1.255-.463-2.39-1.475-.883-.788-1.48-1.761-1.653-2.059-.173-.297-.018-.458.13-.606.134-.133.298-.347.446-.52.149-.174.198-.298.298-.497.099-.198.05-.371-.025-.52-.075-.149-.669-1.612-.916-2.207-.242-.579-.487-.5-.669-.51-.173-.008-.371-.01-.57-.01-.198 0-.52.074-.792.372-.272.297-1.04 1.016-1.04 2.479 0 1.462 1.065 2.875 1.213 3.074.149.198 2.096 3.2 5.077 4.487.709.306 1.262.489 1.694.625.712.227 1.36.195 1.871.118.571-.085 1.758-.719 2.006-1.413.248-.694.248-1.289.173-1.413-.074-.124-.272-.198-.57-.347m-5.421 7.403h-.004a9.87 9.87 0 01-5.031-1.378l-.361-.214-3.741.982.998-3.648-.235-.374a9.86 9.86 0 01-1.51-5.26c.001-5.45 4.436-9.884 9.888-9.884 2.64 0 5.122 1.03 6.988 2.898a9.825 9.825 0 012.893 6.994c-.003 5.45-4.437 9.884-9.885 9.884m8.413-18.297A11.815 11.815 0 0012.05 0C5.495 0 .16 5.335.157 11.892c0 2.096.547 4.142 1.588 5.945L.057 24l6.305-1.654a11.882 11.882 0 005.683 1.448h.005c6.554 0 11.89-5.335 11.893-11.893a11.821 11.821 0 00-3.48-8.413Z",
        "Telegram": "M11.944 0A12 12 0 0 0 0 12a12 12 0 0 0 12 12 12 12 0 0 0 12-12A12 12 0 0 0 12 0a12 12 0 0 0-.056 0zm4.962 7.224c.1-.002.321.023.465.14a.506.506 0 0 1 .171.325c.016.093.036.306.02.472-.18 1.898-.962 6.502-1.36 8.627-.168.9-.499 1.201-.82 1.23-.696.065-1.225-.46-1.9-.902-1.056-.693-1.653-1.124-2.678-1.8-1.185-.78-.417-1.21.258-1.91.177-.184 3.247-2.977 3.307-3.23.007-.032.014-.15-.056-.212s-.174-.041-.249-.024c-.106.024-1.793 1.14-5.061 3.345-.48.33-.913.49-1.302.48-.428-.008-1.252-.241-1.865-.44-.752-.245-1.349-.374-1.297-.789.027-.216.325-.437.893-.663 3.498-1.524 5.83-2.529 6.998-3.014 3.332-1.386 4.025-1.627 4.476-1.635z",
        "Signal": "M12 0q-.934 0-1.83.139l.17 1.111a11 11 0 0 1 3.32 0l.172-1.111A12 12 0 0 0 12 0M9.152.34A12 12 0 0 0 5.77 1.742l.584.961a10.8 10.8 0 0 1 3.066-1.27zm5.696 0-.268 1.094a10.8 10.8 0 0 1 3.066 1.27l.584-.962A12 12 0 0 0 14.848.34M12 2.25a9.75 9.75 0 0 0-8.539 14.459c.074.134.1.292.064.441l-1.013 4.338 4.338-1.013a.62.62 0 0 1 .441.064A9.7 9.7 0 0 0 12 21.75c5.385 0 9.75-4.365 9.75-9.75S17.385 2.25 12 2.25m-7.092.068a12 12 0 0 0-2.59 2.59l.909.664a11 11 0 0 1 2.345-2.345zm14.184 0-.664.909a11 11 0 0 1 2.345 2.345l.909-.664a12 12 0 0 0-2.59-2.59M1.742 5.77A12 12 0 0 0 .34 9.152l1.094.268a10.8 10.8 0 0 1 1.269-3.066zm20.516 0-.961.584a10.8 10.8 0 0 1 1.27 3.066l1.093-.268a12 12 0 0 0-1.402-3.383M.138 10.168A12 12 0 0 0 0 12q0 .934.139 1.83l1.111-.17A11 11 0 0 1 1.125 12q0-.848.125-1.66zm23.723.002-1.111.17q.125.812.125 1.66c0 .848-.042 1.12-.125 1.66l1.111.172a12.1 12.1 0 0 0 0-3.662M1.434 14.58l-1.094.268a12 12 0 0 0 .96 2.591l-.265 1.14 1.096.255.36-1.539-.188-.365a10.8 10.8 0 0 1-.87-2.35m21.133 0a10.8 10.8 0 0 1-1.27 3.067l.962.584a12 12 0 0 0 1.402-3.383zm-1.793 3.848a11 11 0 0 1-2.345 2.345l.664.909a12 12 0 0 0 2.59-2.59zm-19.959 1.1L.357 21.48a1.8 1.8 0 0 0 2.162 2.161l1.954-.455-.256-1.095-1.953.455a.675.675 0 0 1-.81-.81l.454-1.954zm16.832 1.769a10.8 10.8 0 0 1-3.066 1.27l.268 1.093a12 12 0 0 0 3.382-1.402zm-10.94.213-1.54.36.256 1.095 1.139-.266c.814.415 1.683.74 2.591.961l.268-1.094a10.8 10.8 0 0 1-2.35-.869zm3.634 1.24-.172 1.111a12.1 12.1 0 0 0 3.662 0l-.17-1.111q-.812.125-1.66.125a11 11 0 0 1-1.66-.125",
        "Discord": "M20.317 4.3698a19.7913 19.7913 0 00-4.8851-1.5152.0741.0741 0 00-.0785.0371c-.211.3753-.4447.8648-.6083 1.2495-1.8447-.2762-3.68-.2762-5.4868 0-.1636-.3933-.4058-.8742-.6177-1.2495a.077.077 0 00-.0785-.037 19.7363 19.7363 0 00-4.8852 1.515.0699.0699 0 00-.0321.0277C.5334 9.0458-.319 13.5799.0992 18.0578a.0824.0824 0 00.0312.0561c2.0528 1.5076 4.0413 2.4228 5.9929 3.0294a.0777.0777 0 00.0842-.0276c.4616-.6304.8731-1.2952 1.226-1.9942a.076.076 0 00-.0416-.1057c-.6528-.2476-1.2743-.5495-1.8722-.8923a.077.077 0 01-.0076-.1277c.1258-.0943.2517-.1923.3718-.2914a.0743.0743 0 01.0776-.0105c3.9278 1.7933 8.18 1.7933 12.0614 0a.0739.0739 0 01.0785.0095c.1202.099.246.1981.3728.2924a.077.077 0 01-.0066.1276 12.2986 12.2986 0 01-1.873.8914.0766.0766 0 00-.0407.1067c.3604.698.7719 1.3628 1.225 1.9932a.076.076 0 00.0842.0286c1.961-.6067 3.9495-1.5219 6.0023-3.0294a.077.077 0 00.0313-.0552c.5004-5.177-.8382-9.6739-3.5485-13.6604a.061.061 0 00-.0312-.0286zM8.02 15.3312c-1.1825 0-2.1569-1.0857-2.1569-2.419 0-1.3332.9555-2.4189 2.157-2.4189 1.2108 0 2.1757 1.0952 2.1568 2.419 0 1.3332-.9555 2.4189-2.1569 2.4189zm7.9748 0c-1.1825 0-2.1569-1.0857-2.1569-2.419 0-1.3332.9554-2.4189 2.1569-2.4189 1.2108 0 2.1757 1.0952 2.1568 2.419 0 1.3332-.946 2.4189-2.1568 2.4189Z",
        "Instagram": "M7.0301.084c-1.2768.0602-2.1487.264-2.911.5634-.7888.3075-1.4575.72-2.1228 1.3877-.6652.6677-1.075 1.3368-1.3802 2.127-.2954.7638-.4956 1.6365-.552 2.914-.0564 1.2775-.0689 1.6882-.0626 4.947.0062 3.2586.0206 3.6671.0825 4.9473.061 1.2765.264 2.1482.5635 2.9107.308.7889.72 1.4573 1.388 2.1228.6679.6655 1.3365 1.0743 2.1285 1.38.7632.295 1.6361.4961 2.9134.552 1.2773.056 1.6884.069 4.9462.0627 3.2578-.0062 3.668-.0207 4.9478-.0814 1.28-.0607 2.147-.2652 2.9098-.5633.7889-.3086 1.4578-.72 2.1228-1.3881.665-.6682 1.0745-1.3378 1.3795-2.1284.2957-.7632.4966-1.636.552-2.9124.056-1.2809.0692-1.6898.063-4.948-.0063-3.2583-.021-3.6668-.0817-4.9465-.0607-1.2797-.264-2.1487-.5633-2.9117-.3084-.7889-.72-1.4568-1.3876-2.1228C21.2982 1.33 20.628.9208 19.8378.6165 19.074.321 18.2017.1197 16.9244.0645 15.6471.0093 15.236-.005 11.977.0014 8.718.0076 8.31.0215 7.0301.0839m.1402 21.6932c-1.17-.0509-1.8053-.2453-2.2287-.408-.5606-.216-.96-.4771-1.3819-.895-.422-.4178-.6811-.8186-.9-1.378-.1644-.4234-.3624-1.058-.4171-2.228-.0595-1.2645-.072-1.6442-.079-4.848-.007-3.2037.0053-3.583.0607-4.848.05-1.169.2456-1.805.408-2.2282.216-.5613.4762-.96.895-1.3816.4188-.4217.8184-.6814 1.3783-.9003.423-.1651 1.0575-.3614 2.227-.4171 1.2655-.06 1.6447-.072 4.848-.079 3.2033-.007 3.5835.005 4.8495.0608 1.169.0508 1.8053.2445 2.228.408.5608.216.96.4754 1.3816.895.4217.4194.6816.8176.9005 1.3787.1653.4217.3617 1.056.4169 2.2263.0602 1.2655.0739 1.645.0796 4.848.0058 3.203-.0055 3.5834-.061 4.848-.051 1.17-.245 1.8055-.408 2.2294-.216.5604-.4763.96-.8954 1.3814-.419.4215-.8181.6811-1.3783.9-.4224.1649-1.0577.3617-2.2262.4174-1.2656.0595-1.6448.072-4.8493.079-3.2045.007-3.5825-.006-4.848-.0608M16.953 5.5864A1.44 1.44 0 1 0 18.39 4.144a1.44 1.44 0 0 0-1.437 1.4424M5.8385 12.012c.0067 3.4032 2.7706 6.1557 6.173 6.1493 3.4026-.0065 6.157-2.7701 6.1506-6.1733-.0065-3.4032-2.771-6.1565-6.174-6.1498-3.403.0067-6.156 2.771-6.1496 6.1738M8 12.0077a4 4 0 1 1 4.008 3.9921A3.9996 3.9996 0 0 1 8 12.0077",
        "Messenger": "M12 0C5.24 0 0 4.952 0 11.64c0 3.499 1.434 6.521 3.769 8.61a.96.96 0 0 1 .323.683l.065 2.135a.96.96 0 0 0 1.347.85l2.381-1.053a.96.96 0 0 1 .641-.046A13 13 0 0 0 12 23.28c6.76 0 12-4.952 12-11.64S18.76 0 12 0m6.806 7.44c.522-.03.971.567.63 1.094l-4.178 6.457a.707.707 0 0 1-.977.208l-3.87-2.504a.44.44 0 0 0-.49.007l-4.363 3.01c-.637.438-1.415-.317-.995-.966l4.179-6.457a.706.706 0 0 1 .977-.21l3.87 2.505c.15.097.344.094.491-.007l4.362-3.008a.7.7 0 0 1 .364-.13",
        "Snapchat": "M12.206.793c.99 0 4.347.276 5.93 3.821.529 1.193.403 3.219.299 4.847l-.003.06c-.012.18-.022.345-.03.51.075.045.203.09.401.09.3-.016.659-.12 1.033-.301.165-.088.344-.104.464-.104.182 0 .359.029.509.09.45.149.734.479.734.838.015.449-.39.839-1.213 1.168-.089.029-.209.075-.344.119-.45.135-1.139.36-1.333.81-.09.224-.061.524.12.868l.015.015c.06.136 1.526 3.475 4.791 4.014.255.044.435.27.42.509 0 .075-.015.149-.045.225-.24.569-1.273.988-3.146 1.271-.059.091-.12.375-.164.57-.029.179-.074.36-.134.553-.076.271-.27.405-.555.405h-.03c-.135 0-.313-.031-.538-.074-.36-.075-.765-.135-1.273-.135-.3 0-.599.015-.913.074-.6.104-1.123.464-1.723.884-.853.599-1.826 1.288-3.294 1.288-.06 0-.119-.015-.18-.015h-.149c-1.468 0-2.427-.675-3.279-1.288-.599-.42-1.107-.779-1.707-.884-.314-.045-.629-.074-.928-.074-.54 0-.958.089-1.272.149-.211.043-.391.074-.54.074-.374 0-.523-.224-.583-.42-.061-.192-.09-.389-.135-.567-.046-.181-.105-.494-.166-.57-1.918-.222-2.95-.642-3.189-1.226-.031-.063-.052-.15-.055-.225-.015-.243.165-.465.42-.509 3.264-.54 4.73-3.879 4.791-4.02l.016-.029c.18-.345.224-.645.119-.869-.195-.434-.884-.658-1.332-.809-.121-.029-.24-.074-.346-.119-1.107-.435-1.257-.93-1.197-1.273.09-.479.674-.793 1.168-.793.146 0 .27.029.383.074.42.194.789.3 1.104.3.234 0 .384-.06.465-.105l-.046-.569c-.098-1.626-.225-3.651.307-4.837C7.392 1.077 10.739.807 11.727.807l.419-.015h.06z",
        "Slack": "M5.042 15.165a2.528 2.528 0 0 1-2.52 2.523A2.528 2.528 0 0 1 0 15.165a2.527 2.527 0 0 1 2.522-2.52h2.52v2.52zM6.313 15.165a2.527 2.527 0 0 1 2.521-2.52 2.527 2.527 0 0 1 2.521 2.52v6.313A2.528 2.528 0 0 1 8.834 24a2.528 2.528 0 0 1-2.521-2.522v-6.313zM8.834 5.042a2.528 2.528 0 0 1-2.521-2.52A2.528 2.528 0 0 1 8.834 0a2.528 2.528 0 0 1 2.521 2.522v2.52H8.834zM8.834 6.313a2.528 2.528 0 0 1 2.521 2.521 2.528 2.528 0 0 1-2.521 2.521H2.522A2.528 2.528 0 0 1 0 8.834a2.528 2.528 0 0 1 2.522-2.521h6.312zM18.956 8.834a2.528 2.528 0 0 1 2.522-2.521A2.528 2.528 0 0 1 24 8.834a2.528 2.528 0 0 1-2.522 2.521h-2.522V8.834zM17.688 8.834a2.528 2.528 0 0 1-2.523 2.521 2.527 2.527 0 0 1-2.52-2.521V2.522A2.527 2.527 0 0 1 15.165 0a2.528 2.528 0 0 1 2.523 2.522v6.312zM15.165 18.956a2.528 2.528 0 0 1 2.523 2.522A2.528 2.528 0 0 1 15.165 24a2.527 2.527 0 0 1-2.52-2.522v-2.522h2.52zM15.165 17.688a2.527 2.527 0 0 1-2.52-2.523 2.526 2.526 0 0 1 2.52-2.52h6.313A2.527 2.527 0 0 1 24 15.165a2.528 2.528 0 0 1-2.522 2.523h-6.313z",
        "Teams": "M20.625 8.127q-.55 0-1.025-.205-.475-.205-.832-.563-.358-.357-.563-.832Q18 6.053 18 5.502q0-.54.205-1.02t.563-.837q.357-.358.832-.563.474-.205 1.025-.205.54 0 1.02.205t.837.563q.358.357.563.837.205.48.205 1.02 0 .55-.205 1.025-.205.475-.563.832-.357.358-.837.563-.48.205-1.02.205zm0-3.75q-.469 0-.797.328-.328.328-.328.797 0 .469.328.797.328.328.797.328.469 0 .797-.328.328-.328.328-.797 0-.469-.328-.797-.328-.328-.797-.328zM24 10.002v5.578q0 .774-.293 1.46-.293.685-.803 1.194-.51.51-1.195.803-.686.293-1.459.293-.445 0-.908-.105-.463-.106-.85-.329-.293.95-.855 1.729-.563.78-1.319 1.336-.756.557-1.67.861-.914.305-1.898.305-1.148 0-2.162-.398-1.014-.399-1.805-1.102-.79-.703-1.312-1.664t-.674-2.086h-5.8q-.411 0-.704-.293T0 16.881V6.873q0-.41.293-.703t.703-.293h8.59q-.34-.715-.34-1.5 0-.727.275-1.365.276-.639.75-1.114.475-.474 1.114-.75.638-.275 1.365-.275t1.365.275q.639.276 1.114.75.474.475.75 1.114.275.638.275 1.365t-.275 1.365q-.276.639-.75 1.113-.475.475-1.114.75-.638.276-1.365.276-.188 0-.375-.024-.188-.023-.375-.058v1.078h10.875q.469 0 .797.328.328.328.328.797zM12.75 2.373q-.41 0-.78.158-.368.158-.638.434-.27.275-.428.639-.158.363-.158.773 0 .41.158.78.159.368.428.638.27.27.639.428.369.158.779.158.41 0 .773-.158.364-.159.64-.428.274-.27.433-.639.158-.369.158-.779 0-.41-.158-.773-.159-.364-.434-.64-.275-.275-.639-.433-.363-.158-.773-.158zM6.937 9.814h2.25V7.94H2.814v1.875h2.25v6h1.875zm10.313 7.313v-6.75H12v6.504q0 .41-.293.703t-.703.293H8.309q.152.809.556 1.5.405.691.985 1.19.58.497 1.318.779.738.281 1.582.281.926 0 1.746-.352.82-.351 1.436-.966.615-.616.966-1.43.352-.815.352-1.752zm5.25-1.547v-5.203h-3.75v6.855q.305.305.691.452.387.146.809.146.469 0 .879-.176.41-.175.715-.48.304-.305.48-.715t.176-.879Z",
        "X": "M14.234 10.162 22.977 0h-2.072l-7.591 8.824L7.251 0H.258l9.168 13.343L.258 24H2.33l8.016-9.318L16.749 24h6.993zm-2.837 3.299-.929-1.329L3.076 1.56h3.182l5.965 8.532.929 1.329 7.754 11.09h-3.182z",
        "TikTok": "M12.525.02c1.31-.02 2.61-.01 3.91-.02.08 1.53.63 3.09 1.75 4.17 1.12 1.11 2.7 1.62 4.24 1.79v4.03c-1.44-.05-2.89-.35-4.2-.97-.57-.26-1.1-.59-1.62-.93-.01 2.92.01 5.84-.02 8.75-.08 1.4-.54 2.79-1.35 3.94-1.31 1.92-3.58 3.17-5.91 3.21-1.43.08-2.86-.31-4.08-1.03-2.02-1.19-3.44-3.37-3.65-5.71-.02-.5-.03-1-.01-1.49.18-1.9 1.12-3.72 2.58-4.96 1.66-1.44 3.98-2.13 6.15-1.72.02 1.48-.04 2.96-.04 4.44-.99-.32-2.15-.23-3.02.37-.63.41-1.11 1.04-1.36 1.75-.21.51-.15 1.07-.14 1.61.24 1.64 1.82 3.02 3.5 2.87 1.12-.01 2.19-.66 2.77-1.61.19-.33.4-.67.41-1.06.1-1.79.06-3.57.07-5.36.01-4.03-.01-8.05.02-12.07z",
        "Reddit": "M12 0C5.373 0 0 5.373 0 12c0 3.314 1.343 6.314 3.515 8.485l-2.286 2.286C.775 23.225 1.097 24 1.738 24H12c6.627 0 12-5.373 12-12S18.627 0 12 0Zm4.388 3.199c1.104 0 1.999.895 1.999 1.999 0 1.105-.895 2-1.999 2-.946 0-1.739-.657-1.947-1.539v.002c-1.147.162-2.032 1.15-2.032 2.341v.007c1.776.067 3.4.567 4.686 1.363.473-.363 1.064-.58 1.707-.58 1.547 0 2.802 1.254 2.802 2.802 0 1.117-.655 2.081-1.601 2.531-.088 3.256-3.637 5.876-7.997 5.876-4.361 0-7.905-2.617-7.998-5.87-.954-.447-1.614-1.415-1.614-2.538 0-1.548 1.255-2.802 2.803-2.802.645 0 1.239.218 1.712.585 1.275-.79 2.881-1.291 4.64-1.365v-.01c0-1.663 1.263-3.034 2.88-3.207.188-.911.993-1.595 1.959-1.595Zm-8.085 8.376c-.784 0-1.459.78-1.506 1.797-.047 1.016.64 1.429 1.426 1.429.786 0 1.371-.369 1.418-1.385.047-1.017-.553-1.841-1.338-1.841Zm7.406 0c-.786 0-1.385.824-1.338 1.841.047 1.017.634 1.385 1.418 1.385.785 0 1.473-.413 1.426-1.429-.046-1.017-.721-1.797-1.506-1.797Zm-3.703 4.013c-.974 0-1.907.048-2.77.135-.147.015-.241.168-.183.305.483 1.154 1.622 1.964 2.953 1.964 1.33 0 2.47-.81 2.953-1.964.057-.137-.037-.29-.184-.305-.863-.087-1.795-.135-2.769-.135Z",
        "LinkedIn": "M20.447 20.452h-3.554v-5.569c0-1.328-.027-3.037-1.852-3.037-1.853 0-2.136 1.445-2.136 2.939v5.667H9.351V9h3.414v1.561h.046c.477-.9 1.637-1.85 3.37-1.85 3.601 0 4.267 2.37 4.267 5.455v6.286zM5.337 7.433c-1.144 0-2.063-.926-2.063-2.065 0-1.138.92-2.063 2.063-2.063 1.14 0 2.064.925 2.064 2.063 0 1.139-.925 2.065-2.064 2.065zm1.782 13.019H3.555V9h3.564v11.452zM22.225 0H1.771C.792 0 0 .774 0 1.729v20.542C0 23.227.792 24 1.771 24h20.451C23.2 24 24 23.227 24 22.271V1.729C24 .774 23.2 0 22.222 0h.003z",
        "Gmail": "M24 5.457v13.909c0 .904-.732 1.636-1.636 1.636h-3.819V11.73L12 16.64l-6.545-4.91v9.273H1.636A1.636 1.636 0 0 1 0 19.366V5.457c0-2.023 2.309-3.178 3.927-1.964L5.455 4.64 12 9.548l6.545-4.91 1.528-1.145C21.69 2.28 24 3.434 24 5.457z",
        "Tinder": "M9.317 9.451c.045.073.123.12.212.12.06 0 .116-.021.158-.057l.015-.012c.39-.325.741-.66 1.071-1.017 3.209-3.483 1.335-7.759 1.32-7.799-.09-.21-.03-.459.15-.594.195-.135.435-.12.615.033 10.875 10.114 7.995 17.818 7.785 18.337-.87 3.141-4.335 5.414-8.444 5.53-.138.008-.242.008-.363.008-4.852 0-8.977-2.989-8.977-6.807v-.06c0-5.297 4.795-10.522 5.009-10.744.136-.149.345-.195.525-.105.18.076.297.255.291.451-.043 1.036.167 1.935.631 2.7v.015l.002.001z",
        "Marketplace": "M9.101 23.691v-7.98H6.627v-3.667h2.474v-1.58c0-4.085 1.848-5.978 5.858-5.978.401 0 .955.042 1.468.103a8.68 8.68 0 0 1 1.141.195v3.325a8.623 8.623 0 0 0-.653-.036 26.805 26.805 0 0 0-.733-.009c-.707 0-1.259.096-1.675.309a1.686 1.686 0 0 0-.679.622c-.258.42-.374.995-.374 1.752v1.297h3.919l-.386 2.103-.287 1.564h-3.246v8.245C19.396 23.238 24 18.179 24 12.044c0-6.627-5.373-12-12-12s-12 5.373-12 12c0 5.628 3.874 10.35 9.101 11.647Z",
    ]
}

/// A brand logo drawn from its square SVG path, scaled to fit (and centred in) any rect.
/// Fill it (or stroke it) with whatever colour the caller wants.
struct BrandLogoShape: Shape {
    let pathData: String
    var viewBox: CGFloat = 24

    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / viewBox
        let half = viewBox / 2 * scale
        let transform = CGAffineTransform(
            translationX: rect.midX - half,
            y: rect.midY - half
        ).scaledBy(x: scale, y: scale)
        return SVGPathParser.path(from: pathData).applying(transform)
    }
}

// MARK: - SVG path parsing

/// Minimal SVG path-data parser producing a SwiftUI `Path`. Supports the full command set
/// used by the bundled brand logos — M/L/H/V/C/S/Q/T/A and Z, absolute and relative —
/// including elliptical arcs (approximated with cubic Béziers). On malformed input it
/// returns whatever it parsed so far rather than crashing.
enum SVGPathParser {
    static func path(from d: String) -> Path {
        var path = Path()
        var scan = Tokenizer(d)
        var cur = CGPoint.zero        // current point
        var start = CGPoint.zero      // start of the current subpath (for Z)
        var lastCubic: CGPoint?       // previous cubic control point (for S)
        var lastQuad: CGPoint?        // previous quadratic control point (for T)
        var cmd: Character = " "

        while true {
            scan.skipSeparators()
            if scan.isAtEnd { break }
            if scan.peekIsLetter {
                cmd = scan.takeLetter()
            } else if cmd == "M" {
                cmd = "L"             // extra coords after a moveto are implicit linetos
            } else if cmd == "m" {
                cmd = "l"
            }
            let relative = cmd.isLowercase

            switch Character(cmd.uppercased()) {
            case "M":
                guard let x = scan.number(), let y = scan.number() else { return path }
                let p = point(x, y, relative ? cur : .zero)
                path.move(to: p); cur = p; start = p; lastCubic = nil; lastQuad = nil
            case "L":
                guard let x = scan.number(), let y = scan.number() else { return path }
                let p = point(x, y, relative ? cur : .zero)
                path.addLine(to: p); cur = p; lastCubic = nil; lastQuad = nil
            case "H":
                guard let x = scan.number() else { return path }
                let p = CGPoint(x: relative ? cur.x + x : x, y: cur.y)
                path.addLine(to: p); cur = p; lastCubic = nil; lastQuad = nil
            case "V":
                guard let y = scan.number() else { return path }
                let p = CGPoint(x: cur.x, y: relative ? cur.y + y : y)
                path.addLine(to: p); cur = p; lastCubic = nil; lastQuad = nil
            case "C":
                guard let x1 = scan.number(), let y1 = scan.number(),
                      let x2 = scan.number(), let y2 = scan.number(),
                      let x = scan.number(), let y = scan.number() else { return path }
                let o = relative ? cur : .zero
                let c1 = point(x1, y1, o), c2 = point(x2, y2, o), p = point(x, y, o)
                path.addCurve(to: p, control1: c1, control2: c2)
                cur = p; lastCubic = c2; lastQuad = nil
            case "S":
                guard let x2 = scan.number(), let y2 = scan.number(),
                      let x = scan.number(), let y = scan.number() else { return path }
                let o = relative ? cur : .zero
                let c2 = point(x2, y2, o), p = point(x, y, o)
                let c1 = reflect(lastCubic, about: cur)
                path.addCurve(to: p, control1: c1, control2: c2)
                cur = p; lastCubic = c2; lastQuad = nil
            case "Q":
                guard let x1 = scan.number(), let y1 = scan.number(),
                      let x = scan.number(), let y = scan.number() else { return path }
                let o = relative ? cur : .zero
                let c1 = point(x1, y1, o), p = point(x, y, o)
                path.addQuadCurve(to: p, control: c1)
                cur = p; lastQuad = c1; lastCubic = nil
            case "T":
                guard let x = scan.number(), let y = scan.number() else { return path }
                let p = point(x, y, relative ? cur : .zero)
                let c1 = reflect(lastQuad, about: cur)
                path.addQuadCurve(to: p, control: c1)
                cur = p; lastQuad = c1; lastCubic = nil
            case "A":
                guard let rx = scan.number(), let ry = scan.number(), let rot = scan.number(),
                      let large = scan.flag(), let sweep = scan.flag(),
                      let x = scan.number(), let y = scan.number() else { return path }
                let p = point(x, y, relative ? cur : .zero)
                appendArc(to: &path, from: cur, to: p, rx: rx, ry: ry,
                          rotationDeg: rot, largeArc: large != 0, sweep: sweep != 0)
                cur = p; lastCubic = nil; lastQuad = nil
            case "Z":
                path.closeSubpath(); cur = start; lastCubic = nil; lastQuad = nil
            default:
                return path
            }
        }
        return path
    }

    private static func point(_ x: CGFloat, _ y: CGFloat, _ origin: CGPoint) -> CGPoint {
        CGPoint(x: origin.x + x, y: origin.y + y)
    }

    /// The control point for a smooth (S/T) curve: the previous control reflected through
    /// the current point, or the current point itself if there's no previous control.
    private static func reflect(_ ctrl: CGPoint?, about p: CGPoint) -> CGPoint {
        guard let ctrl else { return p }
        return CGPoint(x: 2 * p.x - ctrl.x, y: 2 * p.y - ctrl.y)
    }

    /// Appends an SVG elliptical arc, converted (endpoint → centre parameterisation) and
    /// approximated by up to four cubic Béziers, following the SVG implementation notes.
    private static func appendArc(to path: inout Path, from p0: CGPoint, to p1: CGPoint,
                                  rx rxIn: CGFloat, ry ryIn: CGFloat, rotationDeg: CGFloat,
                                  largeArc: Bool, sweep: Bool) {
        var rx = abs(rxIn), ry = abs(ryIn)
        if rx == 0 || ry == 0 || (p0.x == p1.x && p0.y == p1.y) {
            path.addLine(to: p1); return
        }
        let phi = rotationDeg * .pi / 180
        let cosPhi = cos(phi), sinPhi = sin(phi)

        let dx = (p0.x - p1.x) / 2, dy = (p0.y - p1.y) / 2
        let x1p = cosPhi * dx + sinPhi * dy
        let y1p = -sinPhi * dx + cosPhi * dy

        var rxSq = rx * rx, rySq = ry * ry
        let x1pSq = x1p * x1p, y1pSq = y1p * y1p
        let lambda = x1pSq / rxSq + y1pSq / rySq
        if lambda > 1 {
            let s = sqrt(lambda)
            rx *= s; ry *= s; rxSq = rx * rx; rySq = ry * ry
        }

        var numerator = rxSq * rySq - rxSq * y1pSq - rySq * x1pSq
        if numerator < 0 { numerator = 0 }
        let denominator = rxSq * y1pSq + rySq * x1pSq
        var coef = denominator == 0 ? 0 : sqrt(numerator / denominator)
        if largeArc == sweep { coef = -coef }
        let cxp = coef * rx * y1p / ry
        let cyp = -coef * ry * x1p / rx

        let cx = cosPhi * cxp - sinPhi * cyp + (p0.x + p1.x) / 2
        let cy = sinPhi * cxp + cosPhi * cyp + (p0.y + p1.y) / 2

        func angle(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
            let dot = ux * vx + uy * vy
            let len = sqrt((ux * ux + uy * uy) * (vx * vx + vy * vy))
            var a = acos(min(max(len == 0 ? 1 : dot / len, -1), 1))
            if ux * vy - uy * vx < 0 { a = -a }
            return a
        }

        let ux = (x1p - cxp) / rx, uy = (y1p - cyp) / ry
        let vx = (-x1p - cxp) / rx, vy = (-y1p - cyp) / ry
        let theta1 = angle(1, 0, ux, uy)
        var delta = angle(ux, uy, vx, vy)
        if !sweep && delta > 0 { delta -= 2 * .pi }
        if sweep && delta < 0 { delta += 2 * .pi }

        let segments = max(Int(ceil(abs(delta) / (.pi / 2))), 1)
        let perSeg = delta / CGFloat(segments)
        let alpha = 4.0 / 3.0 * tan(perSeg / 4)

        func onArc(_ a: CGFloat) -> CGPoint {
            let x = rx * cos(a), y = ry * sin(a)
            return CGPoint(x: cosPhi * x - sinPhi * y + cx,
                           y: sinPhi * x + cosPhi * y + cy)
        }
        func tangent(_ a: CGFloat) -> CGPoint {
            let x = -rx * sin(a), y = ry * cos(a)
            return CGPoint(x: cosPhi * x - sinPhi * y, y: sinPhi * x + cosPhi * y)
        }

        var a1 = theta1
        for _ in 0..<segments {
            let a2 = a1 + perSeg
            let p2 = onArc(a2)
            let t1 = tangent(a1), t2 = tangent(a2)
            let from = onArc(a1)
            let c1 = CGPoint(x: from.x + alpha * t1.x, y: from.y + alpha * t1.y)
            let c2 = CGPoint(x: p2.x - alpha * t2.x, y: p2.y - alpha * t2.y)
            path.addCurve(to: p2, control1: c1, control2: c2)
            a1 = a2
        }
    }
}

/// Character scanner that pulls SVG path commands, numbers, and arc flags out of a `d`
/// string, tolerating the compact forms SVGO emits (no separators, packed signs, ".5.5").
private struct Tokenizer {
    private let chars: [Character]
    private var i = 0

    init(_ s: String) { chars = Array(s) }

    var isAtEnd: Bool { i >= chars.count }
    var peekIsLetter: Bool { i < chars.count && chars[i].isLetter }

    mutating func skipSeparators() {
        while i < chars.count,
              chars[i] == " " || chars[i] == "," || chars[i] == "\n" ||
              chars[i] == "\t" || chars[i] == "\r" {
            i += 1
        }
    }

    mutating func takeLetter() -> Character {
        defer { i += 1 }
        return chars[i]
    }

    mutating func number() -> CGFloat? {
        skipSeparators()
        guard i < chars.count else { return nil }
        var str = ""
        if chars[i] == "+" || chars[i] == "-" { str.append(chars[i]); i += 1 }
        var seenDot = false
        while i < chars.count {
            let c = chars[i]
            if c.isNumber {
                str.append(c); i += 1
            } else if c == "." {
                if seenDot { break }   // a second dot begins a new number, e.g. ".5.5"
                seenDot = true; str.append(c); i += 1
            } else if c == "e" || c == "E" {
                str.append(c); i += 1
                if i < chars.count, chars[i] == "+" || chars[i] == "-" {
                    str.append(chars[i]); i += 1
                }
            } else {
                break
            }
        }
        return Double(str).map { CGFloat($0) }
    }

    /// An arc flag is a single '0' or '1' and may be packed with no separator ("0 01 1").
    mutating func flag() -> CGFloat? {
        skipSeparators()
        guard i < chars.count else { return nil }
        if chars[i] == "0" { i += 1; return 0 }
        if chars[i] == "1" { i += 1; return 1 }
        return number()
    }
}
