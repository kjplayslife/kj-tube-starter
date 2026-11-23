import Foundation
import SwiftData
import Testing
@testable import KJTube

@MainActor
final class FakeVideoPlayer: VideoPlayer {
    var onEvent: ((PlayerEvent) -> Void)?
    var loads: [(id: String, start: TimeInterval)] = []
    var cues: [(id: String, start: TimeInterval)] = []
    var plays = 0
    var seeks: [TimeInterval] = []
    var rate: Double = 1
    var captions = false
    var paused = 0

    func load(videoID: String, startAt: TimeInterval) { loads.append((videoID, startAt)) }
    func cue(videoID: String, startAt: TimeInterval) { cues.append((videoID, startAt)) }
    func play() { plays += 1 }
    func pause() { paused += 1 }
    func seek(to seconds: TimeInterval) { seeks.append(seconds) }
    func setRate(_ rate: Double) { self.rate = rate }
    func setCaptions(_ on: Bool) { captions = on }
    var muted = false
    func setMuted(_ on: Bool) { muted = on }

    func send(_ event: PlayerEvent) { onEvent?(event) }
}

/// Player spec P5, P7–P12 at the controller level.
@MainActor
struct PlayerControllerTests {
    let container: ModelContainer
    let store: AppStore
    let player = FakeVideoPlayer()
    let defaults: UserDefaults

