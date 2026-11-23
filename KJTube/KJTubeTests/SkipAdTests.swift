import Foundation
import SwiftData
import Testing
@testable import KJTube

/// docs/specs/skip-ad.md: the pure rules (S2, S6, S9).
struct AdSegmentsTests {
    let ads = [AdSegment(start: 73, end: 90), AdSegment(start: 600, end: 660)]

    @Test("An ad is live from its start up to its end, and not between ads (S2, S6)")
    func active() {
        #expect(AdSegments.active(in: ads, at: 72.9) == nil)
        #expect(AdSegments.active(in: ads, at: 73) == ads[0])
        #expect(AdSegments.active(in: ads, at: 89.9) == ads[0])
        #expect(AdSegments.active(in: ads, at: 90) == nil)
        #expect(AdSegments.active(in: ads, at: 300) == nil)
        #expect(AdSegments.active(in: ads, at: 610) == ads[1])
        #expect(AdSegments.active(in: [], at: 10) == nil)
    }

    @Test("Clean-up drops tiny and broken ads, joins overlaps, trims to the video (S9)")
    func clean() {
        let raw = [
            AdSegment(start: 500, end: 520), AdSegment(start: 515, end: 540), // overlap → one
            AdSegment(start: 10, end: 13),                                    // under 5 s
            AdSegment(start: 80, end: 70),                                    // backwards
            AdSegment(start: 590, end: 700),                                  // past the end
            AdSegment(start: -4, end: 8),                                     // before the start
        ]
        #expect(AdSegments.clean(raw, duration: 600) == [
            AdSegment(start: 0, end: 8), AdSegment(start: 500, end: 540), AdSegment(start: 590, end: 600),
        ])
        #expect(AdSegments.clean([], duration: 600).isEmpty)
    }

    @Test("Reads MM:SS and H:MM:SS times")
    func seconds() {
        #expect(AdSegments.seconds("01:16") == 76)
        #expect(AdSegments.seconds("1:02:03") == 3723)
        #expect(AdSegments.seconds("45") == 45)
        #expect(AdSegments.seconds("abc") == nil)
        #expect(AdSegments.seconds("1:2:3:4") == nil)
    }
}

/// A scripted AI: answers by video ID, counts the calls.
final class FakeAdFinder: AdFinder, @unchecked Sendable {
    var answers: [String: [AdSegment]] = [:]
    private(set) var asked: [String] = []
    func findAds(videoID: String) async throws -> [AdSegment] {
        asked.append(videoID)
        guard let answer = answers[videoID] else { throw AdFinderError.server(500) }
        return answer
    }
}

@MainActor
struct AdStoreTests {
    let defaults = UserDefaults(suiteName: "AdStoreTests-\(UUID())")!
    let finder = FakeAdFinder()
    let videos = [video("a", minutes: 10), video("b", minutes: 10)]

    func makeStore(finder: (any AdFinder)?) -> AdStore { AdStore(finder: finder, defaults: defaults) }

    @Test("Off by default: no button data and no AI calls (S1)")
    func offByDefault() async {
        finder.answers["a"] = [AdSegment(start: 10, end: 40)]
        let store = makeStore(finder: finder)
        #expect(!store.isOn)
        store.check(videos)
        await store.worker?.value
        #expect(finder.asked.isEmpty)
        #expect(store.ads(for: "a").isEmpty)
    }

    @Test("On: each Inbox video is asked once and the cleaned answer is saved (S10)")
    func asksOnce() async {
        finder.answers["a"] = [AdSegment(start: 10, end: 40), AdSegment(start: 50, end: 52)]
        finder.answers["b"] = []
        let store = makeStore(finder: finder)
        store.isOn = true
        store.check(videos)
        await store.worker?.value
        store.check(videos)
        await store.worker?.value
        #expect(finder.asked == ["a", "b"])
        #expect(store.ads(for: "a") == [AdSegment(start: 10, end: 40)])
        #expect(store.ads(for: "b").isEmpty)
        // Saved on the phone: a relaunch asks nothing.
        let relaunched = makeStore(finder: finder)
        relaunched.check(videos)
        await relaunched.worker?.value
        #expect(finder.asked == ["a", "b"])
        #expect(relaunched.ads(for: "a") == [AdSegment(start: 10, end: 40)])
    }

    @Test("A failed check is retried once per app open, three times at most (S10)")
    func retries() async {
        for launch in 1...5 {
            let store = makeStore(finder: finder)
            store.isOn = true
            store.check([videos[0]])
            await store.worker?.value
            store.check([videos[0]]) // same launch: not asked again
            await store.worker?.value
            #expect(finder.asked.count == min(launch, AdStore.maxTries))
            #expect(store.ads(for: "a").isEmpty)
        }
    }

    @Test("Turning it off hides saved ads and stops checks; they're kept for later (S11)")
    func switchOff() async {
        finder.answers["a"] = [AdSegment(start: 10, end: 40)]
        let store = makeStore(finder: finder)
        store.isOn = true
        store.check([videos[0]])
        await store.worker?.value
        store.isOn = false
        #expect(store.ads(for: "a").isEmpty)
        store.check(videos)
        await store.worker?.value
        #expect(finder.asked == ["a"])
        store.isOn = true
        #expect(store.ads(for: "a") == [AdSegment(start: 10, end: 40)])
    }

