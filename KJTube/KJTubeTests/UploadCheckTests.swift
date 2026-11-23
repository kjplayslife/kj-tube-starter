import Foundation
import SwiftData
import Testing
@testable import KJTube

/// Counts what a new-uploads check costs in YouTube quota: one unit per call.
final class CountingYouTubeAPI: YouTubeAPI, @unchecked Sendable {
    private let lock = NSLock()
    private var fake: FakeYouTubeAPI
    private var listed = 0
    private var detailed: [Int] = []

    init(_ fake: FakeYouTubeAPI) { self.fake = fake }

    func change(_ body: (inout FakeYouTubeAPI) -> Void) { lock.withLock { body(&fake) } }
    /// playlistItems.list calls so far.
    var listCalls: Int { lock.withLock { listed } }
    /// How many IDs each videos.list call asked for.
    var detailCalls: [Int] { lock.withLock { detailed } }
    func reset() { lock.withLock { listed = 0; detailed = [] } }
    private var now: FakeYouTubeAPI { lock.withLock { fake } }

    func searchChannels(_ text: String) async throws -> [ChannelSummary] { try await now.searchChannels(text) }
    func channels(ids: [String]) async throws -> [ChannelSummary] { try await now.channels(ids: ids) }
    func channel(handle: String) async throws -> ChannelSummary { try await now.channel(handle: handle) }
    func channelID(ofVideo videoID: String) async throws -> String { try await now.channelID(ofVideo: videoID) }
    func videoExtras(ids: [String]) async throws -> [String: VideoExtras] { try await now.videoExtras(ids: ids) }
    func isShort(videoID: String) async throws -> Bool { try await now.isShort(videoID: videoID) }

    func recentUploads(channelID: String, limit: Int) async throws -> [UploadRef] {
        lock.withLock { listed += 1 }
        return try await now.recentUploads(channelID: channelID, limit: limit)
    }

    func videoDetails(ids: [String]) async throws -> [VideoDetails] {
        lock.withLock { detailed.append(ids.count) }
        return try await now.videoDetails(ids: ids)
    }
}

/// Twice-a-day upload check (D231) and one details call for all creators (D232).
@MainActor
struct UploadCheckTests {
    let container: ModelContainer
    let defaults = UserDefaults(suiteName: "UploadCheckTests-\(UUID())")!
    /// Matches FakeYouTubeAPI's `details(daysAgo:)` clock: 2027-01-15, 3:00 am in New York.
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    /// 6:00 am that day, when new videos arrive.
    var sixAM: Date { now.addingTimeInterval(3 * 3600) }

