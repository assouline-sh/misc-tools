import SwiftUI
import WidgetKit
import UniformTypeIdentifiers

/// Visual editor for the Quick Flag widget buttons: 8 fixed slots that the user
/// drags app icons into from a palette. Changes persist to the shared App Group
/// and reload the widget immediately.
struct PlatformConfigView: View {
    @ObservedObject private var icons = AppIconCache.shared
    @State private var slots: [FlagPlatform?] = PlatformConfigView.initialSlots()
    @State private var customs: [FlagPlatform] = PlatformConfigView.initialCustoms()
    @State private var customName: String = ""
    @State private var paletteTargeted = false
    /// Index of the slot a dragged app is currently hovering over (nil = none).
    @State private var targetedSlot: Int?

    /// A soft "ready to drop" green chosen to sit well next to the amber accent.
    private let readyGreen = Color(red: 0.46, green: 0.80, blue: 0.45)

    private let slotColumns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 4)
    private let paletteColumns = [GridItem(.adaptive(minimum: 68), spacing: 10)]

    /// Catalog + any custom apps the user added, minus whatever is already slotted.
    private var available: [FlagPlatform] {
        let slotted = Set(slots.compactMap { $0?.name })
        return (PlatformCatalog.all + customs).filter { !slotted.contains($0.name) }
    }

    /// Palette groupings, in display order. Names must match catalog entries; any
    /// available app not listed here (e.g. a custom one) falls under "custom".
    private static let categories: [(title: String, names: [String])] = [
        ("messaging", ["WhatsApp", "Telegram", "Signal", "Discord", "Messenger", "Snapchat", "WeChat", "Line", "Viber", "KakaoTalk", "Teams"]),
        ("work", ["Slack"]),
        ("social", ["Instagram", "X", "TikTok", "Reddit", "Facebook", "Threads", "Mastodon", "BeReal", "Twitch", "YouTube", "Pinterest", "Tumblr", "LinkedIn"]),
        ("dating", ["Hinge", "Bumble", "Tinder", "Grindr"]),
        ("email", ["Gmail", "Outlook", "Mail"]),
        ("shopping", ["eBay", "Etsy", "Depop", "Airbnb"]),
        ("payments", ["Venmo", "PayPal"]),
        ("other", ["Voicemail"]),
    ]

    /// Available apps grouped by category (empty groups dropped), with anything
    /// uncategorized collected under "custom" at the end.
    private var categorizedAvailable: [(title: String, apps: [FlagPlatform])] {
        let byName = Dictionary(available.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        var groups: [(title: String, apps: [FlagPlatform])] = []
        var categorized = Set<String>()

        for (title, names) in Self.categories {
            categorized.formUnion(names)
            let apps = names.compactMap { byName[$0] }
            if !apps.isEmpty { groups.append((title, apps)) }
        }

        let leftovers = available.filter { !categorized.contains($0.name) }
        if !leftovers.isEmpty { groups.append(("custom", leftovers)) }
        return groups
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("widget slots")
                    .font(.headline)
                LazyVGrid(columns: slotColumns, spacing: 10) {
                    ForEach(0..<16, id: \.self) { slotView($0) }
                }

                Divider()

                Text("drag app into slot")
                    .font(.headline)
                paletteView

                customAddField
            }
            .padding(.horizontal)
            .padding(.top)
            .padding(.bottom, 80)
        }
        .navigationTitle("widget configuration")
        .navigationBarTitleDisplayMode(.inline)
        .screen()
        .onChange(of: slots) { _, _ in persist() }
        .onAppear {
            let all = PlatformCatalog.all + customs
            icons.loadCached(all)
            icons.fetchMissing(all)
        }
    }

    /// Official app icon if cached, otherwise the SF Symbol fallback.
    @ViewBuilder
    private func platformIcon(_ platform: FlagPlatform, size: CGFloat) -> some View {
        if let image = icons.images[platform.name] {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        } else {
            Image(systemName: platform.icon)
                .font(.system(size: size * 0.68))
                .frame(width: size, height: size)
        }
    }

    // MARK: - Slots

    private func slotView(_ index: Int) -> some View {
        let platform = slots[index]
        let targeted = targetedSlot == index
        // Stroke: green when an app is hovering, amber dashed when empty, hidden when filled.
        let strokeColor: Color = targeted ? readyGreen : (platform == nil ? Theme.accent.opacity(0.7) : .clear)
        let fillColor: Color = targeted
            ? readyGreen.opacity(0.18)
            : (platform == nil ? Color.clear : Color.accentColor.opacity(0.15))

        return RoundedRectangle(cornerRadius: 16)
            .strokeBorder(
                style: StrokeStyle(lineWidth: targeted ? 2.5 : 2, dash: (platform == nil && !targeted) ? [5] : [])
            )
            .foregroundStyle(strokeColor)
            .background(
                RoundedRectangle(cornerRadius: 16).fill(fillColor)
            )
            .frame(height: 76)
            .shadow(color: targeted ? readyGreen.opacity(0.65) : .clear, radius: targeted ? 8 : 0)
            .animation(.easeInOut(duration: 0.15), value: targeted)
            .overlay {
                if let platform {
                    VStack(spacing: 4) {
                        platformIcon(platform, size: 32)
                        Text(platform.name).font(.caption2).lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .padding(6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .draggable(platform.name)
                    .overlay(alignment: .topTrailing) {
                        Button {
                            slots[index] = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                                .background(Circle().fill(.background))
                        }
                        .buttonStyle(.plain)
                        .offset(x: 6, y: -6)
                    }
                } else {
                    Text("\(index + 1)").font(.headline).foregroundStyle(.tertiary)
                }
            }
            .dropDestination(for: String.self) { items, _ in
                targetedSlot = nil
                guard let name = items.first else { return false }
                drop(name: name, into: index)
                return true
            } isTargeted: { isOver in
                if isOver { targetedSlot = index }
                else if targetedSlot == index { targetedSlot = nil }
            }
    }

    // MARK: - Palette

    private var paletteView: some View {
        VStack(alignment: .leading, spacing: 18) {
            if available.isEmpty {
                Text("all apps are in slots. drag one back here to remove it.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else {
                ForEach(categorizedAvailable, id: \.title) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(group.title)
                            .font(.system(.subheadline, design: .monospaced))
                            .foregroundStyle(.secondary)
                        LazyVGrid(columns: paletteColumns, spacing: 10) {
                            ForEach(group.apps) { paletteCell($0) }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(paletteTargeted ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.06))
        )
        .dropDestination(for: String.self) { items, _ in
            guard let name = items.first else { return false }
            removeFromSlots(name)
            return true
        } isTargeted: { paletteTargeted = $0 }
    }

    /// A single draggable app tile in the palette.
    private func paletteCell(_ platform: FlagPlatform) -> some View {
        VStack(spacing: 4) {
            platformIcon(platform, size: 30)
            Text(platform.name).font(.caption2).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(width: 68, height: 60)
        .background(
            RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.12))
        )
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .draggable(platform.name)
    }

    private var customAddField: some View {
        HStack {
            TextField("Add a custom app…", text: $customName)
                .textInputAutocapitalization(.words)
            Button("Add", action: addCustom)
                .disabled(trimmedCustom.isEmpty)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.1)))
    }

    // MARK: - Logic

    private var trimmedCustom: String {
        customName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func resolve(_ name: String) -> FlagPlatform? {
        (PlatformCatalog.all + customs).first { $0.name == name }
    }

    /// Drop an app (by name) into a slot — swaps/moves if it came from another slot.
    private func drop(name: String, into index: Int) {
        guard let platform = resolve(name) else { return }
        if let from = slots.firstIndex(where: { $0?.name == name }) {
            guard from != index else { return }
            slots[from] = slots[index]   // swap; nil if destination was empty (a move)
        }
        slots[index] = platform
    }

    private func removeFromSlots(_ name: String) {
        if let from = slots.firstIndex(where: { $0?.name == name }) {
            slots[from] = nil
        }
    }

    private func addCustom() {
        let name = trimmedCustom
        let allKnown = PlatformCatalog.all + customs
        guard !name.isEmpty,
              !allKnown.contains(where: { $0.name.lowercased() == name.lowercased() })
        else { customName = ""; return }

        let platform = FlagPlatform(name: name, icon: "bell.fill")
        customs.append(platform)
        if let empty = slots.firstIndex(where: { $0 == nil }) {
            slots[empty] = platform
        }
        customName = ""
    }

    private func persist() {
        PlatformStore.save(slots.compactMap { $0 })
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Initial state

    private static func initialSlots() -> [FlagPlatform?] {
        var result: [FlagPlatform?] = PlatformStore.load().prefix(16).map { $0 }
        while result.count < 16 { result.append(nil) }
        return result
    }

    private static func initialCustoms() -> [FlagPlatform] {
        let catalogNames = Set(PlatformCatalog.all.map { $0.name })
        return PlatformStore.load().filter { !catalogNames.contains($0.name) }
    }
}