    init() throws {
        container = try ModelContainer(
            for: Creator.self, EngineRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        store = AppStore(context: container.mainContext, api: FakeYouTubeAPI(), calendar: testCalendar)
        store.seedHome(["a", "b", "c"].map { HomeEntry(video: video($0, minutes: 10)) })
        defaults = UserDefaults(suiteName: "PlayerControllerTests-\(UUID())")!
    }

    func controller(startAt id: String = "a") -> PlayerController {
        let entry = store.engine.state.home.first { $0.id == id }!
        let controller = PlayerController(store: store, player: player, start: entry, defaults: defaults)
        controller.start()
        return controller
    }

    var homeIDs: [String] { store.engine.state.home.map(\.id) }

    @Test("Starts unstarted videos at 0 and resumes started ones 3 s early (P5)")
    func resume() {
        _ = controller()
        #expect(player.loads.last?.start == 0)
        store.recordPlayback(of: "b", position: 100, played: 100)
        _ = controller(startAt: "b")
        #expect(player.loads.last?.id == "b")
        #expect(player.loads.last?.start == 97)
    }

    @Test("Our poster covers YouTube's loading screen until the video plays, for every video")
    func poster() {
        let c = controller()
        #expect(!c.hasStarted)
        c.handle(.state(.buffering))
        #expect(!c.hasStarted)
        c.handle(.state(.playing))
        #expect(c.hasStarted)
        c.handle(.state(.ended))
        c.playNext()
        #expect(!c.hasStarted) // back on for the next video
        c.posterTimedOut()
        #expect(c.hasStarted) // never stuck (e.g. an ad that doesn't report "playing")
    }

    @Test("Time updates save progress and count played seconds; seeks add none")
    func recordsProgress() {
        let c = controller()
        c.handle(.time(1))
        c.handle(.time(2))
        c.handle(.time(120)) // a jump, not watching
        #expect(store.engine.state.home.first?.progress == 120)
        #expect(store.engine.state.watchedSinceShipment == 2)
    }

    @Test("Holding the right side plays at 2× and lets go back to the chosen speed (D66)")
    func holdForSpeed() {
        let c = controller()
        c.rate = 1.25
        c.boosted = true
        #expect(player.rate == 2)
        c.boosted = false
        #expect(player.rate == 1.25)
        #expect(defaults.double(forKey: "playbackRate") == 1.25) // the hold is never saved
    }

    @Test("Playback reaches the store in batches, and every pause hands over the rest")
    func batchesPlayback() {
        let c = controller()
        c.handle(.time(1)) // the first update goes straight through
        c.handle(.time(2))
        c.handle(.time(3))
        #expect(store.engine.state.home.first?.progress == 1)
        #expect(c.position == 3) // the controls still move every update
        c.pause()
        #expect(store.engine.state.home.first?.progress == 3)
        #expect(store.engine.state.watchedSinceShipment == 3)
    }

    @Test("Crossing into the last minute is handed over at once")
    func lineFlushesNow() {
        let c = controller()
        c.handle(.time(1))
        for t in stride(from: 538.0, through: 541, by: 1) { c.handle(.time(t)) }
        #expect(c.currentIsWatched)
    }

    @Test("Reaching the last 60 s marks it watched once the player closes (D11, D103); seeking there counts too (P8, D38)")
    func lastMinute() {
        let c = controller()
        c.seek(to: 545)
        #expect(c.currentIsWatched)
        #expect(homeIDs == ["a", "b", "c"]) // still open: not decided yet
        c.stop()
        #expect(homeIDs == ["b", "c"])
        #expect(store.engine.state.seen.contains("a"))
        #expect(store.engine.state.watchedSinceShipment == 0)
    }

    @Test("Scrubbing to the end and back to the start keeps it in the Inbox (D103)")
    func scrubBackKeeps() {
        let c = controller()
        c.seek(to: 590)
        #expect(c.playNextOffer?.id == "b")
        c.seek(to: 0)
        #expect(!c.currentIsWatched)
        c.stop()
        #expect(homeIDs == ["a", "b", "c"])
        #expect(!store.engine.state.seen.contains("a"))
    }

    @Test("Moving on to the next video from the last 60 s marks the old one watched (D103)")
    func moveOnFromEnd() {
        let c = controller()
        c.seek(to: 590)
        let next = try! #require(c.playNextOffer)
        c.requestSwitch(to: next)
        #expect(homeIDs == ["b", "c"])
        #expect(store.engine.state.seen.contains("a"))
    }

    @Test("A video left in its last 60 s when the app quit counts as watched on the next launch (D103)")
    func settledOnLaunch() {
        let c = controller()
        c.seek(to: 590) // the app is killed here: stop() never runs
        #expect(homeIDs == ["a", "b", "c"])
        let relaunched = AppStore(context: container.mainContext, api: FakeYouTubeAPI(), calendar: testCalendar)
        #expect(relaunched.engine.state.home.map(\.id) == ["b", "c"])
        #expect(relaunched.engine.state.seen.contains("a"))
    }

    @Test("Switching from a started video asks first; confirming drops it for good (P7, D12)")
    func switchConfirm() {
        let c = controller()
        let b = store.engine.state.home[1]
        c.handle(.time(30))
        c.requestSwitch(to: b)
        #expect(c.pendingSwitch?.id == "b")
        #expect(player.loads.last?.id == "a")

        c.confirmSwitch()
        #expect(player.loads.last?.id == "b")
        #expect(homeIDs == ["b", "c"])
        #expect(store.engine.state.seen.contains("a"))
    }

    @Test("Switching from an unstarted video needs no confirmation and keeps it")
    func switchUnstarted() {
        let c = controller()
        c.requestSwitch(to: store.engine.state.home[2])
        #expect(c.pendingSwitch == nil)
        #expect(player.loads.last?.id == "c")
        #expect(homeIDs == ["a", "b", "c"])
    }

    @Test("A video ending shows Next video, with no autoplay (P9)")
    func endShowsNext() {
        let c = controller()
        c.handle(.state(.ended))
        #expect(c.ending == .next(store.engine.state.home[1]))
        #expect(player.loads.count == 1)
        c.playNext()
        #expect(player.loads.last?.id == "b")
        #expect(c.ending == .none)
    }

    @Test("Full-screen Play Next shows in the last 15 s of a long video (F1, F6)")
    func playNextLongVideo() {
        store.seedHome([HomeEntry(video: video("long", minutes: 20)), HomeEntry(video: video("b", minutes: 10))])
        let c = controller(startAt: "long")
        c.handle(.time(1))
        #expect(c.playNextOffer == nil)
        c.seek(to: 1200 - 60)
        #expect(c.playNextOffer == nil)
        c.seek(to: 1200 - 16)
        #expect(c.playNextOffer == nil)
        c.seek(to: 1200 - 15)
        #expect(c.playNextOffer?.id == "b")
        c.seek(to: 600) // seeking back hides it
        #expect(c.playNextOffer == nil)
    }

    @Test("Full-screen Play Next shows in the last 15 s of a short video too (F2)")
    func playNextShortVideo() {
        store.seedHome([HomeEntry(video: video("short", minutes: 2)), HomeEntry(video: video("b", minutes: 10))])
        let c = controller(startAt: "short")
        c.seek(to: 120 - 16)
        #expect(c.playNextOffer == nil)
        c.seek(to: 120 - 15)
        #expect(c.playNextOffer?.id == "b")
    }

    @Test("Tapping full-screen Play Next starts the next video with no alert (F4)")
    func playNextTap() {
        let c = controller()
        c.handle(.time(1))
        c.handle(.time(2))
        c.seek(to: 590)
        let next = try! #require(c.playNextOffer)
        c.requestSwitch(to: next)
        #expect(c.pendingSwitch == nil)
        #expect(player.loads.last?.id == "b")
        #expect(c.playNextOffer == nil) // the new video is at its start
    }

    @Test("No full-screen Play Next on the last video, or once it has ended (F5)")
    func playNextLastVideo() {
        store.seedHome([HomeEntry(video: video("only", minutes: 20))])
        let c = controller(startAt: "only")
        c.seek(to: 1190)
        #expect(c.playNextOffer == nil)

        store.seedHome(["a", "b"].map { HomeEntry(video: video($0, minutes: 10)) })
        let d = controller()
        d.handle(.state(.ended))
        #expect(d.playNextOffer == nil) // the end screen has its own Next video button
    }

    @Test("The last video ending wraps up the day (P10)")
    func lastVideo() {
        store.seedHome([HomeEntry(video: video("only", minutes: 10))])
        let c = controller(startAt: "only")
        c.handle(.state(.ended))
        #expect(c.ending == .allDone)
        c.stop()
        #expect(store.engine.state.home.isEmpty)
    }

    @Test("An unplayable video is dropped for good and the next one starts (P11)")
    func unavailable() {
        let c = controller()
        c.handle(.error(150))
        #expect(c.notice != nil)
        #expect(store.engine.state.seen.contains("a"))
        #expect(player.loads.last?.id == "b")
        #expect(store.lastRemoved == nil) // no Undo for this
    }

    @Test("R10: a passing YouTube error retries once at the same spot, then keeps the video (D108)")
    func passingErrorKeepsVideo() {
        let c = controller()
        c.handle(.state(.playing))
        c.handle(.time(120))
        c.handle(.error(5))
        #expect(c.notice == nil)
        #expect(player.loads.count == 2)
        #expect(player.loads.last?.id == "a")
        #expect(player.loads.last?.start == 120)

        c.handle(.error(5)) // the retry failed too
        #expect(c.notice == "Couldn't play this video. Check your connection and tap play.")
        #expect(player.loads.count == 2) // no endless retrying
        #expect(homeIDs == ["a", "b", "c"])
        #expect(!store.engine.state.seen.contains("a"))
        #expect(store.engine.state.home.first?.progress == 120)

        // Once it plays again, a later hiccup gets its own retry.
        c.handle(.state(.playing))
        c.handle(.error(2))
        #expect(player.loads.count == 3)
    }

    @Test("Reordering Up Next reorders Home and keeps the current video in place (P12)")
    func reorderUpNext() {
        let c = controller(startAt: "a")
        c.moveUpNext(fromOffsets: [1], toOffset: 0) // Up Next: b, c → c, b
        #expect(homeIDs == ["a", "c", "b"])
        #expect(c.upNext.map(\.id) == ["c", "b"])
    }

    @Test("Speed and captions are remembered (P4)")
    func preferences() {
        let c = controller()
        c.rate = 1.5
        c.captions = true
        #expect(player.rate == 1.5)
        #expect(player.captions)
        let next = PlayerController(store: store, player: player, start: store.engine.state.home[1], defaults: defaults)
        #expect(next.rate == 1.5)
        #expect(next.captions)
    }

    @Test("The CC choice is re-applied when each video starts playing")
    func captionsAppliedOnPlay() {
        let c = controller()
        player.captions = true // YouTube turned them on by itself
        c.handle(.state(.playing))
        #expect(!player.captions)
    }

    @Test("Leaving pauses and stops listening (P6)")
    func stop() {
        let c = controller()
        c.stop()
        #expect(player.paused == 1)
        #expect(player.onEvent == nil)
    }

    @Test("If iOS drops the player page in the background, the video comes back paused where it was")
    func resetAfterBackground() {
        let c = controller()
        c.handle(.time(300))
        player.send(.reset)
        #expect(player.cues.last?.id == "a")
        #expect(player.cues.last?.start == 300)
        #expect(c.state == .unstarted)
    }

    @Test("A tap on play that YouTube ignores reloads the video where it was")
    func playIgnoredReloads() async throws {
        let c = controller()
        c.handle(.time(120))
        c.handle(.state(.paused))
        let loadsBefore = player.loads.count
        c.togglePlay()
        #expect(await waitUntil(timeout: PlayerController.playTimeout + 15) { player.loads.count == loadsBefore + 1 })
        #expect(player.loads.last?.start == 120)
    }

    @Test("A tap on play that leaves the video loading forever reloads it too (D195)")
    func playStuckLoadingReloads() async throws {
        let c = controller()
        c.handle(.time(120))
        c.handle(.state(.paused))
        let loadsBefore = player.loads.count
        let started = ContinuousClock.now
        c.togglePlay()
        c.handle(.state(.buffering))
        try await Task.sleep(for: .seconds(PlayerController.playTimeout + 0.5))
        // Loading is given time first. Only checked when this sleep didn't itself run late on a busy Mac.
        if ContinuousClock.now - started < .seconds(PlayerController.bufferTimeout - 1) {
            #expect(player.loads.count == loadsBefore)
        }
        #expect(await waitUntil(timeout: PlayerController.bufferTimeout + 15) { player.loads.count == loadsBefore + 1 })
        #expect(player.loads.last?.start == 120)
    }

    @Test("A tap on play that works does not reload")
    func playAnsweredNoReload() async throws {
        let c = controller()
        c.handle(.state(.paused))
        let loadsBefore = player.loads.count
        c.togglePlay()
        c.handle(.state(.playing))
        try await Task.sleep(for: .seconds(PlayerController.playTimeout + 0.5))
        #expect(player.loads.count == loadsBefore)
    }

    @Test("The button shows playing the moment play is tapped, before YouTube answers (D226)")
    func playShowsAtOnce() {
        let c = controller()
        c.handle(.state(.paused))
        #expect(!c.isPlaying)
        c.togglePlay()
        #expect(c.isPlaying)
        c.handle(.state(.buffering)) // YouTube says "loading" first, "playing" a moment later
        #expect(c.isPlaying)
        c.handle(.state(.playing))
        #expect(c.isPlaying)
        c.handle(.state(.paused))
        #expect(!c.isPlaying)
    }

    @Test("A second tap before YouTube answers pauses (D226)")
    func tapAgainBeforeAnswerPauses() {
        let c = controller()
        c.handle(.state(.paused))
        c.togglePlay()
        let plays = player.plays
        c.togglePlay()
        #expect(!c.isPlaying)
        #expect(player.plays == plays)
    }

    // MARK: - Leaves the Inbox at the watched line (D185, KJ's own app)

    func privateController() -> PlayerController {
        let entry = store.engine.state.home.first { $0.id == "a" }!
        let controller = PlayerController(store: store, player: player, start: entry, defaults: defaults,
                                          leavesInboxAtWatchedLine: true)
        controller.start()
        return controller
    }

    @Test("D185: playing into the watched window takes the video out of the Inbox at once, still playing")
    func leavesAtLine() {
        let c = privateController()
        c.handle(.state(.playing))
        c.handle(.time(1))
        for t in stride(from: 538.0, through: 539, by: 1) { c.handle(.time(t)) }
        #expect(homeIDs == ["a", "b", "c"]) // not in the window yet
        for t in stride(from: 540.0, through: 542, by: 1) { c.handle(.time(t)) }
        #expect(homeIDs == ["b", "c"])
        #expect(store.engine.state.seen.contains("a"))
        #expect(c.current.id == "a") // the player keeps it
        #expect(c.upNext.map(\.id) == ["b", "c"])
        #expect(player.paused == 0)
        c.stop() // closing later changes nothing
        #expect(homeIDs == ["b", "c"])
    }

    @Test("D185: a seek that only lands in the window keeps the video until it plays on from there")
    func seekAloneKeeps() {
        let c = privateController()
        c.seek(to: 590)
        #expect(homeIDs == ["a", "b", "c"])
        c.seek(to: 0)
        c.stop()
        #expect(homeIDs == ["a", "b", "c"]) // D103 still holds for a scrub there and back
    }

    @Test("D185: seek into the window, then play: gone on the next moment of playing")
    func seekThenPlayLeaves() {
        let c = privateController()
        c.seek(to: 590)
        c.handle(.time(590.5))
        #expect(homeIDs == ["b", "c"])
    }

    @Test("D185: off by default (the public app), where the video leaves when the player closes")
    func publicKeepsUntilClose() {
        let c = controller()
        c.handle(.time(1))
        for t in stride(from: 538.0, through: 545, by: 1) { c.handle(.time(t)) }
        #expect(homeIDs == ["a", "b", "c"])
        c.stop()
        #expect(homeIDs == ["b", "c"])
    }

    @Test("D104 + D185: put back while it is still playing its end, and it stays put back")
    func putBackWhileStillPlaying() {
        let c = privateController()
        c.handle(.state(.playing))
        c.handle(.time(1))
        for t in stride(from: 538.0, through: 542, by: 1) { c.handle(.time(t)) }
        #expect(homeIDs == ["b", "c"])
        store.putBackLastVideo()
        #expect(homeIDs == ["a", "b", "c"])
        let before = store.engine.state.watchedSinceShipment
        for t in stride(from: 543.0, through: 580, by: 1) { c.handle(.time(t)) }
        c.stop()
        #expect(homeIDs == ["a", "b", "c"]) // still there after the player closes
        #expect(store.engine.state.home.first { $0.id == "a" }?.progress == 0) // starts over
        #expect(store.engine.state.watchedSinceShipment > before) // the time still counts
    }

    @Test("D104 + D185: put back, scrub back and watch to the end again: it leaves again")
    func putBackThenRewatch() {
        let c = privateController()
        c.handle(.state(.playing))
        c.handle(.time(1))
        for t in stride(from: 538.0, through: 542, by: 1) { c.handle(.time(t)) }
        store.putBackLastVideo()
        c.seek(to: 300)
        for t in stride(from: 301.0, through: 305, by: 1) { c.handle(.time(t)) }
        c.seek(to: 538)
        for t in stride(from: 539.0, through: 542, by: 1) { c.handle(.time(t)) }
        #expect(homeIDs == ["b", "c"])
    }
}
