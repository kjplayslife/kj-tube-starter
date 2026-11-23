import Foundation
import Observation
import SwiftData

/// The app's single source of truth: followed creators (SwiftData) + the shipment engine.
/// Views stay thin and call into this.
@MainActor
@Observable
final class AppStore {
    /// Videos fetched for a newly followed creator: just their latest long-form upload
    /// (PLAN §3.3, D79). Tests may raise it to build fuller backlogs.
    @ObservationIgnored var videosPerNewCreator = 1

    private(set) var engine: ShipmentEngine

    /// Kept for Undo after an unfollow (following spec ⚙︎).
    private(set) var lastUnfollow: Unfollowed?
    /// A "Find creators" button was tapped: Following opens its search bar with the keyboard up (D137).
    var searchRequested = false
    /// How many creators an import just added: the app opens Following and says so (D158).
    /// Cleared once the message has been shown.
    var importedCount: Int?
    /// The first-run sheet that is up: the daily amount, or the check before the first Inbox (D175).
    var firstRunPage: FirstRunPage?

    /// "12 creators added. Hold and drag to rank them." Ranking only matters in Ranked mode.
    nonisolated static func importMessage(count: Int, ranked: Bool) -> String {
        let added = count == 1 ? "1 creator added." : "\(count) creators added."
        return ranked && count > 0 ? added + " Hold and drag to rank them." : added
    }

    /// Kept for Undo after "Remove video" (⚙︎e).
    fileprivate(set) var lastRemoved: RemovedEntry?
    /// When YouTube last answered the new-uploads check (or said its daily limit is reached).
    /// A due shipment waits for this to be fresh (D105).
    /// Saved with the engine state, so closing and opening the app doesn't ask again (D231).
    fileprivate var lastUploadFetch: Date? {
        get { engine.state.lastUploadCheck }
        set { engine.state.lastUploadCheck = newValue }
    }
    /// Why the last new-uploads check got nothing, for the Inbox status line (D110).
    fileprivate(set) var uploadProblem: UploadProblem?
    @ObservationIgnored fileprivate var isCheckingUploads = false
    @ObservationIgnored fileprivate var isFixingUploadDates = false
    /// How many just-followed creators are still having their latest video looked up. While
    /// it's above zero an empty Inbox shows "Getting today's videos…", not "No new videos" (D218).
    private(set) var followsLoading = 0
    /// "Load my Inbox" was tapped while a follow's video was still being looked up: it is
    /// served as soon as it lands, without asking again.
    @ObservationIgnored fileprivate var loadAsked = false
    /// How many creators are asked at the same time.
    nonisolated static let uploadChecksAtOnce = 6

    enum UploadProblem: Equatable, Sendable {
        case offline, unreachable, dailyLimit
    }

    /// Name and picture of unfollowed creators whose videos are still in the Inbox (D109).
    fileprivate(set) var formerCreators: [String: CreatorInfo] = [:]
    static let formerCreatorsKey = "formerCreators"

    /// View counts and descriptions for today's videos, fetched fresh (not stored with the
    /// video, since a count saved at upload time would be tiny). The last answer is kept so the
    /// cards show views in their first frame after a relaunch, not a moment later.
    fileprivate(set) var videoExtras: [String: VideoExtras] = [:]
    static let videoExtrasKey = "videoExtras"
    /// Subscriber counts by channel, for the player (fetched once per launch).
    fileprivate(set) var subscriberCounts: [String: Int] = [:]
    @ObservationIgnored fileprivate var lastExtrasFetch: Date?
    @ObservationIgnored fileprivate var extrasAsked: Set<String> = []
    @ObservationIgnored fileprivate var subscribersAsked: Set<String> = []
    static let extrasFetchInterval: TimeInterval = 30 * 60

    /// Shown on Home once the day's videos are done.
    private(set) var verse: Verse?
    /// A new verse after being away this long (refresh-and-verses spec).
    static let verseAwayInterval: TimeInterval = 5 * 60
    @ObservationIgnored private var backgroundedAt: Date?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let verses: [Verse]

    struct Unfollowed: Sendable {
        let channel: ChannelSummary
        let rank: Int
        let lastUploadAt: Date?
        let loadState: Creator.LoadState
        let backlog: [Video]
        /// "Watch in Order" was on (D150).
        let inOrder: Bool
        /// "Any Length" was on (D151).
        let anyLength: Bool
    }

    @ObservationIgnored let api: any YouTubeAPI
    /// The Skip Ad beta: its switch and the saved ad times (D111).
    @ObservationIgnored let ads: AdStore
    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private let record: EngineRecord

