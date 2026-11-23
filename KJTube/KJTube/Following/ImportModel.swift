import Foundation
import Observation

/// The pick list for importing YouTube subscriptions (docs/specs/import-subscriptions.md).
/// Nothing is ticked to start (D153); the order of ticking becomes the rank order.
@MainActor
@Observable
final class ImportModel: Identifiable {
    enum Phase: Equatable {
        case loading
        case loaded
        case failed(YouTubeError)
    }

    private(set) var phase: Phase = .loading
    /// Every subscription, A to Z.
    private(set) var channels: [ChannelSummary] = []
    /// Ticked channel IDs, in the order they were ticked.
    private(set) var picked: [String] = []
    var filter = ""

    @ObservationIgnored private let loader: SubscriptionsLoader

    init(loader: SubscriptionsLoader) {
        self.loader = loader
    }

    func load() async {
        phase = .loading
        do {
            channels = try await loader.all()
            phase = .loaded
        } catch let error as YouTubeError {
            phase = .failed(error)
        } catch {
            phase = .failed(.server(error.localizedDescription))
        }
    }

    /// The list as shown: narrowed by the search box. Ticks are kept while filtering.
    var visible: [ChannelSummary] {
        let text = filter.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return channels }
        return channels.filter { $0.title.localizedCaseInsensitiveContains(text) }
    }

    func isPicked(_ channel: ChannelSummary) -> Bool {
        picked.contains(channel.id)
    }

    func toggle(_ channel: ChannelSummary) {
        if let index = picked.firstIndex(of: channel.id) {
            picked.remove(at: index)
        } else {
            picked.append(channel.id)
        }
    }

    /// Ticks every channel in the list as shown (so a search narrows it), A to Z, after any
    /// ticks already made. Creators already followed are left out (D156).
    func selectAllVisible(alreadyFollowing: Set<String> = []) {
        let already = Set(picked)
        picked += visible.map(\.id).filter { !already.contains($0) && !alreadyFollowing.contains($0) }
    }

    func deselectAllVisible() {
        let shown = Set(visible.map(\.id))
        picked.removeAll { shown.contains($0) }
    }

    /// True when Select all has nothing left to tick, so the button offers Deselect all.
    func allVisiblePicked(alreadyFollowing: Set<String> = []) -> Bool {
        let already = Set(picked)
        let pickable = visible.filter { !alreadyFollowing.contains($0.id) }
        return !pickable.isEmpty && pickable.allSatisfy { already.contains($0.id) }
    }

    /// The ticked channels in tick order, leaving out any already followed (AC5, AC7).
    func pickedChannels(alreadyFollowing: Set<String> = []) -> [ChannelSummary] {
        let byID = Dictionary(channels.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return picked.filter { !alreadyFollowing.contains($0) }.compactMap { byID[$0] }
    }
}
