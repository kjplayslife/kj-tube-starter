import Foundation
import Testing
@testable import KJTube

/// Acceptance criteria S1–S6 from docs/specs/swap-one-video.md (D98).
struct SwapVideoTests {
    /// Inbox: two 10-min videos. Backlog: a 40-min video first, then a 12-min one.
    func swappable(settings: ShipmentSettings = ShipmentSettings()) -> ShipmentEngine {
        makeEngine(
            backlog: [video("long", minutes: 40, published: date(10, 27, 5)), video("n1", minutes: 12, published: date(10, 26))],
            home: [HomeEntry(video: video("h1", minutes: 10)), HomeEntry(video: video("h2", minutes: 10))],
            lastShipment: date(10, 27, 6),
            settings: settings
        )
    }

    @Test("S1: swaps one video in the same spot and uses 1 refresh")
    func swapsInPlace() {
        var engine = swappable()
        #expect(engine.swap("h1", at: date(10, 27, 9)) == .allowed(remaining: 1))
        #expect(engine.homeIDs == ["n1", "h2"])
        #expect(engine.state.seen.contains("h1"))
        #expect(!engine.state.backlog.contains { $0.id == "n1" })
        #expect(engine.refreshesRemaining(at: date(10, 27, 9)) == 0)
    }

    @Test("S2: skips videos more than 15 min longer than the one swapped out")
    func skipsTooLong() {
        let engine = swappable()
        #expect(engine.swapCandidate(for: "h1")?.id == "n1") // 40 > 10 + 15
    }

    @Test("S3: works after watching has started")
    func worksAfterWatching() {
        var engine = swappable()
        engine.recordPlayback(of: "h2", position: 300, played: 300)
        #expect(engine.swap("h2", at: date(10, 27, 9)) == .allowed(remaining: 1))
        #expect(engine.homeIDs == ["h1", "n1"])
    }

    @Test("S4: refused with no refreshes left, nothing changes")
    func refusedNoneLeft() {
        var engine = swappable()
        engine.swap("h1", at: date(10, 27, 9))
        let before = engine.state
        #expect(engine.swap("h2", at: date(10, 27, 10)) == .noneLeft)
        #expect(engine.state == before)
    }

    @Test("S5: refused without using a refresh when nothing fits")
    func refusedNothingFits() {
        var engine = makeEngine(
            backlog: [video("long", minutes: 40)],
            home: [HomeEntry(video: video("h1", minutes: 10))],
            lastShipment: date(10, 27, 6)
        )
        let before = engine.state
        #expect(engine.swap("h1", at: date(10, 27, 9)) == .notEnoughVideos)
        #expect(engine.state == before)
        #expect(engine.refreshesRemaining(at: date(10, 27, 9)) == 1)
    }

    @Test("S6: shares the weekly count with pull to refresh")
    func sharesWeeklyCount() {
        var settings = ShipmentSettings()
        settings.refreshesPerDay = 2
        var engine = swappable(settings: settings)
        engine.swap("h1", at: date(10, 27, 9))
        #expect(engine.refreshCheck(at: date(10, 27, 9)) != .noneLeft)
        #expect(engine.refreshesRemaining(at: date(10, 27, 9)) == 1)
        #expect(engine.refreshesRemaining(at: date(11, 2, 6)) == 2) // Monday at shipment time
    }
}
