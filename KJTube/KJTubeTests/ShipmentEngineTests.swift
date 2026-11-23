import Foundation
import Testing
@testable import KJTube

/// Acceptance criteria E1–E10 from docs/specs/shipment-and-home.md, plus R3 from refresh-and-verses.
struct ShipmentPickingTests {
    @Test("E1: keeps filling until the full budget is reached, never past budget + 15")
    func fillsBudget() {
        let ordered = [video("a", minutes: 12), video("b", minutes: 10), video("c", minutes: 9), video("d", minutes: 25)]
        let picked = ShipmentEngine.pick(budget: 30 * 60, from: ordered)
        #expect(picked.map(\.id) == ["a", "b", "c"]) // 12 + 10 + 9 = 31 min
    }

    @Test("E11: rank wins: a video that would overshoot ends the pick, nothing lower jumps ahead (D99)")
    func stopsAtOvershoot() {
        let ordered = [video("a", minutes: 10), video("big", minutes: 40), video("b", minutes: 8)]
        let picked = ShipmentEngine.pick(budget: 30 * 60, from: ordered)
        #expect(picked.map(\.id) == ["a"])
    }

    @Test("E11: KJ's case: a higher-ranked 15-min video beats a lower-ranked 40-min one (D99)")
    func higherRankBeatsLonger() {
        let engine = makeEngine(backlog: [
            video("odablock", creator: "O", minutes: 40, published: date(10, 26)),
            video("synergy", creator: "S", minutes: 1, published: date(10, 26)),
            video("ken", creator: "K", minutes: 15, published: date(10, 26)),
        ], rank: ["K", "S", "O"])
        let picked = ShipmentEngine.pick(budget: 30 * 60, from: engine.orderedBacklog())
        #expect(picked.map(\.id) == ["ken", "synergy"]) // odablock (16 + 40 > 45) waits for tomorrow
    }

    @Test("E11: a video too long to ever serve doesn't block the ones after it (D9)")
    func tooLongDoesNotBlock() {
        let ordered = [video("huge", minutes: 50), video("a", minutes: 10)]
        #expect(ShipmentEngine.pick(budget: 30 * 60, from: ordered).map(\.id) == ["a"])
    }

    @Test("E2: a video longer than budget + 15 is never picked")
    func neverPicksTooLong() {
        let long = video("long", minutes: 50)
        #expect(ShipmentEngine.pick(budget: 30 * 60, from: [long]).isEmpty)
        // …but fits a 60-minute weekend budget (50 ≤ 75).
        #expect(ShipmentEngine.pick(budget: 60 * 60, from: [long]).map(\.id) == ["long"])
    }

    @Test("E3: ranked mode orders by creator rank, then newest")
    func rankedOrder() {
        let engine = makeEngine(backlog: [
            video("a-new", creator: "A", minutes: 5, published: date(10, 25)),
            video("b-old", creator: "B", minutes: 5, published: date(10, 20)),
            video("b-new", creator: "B", minutes: 5, published: date(10, 24)),
            video("x", creator: "unranked", minutes: 5, published: date(10, 26)),
        ], rank: ["B", "A"])
        #expect(engine.orderedBacklog().map(\.id) == ["b-new", "b-old", "a-new", "x"])
    }

    @Test("E3: random mode orders by newest only")
    func randomOrder() {
        var settings = ShipmentSettings()
        settings.creatorOrder = .random
        let engine = makeEngine(backlog: [
            video("a-new", creator: "A", minutes: 5, published: date(10, 25)),
            video("b-old", creator: "B", minutes: 5, published: date(10, 20)),
            video("b-new", creator: "B", minutes: 5, published: date(10, 24)),
        ], settings: settings, rank: ["B", "A"])
        #expect(engine.orderedBacklog().map(\.id) == ["a-new", "b-new", "b-old"])
    }
}

struct ShipmentScheduleTests {
    @Test("E4: unwatched carryover stays on top and the new shipment is appended, no cap")
    func carryoverOnTop() {
        let carry = HomeEntry(video: video("carry", minutes: 40), progress: 300)
        var engine = makeEngine(
            backlog: [video("new1", minutes: 10), video("new2", minutes: 10)],
            home: [carry],
            lastShipment: date(10, 26, 6)
        )
        engine.applyDueShipments(at: date(10, 27, 7))
        #expect(engine.homeIDs == ["carry", "new1", "new2"])
        #expect(engine.state.home.first?.progress == 300)
        #expect(engine.state.backlog.isEmpty)
    }