    @Test("A missing key: the switch can't be on (S12)")
    func noKey() {
        defaults.set(true, forKey: AdStore.switchKey)
        let store = makeStore(finder: nil)
        #expect(!store.hasFinder)
        #expect(!store.isOn)
    }

    @Test("Videos that left the Inbox are forgotten")
    func prunes() async {
        finder.answers["a"] = [AdSegment(start: 10, end: 40)]
        finder.answers["b"] = []
        let store = makeStore(finder: finder)
        store.isOn = true
        store.check(videos)
        await store.worker?.value
        store.check([videos[1]])
        await store.worker?.value
        #expect(store.records.keys.sorted() == ["b"])
    }
}

/// The Skip Ad button at the controller level (S2, S3, S5, S7, S8, S11).
@MainActor
struct SkipAdPlayerTests {
    let container: ModelContainer
    let store: AppStore
    let player = FakeVideoPlayer()
    let defaults = UserDefaults(suiteName: "SkipAdPlayerTests-\(UUID())")!

    init() throws {
        container = try ModelContainer(
            for: Creator.self, EngineRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        store = AppStore(
            context: container.mainContext, api: FakeYouTubeAPI(), calendar: testCalendar,
            defaults: defaults, adFinder: FakeAdFinder()
        )
        store.seedHome(["a", "b"].map { HomeEntry(video: video($0, minutes: 10)) })
        store.ads.isOn = true
        store.ads.seed([AdSegment(start: 73, end: 90), AdSegment(start: 540, end: 600)], for: "a")
    }

    func controller(_ id: String = "a") -> PlayerController {
        let entry = store.engine.state.home.first { $0.id == id }!
        let controller = PlayerController(store: store, player: player, start: entry, defaults: defaults)
        controller.start()
        player.send(.state(.playing))
        return controller
    }

    @Test("The button shows from the ad's start to its end (S2)")
    func window() {
        let c = controller()
        player.send(.time(72))
        #expect(c.activeAd == nil)
        player.send(.time(73))
        #expect(c.activeAd == AdSegment(start: 73, end: 90))
        player.send(.time(90))
        #expect(c.activeAd == nil)
    }

    @Test("Tapping jumps to the ad's end and keeps playing (S3)")
    func skip() {
        let c = controller()
        player.send(.time(75))
        c.skipAd()
        #expect(player.seeks.last == 90)
        #expect(c.position == 90)
        #expect(c.activeAd == nil)
    }

    @Test("A skip that leaves YouTube paused is started again, then reloaded at the ad's end (D195)")
    func skipLeftPaused() async throws {
        let c = controller()
        player.send(.time(75))
        c.skipAd()
        player.send(.state(.paused))
        let plays = player.plays, loads = player.loads.count
        let started = ContinuousClock.now
        #expect(await waitUntil(timeout: PlayerController.playNudge + 15) { player.plays == plays + 1 })
        // The reload comes later. Only checked when the nudge didn't itself run late on a busy Mac.
        if ContinuousClock.now - started < .seconds(PlayerController.playTimeout - 0.5) {
            #expect(player.loads.count == loads)
        }
        #expect(await waitUntil(timeout: PlayerController.playTimeout + 15) { player.loads.count == loads + 1 })
        #expect(player.loads.last?.start == 90)
    }

    @Test("A skip that keeps playing is left alone (D195)")
    func skipKeepsPlaying() async throws {
        let c = controller()
        player.send(.time(75))
        c.skipAd()
        player.send(.state(.buffering))
        player.send(.state(.playing))
        let plays = player.plays, loads = player.loads.count
        try await Task.sleep(for: .seconds(PlayerController.playTimeout + 0.4))
        #expect(player.plays == plays)
        #expect(player.loads.count == loads)
    }

    @Test("Pausing right after a skip stays paused (D195)")
    func pauseAfterSkip() async throws {
        let c = controller()
        player.send(.time(75))
        c.skipAd()
        c.togglePlay()
        player.send(.state(.paused))
        let plays = player.plays, loads = player.loads.count
        try await Task.sleep(for: .seconds(PlayerController.playTimeout + 0.4))
        #expect(player.plays == plays)
        #expect(player.loads.count == loads)
    }

    @Test("Scrubbing in shows it, scrubbing out hides it (S5)")
    func scrub() {
        let c = controller()
        c.seek(to: 80)
        #expect(c.activeAd != nil)
        c.seek(to: 200)
        #expect(c.activeAd == nil)
    }

    @Test("A video with no saved ads plays as before (S7)")
    func noAds() {
        let c = controller("b")
        player.send(.time(75))
        #expect(c.activeAd == nil)
        c.skipAd()
        #expect(player.seeks.isEmpty)
    }

    @Test("An ad that runs to the end: the tap jumps there, watched only on leaving (S8)")
    func adAtEnd() {
        let c = controller()
        player.send(.time(545))
        c.skipAd()
        #expect(player.seeks.last == 600)
        #expect(store.engine.state.home.contains { $0.id == "a" })
        c.stop()
        #expect(!store.engine.state.home.contains { $0.id == "a" })
    }

    @Test("Switching it off hides the button mid-video (S11)")
    func off() {
        let c = controller()
        player.send(.time(75))
        #expect(c.activeAd != nil)
        store.ads.isOn = false
        #expect(c.activeAd == nil)
    }
}
