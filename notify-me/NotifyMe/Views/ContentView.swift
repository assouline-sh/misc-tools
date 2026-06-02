import SwiftUI

struct ContentView: View {
    @StateObject private var fly = FlyCoordinator()
    @State private var selection = 0
    @State private var statsIconFrame: CGRect = .zero  // global frame of the stats icon

    var body: some View {
        ZStack {
            // All three tabs stay mounted (like TabView) so state/scroll is preserved.
            ReminderListView()
                .opacity(selection == 0 ? 1 : 0)
                .allowsHitTesting(selection == 0)
            StatsView()
                .opacity(selection == 1 ? 1 : 0)
                .allowsHitTesting(selection == 1)
            SettingsView()
                .opacity(selection == 2 ? 1 : 0)
                .allowsHitTesting(selection == 2)
        }
        .environmentObject(fly)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            CustomTabBar(selection: $selection, flightID: fly.flight?.id)
        }
        .onPreferenceChange(StatsIconFrameKey.self) { statsIconFrame = $0 }
        .overlay {
            // Full-screen overlay; local coords == global, matching captured frames.
            GeometryReader { geo in
                if let flight = fly.flight {
                    FlyingLogoView(
                        flight: flight,
                        target: statsTarget(in: geo.size),
                        screen: geo.size,
                        onDone: { fly.clear() }
                    )
                    .id(flight.id)
                }
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
        .tint(Theme.accent)
        .fontDesign(.monospaced)
        .preferredColorScheme(.dark)
    }

    /// Where the flung logo should land: the real stats icon, or a bottom-center
    /// fallback before the tab bar has reported its frame.
    private func statsTarget(in size: CGSize) -> CGPoint {
        guard statsIconFrame != .zero else {
            return CGPoint(x: size.width / 2, y: size.height - 40)
        }
        return CGPoint(x: statsIconFrame.midX, y: statsIconFrame.midY)
    }
}

/// Global frame of the stats tab icon, published up so the fling can target it exactly.
struct StatsIconFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}
