import Foundation
import SwiftData
import Testing
@testable import KJTube

/// YouTube-style Home cards: views and age text, fresh view counts.
struct CardFormatTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("View counts read like YouTube's")
    func views() {
        #expect(Format.views(940) == "940")
        #expect(Format.views(59_321) == "59K")
        #expect(Format.views(1_234_567) == "1.2M")
    }

    @Test("Web addresses in a description become links; other text doesn't")
    func links() {
        let text = Format.linked("Merch: https://www.odablock.net and more")
        let links = text.runs.compactMap { $0.link }
        #expect(links == [URL(string: "https://www.odablock.net")!])
        #expect(String(text.characters) == "Merch: https://www.odablock.net and more")
    }

    @Test("The Inbox title spells minutes out")
    func minutesLong() {
        #expect(Format.minutesLong(60) == "1 minute")
        #expect(Format.minutesLong(44 * 60) == "44 minutes")
        #expect(Format.minutesLong(60 * 60) == "1 hour")
        #expect(Format.minutesLong(65 * 60) == "1 hour 5 minutes")
        #expect(Format.minutesLong(125 * 60) == "2 hours 5 minutes")
    }

    @Test("Ages read like YouTube's")
    func ages() {
        #expect(Format.age(now.addingTimeInterval(-20), now: now) == "1m ago")
        #expect(Format.age(now.addingTimeInterval(-5 * 60), now: now) == "5m ago")
        #expect(Format.age(now.addingTimeInterval(-3 * 3600), now: now) == "3h ago")
        #expect(Format.age(now.addingTimeInterval(-7 * 86_400 + 60), now: now) == "6d ago")
        #expect(Format.age(now.addingTimeInterval(-7 * 86_400), now: now) == "1w ago")
        #expect(Format.age(now.addingTimeInterval(-60 * 86_400), now: now) == "2mo ago")
        #expect(Format.age(now.addingTimeInterval(-400 * 86_400), now: now) == "1y ago")
    }
}

@MainActor
struct ViewCountTests {
    let container: ModelContainer
    let a = channel("UCaaaaaaaaaaaaaaaaaaaaaa", "Alpha")
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    init() throws {
        container = try ModelContainer(
            for: Creator.self, EngineRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    let defaults = UserDefaults(suiteName: "HomeCardTests-\(UUID())")!

    func makeStore(extras: [String: VideoExtras]) async -> AppStore {
        var fake = FakeYouTubeAPI()
        fake.channelsByID[a.id] = a
        fake.uploads[a.id] = (1...2).map { details("a\($0)", channel: a.id, daysAgo: $0) }
        fake.extras = extras
        let store = AppStore(context: container.mainContext, api: fake, calendar: testCalendar, defaults: defaults)
        await store.follow(a)
        store.applyShipments(now: now)
        return store
    }

    @Test("Today's videos get views and descriptions; creators get subscriber counts")
    func fetched() async {
        let extras = VideoExtras(viewCount: 59_321, description: "Hello")
        let store = await makeStore(extras: ["a1": extras])
        await store.refreshExtras(now: now)
        #expect(store.videoExtras == ["a1": extras])
        #expect(store.subscriberCounts == [a.id: 1_000]) // `channel()` test helper's count
    }

    @Test("Views from the last fetch show right away after a relaunch")
    func keptForRelaunch() async {
        let extras = VideoExtras(viewCount: 11_000, description: "Hi")
        let store = await makeStore(extras: ["a1": extras])
        await store.refreshExtras(now: now)
        let relaunched = AppStore(context: container.mainContext, api: FakeYouTubeAPI(), calendar: testCalendar, defaults: defaults)
        #expect(relaunched.videoExtras == ["a1": extras])
    }

    @Test("Card avatars come from the followed creator")
    func avatar() async {
        let store = await makeStore(extras: [:])
        #expect(store.creator(a.id)?.title == "Alpha")
        #expect(store.creator("UCnobody") == nil)
    }
}
