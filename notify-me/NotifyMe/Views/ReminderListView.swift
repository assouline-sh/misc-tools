import SwiftUI
import SwiftData

struct ReminderListView: View {
    @Query(
        filter: #Predicate<ReminderItem> { !$0.isAnswered },
        sort: \ReminderItem.createdAt,
        order: .reverse
    )
    private var reminders: [ReminderItem]

    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @ObservedObject private var icons = AppIconCache.shared
    @EnvironmentObject private var fly: FlyCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("answer your fucking messages")
                .font(.system(size: 20, weight: .bold, design: .monospaced))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .padding(.horizontal)
                .padding(.top, 8)

            if reminders.isEmpty {
                Spacer()
                Text("nothing. you're good.")
                    .foregroundStyle(Theme.accent)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(reminders) { item in
                            AnswerSwipeRow(
                                logo: icons.images[item.sourceApp ?? ""],
                                color: Theme.brand(for: item.sourceApp),
                                onAnswer: { frame, velocity in answer(item, from: frame, velocity: velocity) }
                            ) {
                                ReminderRow(item: item)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if let url = AppLinks.url(for: item.sourceApp) {
                                    openURL(url)
                                }
                            }
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.background.ignoresSafeArea())
        .onAppear(perform: loadIcons)
        .onChange(of: reminders.count) { _, _ in loadIcons() }
    }

    /// Hand the row's logo + frame + swipe velocity to the fling overlay, stop nagging,
    /// then mark answered.
    private func answer(_ item: ReminderItem, from frame: CGRect, velocity: CGSize) {
        fly.launch(
            image: icons.images[item.sourceApp ?? ""],
            color: Theme.brand(for: item.sourceApp),
            from: frame,
            velocity: velocity
        )
        NotificationManager.shared.cancelReminder(id: item.id)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            item.isAnswered = true
            item.answeredAt = Date()
        }
        try? context.save()
    }

    private func loadIcons() {
        let platforms = Set(reminders.compactMap { $0.sourceApp })
            .map { FlagPlatform(name: $0, icon: "app") }
        icons.loadCached(platforms)
        icons.fetchMissing(platforms)
    }
}
