import SwiftData
import SwiftUI

/// The Following tab: choose which creators shipments come from, and in what order
/// (docs/specs/following.md).
struct FollowingView: View {
    @Environment(AppStore.self) private var store
    @Query(sort: \Creator.rank) private var creators: [Creator]
    @Binding var tab: AppTab
    @State private var showsInfo = false
    /// The middle of the list on screen, for telling when a row is swiped aside (D172).
    @State private var listMidX: CGFloat = 0
    /// The creator whose row was just dropped after a drag. iOS keeps a dropped row round for
    /// about a second and then lets go all at once; the row stays round through that and then
    /// eases back to straight, so the corners don't snap (D173).
    @State private var settlingID: String?
    /// The creator let go above the list, until its card has landed in first place (D221).
    @State private var landingID: String?
    /// The creator whose icons were tapped, for a reminder of what they mean (D174).
    @State private var reminding: Creator?
    /// A switch waiting on its one-time explainer (D173).
    @State private var explaining: PendingSwitch?

    struct PendingSwitch {
        let kind: CreatorSwitch
        let creator: Creator
    }

    @State private var query = ""
    @State private var search: SearchState = .idle
    @State private var searchTask: Task<Void, Never>?
    @FocusState private var searchFocused: Bool
    /// The search bar is in use (typing or showing results), so the page title is out of the way.
    @State private var searchActive = false

    enum SearchState: Equatable {
        case idle
        case searching
        case results([ChannelSummary])
        case failed(YouTubeError)
    }