    @Test("E5: three skipped weekdays → three shipments on the next open")
    func skippedDaysStack() {
        var engine = makeEngine(
            backlog: (1...9).map { video("v\($0)", minutes: 10, published: date(10, 25, $0)) },
            lastShipment: date(10, 26, 6) // Monday
        )
        #expect(engine.dueShipments(at: date(10, 29, 8)) == [date(10, 27, 6), date(10, 28, 6), date(10, 29, 6)])
        #expect(engine.applyDueShipments(at: date(10, 29, 8)) == 3)
        // Each 30-min weekday shipment takes 3 × 10 min.
        #expect(engine.state.home.count == 9)
        #expect(engine.state.lastShipment == date(10, 29, 6))
    }

    @Test("E5: weekend shipments use the weekend budget, across the DST change")
    func weekendBudgetAcrossDST() {
        let engine = makeEngine(lastShipment: date(10, 30, 6)) // Friday
        let due = engine.dueShipments(at: date(11, 1, 7))       // Sunday, DST ends that morning
        #expect(due == [date(10, 31, 6), date(11, 1, 6)])
        #expect(due.allSatisfy { engine.budget(for: $0) == 60 * 60 })
        #expect(engine.budget(for: date(11, 2, 6)) == 30 * 60)
    }

    @Test("No shipment is due before shipment time")
    func notDueEarly() {
        let engine = makeEngine(lastShipment: date(10, 26, 6))
        #expect(engine.dueShipments(at: date(10, 27, 5, 59)).isEmpty)
        #expect(engine.nextShipment(after: date(10, 27, 5, 59)) == date(10, 27, 6))
    }

    @Test("First shipment arrives immediately and the next one is tomorrow at shipment time (D16)")
    func firstShipment() {
        var engine = makeEngine(backlog: [video("a", minutes: 20)])
        engine.shipNow(at: date(10, 27, 15))
        #expect(engine.homeIDs == ["a"])
        #expect(engine.dueShipments(at: date(10, 27, 23)).isEmpty)
        #expect(engine.dueShipments(at: date(10, 28, 6)) == [date(10, 28, 6)])
    }

    @Test("E6: backlog videos older than 30 days become SEEN")
    func backlogExpires() {
        var engine = makeEngine(backlog: [
            video("old", minutes: 10, published: date(9, 20)),
            video("fresh", minutes: 10, published: date(10, 20)),
        ])
        engine.expireBacklog(at: date(10, 27, 6))
        #expect(engine.state.backlog.map(\.id) == ["fresh"])
        #expect(engine.state.seen.contains("old"))
    }
}

struct RefreshTests {
    /// Home with one 20-min video, and enough backlog for a full refresh.
    func refreshable(settings: ShipmentSettings = ShipmentSettings()) -> ShipmentEngine {
        makeEngine(
            backlog: [video("n1", minutes: 10), video("n2", minutes: 10)],
            home: [HomeEntry(video: video("h1", minutes: 20))],
            lastShipment: date(10, 27, 6),
            settings: settings
        )
    }

    @Test("E8: refresh swaps the whole list and old videos become SEEN")
    func refreshSwaps() {
        var engine = refreshable()
        #expect(engine.refreshCheck(at: date(10, 27, 9)) == .allowed(remaining: 1))
        #expect(engine.refresh(at: date(10, 27, 9)) == .allowed(remaining: 1))
        #expect(engine.homeIDs == ["n1", "n2"])
        #expect(engine.state.seen.contains("h1"))
        #expect(engine.refreshesRemaining(at: date(10, 27, 9)) == 0)
    }

    @Test("E7: refused when no refreshes are left, and nothing changes")
    func refusedNoneLeft() {
        var settings = ShipmentSettings()
        settings.refreshesPerDay = 0
        var engine = refreshable(settings: settings)
        let before = engine.state
        #expect(engine.refresh(at: date(10, 27, 9)) == .noneLeft)
        #expect(engine.state == before)
    }

    @Test("E7: refused after more than 60 s of watching since the shipment")
    func refusedAlreadyStarted() {
        var engine = refreshable()
        engine.recordPlayback(of: "h1", position: 61, played: 61)
        let before = engine.state
        #expect(engine.refresh(at: date(10, 27, 9)) == .alreadyStarted)
        #expect(engine.state == before)
    }

