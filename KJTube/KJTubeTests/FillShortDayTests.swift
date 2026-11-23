import Foundation
import SwiftData
import Testing
@testable import KJTube

/// D136: a short day fills up from the creators just followed, once KJ is back on the Inbox
/// (docs/specs/fill-short-day.md).
struct FillShortDayTests {
    let shipped = date(10, 27, 7) // Tuesday, 30-min budget
    let later = date(10, 27, 9)

    /// A 30-min day that got only `minutes` of video.
    func shortDay(minutes: Double = 10, rank: [String] = ["c1", "A", "B"]) -> ShipmentEngine {
        var engine = makeEngine(backlog: [video("h", minutes: minutes)], lastShipment: date(10, 26, 6), rank: rank)
        engine.applyDueShipments(at: shipped)
        return engine
    }

    @Test("F1, F2, F5, F11: a new follow's latest video is added at the bottom, only on the fill")
    func fillsFromNewFollow() {
        var engine = shortDay()
        #expect(engine.wantsStarters)
        engine.addStarters([video("a", creator: "A", minutes: 15)])
        #expect(engine.homeIDs == ["h"]) // nothing moves until KJ is back on the Inbox
        #expect(engine.fillToday(at: later) == 1)
        #expect(engine.homeIDs == ["h", "a"])
        #expect(!engine.isShortToday)
        #expect(engine.state.refreshesUsed == 0)
        #expect(engine.state.backlog.isEmpty && engine.state.starters == nil)
    }

    @Test("F3: creators fill in Following order, and rank wins over fit")
    func rankOrder() {
        var engine = shortDay()
        engine.addStarters([video("b", creator: "B", minutes: 20), video("a", creator: "A", minutes: 20)])
        engine.fillToday(at: later)
        #expect(engine.homeIDs == ["h", "a"]) // the day is full at 30 min, so b waits
        #expect(engine.state.backlog.map(\.id) == ["b"])

        var tight = shortDay()
        tight.addStarters([video("a", creator: "A", minutes: 40), video("b", creator: "B", minutes: 10)])
        #expect(tight.fillToday(at: later) == 0) // a won't fit, and b never jumps ahead (D99)
        #expect(tight.isShortToday)
    }

    @Test("F3: two short videos both fit")
    func twoFit() {
        var engine = shortDay(minutes: 5)
        engine.addStarters([video("a", creator: "A", minutes: 10), video("b", creator: "B", minutes: 10)])
        #expect(engine.fillToday(at: later) == 2)
        #expect(engine.homeIDs == ["h", "a", "b"])
    }

    @Test("F4: reordering before going back changes who fills")
    func reorder() {
        var engine = shortDay()
        engine.addStarters([video("a", creator: "A", minutes: 20), video("b", creator: "B", minutes: 20)])
        engine.creatorRank = ["c1", "B", "A"]
        engine.fillToday(at: later)
        #expect(engine.homeIDs == ["h", "b"])
    }

    @Test("F6: a fill that leaves the day short keeps the note")
    func stillShort() {
        var engine = shortDay(minutes: 5)
        engine.addStarters([video("a", creator: "A", minutes: 5)])
        engine.fillToday(at: later)
        #expect(engine.homeIDs == ["h", "a"])
        #expect(engine.isShortToday)
    }

    @Test("F7: a full day takes no old videos and never fills")
    func fullDay() {
        var engine = shortDay(minutes: 20)
        #expect(!engine.wantsStarters)
        engine.addToBacklog([video("x", creator: "A", minutes: 5)])
        #expect(engine.fillToday(at: later) == 0)
        #expect(engine.homeIDs == ["h"])
    }

    @Test("F8: after a video is finished, the day is done")
    func finishedDay() {
        var engine = makeEngine(backlog: [video("h", minutes: 5), video("h2", minutes: 5)], lastShipment: date(10, 26, 6))
        engine.applyDueShipments(at: shipped)
        engine.recordPlayback(of: "h", position: 5 * 60, played: 5 * 60, at: later)
        #expect(!engine.wantsStarters)
        engine.addToBacklog([video("a", creator: "A", minutes: 15)])
        #expect(engine.fillToday(at: later) == 0)
    }

