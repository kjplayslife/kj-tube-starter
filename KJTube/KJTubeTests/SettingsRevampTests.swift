import Foundation
import SwiftData
import Testing
@testable import KJTube

/// docs/specs/settings-revamp.md
struct SettingsRevampTests {
    private func decode(_ json: String) throws -> ShipmentSettings {
        try JSONDecoder().decode(ShipmentSettings.self, from: Data(json.utf8))
    }

    @Test("V2: a swap and a pull to refresh share the day's count")
    func swapUsesTodaysRefresh() {
        var settings = ShipmentSettings()
        settings.refreshesPerDay = 2
        var engine = makeEngine(
            backlog: [video("n1", minutes: 20), video("n2", minutes: 20), video("n3", minutes: 20)],
            home: [HomeEntry(video: video("h1", minutes: 20))],
            lastShipment: date(10, 27, 6), settings: settings
        )
        #expect(engine.swap("h1", at: date(10, 27, 9)) == .allowed(remaining: 2))
        #expect(engine.refreshesRemaining(at: date(10, 27, 10)) == 1)
        #expect(engine.refreshesRemaining(at: date(10, 28, 6)) == 2)
    }

    @Test("V3: an old weekly count becomes a daily one, capped at 2")
    func weeklyBecomesDaily() throws {
        #expect(try decode(#"{"refreshesPerWeek":3}"#).refreshesPerDay == 2)
        #expect(try decode(#"{"refreshesPerWeek":1}"#).refreshesPerDay == 1)
        #expect(try decode(#"{"refreshesPerWeek":0}"#).refreshesPerDay == 0)
        #expect(try decode("{}").refreshesPerDay == 1)
        #expect(try decode(#"{"refreshesPerWeek":3,"refreshesPerDay":1}"#).refreshesPerDay == 1)
    }

    @Test("V5: a lock from the old 30-day rule ends 7 days after it was set")
    func oldLocksAreTrimmed() throws {
        var old = ShipmentSettings()
        old.weekdayBudget = 90 * 60
        let data = try JSONEncoder().encode(old)
        var json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let setOn = date(10, 27, 12)
        let oldLock = setOn.addingTimeInterval(30 * 86_400)
        json["budgetRaiseLockedUntil"] = oldLock.timeIntervalSinceReferenceDate
        json["refreshRaiseLockedUntil"] = oldLock.timeIntervalSinceReferenceDate
        let settings = try JSONDecoder().decode(ShipmentSettings.self, from: JSONSerialization.data(withJSONObject: json))
        let sevenDays = setOn.addingTimeInterval(7 * 86_400)
        #expect(settings.weekdayBudget == 90 * 60)
        #expect(settings.weekdayBudgetLockedUntil == sevenDays)
        #expect(settings.weekendBudgetLockedUntil == sevenDays)
        #expect(settings.refreshLockedUntil == sevenDays)
    }

    @Test("Settings survive an encode and decode round trip")
    func roundTrip() throws {
        var settings = ShipmentSettings()
        settings.refreshesPerDay = 2
        settings.fridayIsWeekend = true
        settings.weekendBudgetLockedUntil = date(11, 3)
        settings.creatorOrder = .random
        #expect(try JSONDecoder().decode(ShipmentSettings.self, from: JSONEncoder().encode(settings)) == settings)
    }

    @Test("V6: Friday uses the weekend minutes only when the switch is on")
    func friday() {
        var settings = ShipmentSettings()
        let friday = date(10, 30, 6)
        #expect(makeEngine(settings: settings).budget(for: friday) == 30 * 60)
        settings.fridayIsWeekend = true
        let engine = makeEngine(settings: settings)
        #expect(engine.budget(for: friday) == 60 * 60)
        #expect(engine.budget(for: date(10, 29, 6)) == 30 * 60) // Thursday
        #expect(engine.budget(for: date(10, 31, 6)) == 60 * 60) // Saturday
        #expect(engine.weekStats(now: friday).budget == (4 * 30 + 3 * 60) * 60)
    }

    @Test("V7: daily average, change from last week, total and days within budget")
    func weekStats() {
        var engine = makeEngine(home: [HomeEntry(video: video("a", minutes: 600))])
        // Last week (Oct 19–25): 20 min a day.
        for day in 19...25 { engine.recordPlayback(of: "a", position: 1, played: 20 * 60, at: date(10, day, 20)) }
        // This week: Mon 40 min (over 30), Tue 10 min, Wed nothing yet.
        engine.recordPlayback(of: "a", position: 1, played: 40 * 60, at: date(10, 26, 20))
        engine.recordPlayback(of: "a", position: 1, played: 10 * 60, at: date(10, 27, 20))
        let now = date(10, 28, 12)
        let week = engine.weekStats(now: now)
        #expect(week.total == 50 * 60)
        #expect(week.daysCounted == 3)
        #expect(week.dailyAverage == 50 * 60 / 3)
        #expect(week.daysWithinBudget == 2)
        #expect(week.days[0].isOver)
        #expect(week.days[3].isFuture)

        let last = engine.weekStats(weeksAgo: 1, now: now)
        #expect(last.days.first?.date == date(10, 19))
        #expect(last.dailyAverage == 20 * 60)
        #expect(last.daysWithinBudget == 7)
        let change = try! #require(week.change(from: last))
        #expect(abs(change - (-1.0 / 6)) < 0.0001)
        #expect(last.change(from: engine.weekStats(weeksAgo: 2, now: now)) == nil)
    }

