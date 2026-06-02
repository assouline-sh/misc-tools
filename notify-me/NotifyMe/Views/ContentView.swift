import SwiftUI

struct ContentView: View {
    @StateObject private var fly = FlyCoordinator()

    var body: some View {
        ZStack {
            TabView {
                ReminderListView()
                    .tabItem {
                        Label("shit to do", systemImage: "tray.full")
                    }

                StatsView()
                    .tabItem {
                        Label("stats", systemImage: "chart.bar")
                    }

                SettingsView()
                    .tabItem {
                        Label("settings", systemImage: "slider.horizontal.3")
                    }
            }
            .environmentObject(fly)

            if let flight = fly.flight {
                GeometryReader { geo in
                    FlyingLogoView(
                        flight: flight,
                        target: CGPoint(x: geo.size.width / 2, y: geo.size.height - 10),
                        screen: geo.size,
                        onDone: { fly.clear() }
                    )
                    .id(flight.id)
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)
            }
        }
        .tint(Theme.accent)
        .fontDesign(.monospaced)
        .preferredColorScheme(.dark)
    }
}
