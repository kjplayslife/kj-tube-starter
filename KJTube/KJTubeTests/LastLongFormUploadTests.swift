import Foundation
import SwiftData
import Testing
@testable import KJTube

/// "Last upload" on Following counts long-form videos only (D230).
@MainActor
struct LastLongFormUploadTests {
    let container: ModelContainer
    let a = channel("UCaaaaaaaaaaaaaaaaaaaaaa", "Alpha")
    /// Matches FakeYouTubeAPI's `details(daysAgo:)` clock.
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    init() throws {
        container = try ModelContainer(
            for: Creator.self, EngineRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    func makeStore(_ api: FakeYouTubeAPI) -> AppStore {
        AppStore(context: container.mainContext, api: api, calendar: testCalendar)
    }

    func api(_ uploads: [VideoDetails], shorts: Set<String> = []) -> FakeYouTubeAPI {
        var fake = FakeYouTubeAPI()
        fake.channelsByID[a.id] = a
        fake.uploads = [a.id: uploads]
        fake.shorts = shorts
        return fake
    }

    @Test("Following a creator: a newer Short or live replay doesn't count as the last upload")
    func followSkipsShortsAndLives() async {
        let store = makeStore(api([
            details("short", channel: a.id, minutes: 0.5, daysAgo: 1),
            details("replay", channel: a.id, daysAgo: 2, wasLivestream: true),
            details("long", channel: a.id, daysAgo: 6),
        ], shorts: ["short"]))
        await store.follow(a)
        #expect(store.creator(a.id)?.lastUploadAt == details("long", daysAgo: 6).publishedAt)
    }

    @Test("The daily check: a new Short or live stream leaves the last upload alone, a new video moves it")
    func dailyCheckSkipsShortsAndLives() async {
        var fake = api([details("long", channel: a.id, daysAgo: 6)])
        let store = makeStore(fake)
        await store.follow(a)
        store.applyShipments(now: now)

        fake.uploads[a.id]! += [
            details("short", channel: a.id, minutes: 0.5, daysAgo: 3),
            details("live", channel: a.id, daysAgo: 2, live: "live"),
        ]
        fake.shorts = ["short"]
        let next = makeStore(fake)
        await next.fetchNewUploads(now: now)
        #expect(next.creator(a.id)?.lastUploadAt == details("long", daysAgo: 6).publishedAt)
        #expect(next.engine.state.backlog.isEmpty)

        // The Short and the stream aren't looked at again, and a real video still arrives.
        fake.uploads[a.id]! += [details("long2", channel: a.id, daysAgo: 1)]
        let later = makeStore(fake)
        await later.fetchNewUploads(now: now.addingTimeInterval(ShipmentEngine.uploadCheckGap)) // the next check (D231)
        #expect(later.creator(a.id)?.lastUploadAt == details("long2", daysAgo: 1).publishedAt)
        #expect(later.engine.state.backlog.map(\.id) == ["long2"])
    }

    @Test("One time: a date saved from a Short by an older build is put right")
    func oldDatesAreFixedOnce() async {
        var fake = api([
            details("short", channel: a.id, minutes: 0.5, daysAgo: 1),
            details("long", channel: a.id, daysAgo: 6),
        ], shorts: ["short"])
        let store = makeStore(fake)
        await store.follow(a)
        store.applyShipments(now: now)
        // What an older build saved: the Short's time.
        store.creator(a.id)?.lastUploadAt = details("short", daysAgo: 1).publishedAt
        store.save()

        let relaunched = makeStore(fake)
        await relaunched.catchUp(now: now)
        #expect(relaunched.creator(a.id)?.lastUploadAt == details("long", daysAgo: 6).publishedAt)
        #expect(relaunched.engine.state.longFormDatesDone == true)

        // Done once: a later catch-up doesn't scan again.
        relaunched.creator(a.id)?.lastUploadAt = nil
        fake.uploads[a.id] = []
        await relaunched.catchUp(now: now.addingTimeInterval(ShipmentEngine.uploadCheckGap + 60))
        #expect(relaunched.creator(a.id)?.lastUploadAt == nil)
    }

    @Test("One time fix: tried again later when YouTube didn't answer")
    func fixRetriesAfterFailure() async {
        var fake = api([details("long", channel: a.id, daysAgo: 6)])
        let store = makeStore(fake)
        await store.follow(a)
        fake.failWith = .offline
        let offline = makeStore(fake)
        await offline.fixLastUploadDates()
        #expect(offline.engine.state.longFormDatesDone != true)
    }
}
