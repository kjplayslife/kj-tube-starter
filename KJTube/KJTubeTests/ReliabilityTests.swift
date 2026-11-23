import Foundation
import SwiftData
import Testing
@testable import KJTube

/// A YouTube whose answers can change between calls: go offline, come back, fail one creator.
final class ChangeableYouTubeAPI: YouTubeAPI, @unchecked Sendable {
    private let lock = NSLock()
    private var fake: FakeYouTubeAPI
    private var failing: Set<String> = []
    private var running = 0
    private var mostAtOnce = 0
    /// Makes each upload check take a moment, so overlapping ones can be counted.
    var delay: Duration = .zero

    init(_ fake: FakeYouTubeAPI) { self.fake = fake }

    func change(_ body: (inout FakeYouTubeAPI) -> Void) { lock.withLock { body(&fake) } }
    func fail(channels: Set<String>) { lock.withLock { failing = channels } }
    var peak: Int { lock.withLock { mostAtOnce } }
    private var now: FakeYouTubeAPI { lock.withLock { fake } }

    func searchChannels(_ text: String) async throws -> [ChannelSummary] { try await now.searchChannels(text) }
    func channels(ids: [String]) async throws -> [ChannelSummary] { try await now.channels(ids: ids) }
    func channel(handle: String) async throws -> ChannelSummary { try await now.channel(handle: handle) }
    func channelID(ofVideo videoID: String) async throws -> String { try await now.channelID(ofVideo: videoID) }
    func videoDetails(ids: [String]) async throws -> [VideoDetails] { try await now.videoDetails(ids: ids) }
    func videoExtras(ids: [String]) async throws -> [String: VideoExtras] { try await now.videoExtras(ids: ids) }
    func isShort(videoID: String) async throws -> Bool { try await now.isShort(videoID: videoID) }

    func recentUploads(channelID: String, limit: Int) async throws -> [UploadRef] {
        lock.withLock {
            running += 1
            mostAtOnce = max(mostAtOnce, running)
        }
        defer { lock.withLock { running -= 1 } }
        if delay > .zero { try? await Task.sleep(for: delay) }
        if lock.withLock({ failing.contains(channelID) }) { throw YouTubeError.server("down") }
        return try await now.recentUploads(channelID: channelID, limit: limit)
    }
}

/// Reliability pass (docs/specs/reliability-pass.md): R1–R6, R11, R12.
@MainActor
struct ReliabilityTests {
    let container: ModelContainer
    let defaults = UserDefaults(suiteName: "ReliabilityTests-\(UUID())")!
    let a = channel("UCaaaaaaaaaaaaaaaaaaaaaa", "Alpha")
    let b = channel("UCbbbbbbbbbbbbbbbbbbbbbb", "Beta")
    /// Matches FakeYouTubeAPI's `details(daysAgo:)` clock: 2027-01-15, 3:00 am in New York.
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    /// The next morning, an hour after the 6:00 am shipment.
    var morning: Date { now.addingTimeInterval(28 * 3600) }