    init(
        context: ModelContext,
        api: any YouTubeAPI,
        calendar: Calendar = .current,
        defaults: UserDefaults = .standard,
        verses: [Verse] = VerseLibrary.all,
        adFinder: (any AdFinder)? = nil,
        firstRun: Bool = false
    ) {
        self.context = context
        self.api = api
        ads = AdStore(finder: adFinder, defaults: defaults)
        self.defaults = defaults
        self.verses = verses
        let record = (try? context.fetch(FetchDescriptor<EngineRecord>()).first) ?? {
            let new = EngineRecord(state: ShipmentState(), settings: ShipmentSettings())
            context.insert(new)
            return new
        }()
        self.record = record
        let decoder = JSONDecoder()
        engine = ShipmentEngine(
            state: (try? decoder.decode(ShipmentState.self, from: record.stateData)) ?? ShipmentState(),
            settings: (try? decoder.decode(ShipmentSettings.self, from: record.settingsData)) ?? ShipmentSettings(),
            calendar: calendar
        )
        engine.creatorRank = creators().map(\.channelID)
        // Only a phone with nothing on it starts first run; anyone already using the app never sees it.
        if firstRun, engine.state.firstRunDone == nil {
            let state = engine.state
            engine.state.firstRunDone = !engine.creatorRank.isEmpty || state.lastShipment != nil
                || !state.home.isEmpty || !state.seen.isEmpty
        }
        engine.finishAllWatched()
        if let data = defaults.data(forKey: Self.videoExtrasKey),
           let saved = try? JSONDecoder().decode([String: VideoExtras].self, from: data) {
            videoExtras = saved
        }
        if let data = defaults.data(forKey: Self.formerCreatorsKey),
           let saved = try? JSONDecoder().decode([String: CreatorInfo].self, from: data) {
            let onHome = Set(engine.state.home.map(\.video.creatorID))
            formerCreators = saved.filter { onHome.contains($0.key) } // forgotten once their videos leave
        }
    }

    // MARK: - Creators

    func creators() -> [Creator] {
        (try? context.fetch(FetchDescriptor<Creator>(sortBy: [SortDescriptor(\.rank)]))) ?? []
    }

    func isFollowing(_ channelID: String) -> Bool {
        creators().contains { $0.channelID == channelID }
    }

    /// Adds the creator at the bottom of the rank (⚙︎f). On day one their newest eligible upload
    /// joins the backlog; after that, only uploads posted from now on (D92), except on a short day,
    /// where the latest upload waits to fill today once KJ is back on the Inbox (D136).
    /// Today's Home list is never touched here (D26).
    func follow(_ channel: ChannelSummary) async {
        guard !isFollowing(channel.id) else { return }
        let creator = Creator(channel: channel, rank: creators().count)
        context.insert(creator)
        // A fresh follow starts a fresh fetch cursor (D92), even after an earlier unfollow.
        engine.state.fetchedThrough?[channel.id] = nil
        engine.creatorRank = creators().map(\.channelID)
        save()
        await loadUploads(for: creator)
    }

    /// Follows several creators at once, in the order given (import spec AC7). Each one goes
    /// through the same steps as a single follow, so the video rules are the same (AC8).
    /// All of them appear in Following right away; their videos are looked up side by side.
    func follow(_ channels: [ChannelSummary]) async {
        var added: [Creator] = []
        for channel in channels where !isFollowing(channel.id) {
            let creator = Creator(channel: channel, rank: creators().count)
            context.insert(creator)
            engine.state.fetchedThrough?[channel.id] = nil
            added.append(creator)
        }
        guard !added.isEmpty else { return }
        engine.creatorRank = creators().map(\.channelID)
        save()
        followsLoading += 1 // covers the moment before each creator's own lookup starts
        defer { followsLoading -= 1 }
        await withTaskGroup(of: Void.self) { group in
            for channelID in added.map(\.channelID) {
                group.addTask { await self.loadUploads(forChannelID: channelID) }
            }
        }
    }

    /// Retries creators whose first fetch failed (e.g. followed while offline).
    func retryFailedLoads() async {
        for creator in creators() where creator.loadState == .failed || creator.loadState == .loading {
            await loadUploads(for: creator)
        }
    }

    private func loadUploads(forChannelID channelID: String) async {
        guard let creator = creators().first(where: { $0.channelID == channelID }) else { return }
        await loadUploads(for: creator)
    }

    private func loadUploads(for creator: Creator) async {
        creator.loadState = .loading
        followsLoading += 1
        defer { followsLoading -= 1 }
        let channelID = creator.channelID
        do {
            let result = try await UploadsLoader(api: api)
                .latestEligible(channelID: channelID, count: videosPerNewCreator)
            // The creator may have been unfollowed while we were fetching.
            guard creator.modelContext != nil, !creator.isDeleted else { return }
            creator.lastUploadAt = result.lastLongFormAt // long-form only (D230)
            creator.loadState = result.videos.isEmpty ? .noEligible : .ready
            // The daily fetch starts after this upload. Set only once, so a retry never skips
            // a video posted since the follow.
            if engine.state.fetchedThrough?[channelID] == nil, let newest = result.newestUploadAt {
                var cursors = engine.state.fetchedThrough ?? [:]
                cursors[channelID] = newest
                engine.state.fetchedThrough = cursors
            }
            // After day one, old videos stay out: KJ has likely seen them on YouTube (D92).
            // A short day (D136) and an empty "No new videos" Inbox (D218) are the exceptions.
            if engine.wantsStarters { engine.addStarters(result.videos) }
        } catch {
            guard creator.modelContext != nil, !creator.isDeleted else { return }
            creator.loadState = .failed
        }
        save()
    }

