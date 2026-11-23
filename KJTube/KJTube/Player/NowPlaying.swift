import SwiftUI

/// The video the player is showing, if any. The player sits on top of the tabs rather than in a
/// full-screen cover, so it can shrink to a small player and keep playing over the Inbox (D165).
@MainActor @Observable
final class NowPlaying {
    static let shared = NowPlaying()

    private(set) var entry: HomeEntry?
    /// The top of the tapped card's picture, where the player starts its slide from (D138).
    private(set) var openFrom: CGFloat?
    /// New for every open, so tapping a card always builds a fresh player.
    private(set) var token = UUID()

    func play(_ entry: HomeEntry, from openFrom: CGFloat?) {
        guard self.entry != nil else { return show(entry, openFrom) }
        // Close the small player first and open the new video on the next pass, so the old
        // player has stopped before the new one starts on the same web view.
        self.entry = nil
        DispatchQueue.main.async { self.show(entry, openFrom) }
    }

    func close() { entry = nil }

    private func show(_ entry: HomeEntry, _ openFrom: CGFloat?) {
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) {
            self.openFrom = openFrom
            token = UUID()
            self.entry = entry
        }
    }
}