    init() throws {
        container = try ModelContainer(
            for: Creator.self, EngineRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    func makeStore(_ api: any YouTubeAPI) -> AppStore {
        AppStore(context: container.mainContext, api: api, calendar: testCalendar, defaults: defaults)
    }

    /// Day one is done: Alpha and Beta are followed and their first videos are in the Inbox.
    func dayOne() async -> ChangeableYouTubeAPI {
        var fake = FakeYouTubeAPI()
        for ch in [a, b] { fake.channelsByID[ch.id] = ch }
        fake.uploads = [
            a.id: [details("a1", channel: a.id, minutes: 10, daysAgo: 1)],
            b.id: [details("b1", channel: b.id, minutes: 10, daysAgo: 2)],
        ]
        let api = ChangeableYouTubeAPI(fake)
        let store = makeStore(api)
        await store.follow(a)
        await store.follow(b)
        store.applyShipments(now: now)
        #expect(store.engine.state.home.map(\.id) == ["a1", "b1"])
        return api
    }

    /// A video posted an hour before `morning`.
    func fresh(_ id: String, _ ch: ChannelSummary) -> VideoDetails {
        VideoDetails(id: id, channelID: ch.id, title: id, publishedAt: morning.addingTimeInterval(-3600),
                     duration: 600, liveBroadcastContent: "none", wasLivestream: false, embeddable: true, isPublic: true)
    }

    @Test("R1: a video posted since yesterday is in today's shipment, even with no background wake-up")
    func shipmentWaitsForTheCheck() async {
        let api = await dayOne()
        api.change { $0.uploads[self.a.id]! += [self.fresh("a2", self.a)] }
        let store = makeStore(api)

        // The Inbox appears before YouTube has answered: nothing is delivered yet.
        store.applyShipmentsIfChecked(now: morning)
        #expect(store.isShipmentWaiting(at: morning))
        #expect(store.engine.state.home.map(\.id) == ["a1", "b1"])

        await store.catchUp(now: morning)
        #expect(store.engine.state.home.map(\.id) == ["a1", "b1", "a2"])
        #expect(!store.isShipmentWaiting(at: morning))
        #expect(store.uploadProblem == nil)
    }

    @Test("R2–R4: offline holds the shipment; back online it arrives at once, with the newest uploads")
    func offlineThenBack() async {
        let api = await dayOne()
        api.change {
            $0.uploads[self.a.id]! += [self.fresh("a2", self.a)]
            $0.failWith = .offline
        }
        let store = makeStore(api)
        await store.catchUp(now: morning)
        #expect(store.engine.state.home.map(\.id) == ["a1", "b1"]) // leftovers still there
        #expect(store.isShipmentWaiting(at: morning))
        #expect(store.uploadProblem == .offline)

        // A minute later the connection is back: no 30-minute wait after a failed check.
        api.change { $0.failWith = nil }
        let later = morning.addingTimeInterval(60)
        await store.catchUp(now: later)
        #expect(store.engine.state.home.map(\.id) == ["a1", "b1", "a2"])
        #expect(store.uploadProblem == nil)
    }

    @Test("R5: at YouTube's daily limit the shipment comes from the videos already waiting")
    func dailyLimit() async {
        let api = await dayOne()
        // a2 is fetched into the waiting line during the day, then the limit is hit overnight.
        api.change { $0.uploads[self.a.id]! += [details("a2", channel: self.a.id, minutes: 10, daysAgo: 0)] }
        let store = makeStore(api)
        await store.fetchNewUploads(now: now.addingTimeInterval(60))
        #expect(store.engine.state.backlog.map(\.id) == ["a2"])

        api.change { $0.failWith = .quotaExceeded }
        await store.catchUp(now: morning)
        #expect(store.engine.state.home.map(\.id) == ["a1", "b1", "a2"])
        #expect(store.uploadProblem == .dailyLimit)
    }

    @Test("R6: one creator not answering doesn't hold the shipment, and their video isn't skipped")
    func oneCreatorFails() async {
        let api = await dayOne()
        api.change {
            $0.uploads[self.a.id]! += [self.fresh("a2", self.a)]
            $0.uploads[self.b.id]! += [self.fresh("b2", self.b)]
        }
        api.fail(channels: [b.id])
        let store = makeStore(api)
        await store.catchUp(now: morning)
        #expect(store.engine.state.home.map(\.id) == ["a1", "b1", "a2"])
        #expect(store.uploadProblem == nil)

        api.fail(channels: [])
        let nextDay = morning.addingTimeInterval(24 * 3600)
        await store.catchUp(now: nextDay)
        #expect(store.engine.state.home.map(\.id).contains("b2"))
    }

    @Test("R11: an unfollowed creator's Inbox video keeps their name and picture, even after a relaunch")
    func unfollowedKeepsName() async throws {
        let api = await dayOne()
        let store = makeStore(api)
        let beta = try #require(store.creator(b.id))
        store.unfollow(beta)
        #expect(store.creatorInfoByID()[b.id]?.title == "Beta")
        #expect(store.creatorTitle(b.id) == "Beta")
        #expect(makeStore(api).creatorInfoByID()[b.id]?.title == "Beta")

        // Forgotten once their video has left the Inbox.
        store.removeVideo("b1")
        #expect(makeStore(api).creatorInfoByID()[b.id] == nil)
    }

    @Test("R12: creators are checked several at once, and every video still lands")
    func checkedInParallel() async {
        var fake = FakeYouTubeAPI()
        let channels = (0..<12).map { channel("UC" + String(repeating: Character(UnicodeScalar(UInt8(97 + $0))), count: 22), "C\($0)") }
        for ch in channels {
            fake.channelsByID[ch.id] = ch
            fake.uploads[ch.id] = [details("old-\(ch.title)", channel: ch.id, minutes: 5, daysAgo: 3)]
        }
        let api = ChangeableYouTubeAPI(fake)
        let store = makeStore(api)
        for ch in channels { await store.follow(ch) }
        store.applyShipments(now: now)

        api.change { fake in
            for ch in channels { fake.uploads[ch.id]! += [self.fresh("new-\(ch.title)", ch)] }
        }
        api.delay = .milliseconds(30)
        await store.fetchNewUploads(now: morning)
        #expect(api.peak > 1)
        #expect(api.peak <= AppStore.uploadChecksAtOnce)
        #expect(Set(store.engine.state.backlog.map(\.id)).isSuperset(of: channels.map { "new-\($0.title)" }))
    }
}