    func unfollow(_ creator: Creator) {
        let all = creators()
        guard let rank = all.firstIndex(of: creator) else { return }
        let removedBacklog = engine.removeCreator(creator.channelID)
        // Their videos already in the Inbox stay (⚙︎d), and keep the name and picture (D109).
        if engine.state.home.contains(where: { $0.video.creatorID == creator.channelID }) {
            formerCreators[creator.channelID] = CreatorInfo(title: creator.title, avatarURL: creator.avatarURL)
            if let data = try? JSONEncoder().encode(formerCreators) { defaults.set(data, forKey: Self.formerCreatorsKey) }
        }
        lastUnfollow = Unfollowed(
            channel: ChannelSummary(id: creator.channelID, title: creator.title, handle: creator.handle,
                                    avatarURL: creator.avatarURL, subscriberCount: nil),
            rank: rank,
            lastUploadAt: creator.lastUploadAt,
            loadState: creator.loadState,
            backlog: removedBacklog,
            inOrder: engine.isInOrder(creator.channelID),
            anyLength: engine.isAnyLength(creator.channelID)
        )
        // A later follow starts with both switches off; Undo brings them back (D150, D151).
        engine.setInOrder(false, for: creator.channelID)
        engine.setAnyLength(false, for: creator.channelID)
        context.delete(creator)
        renumber(all.filter { $0 !== creator })
    }

    func undoUnfollow() {
        guard let undo = lastUnfollow, !isFollowing(undo.channel.id) else { return }
        lastUnfollow = nil
        let creator = Creator(channel: undo.channel, rank: undo.rank)
        creator.lastUploadAt = undo.lastUploadAt
        creator.loadState = undo.loadState
        context.insert(creator)
        var ordered = creators().filter { $0 !== creator }
        ordered.insert(creator, at: min(undo.rank, ordered.count))
        engine.addToBacklog(undo.backlog)
        engine.setInOrder(undo.inOrder, for: undo.channel.id)
        engine.setAnyLength(undo.anyLength, for: undo.channel.id)
        renumber(ordered)
    }

    func clearUndo() {
        lastUnfollow = nil
    }

    /// Long-press reorder in the Following list = new rank (D17).
    func moveCreators(fromOffsets source: IndexSet, toOffset destination: Int) {
        var ordered = creators()
        let sorted = source.sorted()
        let moving = sorted.map { ordered[$0] }
        let insertAt = destination - sorted.filter { $0 < destination }.count
        for index in sorted.reversed() { ordered.remove(at: index) }
        ordered.insert(contentsOf: moving, at: insertAt)
        renumber(ordered)
    }

    /// "Watch in Order" (D150): this creator's waiting videos are served oldest first.
    func isInOrder(_ creator: Creator) -> Bool {
        engine.isInOrder(creator.channelID)
    }

    func setInOrder(_ on: Bool, for creator: Creator) {
        engine.setInOrder(on, for: creator.channelID)
        save()
    }

    /// "Any Length" (D151): this creator's videos are never too long for the day.
    func isAnyLength(_ creator: Creator) -> Bool {
        engine.isAnyLength(creator.channelID)
    }

    func setAnyLength(_ on: Bool, for creator: Creator) {
        engine.setAnyLength(on, for: creator.channelID)
        save()
    }

    private func renumber(_ ordered: [Creator]) {
        for (rank, creator) in ordered.enumerated() where creator.rank != rank {
            creator.rank = rank
        }
        engine.creatorRank = ordered.map(\.channelID)
        save()
    }

    // MARK: - Settings

    var creatorOrder: CreatorOrder {
        get { engine.settings.creatorOrder }
        set {
            engine.settings.creatorOrder = newValue
            save()
        }
    }

    // MARK: - First run (docs/specs/first-run.md)

    var isFirstRun: Bool { engine.isFirstRun }

    var firstRunStep: FirstRunStep {
        FirstRun.step(done: !engine.isFirstRun, hasCreators: !engine.creatorRank.isEmpty)
    }

    /// The daily amount sheet came up, so it isn't shown by itself again. Continue keeps 30 / 60.
    func firstRunAmountShown() {
        guard engine.state.firstRunAmountPicked != true else { return }
        engine.state.firstRunAmountPicked = true
        save()
    }

    /// "Load my Inbox" was tapped: the check comes up, after the daily amount if it wasn't picked yet.
    func askToLoadInbox() {
        firstRunPage = engine.state.firstRunAmountPicked == true ? .check : .amount(thenCheck: true)
    }

