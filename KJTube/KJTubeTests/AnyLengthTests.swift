import Foundation
import Testing
@testable import KJTube

/// Acceptance criteria L1–L6 from docs/specs/any-length.md (D151).
struct AnyLengthTests {
    /// c1 is ranked over c2 and c3. c2 has a 75-min video waiting; c3 has two 15-min videos.
    /// Weekday budget is 30 min, so "over time" is anything past 45 min.
    func longWaiting(anyLength: Bool = true) -> ShipmentEngine {
        var engine = makeEngine(
            backlog: [
                video("long", creator: "c2", minutes: 75, published: date(10, 26)),
                video("s1", creator: "c3", minutes: 15, published: date(10, 26)),
                video("s2", creator: "c3", minutes: 15, published: date(10, 25)),
            ],
            lastShipment: date(10, 26, 6),
            rank: ["c1", "c2", "c3"]
        )
        engine.setAnyLength(anyLength, for: "c2")
        return engine
    }

    @Test("L1: an over-time video that is first in line is served, alone")
    func servedAlone() {
        var engine = longWaiting()
        engine.applyDueShipments(at: date(10, 27, 6))
        #expect(engine.homeIDs == ["long"])
        #expect(engine.state.backlog.map(\.id) == ["s1", "s2"])
        // The next day goes back to normal.
        engine.applyDueShipments(at: date(10, 28, 6))
        #expect(engine.homeIDs == ["long", "s1", "s2"])
    }

    @Test("L2: with the switch off, an over-time video is never served")
    func offIsUnchanged() {
        var engine = longWaiting(anyLength: false)
        #expect(engine.state.anyLengthCreators == nil)
        engine.applyDueShipments(at: date(10, 27, 6))
        #expect(engine.homeIDs == ["s1", "s2"])
        #expect(engine.state.backlog.map(\.id) == ["long"])
    }

    @Test("L3: behind a higher creator's video it waits, the day fills as normal, and it comes later")
    func waitsBehindHigherRank() {
        var engine = longWaiting()
        engine.addToBacklog([video("top", creator: "c1", minutes: 20, published: date(10, 26))])
        engine.applyDueShipments(at: date(10, 27, 6))
        // top (20) is picked first, long is passed over, s1 fills the day (35 >= 30).
        #expect(engine.homeIDs == ["top", "s1"])
        #expect(engine.state.backlog.contains { $0.id == "long" })
        // Next day nothing is ranked above it: it comes alone, under the carryover.
        engine.applyDueShipments(at: date(10, 28, 6))
        #expect(engine.homeIDs == ["top", "s1", "long"])
        #expect(engine.state.backlog.map(\.id) == ["s2"])
    }

    @Test("L4: an Any Length creator's video that fits follows the normal rules")
    func normalWhenItFits() {
        var engine = longWaiting()
        engine.state.backlog[0] = video("mid", creator: "c2", minutes: 25, published: date(10, 26))
        engine.applyDueShipments(at: date(10, 27, 6))
        // mid (25) + s1 (15) = 40, under 45, and the budget is reached.
        #expect(engine.homeIDs == ["mid", "s1"])
    }

    @Test("L4: on a day with a bigger budget the same video is just a normal pick")
    func fitsOnWeekend() {
        var settings = ShipmentSettings()
        settings.weekendBudget = 90 * 60
        var engine = longWaiting()
        engine.settings = settings
        engine.state.lastShipment = date(10, 30, 6) // Friday; the next shipment is Saturday
        engine.applyDueShipments(at: date(10, 31, 6))
        // 75 + 15 = 90: both fit under 105 and the budget is reached.
        #expect(engine.homeIDs == ["long", "s1"])
    }

    @Test("L5: refresh can bring it as the only video; swap and the short-day fill never do")
    func otherPickers() {
        var refreshed = longWaiting()
        refreshed.state.home = [HomeEntry(video: video("h1", minutes: 30))]
        #expect(refreshed.refresh(at: date(10, 26, 9)) == .allowed(remaining: 1))
        #expect(refreshed.homeIDs == ["long"])

        var swapped = longWaiting()
        swapped.state.home = [HomeEntry(video: video("h1", minutes: 30))]
        #expect(swapped.swapCandidate(for: "h1")?.id == "s1") // 75 > 30 + 15

        var short = longWaiting()
        short.state.home = [HomeEntry(video: video("h1", minutes: 5))]
        short.state.lastShipmentContent = 5 * 60
        short.state.lastShipmentDelivered = 1
        #expect(short.isShortToday)
        short.fillToday(at: date(10, 26, 9))
        #expect(short.homeIDs == ["h1", "s1", "s2"])
        #expect(short.state.backlog.map(\.id) == ["long"])
    }

    @Test("L6: turning the switch on or off never changes the Inbox")
    func inboxUntouched() {
        var engine = longWaiting(anyLength: false)
        engine.applyDueShipments(at: date(10, 27, 6))
        let before = engine.state.home
        engine.setAnyLength(true, for: "c2")
        #expect(engine.state.home == before)
        engine.setAnyLength(false, for: "c2")
        #expect(engine.state.home == before)
        #expect(engine.state.anyLengthCreators == nil)
    }

    @Test("Works with Watch in Order: the older, shorter episode goes first, then the long one alone")
    func withWatchInOrder() {
        var engine = longWaiting()
        engine.setInOrder(true, for: "c2")
        engine.addToBacklog([video("ep1", creator: "c2", minutes: 20, published: date(10, 25))])
        engine.applyDueShipments(at: date(10, 27, 6))
        #expect(engine.homeIDs == ["ep1", "s1"])
        engine.applyDueShipments(at: date(10, 28, 6))
        #expect(engine.homeIDs == ["ep1", "s1", "long"])
    }
}
