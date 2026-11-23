import Foundation
import SwiftData
import Testing
@testable import KJTube

/// D218: on the "No new videos from your creators" Inbox, a new follow brings its latest video,
/// and "Load my Inbox" serves it. While it's looked up, the Inbox says so.
@MainActor
struct EmptyInboxFollowTests {
    let container: ModelContainer
    let a = channel("UCaaaaaaaaaaaaaaaaaaaaaa", "Alpha")
    let b = channel("UCbbbbbbbbbbbbbbbbbbbbbb", "Beta")
    /// Matches FakeYouTubeAPI's `details(daysAgo:)` clock.
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    var later: Date { now.addingTimeInterval(2 * 86_400) }

    init() throws {
        container = try ModelContainer(
            for: Creator.self, EngineRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    func api() -> FakeYouTubeAPI {
        var fake = FakeYouTubeAPI()
        for ch in [a, b] { fake.channelsByID[ch.id] = ch }
        fake.uploads = [
            a.id: [details("a1", channel: a.id, minutes: 30, daysAgo: 1)],
            b.id: [details("b1", channel: b.id, minutes: 20, daysAgo: 2)],
        ]
        return fake
    }

    /// Day one is over: a1 was served and watched, and the next shipment found nothing.
    func emptyInboxStore(_ api: any YouTubeAPI) async -> AppStore {
        let store = AppStore(context: container.mainContext, api: api, calendar: testCalendar, firstRun: true)
        await store.follow(a)
        store.finishFirstRun(now: now)
        for entry in store.engine.state.home {
            store.recordPlayback(of: entry.id, position: entry.video.duration, played: 0)
        }
        store.applyShipments(now: later)
        return store
    }

    @Test("The engine takes a new follow's latest video while the Inbox is starved, even after day one")
    func starvedWantsStarters() {
        var engine = makeEngine(backlog: [video("h", minutes: 10)], lastShipment: date(10, 26, 6))
        engine.applyDueShipments(at: date(10, 27, 7))
        engine.recordPlayback(of: "h", position: 600, played: 600, at: date(10, 27, 8))
        #expect(engine.homeIDs.isEmpty && !engine.state.seen.isEmpty)
        #expect(!engine.wantsStarters) // all watched: today is done (empty state A)

        engine.applyDueShipments(at: date(10, 28, 7)) // the next shipment finds nothing
        #expect(engine.isStarved)
        #expect(engine.wantsStarters)
    }

    @Test("Following from the empty Inbox brings the latest video, served on coming back")
    func followFillsEmptyInbox() async {
        let store = await emptyInboxStore(api())
        #expect(store.engine.isStarved)
        #expect(!store.engine.state.seen.isEmpty)

        await store.follow(b)
        store.applyShipmentsIfChecked(now: later.addingTimeInterval(60)) // back on the Inbox
        #expect(store.engine.state.home.isEmpty) // it waits for the button
        #expect(store.isWaitingForLoad)

        store.loadInbox(now: later.addingTimeInterval(120))
        #expect(store.engine.state.home.map(\.id) == ["b1"])
        #expect(!store.engine.isStarved && !store.isWaitingForLoad)
    }

    @Test("Load my Inbox serves in the order the creators are ranked at that moment")
    func loadUsesCurrentRank() async {
        var fake = api()
        let c = channel("UCcccccccccccccccccccccc", "Gamma")
        fake.channelsByID[c.id] = c
        fake.uploads[c.id] = [details("c1", channel: c.id, minutes: 20, daysAgo: 2)]
        let store = await emptyInboxStore(fake)
        await store.follow([b, c])
        store.moveCreators(fromOffsets: [2], toOffset: 0) // Gamma to the top
        store.loadInbox(now: later.addingTimeInterval(60))
        #expect(store.engine.state.home.map(\.id) == ["c1", "b1"])
    }

    @Test("A brand-new upload on the empty Inbox is still served by itself (D26)")
    func newUploadServesAtOnce() async {
        var fake = api()
        let store = await emptyInboxStore(fake)
        fake.uploads[a.id]! += [details("a2", channel: a.id, minutes: 10, daysAgo: -2)]
        let relaunched = AppStore(context: container.mainContext, api: fake, calendar: testCalendar, firstRun: true)
        _ = store
        await relaunched.catchUp(now: later.addingTimeInterval(3_600))
        #expect(relaunched.engine.state.home.map(\.id) == ["a2"])
    }

    @Test("Load my Inbox tapped while a video is still being looked up serves it when it lands")
    func loadBeforeLookupEnds() async {
        let gate = Gate()
        let store = await emptyInboxStore(GatedYouTubeAPI(inner: api(), gate: gate, holds: b.id))
        let follow = Task { await store.follow(b) }
        #expect(await waitUntil(timeout: 5) { store.followsLoading > 0 })
        store.loadInbox(now: later.addingTimeInterval(60))
        await gate.open()
        await follow.value
        #expect(!store.isWaitingForLoad)
        store.applyShipmentsIfChecked(now: later.addingTimeInterval(120)) // what the Inbox does when it lands
        #expect(store.engine.state.home.map(\.id) == ["b1"])
    }

    @Test("Dev: emptying the Inbox gives the No new videos screen, and a follow then waits for the button")
    func devEmptyInbox() async {
        let store = AppStore(context: container.mainContext, api: api(), calendar: testCalendar, firstRun: true)
        await store.follow(a)
        store.finishFirstRun(now: now)
        #expect(store.engine.state.home.map(\.id) == ["a1"])
        store.emptyInboxForTesting(now: now)
        #expect(store.engine.isStarved && !store.isShipmentWaiting(at: now))
        await store.follow(b)
        #expect(store.isWaitingForLoad)
        store.loadInbox(now: now)
        #expect(store.engine.state.home.map(\.id) == ["b1"])
    }

    @Test("Once the Inbox has videos again, a follow brings no old video (D92 as before)")
    func servedInboxTakesNoStarter() async {
        var fake = api()
        fake.uploads[b.id] = [details("b1", channel: b.id, minutes: 60, daysAgo: 2)] // fills the day (a weekend, 60 min)
        let c = channel("UCcccccccccccccccccccccc", "Gamma")
        fake.channelsByID[c.id] = c
        fake.uploads[c.id] = [details("c1", channel: c.id, minutes: 10, daysAgo: 2)]
        let store = await emptyInboxStore(fake)
        await store.follow(b)
        store.loadInbox(now: later.addingTimeInterval(60))
        #expect(store.engine.state.home.map(\.id) == ["b1"])

        await store.follow(c)
        #expect(store.engine.state.backlog.isEmpty)
    }

    @Test("The store says a follow is loading until its video lookup is done")
    func loadingWhileLookingUp() async {
        let gate = Gate()
        let store = await emptyInboxStore(GatedYouTubeAPI(inner: api(), gate: gate, holds: b.id))
        #expect(store.followsLoading == 0)

        let follow = Task { await store.follow(b) }
        #expect(await waitUntil(timeout: 5) { store.followsLoading > 0 })
        #expect(store.engine.state.backlog.isEmpty)

        await gate.open()
        await follow.value
        #expect(store.followsLoading == 0)
        #expect(store.engine.state.backlog.map(\.id) == ["b1"])
    }

    @Test("Following several at once counts as loading until all are done")
    func loadingForSeveral() async {
        let gate = Gate()
        let store = await emptyInboxStore(GatedYouTubeAPI(inner: api(), gate: gate, holds: b.id))
        let follow = Task { await store.follow([b]) }
        #expect(await waitUntil(timeout: 5) { store.followsLoading > 0 })
        await gate.open()
        await follow.value
        #expect(store.followsLoading == 0)
    }
}

/// Holds a lookup until it's opened, so a test can look at the app mid-load.
actor Gate {
    private var isOpen = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiting.append($0) }
    }