    init() throws {
        container = try ModelContainer(
            for: Creator.self, EngineRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    private func makeStore(_ api: any YouTubeAPI) -> AppStore {
        AppStore(context: container.mainContext, api: api, calendar: testCalendar, defaults: defaults)
    }

    private func channels(_ count: Int) -> [ChannelSummary] {
        (0..<count).map { channel("UC" + String(format: "%022d", $0), "C\($0)") }
    }

    private func fresh(_ id: String, _ ch: ChannelSummary, at date: Date) -> VideoDetails {
        VideoDetails(id: id, channelID: ch.id, title: id, publishedAt: date, duration: 600,
                     liveBroadcastContent: "none", wasLivestream: false, embeddable: true, isPublic: true)
    }

    @Test("D231: the check stretches start 30 min before new videos arrive and 12 hours after that")
    func checkStretches() {
        let engine = makeEngine() // new videos at 6:00 am
        #expect(engine.uploadCheckStart(containing: date(10, 26, 5, 29)) == date(10, 25, 17, 30))
        #expect(engine.uploadCheckStart(containing: date(10, 26, 5, 30)) == date(10, 26, 5, 30))
        #expect(engine.uploadCheckStart(containing: date(10, 26, 17, 29)) == date(10, 26, 5, 30))
        #expect(engine.uploadCheckStart(containing: date(10, 26, 17, 30)) == date(10, 26, 17, 30))
        #expect(engine.uploadCheckStart(containing: date(10, 27, 2)) == date(10, 26, 17, 30))
    }

    @Test("D231: YouTube is asked once in the morning and once 12 hours later, however often the app opens")
    func twiceADay() async {
        var fake = FakeYouTubeAPI()
        let all = channels(3)
        for ch in all {
            fake.channelsByID[ch.id] = ch
            fake.uploads[ch.id] = [details("old-\(ch.title)", channel: ch.id, daysAgo: 3)]
        }
        let api = CountingYouTubeAPI(fake)
        let store = makeStore(api)
        for ch in all { await store.follow(ch) }
        api.reset()

        await store.fetchNewUploads(now: sixAM)
        #expect(api.listCalls == 3)
        // Opening again and again through the day asks nothing.
        for hours in [1.0, 4, 8, 11] { await store.fetchNewUploads(now: sixAM.addingTimeInterval(hours * 3600)) }
        #expect(api.listCalls == 3)
        // Not even after the app was closed and opened again.
        await makeStore(api).fetchNewUploads(now: sixAM.addingTimeInterval(5 * 3600))
        #expect(api.listCalls == 3)

        // 12 hours on, a video posted during the day is found.
        api.change { $0.uploads[all[0].id]!.append(self.fresh("noon", all[0], at: self.sixAM.addingTimeInterval(6 * 3600))) }
        await store.fetchNewUploads(now: sixAM.addingTimeInterval(12 * 3600))
        #expect(api.listCalls == 6)
        #expect(store.engine.state.backlog.map(\.id).contains("noon"))
        await store.fetchNewUploads(now: sixAM.addingTimeInterval(20 * 3600))
        #expect(api.listCalls == 6)

        // The next morning's check may run up to 30 min early (the background wake-up).
        await store.fetchNewUploads(now: sixAM.addingTimeInterval(23.6 * 3600))
        #expect(api.listCalls == 9)
        await store.fetchNewUploads(now: sixAM.addingTimeInterval(24.5 * 3600))
        #expect(api.listCalls == 9)
    }

    @Test("D232: new videos from every creator share one details call, 50 at a time")
    func detailsInOneCall() async {
        var fake = FakeYouTubeAPI()
        let all = channels(60)
        for ch in all {
            fake.channelsByID[ch.id] = ch
            fake.uploads[ch.id] = [details("old-\(ch.title)", channel: ch.id, daysAgo: 3)]
        }
        let api = CountingYouTubeAPI(fake)
        let store = makeStore(api)
        for ch in all { await store.follow(ch) }
        api.reset()

        // 55 of the 60 creators posted since.
        api.change { fake in
            for ch in all.prefix(55) { fake.uploads[ch.id]!.append(self.fresh("new-\(ch.title)", ch, at: self.now)) }
        }
        await store.fetchNewUploads(now: sixAM)
        #expect(api.listCalls == 60)
        #expect(api.detailCalls == [50, 5])
        #expect(Set(store.engine.state.backlog.map(\.id)).isSuperset(of: all.prefix(55).map { "new-\($0.title)" }))

        // Nobody posted: no details call at all.
        api.reset()
        await store.fetchNewUploads(now: sixAM.addingTimeInterval(12 * 3600))
        #expect(api.listCalls == 60)
        #expect(api.detailCalls.isEmpty)
    }

    @Test("D235: after a week without opening the app, the background wake-up asks YouTube nothing")
    func quietAfterAWeekUnopened() async {
        var fake = FakeYouTubeAPI()
        let all = channels(3)
        for ch in all {
            fake.channelsByID[ch.id] = ch
            fake.uploads[ch.id] = [details("old-\(ch.title)", channel: ch.id, daysAgo: 3)]
        }
        let api = CountingYouTubeAPI(fake)
        let store = makeStore(api)
        for ch in all { await store.follow(ch) }
        store.appBecameActive(now: sixAM)
        api.reset()

        // Six days on, the wake-up still checks.
        await store.backgroundRefresh(now: sixAM.addingTimeInterval(6 * 86_400))
        let whileActive = api.listCalls
        #expect(whileActive >= 3)

        // Eight days after the last open: nothing, however many times iOS wakes the app.
        api.change { $0.uploads[all[0].id]!.append(self.fresh("while-away", all[0], at: self.sixAM.addingTimeInterval(7 * 86_400))) }
        api.reset()
        for days in [8.0, 9, 20] { await store.backgroundRefresh(now: sixAM.addingTimeInterval(days * 86_400)) }
        #expect(api.listCalls == 0)
        #expect(api.detailCalls.isEmpty)

        // Opening the app brings it back, with what was posted meanwhile.
        let back = sixAM.addingTimeInterval(21 * 86_400)
        store.appBecameActive(now: back)
        await store.catchUp(now: back)
        #expect(api.listCalls == 3)
        #expect(store.engine.state.backlog.map(\.id).contains("while-away") || store.engine.state.home.map(\.id).contains("while-away"))
        await store.backgroundRefresh(now: back.addingTimeInterval(86_400))
        #expect(api.listCalls == 6)
    }

    @Test("D235: an install from before this was tracked starts its week at the first wake-up")
    func olderInstallStartsItsWeek() async {
        let store = makeStore(CountingYouTubeAPI(FakeYouTubeAPI()))
        #expect(store.engine.state.lastOpenedAt == nil)
        #expect(!store.isDormant(at: sixAM))
        #expect(store.engine.state.lastOpenedAt == sixAM)
        #expect(!store.isDormant(at: sixAM.addingTimeInterval(7 * 86_400)))
        #expect(store.isDormant(at: sixAM.addingTimeInterval(7 * 86_400 + 60)))
    }
}
