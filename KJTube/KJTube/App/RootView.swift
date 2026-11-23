import SwiftData
import SwiftUI

enum AppTab: Hashable {
    case home, following, settings
}

/// Tab bar: Inbox · Following · Settings (PLAN D6).
struct RootView: View {
    @Environment(AppStore.self) private var store
    @State private var tab: AppTab = .home
    private static let order: [AppTab] = [.home, .following, .settings]
    /// Where a tab sits in the tab bar, counting from 0 at the left.
    private static func position(_ tab: AppTab) -> Int { order.firstIndex(of: tab) ?? 0 }

    private var firstRunSheetShown: Binding<Bool> {
        Binding { store.firstRunPage != nil } set: { if !$0 { store.firstRunPage = nil } }
    }

    var body: some View {
        TabView(selection: $tab) {
            Tab("Inbox", systemImage: "tray", value: .home) {
                HomeView(tab: $tab)
                    .customTabTransition(position: Self.position(.home), of: Self.order.count)
                    .tabSwipe($tab, order: Self.order)
            }
            Tab("Following", systemImage: "person.2", value: .following) {
                FollowingView(tab: $tab)
                    .customTabTransition(position: Self.position(.following), of: Self.order.count) // no tab swipe: it fought with dragging creators (D93)
            }
            Tab("Settings", systemImage: "gearshape", value: .settings) {
                SettingsView(tab: $tab)
                    .customTabTransition(position: Self.position(.settings), of: Self.order.count)
                    .tabSwipe($tab, order: Self.order)
            }
        }
        // The player sits on top of the tabs, so it can shrink to a small player and keep
        // playing while the tabs are used (D165).
        .overlay {
            if let entry = NowPlaying.shared.entry {
                PlayerView(store: store, start: entry, openFrom: NowPlaying.shared.openFrom) {
                    NowPlaying.shared.close()
                }
                .id(NowPlaying.shared.token)
            }
        }
        // After an import, go straight to Following, wherever it was started from (D158).
        .onChange(of: store.importedCount) { _, count in
            guard count != nil else { return }
            tab = .following
            // First run: the bar on Following takes the note's place, and the daily amount is
            // asked once the pick list has slid away (D175).
            guard store.isFirstRun else { return }
            Task {
                try? await Task.sleep(for: .milliseconds(700))
                store.importedCount = nil
                store.askAmountAfterImport()
            }
        }
        .sheet(isPresented: firstRunSheetShown) {
            FirstRunSheet(start: store.firstRunPage ?? .check) { tab = .home }
        }
    }
}

#Preview {
    let container = try! ModelContainer(
        for: Creator.self, EngineRecord.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    RootView()
        .preferredColorScheme(.dark)
        .environment(AppStore(context: container.mainContext, api: LiveYouTubeClient(apiKey: AppConfig.youTubeAPIKey)))
        .modelContainer(container)
}
