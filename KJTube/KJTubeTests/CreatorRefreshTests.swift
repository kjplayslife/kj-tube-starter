import Foundation
import SwiftData
import Testing
@testable import KJTube

/// Saved creator names and pictures are refreshed from YouTube at most once a week, so nothing
/// from YouTube is kept longer than its 30-day rule allows (public release, D177).
@MainActor
struct CreatorRefreshTests {
    let container: ModelContainer
    let defaults: UserDefaults
    let a = channel("UCaaaaaaaaaaaaaaaaaaaaaa", "Alpha", handle: "@alpha")
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    init() throws {
        container = try ModelContainer(
            for: Creator.self, EngineRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let suite = "CreatorRefreshTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
    }

    private func store(_ fake: FakeYouTubeAPI) -> AppStore {
        AppStore(context: container.mainContext, api: fake, calendar: testCalendar, defaults: defaults)
    }

    private func followed() async -> FakeYouTubeAPI {
        var fake = FakeYouTubeAPI()
        fake.channelsByID[a.id] = a
        await store(fake).follow(a)
        return fake
    }

    @Test func aRenamedCreatorGetsTheNewNameHandleAndPicture() async {
        var fake = await followed()
        let picture = URL(string: "https://example.com/new.jpg")!
        fake.channelsByID[a.id] = ChannelSummary(id: a.id, title: "Alpha Prime", handle: "@alphaprime", avatarURL: picture, subscriberCount: 5)
        let store = store(fake)
        await store.refreshCreators(now: now)
        let creator = store.creator(a.id)
        #expect(creator?.title == "Alpha Prime")
        #expect(creator?.handle == "@alphaprime")
        #expect(creator?.avatarURL == picture)
    }

    @Test func itAsksAtMostOnceAWeek() async {
        var fake = await followed()
        await store(fake).refreshCreators(now: now)
        fake.channelsByID[a.id] = channel(a.id, "Later Name")
        let store = store(fake)
        await store.refreshCreators(now: now.addingTimeInterval(6 * 86_400))
        #expect(store.creator(a.id)?.title == "Alpha")
        await store.refreshCreators(now: now.addingTimeInterval(7 * 86_400))
        #expect(store.creator(a.id)?.title == "Later Name")
    }

    @Test func aFailedLookupChangesNothingAndIsTriedAgain() async {
        var fake = await followed()
        fake.failWith = .offline
        let offline = store(fake)
        await offline.refreshCreators(now: now)
        #expect(offline.creator(a.id)?.title == "Alpha")
        fake.failWith = nil
        fake.channelsByID[a.id] = channel(a.id, "Back Online")
        let online = store(fake)
        await online.refreshCreators(now: now.addingTimeInterval(60))
        #expect(online.creator(a.id)?.title == "Back Online")
    }
}