    func open() {
        isOpen = true
        waiting.forEach { $0.resume() }
        waiting = []
    }
}

/// The fake YouTube, with one creator's uploads list held behind a gate.
struct GatedYouTubeAPI: YouTubeAPI {
    let inner: FakeYouTubeAPI
    let gate: Gate
    let holds: String

    func searchChannels(_ text: String) async throws -> [ChannelSummary] { try await inner.searchChannels(text) }
    func channels(ids: [String]) async throws -> [ChannelSummary] { try await inner.channels(ids: ids) }
    func channel(handle: String) async throws -> ChannelSummary { try await inner.channel(handle: handle) }
    func channelID(ofVideo videoID: String) async throws -> String { try await inner.channelID(ofVideo: videoID) }
    func recentUploads(channelID: String, limit: Int) async throws -> [UploadRef] {
        if channelID == holds { await gate.wait() }
        return try await inner.recentUploads(channelID: channelID, limit: limit)
    }
    func videoDetails(ids: [String]) async throws -> [VideoDetails] { try await inner.videoDetails(ids: ids) }
    func videoExtras(ids: [String]) async throws -> [String: VideoExtras] { try await inner.videoExtras(ids: ids) }
    func isShort(videoID: String) async throws -> Bool { try await inner.isShort(videoID: videoID) }
}
