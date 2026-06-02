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

    private let slotColumns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 4)
    private let paletteColumns = [GridItem(.adaptive(minimum: 68), spacing: 10)]

    /// Catalog + any custom apps the user added, minus whatever is already slotted.
    private var available: [FlagPlatform] {
        let slotted = Set(slots.compactMap { $0?.name })
        return (PlatformCatalog.all + customs).filter { !slotted.contains($0.name) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Your 8 slots")
                    .font(.headline)
                LazyVGrid(columns: slotColumns, spacing: 10) {
                    ForEach(0..<8, id: \.self) { slotView($0) }
                }

                Divider()

                Text("Drag an app into a slot")
                    .font(.headline)
                paletteView

                customAddField
            }
            .padding()
        }
        .navigationTitle("Quick Flag Buttons")
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
        return RoundedRectangle(cornerRadius: 16)
            .strokeBorder(
                style: StrokeStyle(lineWidth: 2, dash: platform == nil ? [5] : [])
            )
            .foregroundStyle(platform == nil ? Color.secondary.opacity(0.5) : .clear)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(platform == nil ? Color.clear : Color.accentColor.opacity(0.15))
            )
            .frame(height: 76)
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
                guard let name = items.first else { return false }
                drop(name: name, into: index)
                return true
            }
    }

    // MARK: - Palette

    private var paletteView: some View {
        Group {
            if available.isEmpty {
                Text("All apps are in slots. Drag one back here to remove it.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else {
                LazyVGrid(columns: paletteColumns, spacing: 10) {
                    ForEach(available) { platform in
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
                }
            }
        }
        .frame(maxWidth: .infinity)
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

    private var customAddField: some View {
        HStack {
            Image(systemName: "plus.circle.fill").foregroundStyle(.secondary)
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
        var result: [FlagPlatform?] = PlatformStore.load().prefix(8).map { $0 }
        while result.count < 8 { result.append(nil) }
        return result
    }

    private static func initialCustoms() -> [FlagPlatform] {
        let catalogNames = Set(PlatformCatalog.all.map { $0.name })
        return PlatformStore.load().filter { !catalogNames.contains($0.name) }
    }
}
