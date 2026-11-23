import Foundation
@testable import KJTube

/// In-memory YouTube for tests: no network.
struct FakeYouTubeAPI: YouTubeAPI {
    var channelsByID: [String: ChannelSummary] = [:]
    var uploads: [String: [VideoDetails]] = [:]
    var shorts: Set<String> = []
    var extras: [String: VideoExtras] = [:]
    var failWith: YouTubeError?

    func searchChannels(_ text: String) async throws -> [ChannelSummary] {
        if let failWith { throw failWith }
        return channelsByID.values.filter { $0.title.localizedCaseInsensitiveContains(text) }.sorted { $0.id < $1.id }
    }

    func channels(ids: [String]) async throws -> [ChannelSummary] {
        if let failWith { throw failWith }
        let found = ids.compactMap { channelsByID[$0] }
        if found.isEmpty { throw YouTubeError.notFound }
        return found
    }

    func channel(handle: String) async throws -> ChannelSummary {
        if let failWith { throw failWith }
        guard let channel = channelsByID.values.first(where: { $0.handle?.lowercased() == "@" + handle.lowercased() }) else {
            throw YouTubeError.notFound
        }
        return channel
    }

    func channelID(ofVideo videoID: String) async throws -> String {
        if let failWith { throw failWith }
        guard let video = uploads.values.joined().first(where: { $0.id == videoID }) else { throw YouTubeError.notFound }
        return video.channelID
    }

    func recentUploads(channelID: String, limit: Int) async throws -> [UploadRef] {
        if let failWith { throw failWith }
        return (uploads[channelID] ?? [])
            .sorted { $0.publishedAt > $1.publishedAt }
            .prefix(limit)
            .map { UploadRef(videoID: $0.id, publishedAt: $0.publishedAt) }
    }

    func videoDetails(ids: [String]) async throws -> [VideoDetails] {
        if let failWith { throw failWith }
        let all = Dictionary(uploads.values.joined().map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return ids.compactMap { all[$0] }
    }

    func videoExtras(ids: [String]) async throws -> [String: VideoExtras] {
        if let failWith { throw failWith }
        return extras.filter { ids.contains($0.key) }
    }

    func isShort(videoID: String) async throws -> Bool {
        shorts.contains(videoID)
    }
}

func details(
    _ id: String,
    channel: String = "UCaaaaaaaaaaaaaaaaaaaaaa",
    minutes: Double = 10,
    daysAgo: Int = 1,
    live: String = "none",
    wasLivestream: Bool = false,
    embeddable: Bool = true,
    isPublic: Bool = true
) -> VideoDetails {
    VideoDetails(
        id: id, channelID: channel, title: id,
        publishedAt: Date(timeIntervalSince1970: 1_800_000_000 - Double(daysAgo) * 86_400),
        duration: minutes * 60, liveBroadcastContent: live, wasLivestream: wasLivestream,
        embeddable: embeddable, isPublic: isPublic
    )
}

func channel(_ id: String, _ title: String, handle: String? = nil) -> ChannelSummary {
    ChannelSummary(id: id, title: title, handle: handle, avatarURL: nil, subscriberCount: 1_000)
}
