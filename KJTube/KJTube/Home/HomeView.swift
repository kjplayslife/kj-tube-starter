import Combine
import SwiftUI

/// Today's shipment (docs/specs/shipment-and-home.md).
struct HomeView: View {
    @Environment(AppStore.self) private var store
    @Binding var tab: AppTab

    /// Every "Find creators" button: opens Following with the search bar ready to type in (D137).
    private func findCreators() {
        store.searchRequested = true
        tab = .following
    }

    @State private var refreshAlert: RefreshCheck?
    /// A pull-down's answer, held until the list has let go and settled.
    @State private var pendingRefreshAlert: RefreshCheck?
    @State private var listIsSettled = true
    @State private var swapAlert: SwapRequest?
    @State private var showsInfo = false
    @State private var now = Date.now

    /// Every second, but the screen only changes once a minute until the final minute.
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            Group {
                if store.engine.state.home.isEmpty {
                    emptyState
                } else {
                    shipmentList
                }
            }
            .pageTitle("Inbox")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Inbox info", systemImage: "info.circle") { showsInfo = true }
                }
            }
            .sheet(isPresented: $showsInfo) {
                InboxInfoView(tab: $tab) // full height: a half sheet glitched when dragged up
            }
            .undoToast(
                id: store.lastRemoved?.entry.id,
                message: "Removed \(store.lastRemoved?.entry.video.title ?? "")",
                onUndo: { store.undoRemoveVideo() },
                onExpire: { store.clearRemoveUndo() }
            )
            .animation(.default, value: store.engine.state.home.map(\.id))
        }
        .alert(alertTitle, isPresented: alertShown, presenting: refreshAlert) { check in
            alertButtons(check)
        } message: { check in
            Text(alertMessage(check))
        }
        .alert(swapTitle, isPresented: swapShown, presenting: swapAlert) { request in
            swapButtons(request)
        } message: { request in
            Text(swapMessage(request.check))
        }
        // Coming back from Following serves straight away if Home was starved (D26).
        .onAppear {
            store.applyShipmentsIfChecked()
            store.fillShortDay() // a short day fills up from the creators just followed (D136)
            Task { await store.catchUp() } // a due shipment arrives once YouTube has been checked (D105)
        }
        // A follow whose video was still loading when KJ came back fills in once it lands (D136).
        .onChange(of: store.engine.state.backlog.count) {
            guard tab == .home else { return }
            store.fillShortDay()
            // A first video that was still loading when the Inbox opened is served once it lands (D26).
            if store.engine.isStarved { store.applyShipmentsIfChecked() }
        }
        .onChange(of: store.engine.state.home.map(\.id), initial: true) { _, ids in
            ImageCache.shared.prefetch(ids.map(Thumbnail.urls))
        }
        .task(id: store.engine.state.home.map(\.id)) {
            store.ads.check(store.engine.state.home.map(\.video)) // Skip Ad beta: runs alone in the background
            await store.refreshExtras()
            await store.refreshCreators() // at most once a week
        }
        .onReceive(tick) { date in
            let changedMinute = !Calendar.current.isDate(date, equalTo: now, toGranularity: .minute)
            guard changedMinute || timeToNextShipment < 61 else { return }
            now = date
            store.applyShipmentsIfChecked(now: date) // A shipment that comes due while Home is open appears.
            // Still owed one: check YouTube first, and keep trying each minute if that failed (D106).
            if store.isShipmentWaiting(at: date) { Task { await store.catchUp(now: date) } }
        }
        .onAppear { Timing.homeVisible() }
        .sensoryFeedback(.impact(weight: .light), trigger: store.lastRemoved?.entry.id) { _, new in new != nil }
        .sensoryFeedback(.impact(weight: .medium), trigger: store.engine.state.refreshesUsed) { old, new in new > old }
    }

    // MARK: - Shipment

    private var shipmentList: some View {
        List {
            if let problem = store.uploadProblem {
                Text(problem.message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 8, trailing: 16))
            }
            Section {
                let home = store.engine.state.home
                let creators = store.creatorInfoByID() // one fetch for the whole list, not one per card
                ForEach(Array(home.enumerated()), id: \.element.id) { index, entry in
                    let creator = creators[entry.video.creatorID]
                    InboxRow(
                        entry: entry,
                        creator: creator?.title ?? "",
                        avatarURL: creator?.avatarURL,
                        views: store.videoExtras[entry.id]?.viewCount,
                        canMoveUp: index > 0,
                        canMoveDown: index < home.count - 1,
                        perform: handle
                    )
                    .equatable() // a card redraws only when its own info changes
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                }
                .onMove { store.moveHome(fromOffsets: $0, toOffset: $1) }
            }
            if store.engine.isShortToday, store.followsLoading > 0 {
                // Back from following someone on a short day: their video is on its way (D136).
                Section {
                    LoadingNewVideos()
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 24, trailing: 16))
                }
            } else if store.engine.isShortToday {
                Section {
                    ShortInboxNote(budgetMinutes: shortNoteBudgetMinutes) { findCreators() }
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 24, trailing: 16))
                }
            }
        }
        .listStyle(.plain)
        .refreshable {
            pendingRefreshAlert = store.refreshCheck()
            showRefreshAlertOnceSettled()
        }
        .onScrollPhaseChange { _, phase in
            listIsSettled = phase == .idle
            if listIsSettled { showRefreshAlertOnceSettled() }
        }
    }

    /// Shows the pull-down's alert only after the finger is off and the list is back in place.
    /// An alert that comes up while the list is still held down leaves the spinner showing and
    /// the list pulled down for good, whatever the alert says. A fixed wait wasn't enough: a
    /// finger can hold the list down longer than any wait.
    private func showRefreshAlertOnceSettled() {
        guard pendingRefreshAlert != nil else { return }
        Task {
            try? await Task.sleep(for: .milliseconds(400))
            // Still held or moving: the next time the list comes to rest tries again.
            guard listIsSettled, let check = pendingRefreshAlert else { return }
            pendingRefreshAlert = nil
            refreshAlert = check
        }
    }

    /// A card's tap or menu choice. Looks the video up by ID when it happens, so a card that
    /// skipped redrawing never acts on an old position.
    private func handle(_ action: InboxRow.Action, _ id: String) {
        let home = store.engine.state.home
        guard let index = home.firstIndex(where: { $0.id == id }) else { return }
        switch action {
        case .play:
            Timing.videoRequested()
            // No system slide from the bottom of the screen: the player moves itself up from
            // the tapped card's picture, which is a shorter trip (D138).
            NowPlaying.shared.play(home[index], from: CardOrigins.top[id])
        case .moveUp:
            guard index > 0 else { return }
            store.moveHome(fromOffsets: [index], toOffset: index - 1)
        case .moveDown:
            guard index < home.count - 1 else { return }
            store.moveHome(fromOffsets: [index], toOffset: index + 2)
        case .swap:
            swapAlert = SwapRequest(videoID: id, check: store.swapCheck(id))
        case .remove:
            store.removeVideo(id)
        }
    }

    /// The budget the last shipment tried to fill, for the short-Inbox note (D97).
    private var shortNoteBudgetMinutes: Int {
        let engine = store.engine
        return Int(engine.budget(for: engine.state.lastShipment ?? now) / 60)
    }

    private var timeToNextShipment: TimeInterval {
        store.engine.nextShipment(after: max(now, store.engine.state.lastShipment ?? now)).timeIntervalSince(now)
    }

    // MARK: - Empty states

    @ViewBuilder
    private var emptyState: some View {
        let hasCreators = !store.creators().isEmpty
        if store.isFirstRun {
            // Nothing is served until the first Inbox is loaded on purpose (D175).
            FirstRunInbox(
                hasCreators: hasCreators,
                findCreators: { findCreators() },
                rankCreators: { tab = .following }
            )
        } else if !hasCreators {
            EmptyHomeMessage(
                title: "Welcome to KJ Tube",
                message: "Follow a few creators you trust. Each morning you'll get a few of their new videos, sized to your time.",
                action: ("Find creators", { findCreators() })
            )
        } else if store.isShipmentWaiting(at: now) {
            // Today's shipment is owed but YouTube hasn't been checked yet (D105, D106).
            if let problem = store.uploadProblem {
                EmptyHomeMessage(title: "Today's videos are waiting", message: problem.message, action: nil)
            } else {
                GettingVideos()
            }
        } else if store.engine.isStarved, store.followsLoading > 0 {
            // Back from following someone: their latest video is still being looked up (D218).
            GettingVideos()
        } else if store.isWaitingForLoad {
            // Their videos are here: rank first if wanted, then load, like the first Inbox (D218).
            LoadInboxMessage(load: { store.loadInbox() }, rankCreators: { tab = .following })
        } else if store.engine.isStarved {
            EmptyHomeMessage(
                title: "No new videos from your creators",
                message: "Follow more creators to get more videos.",
                action: ("Find creators", { findCreators() })
            )
        } else {
            DoneForToday(verse: store.verse, countdown: Format.countdown(timeToNextShipment))
        }
    }

    // MARK: - Refresh alerts (refresh-and-verses spec)

    private var alertShown: Binding<Bool> {
        Binding(get: { refreshAlert != nil }, set: { if !$0 { refreshAlert = nil } })
    }

    private var alertTitle: String {
        switch refreshAlert {
        case .allowed: "Swap today's videos?"
        case .noneLeft: "No refreshes left today"
        case .alreadyStarted: "Already started"
        case .notEnoughVideos: "Not enough new videos"
        case .nothingToSwap, nil: ""
        }
    }

    private func alertMessage(_ check: RefreshCheck) -> String {
        switch check {
        case .allowed(let remaining):
            "You have \(remaining) of \(store.engine.settings.refreshesPerDay) refreshes left today. These videos won't come back."
        case .noneLeft: "More when new videos arrive."
        case .alreadyStarted: "You've already started today's videos, so it can't be swapped."
        case .notEnoughVideos: "Not enough new videos to swap in. Follow more creators to get more."
        case .nothingToSwap: ""
        }
    }

    @ViewBuilder
    private func alertButtons(_ check: RefreshCheck) -> some View {
        switch check {
        case .allowed:
            Button("Swap", role: .destructive) { store.refresh() }
            Button("Cancel", role: .cancel) {}
        case .notEnoughVideos:
            Button("Find creators") { findCreators() }
            Button("OK", role: .cancel) {}
        default:
            Button("OK", role: .cancel) {}
        }
    }
}

