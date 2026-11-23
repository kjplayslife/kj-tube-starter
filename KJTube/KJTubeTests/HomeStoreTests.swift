import Foundation
import SwiftData
import Testing
@testable import KJTube

/// Home behavior at the store level (shipment-and-home spec, D16, D26).
@MainActor
struct HomeStoreTests {
    let container: ModelContainer
    let a = channel("UCaaaaaaaaaaaaaaaaaaaaaa", "Alpha")
    let b = channel("UCbbbbbbbbbbbbbbbbbbbbbb", "Beta")
    /// Matches FakeYouTubeAPI's `details(daysAgo:)` clock.
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    init() throws {
        container = try ModelContainer(
            for: Creator.self, EngineRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    /// Pulls 3 videos per new creator (the app pulls 1, D79) so these scenarios have a fuller Home.
    func makeStore(_ api: FakeYouTubeAPI) -> AppStore {
        let store = AppStore(context: container.mainContext, api: api, calendar: testCalendar)
        store.videosPerNewCreator = 3
        return store
    }

    func api(uploads: [String: [VideoDetails]] = [:]) -> FakeYouTubeAPI {
        var fake = FakeYouTubeAPI()
        for ch in [a, b] { fake.channelsByID[ch.id] = ch }
        fake.uploads = uploads
        return fake
    }

    @Test("D16: the first shipment arrives as soon as Home sees creators")
    func firstShipment() async {
        let store = makeStore(api(uploads: [a.id: (1...3).map { details("a\($0)", channel: a.id, minutes: 10, daysAgo: $0) }]))
        await store.follow(a)
        #expect(store.engine.state.home.isEmpty) // following alone never touches Home
        store.applyShipments(now: now)
        #expect(store.engine.state.home.map(\.id) == ["a1", "a2", "a3"])
    }

    @Test("Empty state A (all watched) does not serve early")
    func allWatchedWaits() async {
        let store = makeStore(api(uploads: [a.id: (1...6).map { details("a\($0)", channel: a.id, minutes: 10, daysAgo: $0) }]))
        await store.follow(a)
        store.applyShipments(now: now)
        for entry in store.engine.state.home {
            store.recordPlayback(of: entry.id, position: entry.video.duration, played: 0)
        }
        await store.follow(b)
        store.applyShipments(now: now.addingTimeInterval(60))
        #expect(store.engine.state.home.isEmpty)
        #expect(!store.engine.isStarved)
    }

    @Test("D26: empty state B serves as soon as a new creator brings videos")
    func starvedServes() async {
        var fake = api(uploads: [b.id: [details("b1", channel: b.id, minutes: 20)]])
        fake.uploads[a.id] = [details("live", channel: a.id, live: "live")]
        let store = makeStore(fake)
        await store.follow(a)
        store.applyShipments(now: now)
        #expect(store.engine.isStarved)

        await store.follow(b)
        store.applyShipments(now: now.addingTimeInterval(60))
        #expect(store.engine.state.home.map(\.id) == ["b1"])
    }

    @Test("PLAN §3.3: only uploads newer than the last one seen join the backlog")
    func fetchesOnlyNewUploads() async {
        var fake = api(uploads: [a.id: (2...6).map { details("old\($0)", channel: a.id, daysAgo: $0) }])
        let store = makeStore(fake)
        await store.follow(a) // backlog: old2, old3, old4
        #expect(store.engine.state.backlog.count == 3)

        fake.uploads[a.id]! += [details("new1", channel: a.id, daysAgo: 1), details("new0", channel: a.id, daysAgo: 0)]
        let refreshed = AppStore(context: container.mainContext, api: fake, calendar: testCalendar)
        await refreshed.fetchNewUploads(now: now)
        // The follow's starters leave once the creator posts something new (D80).
        #expect(Set(refreshed.engine.state.backlog.map(\.id)) == ["new1", "new0"])
    }

    @Test("PLAN §3.3: a \"Last upload\" time saved without its video doesn't hide the video")
    func lastUploadAloneDoesNotHideVideo() async {
        var fake = api(uploads: [a.id: [details("a-old", channel: a.id, daysAgo: 5)]])
        let store = makeStore(fake)
        await store.follow(a)
        store.applyShipments(now: now)

        // A new upload's time reaches Following (saved on its own, or by a retry),
        // but the video never joined the line.
        fake.uploads[a.id]! += [details("a-new", channel: a.id, daysAgo: 1)]
        store.creator(a.id)?.lastUploadAt = details("a-new", daysAgo: 1).publishedAt
        store.save()

        let relaunched = makeStore(fake)
        await relaunched.fetchNewUploads(now: now)
        #expect(relaunched.engine.state.backlog.map(\.id) == ["a-new"])
    }

    @Test("Older installs look back 3 days once, then only fetch what's new")
    func olderInstallRecoversRecentUploads() async {
        var fake = api(uploads: [a.id: [details("a-old", channel: a.id, daysAgo: 6)]])
        let store = makeStore(fake)
        await store.follow(a)
        store.applyShipments(now: now)
        #expect(store.engine.state.home.map(\.id) == ["a-old"])

        // Saved by an older build: "Last upload" moved to a2, but a2 never joined the line.
        fake.uploads[a.id]! += [details("a2", channel: a.id, daysAgo: 2), details("a5", channel: a.id, daysAgo: 5)]
        store.creator(a.id)?.lastUploadAt = details("a2", daysAgo: 2).publishedAt
        store.clearFetchCursors()

        let relaunched = makeStore(fake)
        await relaunched.fetchNewUploads(now: now)
        // a2 is back; a5 is older than 3 days; a-old is already on Home.
        #expect(relaunched.engine.state.backlog.map(\.id) == ["a2"])

        // From now on, only newer uploads.
        let later = now.addingTimeInterval(ShipmentEngine.uploadCheckGap + 60)
        await relaunched.fetchNewUploads(now: later)
        #expect(relaunched.engine.state.backlog.map(\.id) == ["a2"])
    }

    @Test("D91: once, an older install drops day-one videos and keeps only the last 24 hours")
    func oneTimeRecentReset() async throws {
        var fake = api(uploads: [a.id: (1...3).map { details("a\($0)", channel: a.id, minutes: 10, daysAgo: $0) }])
        let store = makeStore(fake)
        await store.follow(a)
        store.applyShipments(now: now)
        #expect(store.engine.state.home.map(\.id) == ["a1", "a2", "a3"])

        // Pretend this install is from before the cleanup existed.
        let record = try #require(try container.mainContext.fetch(FetchDescriptor<EngineRecord>()).first)
        var state = try JSONDecoder().decode(ShipmentState.self, from: record.stateData)
        state.recentResetDone = nil
        record.stateData = try JSONEncoder().encode(state)

        fake.uploads[a.id]! += [details("new", channel: a.id, minutes: 10, daysAgo: 0)]
        let later = now.addingTimeInterval(60 * 60)
        let relaunched = makeStore(fake)
        await relaunched.catchUp(now: later)
        #expect(relaunched.engine.state.home.map(\.id) == ["new"])
        #expect(relaunched.engine.state.seen.isSuperset(of: ["a1", "a2", "a3"]))
        #expect(relaunched.creators().map(\.title) == ["Alpha"]) // follows kept

        // It runs only once: a later old-looking video isn't cleared again.
        relaunched.seedHome([HomeEntry(video: Video(id: "kept", creatorID: a.id, title: "kept", duration: 600,
                                                     publishedAt: now.addingTimeInterval(-5 * 86_400)))])
        relaunched.applyShipments(now: later.addingTimeInterval(60))
        #expect(relaunched.engine.state.home.map(\.id) == ["kept"])
    }

    @Test("D92: after day one, following brings no old videos, only new uploads")
    func laterFollowSkipsOldVideos() async {
        var fake = api(uploads: [
            a.id: [details("a1", channel: a.id, minutes: 20, daysAgo: 1)], // fills the day, so no D136 fill
            b.id: [details("b-old", channel: b.id, minutes: 10, daysAgo: 2)],
        ])
        let store = makeStore(fake)
        await store.follow(a)
        store.applyShipments(now: now)
        #expect(store.engine.state.home.map(\.id) == ["a1"])

        await store.follow(b)
        #expect(store.engine.state.backlog.isEmpty)
        #expect(store.creator(b.id)?.loadState == .ready)

        fake.uploads[b.id]! += [details("b-new", channel: b.id, minutes: 10, daysAgo: 0)]
        let relaunched = makeStore(fake)
        await relaunched.fetchNewUploads(now: now)
        #expect(relaunched.engine.state.backlog.map(\.id) == ["b-new"])
    }

    @Test("Remove + Undo through the store, and removal persists")
    func removeUndo() async {
        let store = makeStore(api(uploads: [a.id: (1...3).map { details("a\($0)", channel: a.id, minutes: 10, daysAgo: $0) }]))
        await store.follow(a)
        store.applyShipments(now: now)
        store.removeVideo("a2")
        #expect(store.engine.state.home.map(\.id) == ["a1", "a3"])
        store.undoRemoveVideo()
        #expect(store.engine.state.home.map(\.id) == ["a1", "a2", "a3"])
        store.removeVideo("a1")
        store.clearRemoveUndo()
        #expect(makeStore(api()).engine.state.seen.contains("a1"))
    }

    @Test("State saved before lastShipmentDelivered existed still loads")
    func oldStateDecodes() throws {
        let old = #"{"home":[],"backlog":[],"seen":["x"],"watchedSinceShipment":0,"refreshesUsed":0}"#
        let state = try JSONDecoder().decode(ShipmentState.self, from: Data(old.utf8))
        #expect(state.seen == ["x"])
        #expect(state.lastShipmentDelivered == nil)
    }
}

struct FormatTests {
    @Test func clock() {
        #expect(Format.clock(754) == "12:34")
        #expect(Format.clock(3723) == "1:02:03")
    }

    @Test func minutes() {
        #expect(Format.minutes(42 * 60) == "42 min")
        #expect(Format.minutes(65 * 60) == "1 h 5 min")
        #expect(Format.minutes(30) == "1 min")
    }

    @Test func countdown() {
        #expect(Format.countdown(9 * 3600 + 12 * 60) == "9h 12m")
        #expect(Format.countdown(42 * 60) == "42m")
        #expect(Format.countdown(20) == "20s")
    }
}
