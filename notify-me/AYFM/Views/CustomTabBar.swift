import SwiftUI

/// A hand-rolled tab bar so we fully own the stats icon — when a flung app lands we
/// recolor and pulse that *actual* icon (no overlay). Looks like the system bar:
/// translucent material, hairline top, accent for the selected item.
struct CustomTabBar: View {
    @Binding var selection: Int
    let flightID: UUID?

    // Pulse state for the stats icon, independent of selection.
    @State private var statsScale: CGFloat = 1
    @State private var statsLit = false

    private let items: [(icon: String, label: String)] = [
        ("tray.full", "sh*t to answer"),
        ("chart.bar", "stats"),
        ("slider.horizontal.3", "settings"),
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items.indices, id: \.self) { tab($0) }
        }
        .padding(.top, 8)
        .padding(.bottom, 2)
        .background(.bar)
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.border).frame(height: 0.5)
        }
        .onChange(of: flightID) { _, newID in
            guard newID != nil else { return }
            // Light the icon up just as the flung logo arrives.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.60) { pulse() }
        }
    }

    @ViewBuilder private func tab(_ i: Int) -> some View {
        let isStats = i == 1
        // The stats icon goes accent when selected OR while lit by a landing.
        let active = selection == i || (isStats && statsLit)

        VStack(spacing: 4) {
            Image(systemName: items[i].icon)
                .font(.system(size: 22))
                .scaleEffect(isStats ? statsScale : 1)  // scaleEffect doesn't move layout,
                .background(isStats ? statsIconFrameReader : nil)  // so the frame stays put
                .shadow(color: Theme.accent.opacity(isStats && statsLit ? 0.9 : 0), radius: 8)
            Text(items[i].label)
                .font(.system(size: 10, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .foregroundStyle(active ? Theme.accent : Theme.dim)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { selection = i }
    }

    /// Reports the resting (unscaled) global frame of the stats icon to the overlay.
    private var statsIconFrameReader: some View {
        GeometryReader { g in
            Color.clear.preference(key: StatsIconFrameKey.self, value: g.frame(in: .global))
        }
    }

    private func pulse() {
        withAnimation(.spring(response: 0.22, dampingFraction: 0.5)) {
            statsScale = 1.5
            statsLit = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.26) {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) { statsScale = 1 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            withAnimation(.easeOut(duration: 0.5)) { statsLit = false }
        }
    }
}