    var body: some View {
        NavigationStack {
            List {
                switch search {
                case .idle:
                    followedSection
                case .searching:
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                case .results(let channels):
                    resultsSection(channels)
                case .failed(let error):
                    errorSection(error)
                    followedSection
                }
            }
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).midX } action: { listMidX = $0 }
            .listSectionSpacing(.compact)
            // Scrolls sooner while dragging a channel toward the top or bottom (D84). Let go above
            // the list, over the title or search bar, a creator lands in first place (D221).
            .dragAutoScroll(onDropAboveList: { from in
                guard store.creatorOrder == .ranked, creators.indices.contains(from), from != 0 else { return }
                // Its row stays out of sight while the others slide down and the card glides into
                // first place, like any other drop. Shown, it slid up the list as a second card.
                let id = creators[from].channelID
                landingID = id
                withAnimation(.snappy) { store.moveCreators(fromOffsets: [from], toOffset: 0) }
                Task { // in case iOS never reports the landing
                    try? await Task.sleep(for: .milliseconds(900))
                    if landingID == id { landingID = nil }
                }
            }, onDropLanded: { landingID = nil })
            .contentMargins(.top, 8, for: .scrollContent) // the list starts right under the search bar
            .pageTitle("Following", hidden: searchActive)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Following info", systemImage: "info.circle") { showsInfo = true }
                }
            }
            .sheet(isPresented: $showsInfo) {
                FollowingInfoView() // full height, like the Inbox one
            }
            .searchable(text: $query, isPresented: $searchActive, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search YouTube to add a creator") // it adds; it doesn't search this list (D196)
            .searchFocused($searchFocused)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .onSubmit(of: .search) { runSearch() }
            .onChange(of: query) { _, newValue in
                if newValue.isEmpty {
                    searchTask?.cancel()
                    search = .idle
                } else if ChannelQuery.looksLikeLink(newValue), let parsed = ChannelQuery.parse(newValue),
                          parsed.isDirectLookup {
                    runSearch(debounce: true) // Complete links resolve without waiting for Return (D27).
                }
            }
            .undoToast(
                id: store.lastUnfollow?.channel.id,
                message: "Unfollowed \(store.lastUnfollow?.channel.title ?? "")",
                onUndo: { store.undoUnfollow() },
                onExpire: { store.clearUndo() }
            )
            .noticeToast(
                store.isFirstRun ? nil : store.importedCount.map { AppStore.importMessage(count: $0, ranked: store.creatorOrder == .ranked) },
                onExpire: { store.importedCount = nil }
            )
            // First run: how to rank, and the button that loads the first Inbox (D175).
            .safeAreaInset(edge: .bottom) {
                if store.isFirstRun, !creators.isEmpty, !searchActive {
                    FirstRunBar(ranked: store.creatorOrder == .ranked) { store.askToLoadInbox() }
                } else if store.isWaitingForLoad, !searchActive {
                    // Followed from the "No new videos" Inbox: load it from here too (D218).
                    FirstRunBar(ranked: store.creatorOrder == .ranked, offersImport: false) {
                        store.loadInbox()
                        tab = .home
                    }
                }
            }
            .sensoryFeedback(.success, trigger: creators.count) { old, new in new > old }
            .sensoryFeedback(.impact(weight: .light), trigger: store.engine.state.inOrderCreators)
            .sensoryFeedback(.impact(weight: .light), trigger: store.engine.state.anyLengthCreators)
            .alert(explaining?.kind.title ?? "", isPresented: Binding(get: { explaining != nil }, set: { if !$0 { explaining = nil } }),
                   presenting: explaining) { pending in
                Button("Continue") {
                    UserDefaults.standard.set(true, forKey: pending.kind.explainedKey) // never asked again
                    set(pending.kind, on: true, for: pending.creator)
                }
                Button("Cancel", role: .cancel) {}
            } message: { pending in
                Text(pending.kind.explainer)
            }
            .alert(reminding?.title ?? "", isPresented: Binding(get: { reminding != nil }, set: { if !$0 { reminding = nil } }),
                   presenting: reminding) { _ in
                Button("OK", role: .cancel) {}
            } message: { creator in
                Text(CreatorSwitch.allCases.filter { isOn($0, for: creator) }.map(\.reminder).joined(separator: "\n\n"))
            }
            .onAppear { focusSearchIfAsked() }
            .onChange(of: store.searchRequested) { focusSearchIfAsked() }
        }
    }

    /// Arriving from a "Find creators" button: the keyboard comes up in the search bar (D137).
    /// Asked for at once, so the keyboard rises while the page slides in. If the search bar wasn't
    /// ready yet (first visit to the tab), it's asked again once the slide is done.
    private func focusSearchIfAsked() {
        guard store.searchRequested else { return }
        store.searchRequested = false
        Task {
            await Task.yield()
            searchFocused = true
            try? await Task.sleep(for: .milliseconds(350))
            if !searchFocused { searchFocused = true }
        }
    }

    // MARK: - Per-creator switches

    private func isOn(_ kind: CreatorSwitch, for creator: Creator) -> Bool {
        switch kind {
        case .inOrder: store.isInOrder(creator)
        case .anyLength: store.isAnyLength(creator)
        }
    }

    private func set(_ kind: CreatorSwitch, on: Bool, for creator: Creator) {
        switch kind {
        case .inOrder: store.setInOrder(on, for: creator)
        case .anyLength: store.setAnyLength(on, for: creator)
        }
    }

    /// Flips a switch from the swipe button or the Hold menu. The first time one is ever turned
    /// on, a short note says what it does and who it is for; Continue turns it on (D173).
    private func toggle(_ kind: CreatorSwitch, for creator: Creator) {
        let on = isOn(kind, for: creator)
        if !on, !UserDefaults.standard.bool(forKey: kind.explainedKey) {
            explaining = PendingSwitch(kind: kind, creator: creator)
        } else {
            set(kind, on: !on, for: creator)
        }
    }

    // MARK: - Followed list

    /// Ranked or Random is chosen in Settings (D74); Ranked shows numbers and can be dragged.
    private var followedSection: some View {
        let ranked = store.creatorOrder == .ranked
        return Section {
            if creators.isEmpty {
                Text("Follow creators you trust. Their new videos arrive each day.")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
                // Bring over creators from YouTube instead of searching one by one (D155).
                ImportButton { Label("Import from YouTube", systemImage: "square.and.arrow.down") }
            }
            ForEach(Array(creators.enumerated()), id: \.element.channelID) { index, creator in
                let inOrder = store.isInOrder(creator)
                let anyLength = store.isAnyLength(creator)
                let isEdge = index == 0 || index == creators.count - 1
                FollowedRow(creator: creator, rank: ranked ? index + 1 : nil, inOrder: inOrder, anyLength: anyLength,
                            showsDivider: index < creators.count - 1, listMidX: listMidX,
                            onTagsTap: { reminding = creator },
                            settlingRadius: settlingID == creator.channelID ? (isEdge ? 26 : FollowedRow.liftedRadius) : nil)
                    .opacity(landingID == creator.channelID ? 0 : 1)
                    // Held or dragged, the row lifts with round corners and goes back to straight when
                    // let go (D172). The first and last rows keep the card's own rounder corners.
                    .contentShape([.contextMenuPreview, .dragPreview], .rect(cornerRadius: isEdge ? 26 : FollowedRow.liftedRadius))
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    // The row paints its own background (D159). iOS's is cleared, so the row's round
                    // corners show while it is swiped aside.
                    .listRowBackground(Color.clear)
                    // A small button, not a full swipe: tapping it is the unfollow (D81). No destructive role,
                    // so iOS doesn't stretch and collapse the row before we remove it.
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button("Unfollow") { // text only: an icon makes iOS draw a small circle
                            withAnimation { store.unfollow(creator) } // rows below slide up instead of jumping
                        }
                        .tint(.red)
                    }
                    // Swipe right for the two per-creator switches (D172). A check marks one that is on.
                    // The icon sits inside the words: a real icon makes iOS draw a small circle.
                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                        ForEach(CreatorSwitch.allCases) { kind in
                            Button {
                                toggle(kind, for: creator)
                            } label: {
                                Label(kind.shortTitle + (isOn(kind, for: creator) ? " ✓" : ""), systemImage: kind.icon)
                            }
                            .tint(kind.tint)
                        }
                    }
                    // Hold for a menu; hold and drag still reorders (D82).
                    .contextMenu {
                        if ranked, creators.count > 1 {
                            Button("Move to Top", systemImage: "arrow.up.to.line") {
                                withAnimation { store.moveCreators(fromOffsets: [index], toOffset: 0) }
                            }
                            .disabled(index == 0)
                            Button("Move to Bottom", systemImage: "arrow.down.to.line") {
                                withAnimation { store.moveCreators(fromOffsets: [index], toOffset: creators.count) }
                            }
                            .disabled(index == creators.count - 1)
                        }
                        // Series creators: waiting videos come oldest first (D150).
                        Button("Watch in Order", systemImage: inOrder ? "checkmark" : "list.number") {
                            toggle(.inOrder, for: creator)
                        }
                        // Long-video creators: never too long for the day (D151).
                        Button("Any Length", systemImage: anyLength ? "checkmark" : "hourglass.badge.plus") {
                            toggle(.anyLength, for: creator)
                        }
                        Button("Unfollow", systemImage: "person.badge.minus", role: .destructive) {
                            withAnimation { store.unfollow(creator) }
                        }
                    }
            }
            .onMove { source, destination in
                let id = source.first.map { creators[$0].channelID }
                settlingID = id
                Task {
                    try? await Task.sleep(for: .milliseconds(1300)) // iOS has let go by then
                    if settlingID == id { settlingID = nil }
                }
                store.moveCreators(fromOffsets: source, toOffset: destination)
            }
        } footer: {
            if ranked, creators.count > 1 {
                Text("Top creators are served first. Hold and drag to reorder.")
            }
        }
    }

    /// A followed row, edge to edge in its cell, painting its own background and divider (D159).
    /// iOS's divider came back half a second after a drag, and its gray press highlight flashed on
    /// a long hold and lingered after the menu closed. Being solid, the row hides that highlight,
    /// and the divider moves with the row and is never missing after a drag.
    private struct FollowedRow: View {
        let creator: Creator
        let rank: Int?
        let inOrder: Bool
        let anyLength: Bool
        let showsDivider: Bool

        /// Corner radius while the row is swiped aside, held or dragged (D172).
        static let liftedRadius: CGFloat = 16

        /// The middle of the list on screen. Compared with the row's own middle, so a tab slide
        /// (which moves both) doesn't count as a swipe.
        let listMidX: CGFloat

        let onTagsTap: () -> Void
        /// Set while the row has just been dropped after a drag: the corner radius to keep.
        let settlingRadius: CGFloat?

        @State private var midX: CGFloat?

        /// The row is slid sideways by a swipe, so its corners round to match the swipe buttons.
        private var swiped: Bool {
            guard let midX else { return false }
            return abs(midX - listMidX) > 0.5
        }

        /// The card color, held at its normal shade. iOS shows a held row as "raised", which
        /// turns the usual color light gray while the menu is up and for a moment after.
        static let cardColor = UIColor { traits in
            UIColor.secondarySystemGroupedBackground
                .resolvedColor(with: traits.modifyingTraits { $0.userInterfaceLevel = .base })
        }

        var body: some View {
            CreatorRow(creator: creator, rank: rank, inOrder: inOrder, anyLength: anyLength, onTagsTap: onTagsTap)
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, minHeight: 78, alignment: .leading)
                .background {
                    Color(Self.cardColor)
                        .overlay(alignment: .bottom) {
                            if showsDivider, !swiped, settlingRadius == nil {
                                Divider().padding(.horizontal, 16)
                            }
                        }
                        .clipShape(.rect(cornerRadius: settlingRadius ?? (swiped ? Self.liftedRadius : 0)))
                        .animation(.easeOut(duration: 0.15), value: swiped)
                        .animation(.easeOut(duration: 0.3), value: settlingRadius)
                }
                // A swipe slides the whole row left or right; at rest it sits in the middle of the list.
                .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).midX } action: { midX = $0 }
        }
    }

    // MARK: - Search

    private func resultsSection(_ channels: [ChannelSummary]) -> some View {
        Section {
            if channels.isEmpty {
                Text("No channels found.")
                    .foregroundStyle(.secondary)
            }
            ForEach(channels) { channel in
                ChannelResultRow(channel: channel, isFollowing: creators.contains { $0.channelID == channel.id }) {
                    Task { await store.follow(channel) }
                }
            }
        }
    }

    private func errorSection(_ error: YouTubeError) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text(message(for: error))
                    .foregroundStyle(.secondary)
                if error != .quotaExceeded {
                    Button("Retry", action: runSearch)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func message(for error: YouTubeError) -> String {
        switch error {
        case .offline: "You're offline. Search needs the internet."
        case .quotaExceeded: "YouTube search is resting until tomorrow."
        case .notFound: "Couldn't find that channel."
        case .missingAPIKey: "No YouTube API key. Add it to Secrets.xcconfig."
        case .server: "YouTube didn't answer. Try again."
        }
    }

    private func runSearch() {
        runSearch(debounce: false)
    }

    /// `debounce` waits briefly so typing a link character by character doesn't fire a lookup per key.
    private func runSearch(debounce: Bool) {
        guard let channelQuery = ChannelQuery.parse(query) else { return }
        searchTask?.cancel() // Only the latest search may update the screen.
        search = .searching
        searchTask = Task {
            if debounce {
                try? await Task.sleep(for: .milliseconds(400))
                if Task.isCancelled { return }
            }
            let result: SearchState
            do {
                result = .results(try await store.api.lookUp(channelQuery))
            } catch let error as YouTubeError {
                result = .failed(error)
            } catch {
                result = .failed(.server(error.localizedDescription))
            }
            if !Task.isCancelled { search = result }
        }
    }
}