    /// An import just finished during first run: the daily amount is asked once.
    func askAmountAfterImport() {
        guard isFirstRun, engine.state.firstRunAmountPicked != true, firstRunPage == nil else { return }
        firstRunPage = .amount(thenCheck: false)
    }

    /// What the check shows: minutes, creators in their current order, and who has a switch on.
    func firstRunSummary() -> FirstRun.Summary {
        let all = creators()
        return FirstRun.summary(
            weekdayMinutes: Int(engine.settings.weekdayBudget / 60),
            weekendMinutes: Int(engine.settings.weekendBudget / 60),
            fridayIsWeekend: engine.settings.fridayIsWeekend,
            creators: all.map(\.title),
            ranked: creatorOrder == .ranked,
            inOrder: all.filter { engine.isInOrder($0.channelID) }.map(\.title),
            anyLength: all.filter { engine.isAnyLength($0.channelID) }.map(\.title)
        )
    }

    /// Ends first run and serves the first shipment with the rank, minutes and switches as they
    /// are right now. From here on the normal rules apply, the weekly loosen clock included.
    func finishFirstRun(now: Date = .now) {
        engine.state.firstRunDone = true
        firstRunPage = nil
        applyShipmentsIfChecked(now: now)
        loadInbox(now: now)
    }

    /// "Load my Inbox" on the "No new videos" Inbox or on Following (D218): the videos waiting
    /// from the creators just followed are served, in the order they are ranked right now.
    func loadInbox(now: Date = .now) {
        loadAsked = followsLoading > 0
        if engine.isStarved, !engine.state.backlog.isEmpty { engine.shipNow(at: now) }
        save()
    }

    /// The Inbox is empty and a just-followed creator's video waits for "Load my Inbox".
    var isWaitingForLoad: Bool { engine.isWaitingForLoad && !loadAsked }

    /// An empty Inbox with videos waiting is served at once (D16, D26), unless they wait for
    /// "Load my Inbox" (D218).
    fileprivate func serveIfStarved(now: Date) {
        guard engine.isStarved, !engine.state.backlog.isEmpty, !isWaitingForLoad else { return }
        engine.shipNow(at: now)
        loadAsked = false
    }

    /// KJ Tube Dev only: empty the app and show first run again, to try it out.
    func startOver() {
        creators().forEach(context.delete)
        var state = ShipmentState()
        state.firstRunDone = false
        engine.state = state
        engine.settings = ShipmentSettings()
        engine.creatorRank = []
        formerCreators = [:]
        lastUnfollow = nil
        lastRemoved = nil
        firstRunPage = nil
        importedCount = nil
        save()
    }

    /// KJ Tube Dev only: put the Inbox on "No new videos from your creators", to try following
    /// from there (D218). Today's videos count as watched, and nothing is due until tomorrow.
    func emptyInboxForTesting(now: Date = .now) {
        engine.state.seen.formUnion(engine.state.home.map(\.id))
        engine.state.seen.formUnion(engine.state.backlog.map(\.id))
        engine.state.home = []
        engine.state.backlog = []
        engine.state.starters = nil
        engine.state.lastShipment = now
        engine.state.lastShipmentDelivered = 0
        engine.state.lastShipmentContent = 0
        lastRemoved = nil
        save()
    }

    // MARK: - Persistence

    func save() {
        let encoder = JSONEncoder()
        record.stateData = (try? encoder.encode(engine.state)) ?? record.stateData
        record.settingsData = (try? encoder.encode(engine.settings)) ?? record.settingsData
        try? context.save()
    }
}

// MARK: - Home (shipments, refresh, remove)

extension AppStore {
    /// Brings everything up to date when the app opens or Home appears: fetches new uploads
    /// (throttled), applies owed shipments, and serves right away if Home is starved (D16, D26).
    func catchUp(now: Date = .now) async {
        let checked = await fetchNewUploads(now: now)
        applyShipmentsIfChecked(now: now)
        if checked { await fixLastUploadDates() }
    }

    /// YouTube has already answered this half-day's new-uploads check (D231): one check when
    /// new videos arrive and one 12 hours later, however often the app is opened.
    func hasFreshCheck(at now: Date = .now) -> Bool {
        lastUploadFetch.map { $0 >= engine.uploadCheckStart(containing: now) } ?? false
    }

    /// A shipment is due but hasn't been delivered, because YouTube hasn't been checked yet (D105).
    func isShipmentWaiting(at now: Date = .now) -> Bool {
        !hasFreshCheck(at: now) && !engine.dueShipments(at: now).isEmpty
    }

    /// What the screens call: a due shipment is delivered only after a new-uploads check, so
    /// today's uploads arrive today (D105). Until then only day-one serving happens (D16, D26).
    func applyShipmentsIfChecked(now: Date = .now) {
        guard isShipmentWaiting(at: now) else { return applyShipments(now: now) }
        serveIfStarved(now: now)
        save()
    }

