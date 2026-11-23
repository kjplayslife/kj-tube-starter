import Foundation
@testable import KJTube

/// Fixed calendar so tests don't depend on the Mac's time zone. New York also covers DST.
let testCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/New_York")!
    return calendar
}()

/// 2026-10-26 is a Monday.
func date(_ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0, year: Int = 2026) -> Date {
    testCalendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}

func video(
    _ id: String,
    creator: String = "c1",
    minutes: Double,
    published: Date = date(10, 25)
) -> Video {
    Video(id: id, creatorID: creator, title: id, duration: minutes * 60, publishedAt: published)
}

func makeEngine(
    backlog: [Video] = [],
    home: [HomeEntry] = [],
    lastShipment: Date? = nil,
    settings: ShipmentSettings = ShipmentSettings(),
    rank: [String] = ["c1"]
) -> ShipmentEngine {
    var state = ShipmentState()
    state.backlog = backlog
    state.home = home
    state.lastShipment = lastShipment
    return ShipmentEngine(state: state, settings: settings, creatorRank: rank, calendar: testCalendar)
}

extension ShipmentEngine {
    var homeIDs: [String] { state.home.map(\.id) }
}

/// Waits until `condition` holds, checking often, for up to `timeout` seconds. Returns whether it
/// held. For tests that wait on one of the app's timers: sleeping a fixed time with a small margin
/// fails when the Mac is busy and the timer runs late.
@MainActor
func waitUntil(timeout: TimeInterval, _ condition: () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + .seconds(timeout)
    while !condition() {
        if ContinuousClock.now >= deadline { return false }
        try? await Task.sleep(for: .milliseconds(50))
    }
    return true
}
