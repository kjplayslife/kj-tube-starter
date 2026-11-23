import Foundation

/// Finds the promotions inside a video. This starter ships with no finder
/// (`AppConfig.adFinder` is nil); write your own without touching the player.
protocol AdFinder: Sendable {
    /// Raw ad times, not yet cleaned up. Throws when there is no answer.
    func findAds(videoID: String) async throws -> [AdSegment]
}

enum AdFinderError: Error, Equatable {
    case server(Int)
    case badAnswer
}