    /// Coming back to the Inbox on a short day: videos waiting from the creators just followed
    /// fill the leftover time (D136). Nothing happens while KJ is still on Following.
    func fillShortDay(now: Date = .now) {
        if engine.fillToday(at: now) > 0 { save() }
    }

    /// Applies owed shipments and serves immediately when starved. No network.
    func applyShipments(now: Date = .now) {
        applyOneTimeReset(now: now)
        let shipped = engine.applyDueShipments(at: now)
        applyRankRepick(shipped: shipped)
        serveIfStarved(now: now)
        save()
    }

    /// Installs from before D79/D80 still had old videos pulled on day one: clear them once,
    /// keeping only the last 24 hours (D91). A brand-new install has nothing to clear.
    private func applyOneTimeReset(now: Date) {
        guard engine.state.recentResetDone != true else { return }
        if engine.state.lastShipment != nil { engine.keepOnlyRecent(at: now) }
        engine.state.recentResetDone = true
    }

    /// After the rank-first fix (D99), re-pick today's Inbox once so it follows the new rule.
    /// Skipped if a new shipment just arrived, since that one already used the new rule.
    private func applyRankRepick(shipped: Int) {
        guard engine.state.rankRepickDone != true else { return }
        if shipped == 0 { engine.repickToday() }
        engine.state.rankRepickDone = true
    }

    /// Installs from before the fetch cursor (`fetchedThrough`) look back this far once, to pick up
    /// any upload whose "Last upload" time was saved without the video joining the line.
    static let cursorRecoveryLookback: TimeInterval = 3 * 24 * 60 * 60

    /// Adds every followed creator's eligible uploads published since we last looked (PLAN §3.3).
    /// The cursor lives in the engine state, saved in the same write as the backlog. "Last upload"
    /// on Following is display only: it can be saved on its own, so it must never decide what's fetched.
    /// Returns true when YouTube was asked and answered just now.
    @discardableResult
    func fetchNewUploads(now: Date = .now) async -> Bool {
        if hasFreshCheck(at: now) || isCheckingUploads { return false }
        isCheckingUploads = true
        defer { isCheckingUploads = false }
        let recovery = now.addingTimeInterval(-Self.cursorRecoveryLookback)
        let jobs = creators().filter { $0.loadState == .ready || $0.loadState == .noEligible }.map { creator in
            UploadsLoader.Job(
                channelID: creator.channelID,
                since: engine.state.fetchedThrough?[creator.channelID]
                    ?? creator.lastUploadAt.map { min($0, recovery) }
                    ?? .distantPast
            )
        }
        let answers = await UploadsLoader(api: api).eligibleUploads(for: jobs, atOnce: Self.uploadChecksAtOnce)

        let stillFollowed = creatorsByID()
        var answered = 0
        var failures: [YouTubeError] = []
        for (job, answer) in zip(jobs, answers) {
            let result: UploadsLoader.Result
            switch answer {
            case .success(let found): result = found
            case .failure(let error):
                failures.append(error)
                continue
            }
            answered += 1
            // The creator may have been unfollowed while we were asking.
            guard let creator = stillFollowed[job.channelID], creator.modelContext != nil else { continue }
            engine.addNewUploads(result.videos)
            var cursors = engine.state.fetchedThrough ?? [:]
            cursors[job.channelID] = max(job.since, result.newestUploadAt ?? job.since)
            engine.state.fetchedThrough = cursors
            if let newest = result.lastLongFormAt, newest > (creator.lastUploadAt ?? .distantPast) {
                creator.lastUploadAt = newest
            }
            if !result.videos.isEmpty { creator.loadState = .ready }
        }

        // One creator failing is fine: their cursor didn't move, so they're asked again next time.
        // Nobody answering means the check didn't happen, and it's tried again soon (D106).
        if jobs.isEmpty || answered > 0 {
            uploadProblem = nil
            lastUploadFetch = now
        } else if failures.contains(.quotaExceeded) {
            // No use asking again today: ship from what's already waiting.
            uploadProblem = .dailyLimit
            lastUploadFetch = now
        } else {
            uploadProblem = failures.contains(.offline) ? .offline : .unreachable
        }
        save()
        return !jobs.isEmpty && answered > 0
    }

    /// One time only (D230): "Last upload" used to count Shorts and live streams. Look at each
    /// creator's recent uploads once and keep the newest long-form video's date instead. Runs
    /// after a new-uploads check that worked, and again after the next one if anybody failed.
    func fixLastUploadDates() async {
        guard engine.state.longFormDatesDone != true, !isFixingUploadDates else { return }
        isFixingUploadDates = true
        defer { isFixingUploadDates = false }
        let jobs = creators().filter { $0.loadState == .ready || $0.loadState == .noEligible }
            .map { UploadJob(channelID: $0.channelID, since: .distantPast) }
        let loader = UploadsLoader(api: api)
        let answers = await Self.check(jobs) { try await loader.latestEligible(channelID: $0.channelID, count: 1) }

        let stillFollowed = creatorsByID()
        var failed = false
        for (job, answer) in zip(jobs, answers) {
            guard case .success(let result) = answer else {
                failed = true
                continue
            }
            guard let creator = stillFollowed[job.channelID], creator.modelContext != nil else { continue }
            if creator.lastUploadAt != result.lastLongFormAt { creator.lastUploadAt = result.lastLongFormAt }
        }
        if !failed { engine.state.longFormDatesDone = true }
        save()
    }

