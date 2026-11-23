import Foundation

/// All shipment, refresh and SEEN rules from PLAN §3. Pure Swift: no UI, no network, no clock.
/// Every time-dependent call takes `now`, so tests can jump days instantly.
struct ShipmentEngine: Sendable {
    /// Allowed distance from the budget when filling a shipment (PLAN §3.4).
    static let buffer: TimeInterval = 15 * 60
    /// A video counts as watched once the playhead is this close to the end (D11).
    static let watchedThreshold: TimeInterval = 60
    /// Watching more than this since the shipment blocks a refresh (PLAN §3.5).
    static let refreshWatchLimit: TimeInterval = 60
    /// Backlog videos older than this expire (D8).
    static let backlogLifetimeDays = 30

    var state: ShipmentState
    var settings: ShipmentSettings
    /// Followed creator IDs, top = served first.
    var creatorRank: [String]
    var calendar: Calendar

    init(
        state: ShipmentState = ShipmentState(),
        settings: ShipmentSettings = ShipmentSettings(),
        creatorRank: [String] = [],
        calendar: Calendar = .current
    ) {
        self.state = state
        self.settings = settings
        self.creatorRank = creatorRank
        self.calendar = calendar
    }

    // MARK: - Schedule

    /// Budget for the shipment arriving at `date`; Sat/Sun use the weekend budget (⚙︎g), and
    /// Friday too when that switch is on (D146).
    func budget(for date: Date) -> TimeInterval {
        Self.budget(for: date, settings: settings, calendar: calendar)
    }

    static func budget(for date: Date, settings: ShipmentSettings, calendar: Calendar) -> TimeInterval {
        let friday = settings.fridayIsWeekend && calendar.component(.weekday, from: date) == 6
        return calendar.isDateInWeekend(date) || friday ? settings.weekendBudget : settings.weekdayBudget
    }

