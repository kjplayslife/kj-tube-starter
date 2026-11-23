import Foundation
import Testing
@testable import KJTube

/// D97: a note at the bottom of the Inbox when the day's shipment can't fill the budget
/// (docs/specs/short-inbox-note.md).
struct ShortInboxTests {
    @Test("N1: a shipment under budget − 15 min shows the note")
    func shortShipmentShowsNote() {
        // Weekday budget 30 min; only 10 min to serve.
        var engine = makeEngine(backlog: [video("a", minutes: 10)], lastShipment: date(10, 26, 6))
        engine.applyDueShipments(at: date(10, 27, 7))
        #expect(engine.homeIDs == ["a"])
        #expect(engine.isShortToday)
    }

    @Test("N2: a full shipment shows no note")
    func fullShipmentNoNote() {
        var engine = makeEngine(
            backlog: [video("a", minutes: 10), video("b", minutes: 10), video("c", minutes: 10)],
            lastShipment: date(10, 26, 6)
        )
        engine.applyDueShipments(at: date(10, 27, 7))
        #expect(!engine.isShortToday)
    }

    @Test("N2: within 15 min of the budget counts as full")
    func nearlyFullNoNote() {
        var engine = makeEngine(backlog: [video("a", minutes: 16)], lastShipment: date(10, 26, 6))
        engine.applyDueShipments(at: date(10, 27, 7))
        #expect(!engine.isShortToday)
    }

    @Test("N3: carryover counts toward the day's videos")
    func carryoverCounts() {
        var engine = makeEngine(
            backlog: [video("new", minutes: 5)],
            home: [HomeEntry(video: video("carry", minutes: 25))],
            lastShipment: date(10, 26, 6)
        )
        engine.applyDueShipments(at: date(10, 27, 7))
        #expect(!engine.isShortToday)
    }

    @Test("N4: starting a video keeps the note")
    func staysWhileWatching() {
        var engine = makeEngine(
            backlog: [video("a", minutes: 10), video("b", minutes: 4)],
            lastShipment: date(10, 26, 6)
        )
        engine.applyDueShipments(at: date(10, 27, 7))
        engine.recordPlayback(of: "a", position: 5 * 60, played: 5 * 60, at: date(10, 27, 8))
        #expect(engine.homeIDs == ["a", "b"])
        #expect(engine.isShortToday)
    }

    @Test("N4: finishing the first video hides the note until the next shipment")
    func finishingHides() {
        var engine = makeEngine(
            backlog: [video("a", minutes: 10), video("b", minutes: 4)],
            lastShipment: date(10, 26, 6)
        )
        engine.applyDueShipments(at: date(10, 27, 7))
        engine.recordPlayback(of: "a", position: 9.5 * 60, played: 9.5 * 60, at: date(10, 27, 8))
        #expect(engine.homeIDs == ["b"])
        #expect(!engine.isShortToday)
        // Next day is short again: the note comes back.
        engine.applyDueShipments(at: date(10, 28, 7))
        #expect(engine.isShortToday)
    }

    @Test("N5: an empty Inbox shows its own message, not the note")
    func emptyHomeNoNote() {
        var engine = makeEngine(lastShipment: date(10, 26, 6))
        engine.applyDueShipments(at: date(10, 27, 7))
        #expect(engine.homeIDs.isEmpty)
        #expect(!engine.isShortToday)
    }

    @Test("N6: weekends use the weekend budget")
    func weekendBudget() {
        // 40 min fills a 30-min weekday but is short of a 60-min Saturday.
        var engine = makeEngine(
            backlog: [video("a", minutes: 20), video("b", minutes: 20)],
            lastShipment: date(10, 30, 6) // Friday
        )
        engine.applyDueShipments(at: date(10, 31, 7)) // Saturday
        #expect(engine.isShortToday)
    }

    @Test("N7: a full next shipment clears the note")
    func nextShipmentClears() {
        var engine = makeEngine(backlog: [video("a", minutes: 10)], lastShipment: date(10, 26, 6))
        engine.applyDueShipments(at: date(10, 27, 7))
        #expect(engine.isShortToday)
        engine.addNewUploads([video("b", minutes: 15, published: date(10, 27, 12)), video("c", minutes: 15, published: date(10, 27, 13))])
        engine.applyDueShipments(at: date(10, 28, 7))
        #expect(!engine.isShortToday)
    }

    @Test("State saved before lastShipmentContent existed shows no note")
    func oldStateNoNote() {
        let engine = makeEngine(home: [HomeEntry(video: video("a", minutes: 5))], lastShipment: date(10, 27, 6))
        #expect(engine.state.lastShipmentContent == nil)
        #expect(!engine.isShortToday)
    }
}
