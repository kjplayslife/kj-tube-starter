import Foundation
import Observation

/// Runs one viewing session over today's list (docs/specs/player.md). All watch rules go through
/// `AppStore` → `ShipmentEngine`; this class only turns player events into those calls.
@MainActor
@Observable
final class PlayerController {
    /// Resume a little before where you left off.
    static let resumeRewind: TimeInterval = 3
    /// Jumps bigger than this between time updates are seeks, not watching.
    static let maxPlayedStep: TimeInterval = 5
    static let skipInterval: TimeInterval = 10
    /// Playback is handed to the store (and saved) at most this often, plus at every pause,
    /// seek, switch and the watched line. Doing it 4× a second made the page below the video
    /// stutter while scrolling.
    static let flushInterval: TimeInterval = 5
    static let rates: [Double] = [1, 1.25, 1.5, 2]
    /// The poster lifts after this even if YouTube never says "playing" (e.g. during an ad).
    static let posterTimeout: TimeInterval = 4
    /// If a tap on play gets no answer from YouTube in this long, reload the video there.
    static let playTimeout: TimeInterval = 2.5
    /// A tap on play, or a Skip Ad jump, that leaves the video paused gets one more "play"
    /// after this long, before the heavier reload at `playTimeout`.
    static let playNudge: TimeInterval = 1
    /// A video that is still loading this long after a tap on play or a Skip Ad jump is taken
    /// as stuck and loaded again. Long enough for a slow connection to catch up by itself.
    static let bufferTimeout: TimeInterval = 10

    enum Ending: Equatable {
        case none
        /// A video ended and another is waiting: show "Next video".
        case next(HomeEntry)
        /// Nothing left today: show "That's today's shipment", then go Home.
        case allDone
    }

    private(set) var current: HomeEntry
    private(set) var position: TimeInterval = 0
    private(set) var state: PlayerState = .unstarted
    /// False until the current video first plays. Until then our own poster covers YouTube's
    /// loading screen (thumbnail, title, logo).
    private(set) var hasStarted = false
    /// Play was tapped and YouTube hasn't said "playing" yet. YouTube starts the video at once
    /// but reports "loading" first and "playing" a moment later, so the button waited on that
    /// and play felt slow next to pause (D226).
    private var playPending = false
    /// What the play/pause button shows and acts on: playing, or about to be.
    var isPlaying: Bool { state == .playing || playPending }
    private var stallCheck: Task<Void, Never>?
    private var playCheck: Task<Void, Never>?
    private(set) var ending: Ending = .none
    /// The current video's preview pictures, shown while the seek bar is dragged (D134).
    /// Nil until YouTube sends them, and for videos that have none.
    private(set) var storyboard: Storyboard?
    /// Goes up each time the picture catches up with a seek. The seek-bar preview stays over
    /// the video until then, so the old spot never flashes back (D134).
    private(set) var seeksLanded = 0
    /// Set while asking "Play next video?" (D12).
    var pendingSwitch: HomeEntry?
    /// "That video isn't available anymore."
    private(set) var notice: String?

    var rate: Double {
        didSet {
            defaults.set(rate, forKey: "playbackRate")
            player.setRate(effectiveRate)
        }
    }

    /// While the right side of the video is held down, play at 2× (like YouTube). Not saved.
    var boosted = false {
        didSet {
            guard boosted != oldValue else { return }
            player.setRate(effectiveRate)
        }
    }
    static let boostRate: Double = 2

    private var effectiveRate: Double { boosted ? Self.boostRate : rate }

    /// The mute button (D214). Not remembered: every time the player opens, the sound is on.
    var muted = false {
        didSet { player.setMuted(muted) }
    }

    var captions: Bool {
        didSet {
            defaults.set(captions, forKey: "captions")
            player.setCaptions(captions)
        }
    }