    /// The first shipment time strictly after `date`.
    func nextShipment(after date: Date) -> Date {
        let sameDay = shipmentTime(on: date)
        if sameDay > date { return sameDay }
        let nextDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date))!
        return shipmentTime(on: nextDay)
    }

    /// Shipments owed since the last one, oldest first. Skipped days each get one (⚙︎a).
    func dueShipments(at now: Date) -> [Date] {
        guard let last = state.lastShipment else { return [] }
        var dates: [Date] = []
        var next = nextShipment(after: last)
        while next <= now {
            dates.append(next)
            next = nextShipment(after: next)
        }
        return dates
    }

    /// Start of the refresh day containing `now`: the latest shipment time at or before it (D144).
    func refreshDayStart(containing now: Date) -> Date {
        let today = shipmentTime(on: now)
        if today <= now { return today }
        return shipmentTime(on: calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now))!)
    }

    /// YouTube is checked for new uploads twice a day (D231): when new videos arrive and 12
    /// hours later. A check counts for a time once it's within `backgroundLead` before it, so
    /// the background wake-up's check serves the shipment that follows. This is the start of
    /// the stretch `now` is in: one check since then is enough.
    func uploadCheckStart(containing now: Date) -> Date {
        let today = calendar.startOfDay(for: now)
        let starts = (-1...1).flatMap { offset -> [Date] in
            let shipment = shipmentTime(on: calendar.date(byAdding: .day, value: offset, to: today)!)
            return [shipment, shipment.addingTimeInterval(Self.uploadCheckGap)]
        }.map { $0.addingTimeInterval(-Self.backgroundLead) }
        return starts.filter { $0 <= now }.max() ?? .distantPast
    }

    /// The second upload check of the day comes this long after new videos arrive (D231).
    static let uploadCheckGap: TimeInterval = 12 * 60 * 60

    private func shipmentTime(on day: Date) -> Date {
        calendar.date(bySettingHour: settings.shipmentHour, minute: 0, second: 0, of: day)!
    }

    // MARK: - Backlog

    /// Adds newly fetched videos, ignoring anything SEEN or already known.
    mutating func addToBacklog(_ videos: [Video]) {
        var known = Set(state.backlog.map(\.id)).union(state.home.map(\.id)).union(state.seen)
        for video in videos where !known.contains(video.id) {
            state.backlog.append(video)
            known.insert(video.id)
        }
    }

    /// Nothing has been served yet (onboarding, or only empty shipments so far). Only then does a
    /// new follow bring a starter; after that it brings only uploads posted from then on (D92).
    /// The one exception is a short day: while the "That's all for today" note shows, a new
    /// follow's latest video can fill the leftover time (D136). The "No new videos from your
    /// creators" Inbox is the shortest day there is, so it takes one too (D218).
    var wantsStarters: Bool {
        (state.home.isEmpty && state.seen.isEmpty) || isShortToday || isStarved
    }

    /// A new follow's latest upload (D80): served after new uploads, and only in the next shipment.
    mutating func addStarters(_ videos: [Video]) {
        let before = Set(state.backlog.map(\.id))
        addToBacklog(videos)
        let added = Set(state.backlog.map(\.id)).subtracting(before)
        state.starters = (state.starters ?? []).union(added)
    }

    /// Fresh uploads from the daily fetch. A creator's starter leaves once they post something new (D80).
    mutating func addNewUploads(_ videos: [Video]) {
        let before = Set(state.backlog.map(\.id))
        addToBacklog(videos)
        let addedCreators = Set(state.backlog.filter { !before.contains($0.id) }.map(\.creatorID))
        guard let starters = state.starters, !addedCreators.isEmpty else { return }
        state.backlog.removeAll { starters.contains($0.id) && addedCreators.contains($0.creatorID) }
        pruneStarters()
    }

    private func isStarter(_ video: Video) -> Bool {
        state.starters?.contains(video.id) ?? false
    }

    /// Forgets starter IDs that are no longer in the backlog.
    private mutating func pruneStarters() {
        guard let starters = state.starters else { return }
        let left = starters.intersection(state.backlog.map(\.id))
        state.starters = left.isEmpty ? nil : left
    }

    /// Unfollow: drops the creator's backlog videos (⚙︎d) and returns them for Undo.
    /// Videos already on Home stay.
    @discardableResult
    mutating func removeCreator(_ creatorID: String) -> [Video] {
        let removed = state.backlog.filter { $0.creatorID == creatorID }
        state.backlog.removeAll { $0.creatorID == creatorID }
        return removed
    }

    /// Backlog videos published more than 30 days before `now` become SEEN (D8).
    mutating func expireBacklog(at now: Date) {
        let cutoff = calendar.date(byAdding: .day, value: -Self.backlogLifetimeDays, to: now)!
        // A starter that is too old was never served, so it just leaves, like the starters a
        // shipment passes over (D80). Marking it SEEN made `wantsStarters` think a video had
        // been served: a first follow with only old videos then stopped every later follow
        // from bringing its latest one, and the Inbox stayed empty (D92).
        for video in state.backlog where video.publishedAt < cutoff && !isStarter(video) {
            state.seen.insert(video.id)
        }
        state.backlog.removeAll { $0.publishedAt < cutoff }
        pruneStarters()
    }

    /// Backlog in serving order (PLAN §3.4).
    func orderedBacklog() -> [Video] {
        let rank = Dictionary(creatorRank.enumerated().map { ($1, $0) }, uniquingKeysWith: min)
        let ranked = settings.creatorOrder == .ranked
        // Ties fall back to backlog order so the result is deterministic. Unranked creators go last.
        var ordered = state.backlog.enumerated().sorted { a, b in
            // New uploads before starters, so the Inbox always leads with what's new (D80).
            let sa = isStarter(a.element), sb = isStarter(b.element)
            if sa != sb { return !sa }
            if ranked {
                let ra = rank[a.element.creatorID] ?? .max
                let rb = rank[b.element.creatorID] ?? .max
                if ra != rb { return ra < rb }
            }
            if a.element.publishedAt != b.element.publishedAt {
                return a.element.publishedAt > b.element.publishedAt
            }
            return a.offset < b.offset
        }.map(\.element)
        // "Watch in Order" creators (D150): their videos keep the same spots in line, but the
        // oldest takes the earliest spot. Nobody else's videos move. Starters are left alone.
        for creatorID in state.inOrderCreators ?? [] {
            let spots = ordered.indices.filter { ordered[$0].creatorID == creatorID && !isStarter(ordered[$0]) }
            guard spots.count > 1 else { continue }
            let oldestFirst = spots.map { ordered[$0] }.enumerated().sorted { a, b in
                a.element.publishedAt != b.element.publishedAt ? a.element.publishedAt < b.element.publishedAt : a.offset < b.offset
            }.map(\.element)
            for (spot, video) in zip(spots, oldestFirst) { ordered[spot] = video }
        }
        return ordered
    }

    // MARK: - Watch in order (D150)

    func isInOrder(_ creatorID: String) -> Bool {
        state.inOrderCreators?.contains(creatorID) ?? false
    }

    /// Turns "Watch in Order" on or off for a creator. Only the order of their waiting videos
    /// changes; the Inbox is never touched.
    mutating func setInOrder(_ on: Bool, for creatorID: String) {
        var creators = state.inOrderCreators ?? []
        if on { creators.insert(creatorID) } else { creators.remove(creatorID) }
        state.inOrderCreators = creators.isEmpty ? nil : creators
    }

    // MARK: - Any length (D151)

    private var anyLength: Set<String> { state.anyLengthCreators ?? [] }

    func isAnyLength(_ creatorID: String) -> Bool {
        anyLength.contains(creatorID)
    }

    /// Turns "Any Length" on or off for a creator. The Inbox is never touched.
    mutating func setAnyLength(_ on: Bool, for creatorID: String) {
        var creators = anyLength
        if on { creators.insert(creatorID) } else { creators.remove(creatorID) }
        state.anyLengthCreators = creators.isEmpty ? nil : creators
    }

    /// Rank always wins (D99): take videos in order and stop once the full budget is reached (D48).
    /// The first video that won't fit under budget + 15 min ends the pick, so a lower-ranked video
    /// never jumps ahead of a higher-ranked one; the skipped video waits for the next shipment.
    /// Only a video longer than budget + 15 on its own is passed over, since it's never served (D9).
    /// `already` is time that counts toward the budget before the first pick (D136).
    /// `anyLength` creators are never too long (D151): their over-time video is served when it
    /// is first in line, as the only video of the pick. Behind another pick it's passed over and waits.
    static func pick(budget: TimeInterval, from ordered: [Video], already: TimeInterval = 0, anyLength: Set<String> = []) -> [Video] {
        var picked: [Video] = []
        var total = already
        guard total < budget else { return [] }
        for video in ordered {
            if video.duration > budget + buffer {
                if anyLength.contains(video.creatorID), picked.isEmpty, already == 0 { return [video] }
                continue
            }
            if total + video.duration > budget + buffer { break }
            picked.append(video)
            total += video.duration
            if total >= budget { break }
        }
        return picked
    }

    /// One-time re-pick of today's Inbox after the rank-first fix (D99). Unstarted videos go back
    /// in line and today's budget is picked again in rank order. Started videos stay put.
    /// Uses no refresh. Does nothing before the first shipment.
    mutating func repickToday() {
        guard let last = state.lastShipment else { return }
        let unstarted = state.home.filter { $0.progress == 0 }
        guard !unstarted.isEmpty else { return }
        let ids = Set(unstarted.map(\.id))
        state.home.removeAll { ids.contains($0.id) }
        state.backlog.removeAll { ids.contains($0.id) }
        state.backlog += unstarted.map(\.video)
        let picked = Self.pick(budget: budget(for: last), from: orderedBacklog(), anyLength: anyLength)
        let pickedIDs = Set(picked.map(\.id))
        state.backlog.removeAll { pickedIDs.contains($0.id) }
        pruneStarters()
        state.home += picked.map { HomeEntry(video: $0) }
        state.lastShipmentDelivered = picked.count
        state.lastShipmentContent = homeTimeRemaining
    }

    /// One-time cleanup (D91): every video published more than 24 hours before `now` leaves Home
    /// and the backlog and goes to SEEN, as if the app had just reached day two. Follows, settings,
    /// refreshes and stats are untouched. If Home ends up empty, it counts as starved so fresh
    /// uploads are served as soon as they arrive.
    mutating func keepOnlyRecent(at now: Date) {
        let cutoff = now.addingTimeInterval(-24 * 60 * 60)
        state.seen.formUnion(state.home.filter { $0.video.publishedAt < cutoff }.map(\.id))
        state.seen.formUnion(state.backlog.filter { $0.publishedAt < cutoff }.map(\.id))
        state.home.removeAll { $0.video.publishedAt < cutoff }
        state.backlog.removeAll { $0.publishedAt < cutoff }
        pruneStarters()
        if state.home.isEmpty, state.lastShipment != nil { state.lastShipmentDelivered = 0 }
    }

    // MARK: - Shipments

    /// Serves a shipment right now: first launch (D16) or an empty Home after following creators (D26).
    /// During first run it waits for "Load my Inbox" (D175, changes D16).
    mutating func shipNow(at now: Date) {
        guard !isFirstRun else { return }
        ship(at: now)
    }

    /// A new person is still setting up: nothing is served until they load their first Inbox (D175).
    var isFirstRun: Bool {
        state.firstRunDone == false
    }

    /// Home is empty because nothing has been served yet (onboarding) or the last shipment
    /// found nothing (empty state B), not because everything was watched (empty state A).
    var isStarved: Bool {
        state.home.isEmpty && (state.lastShipment == nil || state.lastShipmentDelivered == 0)
    }

    /// The "No new videos" Inbox has videos waiting only from creators just followed there.
    /// They are served when "Load my Inbox" is tapped, so there is time to rank first, like the
    /// first Inbox (D218). A new upload waiting too means there is news anyway: served at once (D26).
    /// Before anything was ever shipped, and in setups from before first run existed
    /// (`firstRunDone` never set), the first videos keep arriving by themselves (D16).
    var isWaitingForLoad: Bool {
        guard state.firstRunDone == true, state.lastShipment != nil, isStarved, !state.backlog.isEmpty else { return false }
        return state.backlog.allSatisfy(isStarter)
    }

    /// Applies every shipment owed since the last one. Returns how many arrived.
    @discardableResult
    mutating func applyDueShipments(at now: Date) -> Int {
        let due = dueShipments(at: now)
        due.forEach { ship(at: $0) }
        return due.count
    }

    /// Carryover stays on top and new videos are appended, no cap (D7).
    private mutating func ship(at date: Date) {
        expireBacklog(at: date)
        let picked = Self.pick(budget: budget(for: date), from: orderedBacklog(), anyLength: anyLength)
        let pickedIDs = Set(picked.map(\.id))
        state.backlog.removeAll { pickedIDs.contains($0.id) }
        // Starters had their one chance: the rest leave, so old videos never pile up (D80).
        if let starters = state.starters {
            state.backlog.removeAll { starters.contains($0.id) }
        }
        pruneStarters()
        state.home += picked.map { HomeEntry(video: $0) }
        state.lastShipment = date
        state.lastShipmentDelivered = picked.count
        state.lastShipmentContent = homeTimeRemaining
        state.finishedSinceShipment = false
        state.watchedSinceShipment = 0
    }

    /// Today's Inbox came up short: the last shipment (with carryover) had less than
    /// budget − 15 min to watch (PLAN §3.4). Shows the "follow more creators" note (D97).
    /// Only while Home still has videos (an empty Home has its own messages), and only until
    /// the first video of the day is finished.
    var isShortToday: Bool {
        guard !state.home.isEmpty, state.finishedSinceShipment != true, let last = state.lastShipment, let content = state.lastShipmentContent else { return false }
        return content < budget(for: last) - Self.buffer
    }

    /// Tops up a short day (D136): while the "That's all for today" note shows, the videos waiting
    /// (new follows' starters included) fill the leftover time in the usual order, under the
    /// cards already there. Rank still wins (D99). Uses no refresh, and never moves or removes
    /// what is already in the Inbox. Returns how many videos were added.
    @discardableResult
    mutating func fillToday(at now: Date) -> Int {
        guard isShortToday, let last = state.lastShipment, let content = state.lastShipmentContent else { return 0 }
        expireBacklog(at: now)
        let picked = Self.pick(budget: budget(for: last), from: orderedBacklog(), already: content, anyLength: anyLength)
        guard !picked.isEmpty else { return 0 }
        let pickedIDs = Set(picked.map(\.id))
        state.backlog.removeAll { pickedIDs.contains($0.id) }
        pruneStarters()
        state.home += picked.map { HomeEntry(video: $0) }
        state.lastShipmentDelivered = (state.lastShipmentDelivered ?? 0) + picked.count
        state.lastShipmentContent = content + picked.reduce(0) { $0 + $1.duration }
        return picked.count
    }

    // MARK: - Refresh

    func refreshesRemaining(at now: Date) -> Int {
        let used = state.refreshDayStart == refreshDayStart(containing: now) ? state.refreshesUsed : 0
        return max(settings.refreshesPerDay - used, 0)
    }

    func refreshCheck(at now: Date) -> RefreshCheck {
        if state.home.isEmpty { return .nothingToSwap }
        let remaining = refreshesRemaining(at: now)
        if remaining == 0 { return .noneLeft }
        if state.watchedSinceShipment > Self.refreshWatchLimit { return .alreadyStarted }
        let budget = budget(for: state.lastShipment ?? now)
        let total = Self.pick(budget: budget, from: orderedBacklog(), anyLength: anyLength).reduce(0) { $0 + $1.duration }
        if total < budget - Self.buffer { return .notEnoughVideos }
        return .allowed(remaining: remaining)
    }

    /// Swaps the whole Home list (⚙︎b) if allowed. Refused checks change nothing.
    @discardableResult
    mutating func refresh(at now: Date) -> RefreshCheck {
        let check = refreshCheck(at: now)
        guard case .allowed(let remaining) = check else { return check }
        state.seen.formUnion(state.home.map(\.id))
        state.home = []
        let picked = Self.pick(budget: budget(for: state.lastShipment ?? now), from: orderedBacklog(), anyLength: anyLength)
        let pickedIDs = Set(picked.map(\.id))
        state.backlog.removeAll { pickedIDs.contains($0.id) }
        state.home = picked.map { HomeEntry(video: $0) }
        state.lastShipmentContent = homeTimeRemaining
        state.refreshesUsed = settings.refreshesPerDay - remaining + 1
        state.refreshDayStart = refreshDayStart(containing: now)
        return check
    }

    /// The backlog video that would replace `videoID` (D98): the first in serving order that is
    /// at most 15 min longer than the one it replaces.
    func swapCandidate(for videoID: String) -> Video? {
        guard let old = state.home.first(where: { $0.id == videoID }) else { return nil }
        return orderedBacklog().first { $0.duration <= old.video.duration + Self.buffer }
    }

    /// Can one Inbox video be swapped (D98)? Uses the day's refreshes, but works any time of day,
    /// even after watching has started.
    func swapCheck(for videoID: String, at now: Date) -> RefreshCheck {
        guard state.home.contains(where: { $0.id == videoID }) else { return .nothingToSwap }
        let remaining = refreshesRemaining(at: now)
        if remaining == 0 { return .noneLeft }
        if swapCandidate(for: videoID) == nil { return .notEnoughVideos }
        return .allowed(remaining: remaining)
    }

    /// Swaps one Inbox video for a new one in the same spot, using 1 refresh (D98).
    /// The old video goes to SEEN. Refused checks change nothing.
    @discardableResult
    mutating func swap(_ videoID: String, at now: Date) -> RefreshCheck {
        let check = swapCheck(for: videoID, at: now)
        guard case .allowed(let remaining) = check,
              let index = state.home.firstIndex(where: { $0.id == videoID }),
              let replacement = swapCandidate(for: videoID) else { return check }
        state.seen.insert(videoID)
        state.backlog.removeAll { $0.id == replacement.id }
        state.home[index] = HomeEntry(video: replacement)
        pruneStarters()
        state.refreshesUsed = settings.refreshesPerDay - remaining + 1
        state.refreshDayStart = refreshDayStart(containing: now)
        return check
    }

    // MARK: - Watching

    /// Called from the player. `position` is the playhead; `played` is content seconds actually
    /// played since the last call (seeks add nothing). Reaching the last 60 s, by playing or
    /// seeking, marks the video watched (D11, D38). While the video is still `open` in the
    /// player that waits until it's closed or left (`finishWatching`), so scrubbing to the end
    /// and back keeps it in the Inbox (D103).
    mutating func recordPlayback(of videoID: String, position: TimeInterval, played: TimeInterval, open: Bool = false, at now: Date = .now) {
        recordWatchTime(played, at: now)
        guard let index = state.home.firstIndex(where: { $0.id == videoID }) else { return }
        let duration = state.home[index].video.duration
        state.home[index].progress = min(max(position, 0), duration)
        if !open { finishWatching(videoID) }
    }

    /// Watch time only, for the stats and the day's count. The video's place is left alone:
    /// used while a video that was put back is still playing out its end (D104, D185).
    mutating func recordWatchTime(_ played: TimeInterval, at now: Date = .now) {
        state.watchedSinceShipment += max(played, 0)
        if played > 0 { logWatch(played, at: now) }
    }

    /// The player closed or moved on: if the playhead was left in the last 60 s, it's watched (D103).
    mutating func finishWatching(_ videoID: String) {
        guard let entry = state.home.first(where: { $0.id == videoID }),
              entry.progress >= entry.video.duration - Self.watchedThreshold else { return }
        state.finishedSinceShipment = true
        markSeen(videoID)
    }

    /// The last video that left the Inbox, if it can still go back (D104).
    var puttableBack: HomeEntry? {
        guard let left = state.lastLeft, !state.home.contains(where: { $0.id == left.entry.id }) else { return nil }
        return left.entry
    }

    /// "Put back" on the ⓘ page (D104): the last video that left returns to its old spot. A
    /// watched one starts over, so it isn't marked watched again on the next launch.
    mutating func putBackLast() {
        guard let left = state.lastLeft, var entry = puttableBack else { return }
        if entry.progress >= entry.video.duration - Self.watchedThreshold { entry.progress = 0 }
        state.seen.remove(entry.id)
        state.home.insert(entry, at: min(left.index, state.home.count))
        state.lastLeft = nil
    }

    /// On launch: a video left in its last 60 s when the app was closed mid-play counts as watched.
    mutating func finishAllWatched() {
        for id in state.home.map(\.id) { finishWatching(id) }
    }

    /// Confirmed switch to another Up Next video: a started video is gone for good (D12).
    mutating func switchAway(from videoID: String) {
        guard let entry = state.home.first(where: { $0.id == videoID }), entry.progress > 0 else { return }
        markSeen(videoID)
    }

    /// "Remove video" (⚙︎e). Returns what Undo needs.
    @discardableResult
    mutating func remove(_ videoID: String) -> RemovedEntry? {
        guard let index = state.home.firstIndex(where: { $0.id == videoID }) else { return nil }
        let removed = RemovedEntry(entry: state.home[index], index: index)
        markSeen(videoID)
        return removed
    }

    mutating func undoRemove(_ removed: RemovedEntry) {
        if state.lastLeft?.entry.id == removed.entry.id { state.lastLeft = nil }
        state.seen.remove(removed.entry.id)
        state.home.insert(removed.entry, at: min(removed.index, state.home.count))
    }

    /// Long-press reorder on Home or Up Next (D17).
    mutating func moveHome(fromOffsets source: IndexSet, toOffset destination: Int) {
        // Same semantics as SwiftUI's `move(fromOffsets:toOffset:)`, without importing SwiftUI.
        let sorted = source.sorted()
        let moving = sorted.map { state.home[$0] }
        let insertAt = destination - sorted.filter { $0 < destination }.count
        for index in sorted.reversed() { state.home.remove(at: index) }
        state.home.insert(contentsOf: moving, at: insertAt)
    }

    /// Puts Home in the given order; IDs not on Home are ignored, missing ones keep their order at the end.
    mutating func setHomeOrder(_ ids: [String]) {
        let position = Dictionary(ids.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        state.home = state.home.enumerated().sorted { a, b in
            let pa = position[a.element.id] ?? Int.max
            let pb = position[b.element.id] ?? Int.max
            return pa != pb ? pa < pb : a.offset < b.offset
        }.map(\.element)
    }

    /// Time left across everything on Home (header, D31).
    var homeTimeRemaining: TimeInterval {
        state.home.reduce(0) { $0 + $1.remaining }
    }

    // MARK: - Background refresh (speed-and-polish ⚙︎)

    static let backgroundLead: TimeInterval = 30 * 60

    /// When to wake in the background: 30 min before the next shipment, but never in the past.
    func backgroundRefreshDate(after now: Date) -> Date {
        let next = nextShipment(after: max(now, state.lastShipment ?? now))
        return max(next.addingTimeInterval(-Self.backgroundLead), now)
    }

    /// What the next shipment would pick from today's backlog (to warm its thumbnails).
    func upcomingPick(at date: Date) -> [Video] {
        Self.pick(budget: budget(for: date), from: orderedBacklog(), anyLength: anyLength)
    }

    // MARK: - Settings

    /// New shipment hour (D45). Never grants a second shipment today: if today's shipment already
    /// came and the new hour is still ahead, today counts as shipped at the new hour.
    mutating func changeShipmentHour(to hour: Int, at now: Date) {
        settings.shipmentHour = hour
        guard let last = state.lastShipment, calendar.isDate(last, inSameDayAs: now) else { return }
        let todayAtNewHour = shipmentTime(on: now)
        if todayAtNewHour > last { state.lastShipment = todayAtNewHour }
    }

    // MARK: - Stats (D46)

    static let watchLogDays = 60

    func dayKey(_ date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    func watched(on day: Date) -> TimeInterval {
        state.watchLog?[dayKey(day)] ?? 0
    }

    /// Monday 00:00 of the week containing `now`.
    func calendarWeekStart(containing now: Date) -> Date {
        let weekday = calendar.component(.weekday, from: now) // 1 = Sunday
        return calendar.date(byAdding: .day, value: -((weekday + 5) % 7), to: calendar.startOfDay(for: now))!
    }

    /// One Mon–Sun week of watching for the Settings stats (D147). `weeksAgo` 0 is the week
    /// containing `now`; days after `now` are left out of the average and the "within budget" count.
    func weekStats(weeksAgo: Int = 0, now: Date) -> WeekStats {
        let start = calendar.date(byAdding: .day, value: -7 * weeksAgo, to: calendarWeekStart(containing: now))!
        let today = calendar.startOfDay(for: now)
        let days = (0..<7).map { offset -> WeekStats.Day in
            let date = calendar.date(byAdding: .day, value: offset, to: start)!
            return WeekStats.Day(date: date, watched: watched(on: date), budget: budget(for: date), isFuture: date > today)
        }
        return WeekStats(days: days)
    }

    /// How many weeks back the stats can go: to the week of the oldest logged day.
    func oldestStatsWeek(now: Date) -> Int {
        guard let oldest = state.watchLog?.keys.min() else { return 0 }
        var weeksAgo = 0
        while weeksAgo < Self.watchLogDays / 7 + 1 {
            let start = calendar.date(byAdding: .day, value: -7 * weeksAgo, to: calendarWeekStart(containing: now))!
            if dayKey(start) <= oldest { break }
            weeksAgo += 1
        }
        return weeksAgo
    }

    private mutating func logWatch(_ seconds: TimeInterval, at now: Date) {
        var log = state.watchLog ?? [:]
        log[dayKey(now), default: 0] += seconds
        if log.count > Self.watchLogDays {
            for key in log.keys.sorted().prefix(log.count - Self.watchLogDays) { log[key] = nil }
        }
        state.watchLog = log
    }

    private mutating func markSeen(_ videoID: String) {
        if let index = state.home.firstIndex(where: { $0.id == videoID }) {
            state.lastLeft = LeftEntry(entry: state.home[index], index: index)
        }
        state.home.removeAll { $0.id == videoID }
        state.seen.insert(videoID)
    }
}
