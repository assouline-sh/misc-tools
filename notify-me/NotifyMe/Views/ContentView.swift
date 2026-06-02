import SwiftUI
import UIKit

struct ContentView: View {
    @StateObject private var fly = FlyCoordinator()
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection = 0
    @State private var statsIconFrame: CGRect = .zero  // global frame of the stats icon
    @State private var composeApp: String?
    @State private var showCompose = false
    /// Whether notifications are usable. Starts true to avoid flashing the warning before
    /// we've checked; flipped false only once we confirm permission is missing.
    @State private var notificationsOK = true

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
        // Applied before the tab-bar inset so it sits above the tab bar, not over it.
        .overlay(alignment: .bottomTrailing) {
            if selection == 0 {
                addButton
            }
        }
        .environmentObject(fly)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 8) {
                if !notificationsOK { notificationWarning }
                CustomTabBar(selection: $selection, flightID: fly.flight?.id)
            }
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
        // Keep the whole UI (esp. the tab bar) from riding up over the keyboard.
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .sheet(isPresented: $showCompose) {
            ComposeReminderView(sourceApp: composeApp)
        }
        .onAppear(perform: checkPendingCompose)
        .task { await refreshNotificationStatus() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                checkPendingCompose()
                Task { await refreshNotificationStatus() }
            } else if phase == .background {
                // Leaving the app without explicitly saving or cancelling discards the
                // in-progress form, so returning lands on the main screen.
                showCompose = false
                composeApp = nil
            }
        }
        .onReceive(NotificationCenter.default.publisher(
            for: UIApplication.didBecomeActiveNotification
        )) { _ in
            // Safety net: the widget intent may write the compose target slightly after
            // the scene reports active, so re-check shortly after becoming active too.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { checkPendingCompose() }
        }
    }

    /// Floating "+" on the reminders tab that opens the new-notification form with no
    /// app preselected (you pick one in the form).
    private var addButton: some View {
        Button {
            composeApp = nil
            showCompose = true
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 50, height: 50)
                .background(Circle().fill(Theme.accent))
                .shadow(color: Theme.accent.opacity(0.5), radius: 7, y: 3)
        }
        .padding(.trailing, 18)
        .padding(.bottom, 12)
    }

    /// Small amber bar shown above the tab bar when notifications can't fire — taps open
    /// the system Settings so the user can re-enable them.
    private var notificationWarning: some View {
        Button {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                Text("notifications off — tap to enable")
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .font(.system(size: 12, weight: .bold, design: .monospaced))
            .foregroundStyle(Theme.accent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Theme.accent.opacity(0.15))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Theme.accent.opacity(0.5), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
    }

    /// Notifications are "OK" when authorized or provisional; anything else (denied,
    /// not-yet-requested, ephemeral) surfaces the warning bar.
    private func refreshNotificationStatus() async {
        let status = await NotificationManager.shared.authorizationStatus()
        notificationsOK = status == .authorized || status == .provisional
    }

    /// If a widget tap recently asked us to compose a reminder, present the form for it.
    /// The request is read fresh from disk (see `ComposeHandoff`) so we always get the
    /// app the widget actually wrote, never a stale cached value.
    private func checkPendingCompose() {
        guard !showCompose, let request = ComposeHandoff.consume() else { return }
        composeApp = request.app
        showCompose = true
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

/// A tab's title header, in the app's bold monospaced style. An optional substring is
/// drawn in the accent color.
struct ScreenTitle: View {
    let text: String
    let accented: String?

    init(_ text: String, accent: String? = nil) {
        self.text = text
        self.accented = accent
    }

    var body: some View {
        titleText
            .font(.system(size: 20, weight: .bold, design: .monospaced))
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
            .padding(.top, 8)
    }

    private var titleText: Text {
        guard let accented, let range = text.range(of: accented) else {
            return Text(text).foregroundColor(Theme.text)
        }
        let before = String(text[text.startIndex..<range.lowerBound])
        let mid = String(text[range])
        let after = String(text[range.upperBound...])
        return Text(before).foregroundColor(Theme.text)
            + Text(mid).foregroundColor(Theme.accent)
            + Text(after).foregroundColor(Theme.text)
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