extension AppStore.UploadProblem {
    /// The Inbox status line (D110).
    var message: String {
        switch self {
        case .offline: "Offline. Will check for new videos when you're back."
        case .unreachable: "Couldn't reach YouTube. Will try again shortly."
        case .dailyLimit: "YouTube's daily limit is reached. New videos tomorrow."
        }
    }
}

/// One Inbox card. Equatable on what it shows, so a change elsewhere (a view count arriving,
/// the minute ticking over) doesn't redraw every card while scrolling.
private struct InboxRow: View, Equatable {
    enum Action { case play, moveUp, moveDown, swap, remove }

    let entry: HomeEntry
    let creator: String
    let avatarURL: URL?
    let views: Int?
    let canMoveUp: Bool
    let canMoveDown: Bool
    /// Not compared: it acts by video ID, so an older copy still does the right thing.
    let perform: (Action, String) -> Void

    nonisolated static func == (a: Self, b: Self) -> Bool {
        a.entry == b.entry && a.creator == b.creator && a.avatarURL == b.avatarURL && a.views == b.views
            && a.canMoveUp == b.canMoveUp && a.canMoveDown == b.canMoveDown
    }

    var body: some View {
        let id = entry.id
        Button { perform(.play, id) } label: {
            VideoCard(
                entry: entry,
                creator: creator,
                avatarURL: avatarURL,
                views: views,
                trailing: .menu(
                    moveUp: canMoveUp ? { perform(.moveUp, id) } : nil,
                    moveDown: canMoveDown ? { perform(.moveDown, id) } : nil,
                    swap: { perform(.swap, id) },
                    remove: { perform(.remove, id) }
                )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Swap one video (D98)

private struct SwapRequest: Hashable {
    let videoID: String
    let check: RefreshCheck
}

extension HomeView {
    private var swapShown: Binding<Bool> {
        Binding(get: { swapAlert != nil }, set: { if !$0 { swapAlert = nil } })
    }

    private var swapTitle: String {
        switch swapAlert?.check {
        case .allowed: "Swap this video?"
        case .noneLeft: "No refreshes left today"
        case .notEnoughVideos: "No new video to swap in"
        case .alreadyStarted, .nothingToSwap, nil: ""
        }
    }

    private func swapMessage(_ check: RefreshCheck) -> String {
        switch check {
        case .allowed(let remaining):
            "Uses 1 refresh. You have \(remaining) of \(store.engine.settings.refreshesPerDay) left today. This video won't come back."
        case .noneLeft: "More when new videos arrive."
        case .notEnoughVideos: "Follow more creators to get more videos."
        case .alreadyStarted, .nothingToSwap: ""
        }
    }

    @ViewBuilder
    private func swapButtons(_ request: SwapRequest) -> some View {
        switch request.check {
        case .allowed:
            Button("Swap", role: .destructive) { store.swapVideo(request.videoID) }
            Button("Cancel", role: .cancel) {}
        case .notEnoughVideos:
            Button("Find creators") { findCreators() }
            Button("OK", role: .cancel) {}
        default:
            Button("OK", role: .cancel) {}
        }
    }
}

/// Empty state A: the day's shipment is watched. A verse about work and rest, then the countdown.
private struct DoneForToday: View {
    let verse: Verse?
    let countdown: String

    var body: some View {
        // Scrolls only if a long verse at a large text size doesn't fit.
        ScrollView {
            content.containerRelativeFrame(.vertical) { height, _ in height }
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private var content: some View {
        VStack(spacing: 28) {
            Spacer()
            if let verse {
                VStack(spacing: 16) {
                    Text(verse.text)
                        .font(.system(.title3, design: .serif))
                        .lineSpacing(4)
                    Text("— \(verse.reference) (ESV)")
                        .font(.system(.subheadline, design: .serif))
                        .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)
            } else {
                Text("That's it for today")
                    .font(.title2.weight(.semibold))
            }
            Spacer()
            Text("New videos in \(countdown)")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.bottom, 24)
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Bottom of the Inbox when today's shipment couldn't fill the budget (D97).
private struct ShortInboxNote: View {
    let budgetMinutes: Int
    let findCreators: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("That's all for today")
                .font(.headline)
            Text("Your creators didn't post enough to fill your \(budgetMinutes) minutes. Follow a few more to get more videos.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("Find creators", action: findCreators)
                .buttonStyle(.glassProminent)
                .tint(.blue)
                .padding(.top, 4)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .padding(.horizontal, 16)
        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 16))
    }
}

/// Under today's cards while a just-followed creator's video is being looked up, so the wait
/// doesn't look like nothing happened.
private struct LoadingNewVideos: View {
    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text("Loading new videos…").foregroundStyle(.secondary)
        }
        .font(.subheadline)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 16))
    }
}

/// The Inbox is empty but videos are on their way: a due shipment, or a creator just followed.
private struct GettingVideos: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Getting today's videos…").foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The "No new videos" Inbox after following someone from it: load when ready (D218).
private struct LoadInboxMessage: View {
    let load: () -> Void
    let rankCreators: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Almost ready")
                .font(.title2.weight(.semibold))
            Text("Rank your creators, then load your Inbox.")
                .foregroundStyle(.secondary)
            VStack(spacing: 14) {
                Button(action: load) {
                    Text("Load my Inbox").padding(.horizontal, 8).padding(.vertical, 4)
                }
                .buttonStyle(.glassProminent)
                Button("Rank creators", action: rankCreators)
            }
            .padding(.top, 8)
        }
        .multilineTextAlignment(.center)
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct EmptyHomeMessage: View {
    let title: String
    let message: String
    let action: (String, () -> Void)?

    var body: some View {
        VStack(spacing: 16) {
            Text(title)
                .font(.title2.weight(.semibold))
            Text(message)
                .foregroundStyle(.secondary)
            if let action {
                Button(action.0, action: action.1)
                    .buttonStyle(.glassProminent)
                    .padding(.top, 8)
            }
        }
        .multilineTextAlignment(.center)
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
