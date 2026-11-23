import Foundation

/// A video that passed the eligibility rules (PLAN §3.2). Ineligible videos never become a `Video`.
struct Video: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let creatorID: String
    let title: String
    let duration: TimeInterval
    let publishedAt: Date
}

/// A video on Home, with how far into it KJ has watched.
struct HomeEntry: Identifiable, Hashable, Codable, Sendable {
    let video: Video
    var progress: TimeInterval = 0

    var id: String { video.id }
    var remaining: TimeInterval { max(video.duration - progress, 0) }
}

/// How the shipment orders creators (Following tab toggle).
enum CreatorOrder: String, Codable, Sendable {
    /// Creator rank first, then newest.
    case ranked
    /// Newest first, ignoring rank.
    case random
}

/// The user-facing knobs the engine reads (Settings tab, PLAN §3.6).
struct ShipmentSettings: Hashable, Codable, Sendable {
    var weekdayBudget: TimeInterval = 30 * 60
    var weekendBudget: TimeInterval = 60 * 60
    /// Hour of day (0–23) when a new shipment arrives (D45).
    var shipmentHour = 6
    /// Refreshes (and single-video swaps) allowed per shipment day: 0, 1 or 2 (D144).
    var refreshesPerDay = 1
    /// Friday's shipment uses the weekend budget (D146).
    var fridayIsWeekend = false
    var creatorOrder: CreatorOrder = .ranked

    // Friction on loosening limits (PLAN §3.6, D145): each limit has its own 7-day clock.
    var weekdayBudgetLockedUntil: Date?
    var weekendBudgetLockedUntil: Date?
    var refreshLockedUntil: Date?
    var shipmentHourLockedUntil: Date?
    var fridayLockedUntil: Date?
}

extension ShipmentSettings {
    /// Keys saved by builds before the Settings revamp (D144, D145).
    private enum LegacyKey: String, CodingKey {
        case refreshesPerWeek, budgetRaiseLockedUntil, refreshRaiseLockedUntil
    }

    /// Every key is optional, so settings saved by any older build still decode.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let old = try decoder.container(keyedBy: LegacyKey.self)
        self.init()
        weekdayBudget = try c.decodeIfPresent(TimeInterval.self, forKey: .weekdayBudget) ?? weekdayBudget
        weekendBudget = try c.decodeIfPresent(TimeInterval.self, forKey: .weekendBudget) ?? weekendBudget
        shipmentHour = try c.decodeIfPresent(Int.self, forKey: .shipmentHour) ?? shipmentHour
        fridayIsWeekend = try c.decodeIfPresent(Bool.self, forKey: .fridayIsWeekend) ?? false
        creatorOrder = try c.decodeIfPresent(CreatorOrder.self, forKey: .creatorOrder) ?? creatorOrder
        shipmentHourLockedUntil = try c.decodeIfPresent(Date.self, forKey: .shipmentHourLockedUntil)
        fridayLockedUntil = try c.decodeIfPresent(Date.self, forKey: .fridayLockedUntil)

        // A weekly count becomes a daily one: 1 stays 1, 2 or 3 become 2.
        if let perDay = try c.decodeIfPresent(Int.self, forKey: .refreshesPerDay) {
            refreshesPerDay = perDay
        } else if let perWeek = try old.decodeIfPresent(Int.self, forKey: .refreshesPerWeek) {
            refreshesPerDay = min(max(perWeek, 0), 2)
        }

        // Old locks ran 30 days. Cut them to 7 days from when they were set (23 days earlier).
        func trimmed(_ key: LegacyKey) throws -> Date? {
            try old.decodeIfPresent(Date.self, forKey: key)?.addingTimeInterval(-23 * 86_400)
        }
        let oldBudgetLock = try trimmed(.budgetRaiseLockedUntil)
        weekdayBudgetLockedUntil = try c.decodeIfPresent(Date.self, forKey: .weekdayBudgetLockedUntil) ?? oldBudgetLock
        weekendBudgetLockedUntil = try c.decodeIfPresent(Date.self, forKey: .weekendBudgetLockedUntil) ?? oldBudgetLock
        refreshLockedUntil = try c.decodeIfPresent(Date.self, forKey: .refreshLockedUntil) ?? trimmed(.refreshRaiseLockedUntil)
    }
}

