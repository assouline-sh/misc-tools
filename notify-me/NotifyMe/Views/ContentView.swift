import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            ReminderListView()
                .tabItem {
                    Label("Pending", systemImage: "bell.badge")
                }

            AnsweredListView()
                .tabItem {
                    Label("Answered", systemImage: "checkmark.circle")
                }

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
        }
    }
}