    @Test("V8: the stats go back to the week of the oldest logged day, and no further")
    func oldestWeek() {
        var engine = makeEngine(home: [HomeEntry(video: video("a", minutes: 600))])
        #expect(engine.oldestStatsWeek(now: date(10, 28, 12)) == 0)
        engine.recordPlayback(of: "a", position: 1, played: 60, at: date(10, 13, 20)) // two Mondays back
        engine.recordPlayback(of: "a", position: 1, played: 60, at: date(10, 27, 20))
        #expect(engine.oldestStatsWeek(now: date(10, 28, 12)) == 2)
    }
}

@MainActor
struct SettingsRevampStoreTests {
    /// The container must outlive the store, or SwiftData throws the models away.
    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Creator.self, EngineRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    @Test("V4: each limit locks for 7 days by itself, and lowering always works")
    func ownClocks() throws {
        let container = try makeContainer()
        let store = AppStore(context: container.mainContext, api: FakeYouTubeAPI(), calendar: testCalendar)
        let now = date(10, 27, 12)
        let lock = date(11, 3, 12)
        #expect(store.evaluate(.weekdayBudget, to: 60, now: now) == .confirm(lockUntil: lock))
        store.set(.weekdayBudget, to: 60, lockUntil: lock)
        #expect(store.evaluate(.weekdayBudget, to: 90, now: now) == .locked(until: lock))
        #expect(store.evaluate(.weekdayBudget, to: 30, now: now) == .apply)
        // Weekends and refreshes are not held back by the weekday lock.
        #expect(store.evaluate(.weekendBudget, to: 90, now: now) == .confirm(lockUntil: lock))
        #expect(store.evaluate(.refreshesPerDay, to: 2, now: now) == .confirm(lockUntil: lock))
        #expect(store.evaluateShipmentHour(7, now: now) == .confirm(lockUntil: lock))
        #expect(store.evaluate(.weekdayBudget, to: 90, now: date(11, 3, 13)) == .confirm(lockUntil: date(11, 10, 13)))
    }

    @Test("D210: lowering a daily limit warns first; raising, no change and refreshes don't")
    func lowerWarning() throws {
        let container = try makeContainer()
        let store = AppStore(context: container.mainContext, api: FakeYouTubeAPI(), calendar: testCalendar)
        let now = date(10, 27, 12)
        let lock = date(11, 3, 12)
        store.set(.weekdayBudget, to: 60)
        // The raise is still unused: going back up would spend it.
        #expect(store.lowerWarning(.weekdayBudget, to: 30, now: now)
            == "Going back up will use your once-a-week raise for this limit.")
        #expect(store.lowerWarning(.weekdayBudget, to: 60, now: now) == nil)
        #expect(store.lowerWarning(.weekdayBudget, to: 90, now: now) == nil)
        // The raise was used this week: there is no way back up until the lock ends.
        store.set(.weekdayBudget, to: 90, lockUntil: lock)
        #expect(store.lowerWarning(.weekdayBudget, to: 30, now: now, day: { _ in "Nov 3" })
            == "You already used this week's raise, so you can't go back up until Nov 3.")
        #expect(store.lowerWarning(.weekdayBudget, to: 30, now: date(11, 3, 13))
            == "Going back up will use your once-a-week raise for this limit.")
        // Weekends have their own clock, and the refresh count is not a daily limit.
        store.set(.weekendBudget, to: 90)
        #expect(store.lowerWarning(.weekendBudget, to: 60, now: now)
            == "Going back up will use your once-a-week raise for this limit.")
        store.set(.refreshesPerDay, to: 2)
        #expect(store.lowerWarning(.refreshesPerDay, to: 0, now: now) == nil)
        // Asking changes nothing until the answer is Yes.
        #expect(store.value(of: .weekdayBudget) == 90)
        #expect(SettingsPolicy.spelledOut(minutes: 30) == "30 minutes")
    }

    @Test("V4: turning Friday on is loosening; turning it off is not")
    func fridaySwitch() throws {
        let container = try makeContainer()
        let store = AppStore(context: container.mainContext, api: FakeYouTubeAPI(), calendar: testCalendar)
        let now = date(10, 27, 12)
        #expect(store.evaluateFridayIsWeekend(true, now: now) == .confirm(lockUntil: date(11, 3, 12)))
        store.setFridayIsWeekend(true, lockUntil: date(11, 3, 12))
        #expect(store.evaluateFridayIsWeekend(false, now: now) == .apply)
        store.setFridayIsWeekend(false)
        #expect(store.evaluateFridayIsWeekend(true, now: now) == .locked(until: date(11, 3, 12)))
        // When weekends are not bigger than weekdays, the switch gives nothing extra.
        store.set(.weekendBudget, to: 30)
        #expect(store.evaluateFridayIsWeekend(true, now: now) == .apply)
    }
}