    @ObservationIgnored private let store: AppStore
    @ObservationIgnored private let player: VideoPlayer
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var lastTime: TimeInterval?
    /// Seconds watched since the last hand-off to the store.
    @ObservationIgnored private var pendingPlayed: TimeInterval = 0
    @ObservationIgnored private var lastFlush = Date.distantPast
    /// The position last handed to the store. With nothing watched and the same position there
    /// is nothing new to save, and saving redraws the Inbox: YouTube's first few state changes
    /// did that in the middle of the opening slide (D163).
    @ObservationIgnored private var flushedPosition: TimeInterval?
    /// YouTube may switch captions on by itself once playback starts, so the CC choice is
    /// (re)applied the first time each video plays.
    @ObservationIgnored private var captionsApplied = false
    /// A playback error already got its one retry for this stretch of playing (D108).
    @ObservationIgnored private var retriedAfterError = false
    /// YouTube's "this video is gone" errors: not found or private (100), not allowed in apps (101, 150).
    static let goneErrors: Set<Int> = [100, 101, 150]
    /// KJ's own app: the video leaves the Inbox the moment it plays into its watched window,
    /// even while it keeps playing, full size or small (D185). Off in the public app, where
    /// it leaves when the player closes or moves on (D103).
    @ObservationIgnored private let leavesInboxAtWatchedLine: Bool
    /// The current video has already left the Inbox that way.
    @ObservationIgnored private var leftInbox = false

    init(store: AppStore, player: VideoPlayer, start: HomeEntry, defaults: UserDefaults = .standard,
         leavesInboxAtWatchedLine: Bool = false) {
        self.leavesInboxAtWatchedLine = leavesInboxAtWatchedLine
        self.store = store
        self.player = player
        self.defaults = defaults
        current = start
        let savedRate = defaults.double(forKey: "playbackRate")
        rate = Self.rates.contains(savedRate) ? savedRate : 1
        captions = defaults.bool(forKey: "captions")
        player.setMuted(false) // the one web player is reused, and would stay muted from last time
    }

    var duration: TimeInterval { current.video.duration }

    /// Today's list minus the current video, in Home order.
    var upNext: [HomeEntry] {
        store.engine.state.home.filter { $0.id != current.id }
    }

    /// The playhead is in the last 60 s (D11/D38). It leaves Home once the player closes or
    /// moves on while still there; scrubbing back first keeps it (D103).
    var currentIsWatched: Bool {
        duration > 0 && position >= duration - ShipmentEngine.watchedThreshold
    }

    func start() {
        player.onEvent = { [weak self] in self?.handle($0) }
        load(current)
    }

    func stop() {
        stallCheck?.cancel()
        playCheck?.cancel()
        flush()
        store.finishWatching(current.id)
        player.pause()
        player.onEvent = nil
    }

    // MARK: - Controls

    func togglePlay() {
        if isPlaying {
            playCheck?.cancel() // a pause is a choice: nothing may start the video again
            playPending = false
            player.pause()
        } else {
            playPending = true
            player.play()
            makeSurePlaying()
        }
    }