    @Test("E7: refused without using a refresh when the backlog can't reach budget − 15")
    func refusedThinBacklog() {
        var engine = makeEngine(
            backlog: [video("n1", minutes: 10)],
            home: [HomeEntry(video: video("h1", minutes: 20))],
            lastShipment: date(10, 27, 6)
        )
        #expect(engine.refresh(at: date(10, 27, 9)) == .notEnoughVideos)
        #expect(engine.homeIDs == ["h1"])
        #expect(engine.refreshesRemaining(at: date(10, 27, 9)) == 1)
    }

    @Test("Refresh needs something on Home to swap")
    func nothingToSwap() {
        let engine = makeEngine(backlog: [video("n1", minutes: 20)], lastShipment: date(10, 27, 6))
        #expect(engine.refreshCheck(at: date(10, 27, 9)) == .nothingToSwap)
    }

    @Test("V1: the daily count starts over at the next shipment time")
    func dailyReset() {
        var engine = refreshable()
        engine.refresh(at: date(10, 28, 9))
        #expect(engine.refreshesRemaining(at: date(10, 28, 23)) == 0)
        #expect(engine.refreshesRemaining(at: date(10, 29, 5, 59)) == 0) // still the same shipment day
        #expect(engine.refreshesRemaining(at: date(10, 29, 6)) == 1)
        #expect(engine.refreshDayStart(containing: date(10, 29, 5)) == date(10, 28, 6))
    }
}

struct WatchingTests {
    func engineWithHome() -> ShipmentEngine {
        makeEngine(home: [
            HomeEntry(video: video("a", minutes: 10)),
            HomeEntry(video: video("b", minutes: 10)),
            HomeEntry(video: video("c", minutes: 10)),
        ])
    }

    @Test("E9: progress is kept until the last 60 s, then the video is watched")
    func watchedThreshold() {
        var engine = engineWithHome()
        engine.recordPlayback(of: "a", position: 600 - 61, played: 30)
        #expect(engine.state.home.first?.progress == 539)
        #expect(!engine.state.seen.contains("a"))
        engine.recordPlayback(of: "a", position: 600 - 60, played: 1)
        #expect(engine.homeIDs == ["b", "c"])
        #expect(engine.state.seen.contains("a"))
        #expect(engine.state.watchedSinceShipment == 31)
    }

    @Test("D38: seeking into the last 60 s counts as watched but adds no watch time")
    func seekToEnd() {
        var engine = engineWithHome()
        engine.recordPlayback(of: "b", position: 590, played: 0)
        #expect(engine.homeIDs == ["a", "c"])
        #expect(engine.state.watchedSinceShipment == 0)
    }

    @Test("D103: while open in the player, the last 60 s waits for finishWatching")
    func openWaits() {
        var engine = engineWithHome()
        engine.recordPlayback(of: "a", position: 590, played: 0, open: true)
        #expect(engine.homeIDs == ["a", "b", "c"])
        engine.recordPlayback(of: "a", position: 0, played: 0, open: true)
        engine.finishWatching("a")
        #expect(engine.homeIDs == ["a", "b", "c"]) // scrubbed back: stays
        engine.recordPlayback(of: "a", position: 590, played: 0, open: true)
        engine.finishWatching("a")
        #expect(engine.homeIDs == ["b", "c"])
        #expect(engine.state.seen.contains("a"))
    }

    @Test("D104: Put back returns only the last video that left, to its old spot")
    func putBack() {
        var engine = engineWithHome()
        #expect(engine.puttableBack == nil)
        engine.remove("a")
        engine.recordPlayback(of: "b", position: 590, played: 0) // watched
        #expect(engine.puttableBack?.id == "b")
        engine.putBackLast()
        #expect(engine.homeIDs == ["b", "c"])
        #expect(engine.state.home.first { $0.id == "b" }?.progress == 0) // starts over
        #expect(!engine.state.seen.contains("b"))
        #expect(engine.state.seen.contains("a")) // only the last one
        #expect(engine.puttableBack == nil)
    }

    @Test("D104: Undo on a removed video leaves nothing to put back")
    func putBackAfterUndo() throws {
        var engine = engineWithHome()
        let result = engine.remove("b")
        let removed = try #require(result)
        engine.undoRemove(removed)
        #expect(engine.puttableBack == nil)
    }

