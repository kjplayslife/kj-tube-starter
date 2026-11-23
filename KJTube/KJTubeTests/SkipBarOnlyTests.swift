import Testing
@testable import KJTube

/// While skipping ±10 s only the bar and the times show; while holding for 2×, nothing (D227).
@MainActor
struct SkipBarOnlyTests {
    @Test("A plain tap shows everything; hidden shows nothing")
    func plain() {
        #expect(PlayerView.controlParts(shown: true, barOnly: false, boosted: false) == (bar: true, rest: true))
        #expect(PlayerView.controlParts(shown: false, barOnly: false, boosted: false) == (bar: false, rest: false))
    }

    @Test("Skipping keeps the bar and the times, and drops the rest")
    func skipping() {
        #expect(PlayerView.controlParts(shown: true, barOnly: true, boosted: false) == (bar: true, rest: false))
        // Fading out after the last skip: the other controls must not flash back.
        #expect(PlayerView.controlParts(shown: false, barOnly: true, boosted: false) == (bar: false, rest: false))
    }

    @Test("Holding for 2× shows no controls at all, whether they were up or not")
    func holding() {
        #expect(PlayerView.controlParts(shown: false, barOnly: false, boosted: true) == (bar: false, rest: false))
        #expect(PlayerView.controlParts(shown: true, barOnly: false, boosted: true) == (bar: false, rest: false))
        #expect(PlayerView.controlParts(shown: true, barOnly: true, boosted: true) == (bar: false, rest: false))
    }
}
