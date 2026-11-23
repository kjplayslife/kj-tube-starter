import Foundation
import Testing
@testable import KJTube

/// Acceptance criteria W1–W6 from docs/specs/watch-in-order.md (D150).
struct WatchInOrderTests {
    /// c1 is ranked over c2. c2 has three 25-min episodes waiting; c1 has one 10-min video.
    func series(inOrder: Bool = true, settings: ShipmentSettings = ShipmentSettings()) -> ShipmentEngine {
        var engine = makeEngine(
            backlog: [
                video("ep3", creator: "c2", minutes: 25, published: date(10, 27, 5)),
                video("ep1", creator: "c2", minutes: 25, published: date(10, 25)),
                video("ep2", creator: "c2", minutes: 25, published: date(10, 26)),
                video("top", creator: "c1", minutes: 10, published: date(10, 26)),
            ],
            lastShipment: date(10, 26, 6),
            settings: settings,
            rank: ["c1", "c2"]
        )
        engine.setInOrder(inOrder, for: "c2")
        return engine
    }

    @Test("W1: an in-order creator's waiting videos are served oldest first, day after day")
    func oldestFirst() {
        var engine = series()
        engine.applyDueShipments(at: date(10, 27, 6)) // Tuesday, 30 min: top (10) + ep1 (25)
        #expect(engine.homeIDs == ["top", "ep1"])
        engine.applyDueShipments(at: date(10, 28, 6))
        #expect(engine.homeIDs == ["top", "ep1", "ep2"])
        engine.applyDueShipments(at: date(10, 29, 6))
        #expect(engine.homeIDs == ["top", "ep1", "ep2", "ep3"])
    }

    @Test("W1: with room for all, they land in the Inbox as 1, 2, 3")
    func allInOrder() {
        var settings = ShipmentSettings()
        settings.weekdayBudget = 90 * 60
        var engine = series(settings: settings)
        engine.applyDueShipments(at: date(10, 27, 6))
        #expect(engine.homeIDs == ["top", "ep1", "ep2", "ep3"])
    }

    @Test("W2: with the switch off, the order is newest first as before")
    func offIsUnchanged() {
        let off = series(inOrder: false)
        #expect(off.orderedBacklog().map(\.id) == ["top", "ep3", "ep2", "ep1"])
        #expect(off.state.inOrderCreators == nil)
        var engine = off
        engine.applyDueShipments(at: date(10, 27, 6))
        #expect(engine.homeIDs == ["top", "ep3"])
    }

    @Test("W3: Ranked: rank still wins, and other creators stay newest first")
    func rankStillWins() {
        var engine = series()
        engine.addToBacklog([
            video("top2", creator: "c1", minutes: 10, published: date(10, 27, 5)),
            video("low", creator: "c3", minutes: 5, published: date(10, 27, 5)),
        ])
        engine.creatorRank = ["c1", "c2", "c3"]
        #expect(engine.orderedBacklog().map(\.id) == ["top2", "top", "ep1", "ep2", "ep3", "low"])
        // 30 min: top2 + top = 20, ep1 makes 45 (fits under 45), and the budget is reached.
        engine.applyDueShipments(at: date(10, 27, 6))
        #expect(engine.homeIDs == ["top2", "top", "ep1"])
    }

    @Test("W3: an episode that won't fit still ends the pick (D99)")
    func breakRuleUnchanged() {
        var engine = series()
        engine.addToBacklog([
            video("top2", creator: "c1", minutes: 15, published: date(10, 27, 5)),
            video("low", creator: "c3", minutes: 5, published: date(10, 27, 5)),
        ])
        engine.creatorRank = ["c1", "c2", "c3"]
        // top2 + top = 25; ep1 would make 50 > 45, so the pick ends. "low" never jumps ahead.
        engine.applyDueShipments(at: date(10, 27, 6))
        #expect(engine.homeIDs == ["top2", "top"])
    }

    @Test("W4: Random: same spots in line, oldest first; other creators don't move")
    func randomKeepsSpots() {
        var settings = ShipmentSettings()
        settings.creatorOrder = .random
        var engine = series(settings: settings)
        // Newest first overall: ep3 (10/27), then ep2 and top (10/26, backlog order), then ep1.
        engine.setInOrder(false, for: "c2")
        #expect(engine.orderedBacklog().map(\.id) == ["ep3", "ep2", "top", "ep1"])
        engine.setInOrder(true, for: "c2")
        #expect(engine.orderedBacklog().map(\.id) == ["ep1", "ep2", "top", "ep3"])
    }

    @Test("W5: refresh, swap and the short-day fill use the same order")
    func otherPickersFollow() {
        // Refresh: the Inbox is swapped for a fresh pick, oldest episode first.
        var refreshed = series()
        refreshed.state.home = [HomeEntry(video: video("h1", minutes: 30))]
        #expect(refreshed.refresh(at: date(10, 26, 9)) == .allowed(remaining: 1))
        #expect(refreshed.homeIDs == ["top", "ep1"])

        // Swap: the next in line that is short enough is the oldest episode.
        var swapped = series()
        swapped.state.backlog.removeAll { $0.id == "top" }
        swapped.state.home = [HomeEntry(video: video("h1", minutes: 20))]
        #expect(swapped.swapCandidate(for: "h1")?.id == "ep1")
        swapped.swap("h1", at: date(10, 26, 9))
        #expect(swapped.homeIDs == ["ep1"])

        // Short day: 5 min in the Inbox, so the leftover time is filled in the same order.
        var short = series()
        short.state.home = [HomeEntry(video: video("h1", minutes: 5))]
        short.state.lastShipmentContent = 5 * 60
        short.state.lastShipmentDelivered = 1
        #expect(short.isShortToday)
        short.fillToday(at: date(10, 26, 9))
        #expect(short.homeIDs == ["h1", "top", "ep1"])
    }

    @Test("W6: turning the switch on or off never changes the Inbox")
    func inboxUntouched() {
        var engine = series(inOrder: false)
        engine.applyDueShipments(at: date(10, 27, 6))
        let home = engine.state.home, backlog = engine.state.backlog
        engine.setInOrder(true, for: "c2")
        #expect(engine.state.home == home)
        #expect(engine.state.backlog == backlog)
        // The newer episode stays put; the older ones arrive under it, in order.
        engine.applyDueShipments(at: date(10, 28, 6))
        #expect(engine.homeIDs == ["top", "ep3", "ep1"])
        engine.setInOrder(false, for: "c2")
        #expect(engine.homeIDs == ["top", "ep3", "ep1"])
    }

    @Test("State saved by an older build decodes with every creator off")
    func oldStateDecodes() throws {
        var state = ShipmentState()
        state.backlog = [video("a", minutes: 5)]
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])
        json["inOrderCreators"] = nil
        let decoded = try JSONDecoder().decode(ShipmentState.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(decoded.inOrderCreators == nil)
        #expect(decoded.backlog.map(\.id) == ["a"])
    }
}