    private struct UploadJob: Sendable {
        let channelID: String
        let since: Date
    }

    /// Asks several creators at once (a few, not all, to stay gentle on a weak connection).
    /// Answers come back in the order of `jobs`.
    private nonisolated static func check(
        _ jobs: [UploadJob], ask one: @escaping @Sendable (UploadJob) async throws -> UploadsLoader.Result
    ) async -> [Result<UploadsLoader.Result, YouTubeError>] {
        let ask: @Sendable (Int) async -> (Int, Result<UploadsLoader.Result, YouTubeError>) = { index in
            do {
                return (index, .success(try await one(jobs[index])))
            } catch {
                return (index, .failure((error as? YouTubeError) ?? .server(error.localizedDescription)))
            }
        }
        return await withTaskGroup(of: (Int, Result<UploadsLoader.Result, YouTubeError>).self) { group in
            var answers = [Result<UploadsLoader.Result, YouTubeError>](repeating: .failure(.server("not asked")), count: jobs.count)
            var next = 0
            while next < min(uploadChecksAtOnce, jobs.count) {
                let index = next
                group.addTask { await ask(index) }
                next += 1
            }
            for await (index, answer) in group {
                answers[index] = answer
                if next < jobs.count {
                    let index = next
                    group.addTask { await ask(index) }
                    next += 1
                }
            }
            return answers
        }
    }

    func creatorTitle(_ channelID: String) -> String {
        creator(channelID)?.title ?? formerCreators[channelID]?.title ?? ""
    }

    /// Name and picture for every creator a card may show: the followed ones, plus unfollowed
    /// ones whose videos are still in the Inbox (D109). One fetch for many cards.
    func creatorInfoByID() -> [String: CreatorInfo] {
        var info = formerCreators
        for creator in creators() {
            info[creator.channelID] = CreatorInfo(title: creator.title, avatarURL: creator.avatarURL)
        }
        return info
    }

    func creator(_ channelID: String) -> Creator? {
        creators().first { $0.channelID == channelID }
    }