    @Test("E10: SEEN videos are never added back or served again")
    func seenNeverReturns() {
        var engine = makeEngine(lastShipment: date(10, 26, 6))
        engine.state.seen = ["gone"]
        engine.addToBacklog([video("gone", minutes: 20), video("ok", minutes: 20), video("ok", minutes: 20)])
        #expect(engine.state.backlog.map(\.id) == ["ok"])
        engine.applyDueShipments(at: date(10, 27, 7))
        #expect(engine.homeIDs == ["ok"])
    }

    @Test("D12: confirmed switch removes a started video, but not an unstarted one")
    func switchAway() {
        var engine = engineWithHome()
        engine.switchAway(from: "a")
        #expect(engine.homeIDs == ["a", "b", "c"])
        engine.recordPlayback(of: "a", position: 30, played: 30)
        engine.switchAway(from: "a")
        #expect(engine.homeIDs == ["b", "c"])
        #expect(engine.state.seen.contains("a"))
    }

    @Test("Remove + Undo restores the video in its place")
    func removeUndo() {
        var engine = engineWithHome()
        let removed = engine.remove("b")
        #expect(engine.homeIDs == ["a", "c"])
        engine.undoRemove(removed!)
        #expect(engine.homeIDs == ["a", "b", "c"])
        #expect(!engine.state.seen.contains("b"))
    }

    @Test("Reorder moves cards like SwiftUI's onMove")
    func reorder() {
        var engine = engineWithHome()
        engine.moveHome(fromOffsets: [0], toOffset: 3)
        #expect(engine.homeIDs == ["b", "c", "a"])
        engine.moveHome(fromOffsets: [2], toOffset: 0)
        #expect(engine.homeIDs == ["a", "b", "c"])
    }

    @Test("Header total counts only the time left in each video")
    func timeRemaining() {
        var engine = engineWithHome()
        engine.recordPlayback(of: "a", position: 120, played: 120)
        #expect(engine.homeTimeRemaining == 30 * 60 - 120)
    }

    @Test("Unfollow drops the creator's backlog but not their Home videos (⚙︎d)")
    func unfollow() {
        var engine = makeEngine(
            backlog: [video("x1", creator: "x", minutes: 5), video("y1", creator: "y", minutes: 5)],
            home: [HomeEntry(video: video("x0", creator: "x", minutes: 5))]
        )
        let removed = engine.removeCreator("x")
        #expect(removed.map(\.id) == ["x1"])
        #expect(engine.state.backlog.map(\.id) == ["y1"])
        #expect(engine.homeIDs == ["x0"])
    }
}

/// D80: a new follow's latest upload ("starter") gets one shipment, after new uploads.
struct StarterTests {
    @Test("D80: new uploads are served before starters")
    func newUploadsFirst() {
        var engine = makeEngine(rank: ["A", "B"])
        engine.addStarters([video("a-old", creator: "A", minutes: 10, published: date(10, 20))])
        engine.addNewUploads([video("b-new", creator: "B", minutes: 10, published: date(10, 26))])
        #expect(engine.orderedBacklog().map(\.id) == ["b-new", "a-old"])
    }

    @Test("D80: starters that don't fit the next shipment leave the backlog")
    func startersGetOneShipment() {
        var engine = makeEngine(rank: ["A", "B", "C", "D"])
        engine.addStarters([
            video("a", creator: "A", minutes: 20, published: date(10, 20)),
            video("b", creator: "B", minutes: 20, published: date(10, 21)),
            video("c", creator: "C", minutes: 20, published: date(10, 22)),
        ])
        // From a creator with no starter, so it doesn't replace one.
        engine.addNewUploads([video("fresh", creator: "D", minutes: 50, published: date(10, 26))]) // too long for 30 min
        engine.shipNow(at: date(10, 27, 15)) // Tuesday: 30-minute budget
        #expect(engine.homeIDs == ["a", "b"]) // fresh (50) is too long; a + b fill 30 min
        #expect(engine.state.backlog.map(\.id) == ["fresh"]) // kept: only starters leave
        #expect(engine.state.starters == nil)
    }

    @Test("D80: a creator's new upload replaces their starter")
    func newUploadReplacesStarter() {
        var engine = makeEngine(rank: ["A", "B"])
        engine.addStarters([
            video("a-old", creator: "A", minutes: 10, published: date(10, 20)),
            video("b-old", creator: "B", minutes: 10, published: date(10, 20)),
        ])
        engine.addNewUploads([video("a-new", creator: "A", minutes: 10, published: date(10, 26))])
        #expect(Set(engine.state.backlog.map(\.id)) == ["b-old", "a-new"])
        #expect(engine.state.starters == ["b-old"])
    }
}

