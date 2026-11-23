import Testing
@testable import KJTube

/// The player bar must never fall back to 0:00 while a video is part-way through.
struct PlayerClockTests {
    @Test("A playing video's time is passed on")
    func playingTime() {
        #expect(YouTubeIFramePlayer.timeToReport(state: 1, time: 312.5) == 312.5)
        #expect(YouTubeIFramePlayer.timeToReport(state: 1, time: 0) == 0)
    }

    @Test("A video that isn't running yet can't reset the clock to 0:00")
    func notRunningIsIgnored() {
        for state in [-1, 0, 2, 5] {
            #expect(YouTubeIFramePlayer.timeToReport(state: state, time: 0) == nil)
        }
        #expect(YouTubeIFramePlayer.timeToReport(state: nil, time: 0) == nil)
        #expect(YouTubeIFramePlayer.timeToReport(state: 3, time: 0) == nil) // buffering before the first bytes
    }

    @Test("Buffering part-way through keeps its time; odd values are dropped")
    func bufferingAndOddValues() {
        #expect(YouTubeIFramePlayer.timeToReport(state: 3, time: 300) == 300)
        #expect(YouTubeIFramePlayer.timeToReport(state: 1, time: nil) == nil)
        #expect(YouTubeIFramePlayer.timeToReport(state: 1, time: .nan) == nil)
        #expect(YouTubeIFramePlayer.timeToReport(state: 1, time: -1) == nil)
    }
}
