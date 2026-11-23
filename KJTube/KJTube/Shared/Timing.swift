import Foundation
import os

/// Signposts for the two speed targets (PLAN §5): cold launch → Home visible (< 400 ms) and
/// tap → video playing (< 1.5 s). Visible in Instruments' "Points of Interest".
@MainActor
enum Timing {
    private static let signposter = OSSignposter(subsystem: "com.example.kjtube", category: .pointsOfInterest)
    private static var launch: OSSignpostIntervalState?
    private static var tap: OSSignpostIntervalState?

    static func launchStarted() {
        launch = signposter.beginInterval("Launch")
    }

    static func homeVisible() {
        guard let state = launch else { return }
        signposter.endInterval("Launch", state)
        launch = nil
    }

    static func videoRequested() {
        tap = signposter.beginInterval("TapToPlay")
    }

    static func videoPlaying() {
        guard let tap else { return }
        signposter.endInterval("TapToPlay", tap)
        self.tap = nil
    }
}