/// D91: one-time cleanup that keeps only videos from the last 24 hours.
struct RecentResetTests {
    @Test("D91: old videos leave Home and the backlog for good; the last 24 hours stay")
    func keepsOnlyLast24Hours() {
        var engine = makeEngine(
            backlog: [
                video("old-b", minutes: 10, published: date(10, 22)),
                video("new-b", minutes: 10, published: date(10, 29, 20)),
            ],
            home: [
                HomeEntry(video: video("old-h", minutes: 10, published: date(10, 20)), progress: 120),
                HomeEntry(video: video("new-h", minutes: 10, published: date(10, 29, 12)), progress: 0),
            ],
            lastShipment: date(10, 30, 6)
        )
        engine.state.starters = ["old-b"]
        engine.keepOnlyRecent(at: date(10, 30, 8))
        #expect(engine.homeIDs == ["new-h"])
        #expect(engine.state.backlog.map(\.id) == ["new-b"])
        #expect(engine.state.seen == ["old-b", "old-h"])
        #expect(engine.state.starters == nil)
        engine.addToBacklog([video("old-b", minutes: 10, published: date(10, 22))])
        #expect(engine.state.backlog.map(\.id) == ["new-b"]) // SEEN: never comes back
    }

    @Test("D91: an emptied Home counts as starved, so fresh uploads are served right away")
    func emptiedHomeIsStarved() {
        var engine = makeEngine(
            home: [HomeEntry(video: video("old", minutes: 10, published: date(10, 20)))],
            lastShipment: date(10, 30, 6)
        )
        engine.keepOnlyRecent(at: date(10, 30, 8))
        #expect(engine.homeIDs.isEmpty)
        #expect(engine.isStarved)
    }
}

/// D92: after day one, a new follow brings no old videos.
struct LaterFollowTests {
    @Test("D92: starters only before anything has been served")
    func startersOnlyOnDayOne() {
        #expect(makeEngine().wantsStarters)
        #expect(makeEngine(lastShipment: date(10, 27, 6)).wantsStarters) // empty shipments so far
        #expect(!makeEngine(home: [HomeEntry(video: video("h", minutes: 10))]).wantsStarters)
        var watched = makeEngine(lastShipment: date(10, 27, 6))
        watched.state.seen = ["done"]
        #expect(!watched.wantsStarters) // Inbox emptied by watching still counts as after day one
    }
}

/// D99: one-time re-pick of today's Inbox with the rank-first rule.
struct RankRepickTests {
    @Test("D99: unstarted videos are re-picked in rank order; the rest wait in line")
    func repicksInRankOrder() {
        var engine = makeEngine(
            backlog: [video("ken", creator: "K", minutes: 15, published: date(10, 27))],
            home: [
                HomeEntry(video: video("synergy", creator: "S", minutes: 1, published: date(10, 26))),
                HomeEntry(video: video("odablock", creator: "O", minutes: 40, published: date(10, 24))),
            ],
            lastShipment: date(10, 27, 6), // Tuesday: 30-minute budget
            rank: ["K", "S", "O"]
        )
        engine.repickToday()
        #expect(engine.homeIDs == ["ken", "synergy"])
        #expect(engine.state.backlog.map(\.id) == ["odablock"])
        #expect(engine.state.lastShipmentDelivered == 2)
    }

    @Test("D99: a started video stays on Home")
    func keepsStarted() {
        var started = HomeEntry(video: video("odablock", creator: "O", minutes: 40, published: date(10, 24)))
        started.progress = 120
        var engine = makeEngine(
            backlog: [video("ken", creator: "K", minutes: 15, published: date(10, 27))],
            // repickToday only runs when something unstarted is on Home.
            home: [started, HomeEntry(video: video("osrs", creator: "O", minutes: 10, published: date(10, 25)))],
            lastShipment: date(10, 27, 6),
            rank: ["K", "O"]
        )
        engine.repickToday()
        #expect(engine.homeIDs == ["odablock", "ken", "osrs"])
    }

    @Test("D99: nothing happens before the first shipment")
    func noShipmentYet() {
        var engine = makeEngine(backlog: [video("a", minutes: 10)])
        engine.repickToday()
        #expect(engine.homeIDs.isEmpty)
    }
}