    /// Every followed creator by channel ID, from one fetch: look up many cards without a fetch each.
    func creatorsByID() -> [String: Creator] {
        Dictionary(creators().map { ($0.channelID, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// Reads the first few Inbox cards' pictures from disk before the first frame, so they never
    /// pop in after a cold start. Every other picture loads off the main thread.
    func warmFirstCards(_ count: Int = 3) {
        let entries = engine.state.home.prefix(count)
        let byID = creatorInfoByID()
        ImageCache.shared.warmFromDisk(
            entries.map { Thumbnail.urls($0.id) }
                + entries.compactMap { entry -> [URL]? in byID[entry.video.creatorID]?.avatarURL.map { [$0] } }
        )
    }

    /// Fetches view counts and descriptions for today's videos, and subscriber counts for
    /// their creators: right away for anything new, otherwise views at most every 30 minutes.
    /// One quota unit per call. Failures are ignored.
    func refreshExtras(now: Date = .now) async {
        let ids = engine.state.home.map(\.id)
        guard !ids.isEmpty else { return }
        let missing = ids.contains { !extrasAsked.contains($0) }
        if missing || lastExtrasFetch.map({ now.timeIntervalSince($0) >= Self.extrasFetchInterval }) ?? true {
            lastExtrasFetch = now
            for batch in stride(from: 0, to: ids.count, by: 50).map({ Array(ids[$0..<min($0 + 50, ids.count)]) }) {
                guard let extras = try? await api.videoExtras(ids: batch) else { break }
                extrasAsked.formUnion(batch)
                videoExtras.merge(extras) { _, new in new }
            }
            // Keep only today's videos, so the saved list never grows.
            let kept = videoExtras.filter { ids.contains($0.key) }
            if let data = try? JSONEncoder().encode(kept) { defaults.set(data, forKey: Self.videoExtrasKey) }
        }
        let channels = Array(Set(engine.state.home.map(\.video.creatorID)).subtracting(subscribersAsked))
        guard !channels.isEmpty else { return }
        subscribersAsked.formUnion(channels)
        for batch in stride(from: 0, to: channels.count, by: 50).map({ Array(channels[$0..<min($0 + 50, channels.count)]) }) {
            guard let found = try? await api.channels(ids: batch) else { continue }
            for channel in found { if let count = channel.subscriberCount { subscriberCounts[channel.id] = count } }
        }
    }

    static let creatorsRefreshedKey = "creatorsRefreshedAt"
    /// YouTube asks apps not to keep its data longer than 30 days without refreshing it. A
    /// week keeps names and pictures current and stays far inside that.
    static let creatorsRefreshInterval: TimeInterval = 7 * 24 * 60 * 60

    /// Brings every followed creator's name, @handle and picture up to date, at most once a
    /// week. One quota unit per 50 creators. A failure is ignored and tried again next time.
    func refreshCreators(now: Date = .now) async {
        if let last = defaults.object(forKey: Self.creatorsRefreshedKey) as? Date,
           now.timeIntervalSince(last) < Self.creatorsRefreshInterval { return }
        let all = creators()
        guard !all.isEmpty else { return }
        let ids = all.map(\.channelID)
        var fresh: [String: ChannelSummary] = [:]
        for batch in stride(from: 0, to: ids.count, by: 50).map({ Array(ids[$0..<min($0 + 50, ids.count)]) }) {
            guard let found = try? await api.channels(ids: batch) else { return }
            for channel in found { fresh[channel.id] = channel }
        }
        // By ID again: a creator may have been unfollowed while YouTube was answering.
        for creator in creators() {
            guard let channel = fresh[creator.channelID] else { continue }
            if creator.title != channel.title { creator.title = channel.title }
            if creator.handle != channel.handle { creator.handle = channel.handle }
            if creator.avatarURL != channel.avatarURL { creator.avatarURL = channel.avatarURL }
        }
        save()
        defaults.set(now, forKey: Self.creatorsRefreshedKey)
    }

    func moveHome(fromOffsets source: IndexSet, toOffset destination: Int) {
        engine.moveHome(fromOffsets: source, toOffset: destination)
        save()
    }

    func setHomeOrder(_ ids: [String]) {
        engine.setHomeOrder(ids)
        save()
    }

    /// "Remove video" (⚙︎e).
    func removeVideo(_ videoID: String) {
        lastRemoved = engine.remove(videoID)
        save()
    }

    func undoRemoveVideo() {
        guard let removed = lastRemoved else { return }
        lastRemoved = nil
        engine.undoRemove(removed)
        save()
    }

    func clearRemoveUndo() {
        lastRemoved = nil
    }

    /// From the player (Phase 4): playhead + content seconds played since the last call.
    /// `open`: the video is still on screen, so the last-60-s check waits for `finishWatching` (D103).
    func recordPlayback(of videoID: String, position: TimeInterval, played: TimeInterval, open: Bool = false) {
        engine.recordPlayback(of: videoID, position: position, played: played, open: open)
        save()
    }

    /// Watch time only; the video's place in the Inbox is left alone (D104, D185).
    func recordWatchTime(_ played: TimeInterval) {
        engine.recordWatchTime(played)
        save()
    }

    /// The player closed or moved on from this video (D103).
    func finishWatching(_ videoID: String) {
        engine.finishWatching(videoID)
        save()
    }

    /// Confirmed switch to another Up Next video (D12).
    func switchAway(from videoID: String) {
        engine.switchAway(from: videoID)
        save()
    }

    /// YouTube can't play it (deleted, private, unembeddable): gone for good, no Undo.
    func dropUnavailable(_ videoID: String) {
        engine.remove(videoID)
        engine.state.lastLeft = nil // nothing to put back: it can't play
        save()
    }

    /// "Put back" on the ⓘ page (D104).
    func putBackLastVideo() {
        engine.putBackLast()
        save()
    }

    func refreshCheck(now: Date = .now) -> RefreshCheck {
        engine.refreshCheck(at: now)
    }

    func refresh(now: Date = .now) {
        engine.refresh(at: now)
        save()
    }

    func swapCheck(_ videoID: String, now: Date = .now) -> RefreshCheck {
        engine.swapCheck(for: videoID, at: now)
    }

    /// "Swap this video" from the ⋯ menu (D98).
    func swapVideo(_ videoID: String, now: Date = .now) {
        engine.swap(videoID, at: now)
        save()
    }
}

// MARK: - Settings (PLAN §3.6, D44)

extension AppStore {
    enum Limit: Sendable {
        case weekdayBudget, weekendBudget, refreshesPerDay
    }

    func value(of limit: Limit) -> Double {
        switch limit {
        case .weekdayBudget: engine.settings.weekdayBudget / 60
        case .weekendBudget: engine.settings.weekendBudget / 60
        case .refreshesPerDay: Double(engine.settings.refreshesPerDay)
        }
    }

    func lockedUntil(_ limit: Limit) -> Date? {
        switch limit {
        case .weekdayBudget: engine.settings.weekdayBudgetLockedUntil
        case .weekendBudget: engine.settings.weekendBudgetLockedUntil
        case .refreshesPerDay: engine.settings.refreshLockedUntil
        }
    }

    func evaluate(_ limit: Limit, to new: Double, now: Date = .now) -> SettingChange {
        SettingsPolicy.raise(from: value(of: limit), to: new, lockedUntil: lockedUntil(limit), now: now, calendar: engine.calendar)
    }

    /// The warning to show before lowering a daily limit, or nil when the change needs none:
    /// it isn't a lowering, or it's the refresh count, which isn't a daily limit (D210).
    func lowerWarning(
        _ limit: Limit, to new: Double, now: Date = .now,
        day: (Date) -> String = { $0.formatted(.dateTime.month(.abbreviated).day()) }
    ) -> String? {
        guard limit != .refreshesPerDay, new < value(of: limit) else { return nil }
        return SettingsPolicy.lowerWarning(lockedUntil: lockedUntil(limit), now: now, day: day)
    }

    /// Applies a change already cleared by `evaluate` (and confirmed, for a raise).
    func set(_ limit: Limit, to new: Double, lockUntil: Date? = nil) {
        switch limit {
        case .weekdayBudget:
            engine.settings.weekdayBudget = new * 60
        case .weekendBudget:
            engine.settings.weekendBudget = new * 60
        case .refreshesPerDay:
            engine.settings.refreshesPerDay = Int(new)
        }
        if let lockUntil {
            switch limit {
            case .weekdayBudget: engine.settings.weekdayBudgetLockedUntil = lockUntil
            case .weekendBudget: engine.settings.weekendBudgetLockedUntil = lockUntil
            case .refreshesPerDay: engine.settings.refreshLockedUntil = lockUntil
            }
        }
        save()
    }

    /// The Friday switch loosens only when it gives Fridays more minutes (D146).
    func evaluateFridayIsWeekend(_ on: Bool, now: Date = .now) -> SettingChange {
        let s = engine.settings
        let fridayNow = s.fridayIsWeekend ? s.weekendBudget : s.weekdayBudget
        let fridayThen = on ? s.weekendBudget : s.weekdayBudget
        return SettingsPolicy.change(
            loosens: on != s.fridayIsWeekend && fridayThen > fridayNow,
            lockedUntil: s.fridayLockedUntil, now: now, calendar: engine.calendar
        )
    }

    func setFridayIsWeekend(_ on: Bool, lockUntil: Date? = nil) {
        engine.settings.fridayIsWeekend = on
        if let lockUntil { engine.settings.fridayLockedUntil = lockUntil }
        save()
    }

    func evaluateShipmentHour(_ hour: Int, now: Date = .now) -> SettingChange {
        SettingsPolicy.shipmentTime(
            from: engine.settings.shipmentHour, to: hour,
            lockedUntil: engine.settings.shipmentHourLockedUntil, now: now, calendar: engine.calendar
        )
    }

    func setShipmentHour(_ hour: Int, lockUntil: Date?, now: Date = .now) {
        engine.changeShipmentHour(to: hour, at: now)
        if let lockUntil { engine.settings.shipmentHourLockedUntil = lockUntil }
        save()
    }
}

// MARK: - Verses (D41)

extension AppStore {
    /// Call when the app becomes active: a cold launch or coming back after 5+ minutes away
    /// moves to the next verse in the shuffle bag.
    func appBecameActive(now: Date = .now) {
        let away = backgroundedAt.map { now.timeIntervalSince($0) } ?? .infinity
        backgroundedAt = nil
        if verse == nil || away >= Self.verseAwayInterval { advanceVerse() }
        engine.state.lastOpenedAt = now // the background wake-up goes quiet a week after this (D235)
        save()
    }

    /// How long the app may go unopened before the background wake-up stops asking YouTube (D235).
    static let dormantAfter: TimeInterval = 7 * 24 * 60 * 60

    /// True once the app hasn't been opened for over a week. An install from before this was
    /// tracked starts its week now.
    func isDormant(at now: Date = .now) -> Bool {
        guard let opened = engine.state.lastOpenedAt else {
            engine.state.lastOpenedAt = now
            save()
            return false
        }
        return now.timeIntervalSince(opened) > Self.dormantAfter
    }

    func appWentToBackground(now: Date = .now) {
        backgroundedAt = now
    }

    private func advanceVerse() {
        var bag = (defaults.data(forKey: "verseBag")).flatMap { try? JSONDecoder().decode(VerseBag.self, from: $0) } ?? VerseBag()
        guard let index = bag.next(count: verses.count) else { return }
        verse = verses[index]
        defaults.set(try? JSONEncoder().encode(bag), forKey: "verseBag")
    }
}

#if DEBUG
extension AppStore {
    /// Tests and Simulator checks only: put specific videos on Home.
    func seedHome(_ entries: [HomeEntry]) {
        engine.state.home = entries
        save()
    }

    /// Simulator checks only: pretend the last shipment was two days ago, so one is due now.
    func makeShipmentDue(now: Date = .now) {
        guard let last = engine.state.lastShipment else { return }
        engine.state.lastShipment = min(last, now.addingTimeInterval(-2 * 24 * 60 * 60))
        save()
    }

    /// Tests only: forget the fetch cursors, like state saved by a build from before them.
    func clearFetchCursors() {
        engine.state.fetchedThrough = nil
        save()
    }
}
#endif
