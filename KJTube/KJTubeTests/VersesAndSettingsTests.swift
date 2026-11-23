import Foundation
import SwiftData
import Testing
@testable import KJTube

/// Deterministic RNG for shuffle tests.
struct SeededRNG: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}

struct VerseBagTests {
    @Test("R4: every verse appears exactly once before any repeat")
    func allOnce() {
        var bag = VerseBag()
        var rng = SeededRNG(state: 7)
        let first = (0..<52).compactMap { _ in bag.next(count: 52, using: &rng) }
        #expect(Set(first).count == 52)
    }

    @Test("Never the same verse twice in a row, even across a reshuffle", arguments: 1...20)
    func noRepeatAcrossReshuffle(seed: UInt64) {
        var bag = VerseBag()
        var rng = SeededRNG(state: seed)
        var previous: Int?
        for _ in 0..<(5 * 3) {
            let index = bag.next(count: 5, using: &rng)
            #expect(index != previous)
            previous = index
        }
    }

    @Test("The bundled list loads with all four themes")
    func libraryLoads() {
        #expect(VerseLibrary.all.count == 40)
        #expect(Set(VerseLibrary.all.map(\.theme)).count == 4)
    }
}

struct SettingsPolicyTests {
    let now = date(10, 27, 12)

    @Test("S1: lowering applies at once, even while raising is locked")
    func lowering() {
        #expect(SettingsPolicy.raise(from: 60, to: 30, lockedUntil: date(11, 20), now: now, calendar: testCalendar) == .apply)
    }

    @Test("S2: raising asks first and locks for 7 days; while locked it's refused")
    func raising() {
        #expect(SettingsPolicy.raise(from: 30, to: 60, lockedUntil: nil, now: now, calendar: testCalendar)
                == .confirm(lockUntil: date(11, 3, 12)))
        #expect(SettingsPolicy.raise(from: 30, to: 60, lockedUntil: date(11, 26, 12), now: now, calendar: testCalendar)
                == .locked(until: date(11, 26, 12)))
        #expect(SettingsPolicy.raise(from: 30, to: 60, lockedUntil: date(10, 27, 11), now: now, calendar: testCalendar)
                == .confirm(lockUntil: date(11, 3, 12)))
    }

    @Test("S4: shipment time changes lock for 7 days")
    func shipmentTime() {
        #expect(SettingsPolicy.shipmentTime(from: 6, to: 7, lockedUntil: nil, now: now, calendar: testCalendar)
                == .confirm(lockUntil: date(11, 3, 12)))
        #expect(SettingsPolicy.shipmentTime(from: 6, to: 5, lockedUntil: date(11, 3, 12), now: now, calendar: testCalendar)
                == .locked(until: date(11, 3, 12)))
    }
}

struct ShipmentHourChangeTests {
    @Test("Moving the time later never gives a second shipment today")
    func laterSameDay() {
        var engine = makeEngine(lastShipment: date(10, 27, 6))
        engine.changeShipmentHour(to: 9, at: date(10, 27, 7))
        #expect(engine.dueShipments(at: date(10, 27, 10)).isEmpty)
        #expect(engine.dueShipments(at: date(10, 28, 9)) == [date(10, 28, 9)])
    }

    @Test("Moving the time earlier starts tomorrow at the new time")
    func earlier() {
        var engine = makeEngine(lastShipment: date(10, 27, 6))
        engine.changeShipmentHour(to: 5, at: date(10, 27, 7))
        #expect(engine.dueShipments(at: date(10, 27, 23)).isEmpty)
        #expect(engine.nextShipment(after: date(10, 27, 7)) == date(10, 28, 5))
    }
}

struct WatchLogTests {
    @Test("S5: minutes are logged per day and the week sums Monday–Sunday")
    func logs() {
        var engine = makeEngine(home: [HomeEntry(video: video("a", minutes: 60))])
        engine.recordPlayback(of: "a", position: 600, played: 600, at: date(10, 26, 20)) // Monday
        engine.recordPlayback(of: "a", position: 900, played: 300, at: date(10, 27, 20)) // Tuesday
        engine.recordPlayback(of: "a", position: 2000, played: 0, at: date(10, 27, 21))  // a seek adds nothing
        #expect(engine.watched(on: date(10, 26)) == 600)
        #expect(engine.watched(on: date(10, 27)) == 300)
        #expect(engine.watched(on: date(10, 28)) == 0)
        let week = engine.weekStats(now: date(10, 28, 12))
        #expect(week.total == 900)
        #expect(week.budget == (5 * 30 + 2 * 60) * 60)
    }

    @Test("The log keeps only the last 60 days")
    func trims() {
        var engine = makeEngine(home: [HomeEntry(video: video("a", minutes: 600))])
        for day in 0..<70 {
            let when = testCalendar.date(byAdding: .day, value: day, to: date(8, 1, 12))!
            engine.recordPlayback(of: "a", position: Double(day), played: 1, at: when)
        }
        #expect(engine.state.watchLog?.count == 60)
        #expect(engine.watched(on: date(8, 1)) == 0)
    }
}

@MainActor
struct SettingsStoreTests {
    @Test("S6: settings and lock dates survive a relaunch")
    func persists() throws {
        let container = try ModelContainer(
            for: Creator.self, EngineRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let store = AppStore(context: container.mainContext, api: FakeYouTubeAPI(), calendar: testCalendar)
        store.set(.weekdayBudget, to: 60, lockUntil: date(11, 3))
        store.set(.refreshesPerDay, to: 0)
        store.setFridayIsWeekend(true, lockUntil: date(11, 4))
        store.setShipmentHour(7, lockUntil: date(11, 3), now: date(10, 27, 12))

        let relaunched = AppStore(context: container.mainContext, api: FakeYouTubeAPI(), calendar: testCalendar)
        #expect(relaunched.value(of: .weekdayBudget) == 60)
        #expect(relaunched.value(of: .weekendBudget) == 60)
        #expect(relaunched.value(of: .refreshesPerDay) == 0)
        #expect(relaunched.lockedUntil(.weekdayBudget) == date(11, 3))
        #expect(relaunched.lockedUntil(.weekendBudget) == nil) // each limit has its own clock
        #expect(relaunched.engine.settings.fridayIsWeekend)
        #expect(relaunched.engine.settings.fridayLockedUntil == date(11, 4))
        #expect(relaunched.engine.settings.shipmentHour == 7)
        #expect(relaunched.engine.settings.shipmentHourLockedUntil == date(11, 3))
    }

    @Test("A new verse on cold launch and after 5+ minutes away, not after a quick switch")
    func verseRotation() throws {
        let container = try ModelContainer(
            for: Creator.self, EngineRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let verses = (0..<10).map { Verse(reference: "R\($0)", text: "T\($0)", theme: "X") }
        let defaults = UserDefaults(suiteName: "verse-\(UUID())")!
        let store = AppStore(context: container.mainContext, api: FakeYouTubeAPI(), defaults: defaults, verses: verses)
        let t0 = date(10, 27, 12)

        store.appBecameActive(now: t0)
        let first = try #require(store.verse)
        store.appWentToBackground(now: t0)
        store.appBecameActive(now: t0.addingTimeInterval(60))
        #expect(store.verse == first)
        store.appWentToBackground(now: t0.addingTimeInterval(120))
        store.appBecameActive(now: t0.addingTimeInterval(120 + 301))
        #expect(store.verse != first)
    }
}