    @Test("F10: a latest video older than 30 days is not added")
    func tooOld() {
        var engine = shortDay()
        engine.addStarters([video("old", creator: "A", minutes: 15, published: date(9, 1))])
        #expect(engine.fillToday(at: later) == 0)
        #expect(engine.homeIDs == ["h"])
    }

    @Test("F12: a video already seen is never added")
    func seen() {
        var engine = shortDay()
        engine.state.seen.insert("a")
        engine.addStarters([video("a", creator: "A", minutes: 15)])
        #expect(engine.fillToday(at: later) == 0)
    }

    @Test("A backfill video that didn't fit is a starter: fresh uploads go first, then it leaves (D80)")
    func leftoverIsStarter() {
        var engine = shortDay(rank: ["A", "B", "c1"])
        engine.addStarters([video("a", creator: "A", minutes: 20), video("b-old", creator: "B", minutes: 15)])
        engine.fillToday(at: later)
        #expect(engine.homeIDs == ["h", "a"])
        // Next day: a lower-ranked creator's fresh upload still goes ahead of the old starter.
        engine.addNewUploads([video("c-new", minutes: 20, published: date(10, 27, 20))])
        engine.applyDueShipments(at: date(10, 28, 7))
        #expect(engine.homeIDs == ["h", "a", "c-new", "b-old"]) // fresh first, the old starter after it
        #expect(engine.state.backlog.isEmpty) // the starter had its one shipment

        // And a creator's own new upload replaces their starter.
        var other = shortDay(rank: ["A", "B", "c1"])
        other.addStarters([video("a", creator: "A", minutes: 20), video("b-old", creator: "B", minutes: 15)])
        other.fillToday(at: later)
        other.addNewUploads([video("b-new", creator: "B", minutes: 10, published: date(10, 27, 20))])
        #expect(other.state.backlog.map(\.id) == ["b-new"])
    }
}

/// D136 through the store: following on a short day, then coming back to the Inbox.
@MainActor
struct FillShortDayStoreTests {
    let container: ModelContainer
    let a = channel("UCaaaaaaaaaaaaaaaaaaaaaa", "Alpha")
    let b = channel("UCbbbbbbbbbbbbbbbbbbbbbb", "Beta")
    /// Matches FakeYouTubeAPI's `details(daysAgo:)` clock (a Friday, 30-min budget).
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    init() throws {
        container = try ModelContainer(
            for: Creator.self, EngineRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    @Test("F1, F2, F9: following on a short day waits, then fills on the way back; Shorts are skipped")
    func followThenFill() async {
        var fake = FakeYouTubeAPI()
        for ch in [a, b] { fake.channelsByID[ch.id] = ch }
        fake.uploads = [
            a.id: [details("a1", channel: a.id, minutes: 10, daysAgo: 1)],
            b.id: [details("b-short", channel: b.id, minutes: 1, daysAgo: 1),
                   details("b-latest", channel: b.id, minutes: 15, daysAgo: 2),
                   details("b-older", channel: b.id, minutes: 5, daysAgo: 3)],
        ]
        fake.shorts = ["b-short"]
        let store = AppStore(context: container.mainContext, api: fake, calendar: testCalendar)
        await store.follow(a)
        store.applyShipments(now: now)
        #expect(store.engine.state.home.map(\.id) == ["a1"])
        #expect(store.engine.isShortToday)

        await store.follow(b)
        #expect(store.engine.state.home.map(\.id) == ["a1"]) // still on Following
        store.fillShortDay(now: now)
        #expect(store.engine.state.home.map(\.id) == ["a1", "b-latest"]) // one video, the latest long-form
        #expect(!store.engine.isShortToday)

        // Saved: a relaunch shows the same Inbox.
        let relaunched = AppStore(context: container.mainContext, api: fake, calendar: testCalendar)
        #expect(relaunched.engine.state.home.map(\.id) == ["a1", "b-latest"])
    }
}