/// Everything the engine owns and persists between launches.
struct ShipmentState: Hashable, Codable, Sendable {
    var home: [HomeEntry] = []
    var backlog: [Video] = []
    /// Videos that must never be served again (PLAN §3.1).
    var seen: Set<String> = []
    var lastShipment: Date?
    /// How many videos the last shipment brought (nil before the first one).
    /// Optional so state saved by older builds still decodes.
    var lastShipmentDelivered: Int?
    /// Minutes of video on Home right after the last shipment or refresh, carryover included (D97).
    /// Optional so state saved by older builds still decodes.
    var lastShipmentContent: TimeInterval?
    /// A video was finished (reached the last 60 s) since the last shipment. Hides the short-Inbox note (D97).
    /// Optional so state saved by older builds still decodes.
    var finishedSinceShipment: Bool?
    /// Seconds of video content played since the last shipment (refresh rule, PLAN §3.5).
    var watchedSinceShipment: TimeInterval = 0
    /// Shipment time that started the day `refreshesUsed` counts for (D144).
    var refreshDayStart: Date?
    var refreshesUsed = 0
    /// Seconds of video content played per calendar day ("2026-10-27"), for stats (D46).
    var watchLog: [String: TimeInterval]?
    /// Backlog videos pulled in when a creator was followed: their latest upload, not a new one.
    /// They get one shipment, then leave (D80). Optional so older saved state still decodes.
    var starters: Set<String>?
    /// Set once the one-time "last 24 hours only" cleanup has run (D91). Optional so older saved state still decodes.
    var recentResetDone: Bool?
    /// Set once today's Inbox was re-picked with the rank-first rule (D99). Optional so older saved state still decodes.
    var rankRepickDone: Bool?
    /// Set once every creator's "Last upload" was redone to count long-form videos only (D230).
    /// Optional so older saved state still decodes.
    var longFormDatesDone: Bool?
    /// The last video that left the Inbox (watched, removed or switched away), for "Put back" on
    /// the ⓘ page (D104). Optional so older saved state still decodes.
    var lastLeft: LeftEntry?
    /// Per creator: the newest upload time already looked at by the daily fetch (PLAN §3.3).
    /// Saved together with the backlog, so the app never "remembers" a video it didn't keep.
    /// Optional so older saved state still decodes.
    var fetchedThrough: [String: Date]?
    /// When YouTube last answered the new-uploads check, so it's asked only twice a day (D231).
    /// Optional so older saved state still decodes.
    var lastUploadCheck: Date?
    /// When the app was last opened. After a week without opening, the background wake-up
    /// stops asking YouTube anything (D235). Optional so older saved state still decodes.
    var lastOpenedAt: Date?
    /// Creators with "Watch in Order" on: their waiting videos are served oldest first (D150).
    /// Optional so older saved state still decodes.
    var inOrderCreators: Set<String>?
    /// Creators with "Any Length" on: their videos are never too long for the day (D151).
    /// Optional so older saved state still decodes.
    var anyLengthCreators: Set<String>?
    /// First run (docs/specs/first-run.md): `false` while a new person is still setting up, `true`
    /// once their first Inbox was loaded. Nil on installs from before first run, which never see it.
    var firstRunDone: Bool?
    /// The daily amount sheet was shown during first run. Optional so older saved state still decodes.
    var firstRunAmountPicked: Bool?
}

/// Why a refresh can or can't happen (PLAN §3.5, refresh-and-verses spec).
enum RefreshCheck: Hashable, Sendable {
    case allowed(remaining: Int)
    case nothingToSwap
    case noneLeft
    case alreadyStarted
    case notEnoughVideos
}

/// A Home entry removed via "Remove video", kept for Undo.
/// A video that left the Inbox and where it was (D104).
struct LeftEntry: Hashable, Codable, Sendable {
    let entry: HomeEntry
    let index: Int
}

struct RemovedEntry: Hashable, Sendable {
    let entry: HomeEntry
    let index: Int
}

/// One Mon–Sun week of watching, for the Settings stats (D147).
struct WeekStats: Hashable, Sendable {
    struct Day: Hashable, Sendable, Identifiable {
        let date: Date
        let watched: TimeInterval
        let budget: TimeInterval
        /// After today: not counted in the average.
        let isFuture: Bool

        var id: Date { date }
        var isOver: Bool { watched > budget }
    }

    let days: [Day]

    private var counted: [Day] { days.filter { !$0.isFuture } }
    var total: TimeInterval { days.reduce(0) { $0 + $1.watched } }
    var budget: TimeInterval { days.reduce(0) { $0 + $1.budget } }
    /// Average over the days so far (all seven for a past week).
    var dailyAverage: TimeInterval { counted.isEmpty ? 0 : total / Double(counted.count) }
    var daysCounted: Int { counted.count }
    var daysWithinBudget: Int { counted.filter { !$0.isOver }.count }

    /// Change in the daily average against `previous`, as a fraction (−0.12 = 12% less).
    /// Nil when the earlier week has nothing to compare with.
    func change(from previous: WeekStats) -> Double? {
        previous.dailyAverage > 0 ? (dailyAverage - previous.dailyAverage) / previous.dailyAverage : nil
    }
}
