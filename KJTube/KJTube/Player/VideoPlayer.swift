import Foundation

/// Playback states, matching the YouTube IFrame API's numbers.
enum PlayerState: Int, Sendable {
    case unstarted = -1, ended = 0, playing = 1, paused = 2, buffering = 3, cued = 5
}

enum PlayerEvent: Equatable, Sendable {
    case ready
    case state(PlayerState)
    /// Playhead position, sent ~4× a second while playing.
    case time(TimeInterval)
    /// IFrame API error code (2, 5, 100, 101, 150…).
    case error(Int)
    /// The player had to start over (iOS dropped the web page while the app was in the
    /// background). Whatever was loaded is gone and needs loading again.
    case reset
    /// YouTube's preview pictures for a video (its "storyboard spec"), for the seek bar (D134).
    /// The picture has caught up with a seek: the frame at the new spot is showing.
    case seeked
    case storyboard(videoID: String, spec: String)
}

/// Swappable player (D3): v1 is the YouTube IFrame player; a native AVPlayer can replace it later.
@MainActor
protocol VideoPlayer: AnyObject {
    var onEvent: ((PlayerEvent) -> Void)? { get set }
    func load(videoID: String, startAt: TimeInterval)
    /// Loads a video without starting it.
    func cue(videoID: String, startAt: TimeInterval)
    func play()
    func pause()
    func seek(to seconds: TimeInterval)
    func setRate(_ rate: Double)
    func setCaptions(_ on: Bool)
    func setMuted(_ on: Bool)
}
