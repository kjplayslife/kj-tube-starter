import SwiftData
import SwiftUI

@main
struct KJTubeApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let container: ModelContainer
    @State private var store: AppStore
    @Environment(\.scenePhase) private var scenePhase
    /// System, Light or Dark, picked in Settings (D223).
    @AppStorage(Appearance.key) private var appearance = Appearance.system

    init() {
        Timing.launchStarted()
        #if DEBUG
        // `-resetData` starts from an empty, in-memory store (Simulator testing).
        let inMemory = ProcessInfo.processInfo.arguments.contains("-resetData")
        #else
        let inMemory = false
        #endif
        let container = try! ModelContainer(
            for: Creator.self, EngineRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: inMemory)
        )
        self.container = container
        TipJar.finishLateTips() // a tip Apple finished while the app was closed (D181)
        YouTubeIFramePlayer.shared.prewarm() // warm web view before the first tap (P1)
        var api: any YouTubeAPI = LiveYouTubeClient(apiKey: AppConfig.youTubeAPIKey)
        #if DEBUG
        // `-offline`: YouTube's Data API never answers (Simulator checks of the offline screens).
        if ProcessInfo.processInfo.arguments.contains("-offline") { api = LiveYouTubeClient(apiKey: "", failure: .offline) }
        #endif
        let store = AppStore(context: container.mainContext, api: api, adFinder: AppConfig.adFinder, firstRun: true)
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-clearInbox") { store.seedHome([]) }
        if arguments.contains("-shipmentDue") { store.makeShipmentDue() }
        // `-skipAdOn` turns the Skip Ad beta on; `-seedAd 20-60` pretends the AI found an ad
        // from 0:20 to 1:00 in every Inbox video (Simulator checks, no AI call).
        if arguments.contains("-skipAdOn") { store.ads.isOn = true }
        if let span = UserDefaults.standard.string(forKey: "seedAd")?.split(separator: "-").compactMap({ Double($0) }),
           span.count == 2 {
            for entry in store.engine.state.home { store.ads.seed([AdSegment(start: span[0], end: span[1])], for: entry.id) }
        }
        #endif
        store.warmFirstCards()
        _store = State(initialValue: store)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(appearance.colorScheme)
                .environment(store)
                .task {
                    #if DEBUG
                    await seedCreatorsForTesting()
                    #endif
                    await store.retryFailedLoads()
                }
                .onChange(of: scenePhase, initial: true) { _, phase in
                    switch phase {
                    case .active:
                        store.appBecameActive()
                        Task { await store.catchUp() }
                    case .background:
                        store.appWentToBackground()
                        BackgroundRefresh.schedule(for: store)
                    default:
                        break
                    }
                }
        }
        .modelContainer(container)
        .backgroundTask(.appRefresh(BackgroundRefresh.identifier)) {
            await store.backgroundRefresh()
        }
    }
}

#if DEBUG
extension KJTubeApp {
    /// `-seedCreators veritasium,3blue1brown` follows those @handles on launch (Simulator checks).
    private func seedCreatorsForTesting() async {
        guard let list = UserDefaults.standard.string(forKey: "seedCreators") else { return }
        // `-seedKeepsFirstRun YES` leaves first run on, to check Following with its first-run bar.
        let firstRun = UserDefaults.standard.bool(forKey: "seedKeepsFirstRun")
        if !firstRun { store.finishFirstRun() } // seeded checks go straight to an Inbox, as before first run existed
        for handle in list.split(separator: ",") {
            if let channel = try? await store.api.channel(handle: String(handle)) {
                await store.follow(channel)
            }
        }
        if firstRun { return } // nothing is served until Load my Inbox (D175)
        store.applyShipments()
        await seedVideosForTesting()
    }

    /// `-seedVideos id1,id2` puts exactly those videos in the Inbox, in that order, in place of
    /// what a shipment would pick. For staged App Store screenshots only (D177).
    private func seedVideosForTesting() async {
        guard let list = UserDefaults.standard.string(forKey: "seedVideos") else { return }
        let ids = list.split(separator: ",").map(String.init)
        guard let found = try? await store.api.videoDetails(ids: ids) else { return }
        let byID = Dictionary(found.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        store.seedHome(ids.compactMap { byID[$0] }.map {
            HomeEntry(video: Video(id: $0.id, creatorID: $0.channelID, title: $0.title, duration: $0.duration, publishedAt: $0.publishedAt))
        })
    }
}
#endif