    /// The video must end up playing: called after a tap on play and after a Skip Ad jump.
    /// The YouTube page can be alive but stuck (after the app was away, or after a jump to a
    /// part that isn't loaded yet): it sits paused, or loads forever, and play does nothing.
    /// So if it isn't playing shortly after, ask again; if that gets no answer, load the video
    /// again where it was (which also starts it). Play always works without force-closing the
    /// app. A pause, a new video or the end of the video calls it off.
    private func makeSurePlaying() {
        playCheck?.cancel()
        let id = current.id
        playCheck = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.playNudge))
            guard let self, self.stillWaitingToPlay(id) else { return }
            if self.state != .buffering { self.player.play() }
            try? await Task.sleep(for: .seconds(Self.playTimeout - Self.playNudge))
            guard self.stillWaitingToPlay(id) else { return }
            if self.state == .buffering {
                // Loading is an answer, but not forever.
                try? await Task.sleep(for: .seconds(Self.bufferTimeout - Self.playTimeout))
                guard self.stillWaitingToPlay(id) else { return }
            }
            self.playPending = false // no answer: the button goes back to play while it reloads
            self.player.load(videoID: id, startAt: self.position)
            self.player.setRate(self.effectiveRate)
        }
    }

    private func stillWaitingToPlay(_ id: String) -> Bool {
        !Task.isCancelled && current.id == id && ending == .none && state != .playing
    }

    func pause() {
        playCheck?.cancel()
        playPending = false
        flush()
        player.pause()
    }

    /// Seeking adds no watch time, but landing in the last 60 s still counts as watched (D38).
    func seek(to seconds: TimeInterval) {
        let target = min(max(seconds, 0), duration)
        player.seek(to: target)
        lastTime = target
        position = target
        if leftInbox, !currentIsWatched { leftInbox = false } // scrubbed back out: counts again
        // Still at the end of a video that already left (D185): a put-back one keeps its fresh start (D104).
        if !leftInbox { store.recordPlayback(of: current.id, position: target, played: 0, open: true) }
        flushedPosition = target
    }

    func skip(by delta: TimeInterval) {
        seek(to: position + delta)
    }

    // MARK: - Moving between videos

    /// Tapping an Up Next row. A started video needs confirmation because it'll be gone (D12).
    func requestSwitch(to entry: HomeEntry) {
        if position > 0, !currentIsWatched {
            pendingSwitch = entry
        } else {
            open(entry)
        }
    }

    func confirmSwitch() {
        guard let entry = pendingSwitch else { return }
        pendingSwitch = nil
        flush()
        store.switchAway(from: current.id)
        open(entry)
    }

    /// The next video, offered by the full-screen Play Next button near the end (D102): only
    /// in the last 15 s, however long the video is (D161). Nothing on the last video of the day.
    var playNextOffer: HomeEntry? {
        guard ending == .none, duration > 0, let next = upNext.first else { return nil }
        return position >= duration - Self.playNextWindow ? next : nil
    }

    static let playNextWindow: TimeInterval = 15

    // MARK: - Skip Ad (beta, D111)

    /// The in-video promotion playing right now, if the Skip Ad switch is on and the AI found
    /// one here. Scrubbing in shows it, scrubbing out hides it.
    var activeAd: AdSegment? {
        guard ending == .none else { return nil }
        return AdSegments.active(in: store.ads.ads(for: current.id), at: position)
    }

    /// Jumps to the end of the ad and keeps playing. Never automatic: skipping is a choice.
    func skipAd() {
        guard let ad = activeAd else { return }
        seek(to: ad.end)
        if state != .playing { player.play() }
        // A jump can leave YouTube paused or loading forever. Skip Ad always ends in playback.
        makeSurePlaying()
    }

    func playNext() {
        guard case .next(let entry) = ending else { return }
        open(entry)
    }

    /// Reordering Up Next reorders Home too (P12). The current video keeps its place.
    func moveUpNext(fromOffsets source: IndexSet, toOffset destination: Int) {
        var ids = upNext.map(\.id)
        let moving = source.sorted().map { ids[$0] }
        let insertAt = destination - source.filter { $0 < destination }.count
        ids.removeAll { moving.contains($0) }
        ids.insert(contentsOf: moving, at: insertAt)
        if let currentIndex = store.engine.state.home.firstIndex(where: { $0.id == current.id }) {
            ids.insert(current.id, at: min(currentIndex, ids.count))
        }
        store.setHomeOrder(ids)
    }

    private func open(_ entry: HomeEntry) {
        Timing.videoRequested()
        // Use the latest saved progress for that video.
        load(store.engine.state.home.first { $0.id == entry.id } ?? entry)
    }

    private func load(_ entry: HomeEntry) {
        if lastTime != nil { flush() } // whatever the previous video had pending
        if entry.id != current.id { store.finishWatching(current.id) }
        if entry.id != current.id { storyboard = nil }
        current = entry
        ending = .none
        state = .unstarted
        playPending = false
        hasStarted = false
        let start = entry.progress > 0 ? max(entry.progress - Self.resumeRewind, 0) : 0
        position = start
        lastTime = start
        pendingPlayed = 0
        lastFlush = .distantPast
        flushedPosition = start
        leftInbox = false
        captionsApplied = false
        retriedAfterError = false
        player.load(videoID: entry.id, startAt: start)
        player.setRate(rate)
        nudgeIfStalled(entry.id)
    }

    /// Now and then YouTube loads a video but doesn't start it (it sits cued). If it hasn't
    /// started shortly after the tap, ask again, so a tap always ends in playback (D87).
    private func nudgeIfStalled(_ id: String) {
        stallCheck?.cancel()
        stallCheck = Task { [weak self] in
            for delay in [1.2, 2.5] {
                try? await Task.sleep(for: .seconds(delay))
                guard let self, !Task.isCancelled, self.current.id == id, !self.hasStarted else { return }
                self.player.play()
            }
        }
    }

    // MARK: - Player events

    func handle(_ event: PlayerEvent) {
        switch event {
        case .ready:
            break
        case .seeked:
            seeksLanded += 1
        case .storyboard(let videoID, let spec):
            if videoID == current.id { storyboard = Storyboard(spec: spec, duration: duration) }
        case .reset:
            // The page was rebuilt: put the video back where it was, paused, ready for play.
            stallCheck?.cancel()
            playCheck?.cancel()
            playPending = false
            state = .unstarted
            captionsApplied = false
            player.cue(videoID: current.id, startAt: position)
            player.setRate(rate)
        case .time(let t):
            record(t)
        case .state(let newState):
            state = newState
            if newState == .playing || newState == .ended {
                playCheck?.cancel()
                playPending = false
            }
            if newState != .playing { flush() }
            if newState == .playing {
                Timing.videoPlaying()
                hasStarted = true
                retriedAfterError = false
            }
            if newState == .playing, !captionsApplied {
                captionsApplied = true
                player.setCaptions(captions)
                player.setRate(rate)
                player.setMuted(muted)
            }
            if newState == .ended {
                record(duration)
                finishCurrent()
            }
        case .error(let code) where Self.goneErrors.contains(code):
            notice = "That video isn't available anymore."
            store.dropUnavailable(current.id)
            if let next = upNext.first { open(next) } else { ending = .allDone }
        case .error:
            // Anything else may pass (a weak connection, a YouTube hiccup): the video stays (D108).
            // Try once more at the same spot, then say so and wait for a tap on play.
            stallCheck?.cancel()
            playCheck?.cancel()
            playPending = false
            if retriedAfterError {
                hasStarted = true // lift the loading cover so the banner isn't over a spinner
                notice = "Couldn't play this video. Check your connection and tap play."
            } else {
                retriedAfterError = true
                player.load(videoID: current.id, startAt: position)
                player.setRate(effectiveRate)
            }
        }
    }

    func posterTimedOut() {
        hasStarted = true
    }

    func clearNotice() {
        notice = nil
    }

    private func record(_ t: TimeInterval) {
        let wasWatched = currentIsWatched
        let step = t - (lastTime ?? t)
        let played = (step > 0 && step <= Self.maxPlayedStep) ? step : 0
        lastTime = t
        position = t
        pendingPlayed += played
        let now = Date.now
        let jumped = played == 0 // a seek or skip, not watching
        let crossedLine = currentIsWatched && !wasWatched
        // Scrubbed back out of the watched window: it counts again from here, so a video that
        // was put back (D104) keeps its place, and leaves again if played to the end again.
        if leftInbox, !currentIsWatched { leftInbox = false }
        if jumped || crossedLine || now.timeIntervalSince(lastFlush) >= Self.flushInterval {
            flush(now)
        }
        // Playing inside the watched window: gone from the Inbox right away (D185). A seek
        // that only lands there doesn't count until the video plays on from it.
        if leavesInboxAtWatchedLine, !leftInbox, played > 0, currentIsWatched {
            leftInbox = true
            flush(now)
            store.finishWatching(current.id)
        }
    }

    /// Hands the latest position and watched seconds to the store.
    private func flush(_ now: Date = .now) {
        guard lastTime != nil else { return }
        guard pendingPlayed > 0 || position != flushedPosition else { return }
        if leftInbox {
            // It already left the Inbox while playing (D185). If "Put back" brought it back
            // (D104) it starts over, so playing out the end must not take it away again.
            store.recordWatchTime(pendingPlayed)
        } else {
            store.recordPlayback(of: current.id, position: position, played: pendingPlayed, open: true)
        }
        flushedPosition = position
        pendingPlayed = 0
        lastFlush = now
    }

    /// No autoplay: show "Next video", or wrap up if that was the last one.
    private func finishCurrent() {
        if let next = upNext.first {
            ending = .next(next)
        } else {
            ending = .allDone
        }
    }
}
