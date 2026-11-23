import Foundation

/// Everything the app asks of YouTube. The live client talks to the Data API v3;
/// tests use a fake.
protocol YouTubeAPI: Sendable {
    func searchChannels(_ text: String) async throws -> [ChannelSummary]
    func channels(ids: [String]) async throws -> [ChannelSummary]
    func channel(handle: String) async throws -> ChannelSummary
    func channelID(ofVideo videoID: String) async throws -> String
    /// Newest first, at most `limit` (≤ 50).
    func recentUploads(channelID: String, limit: Int) async throws -> [UploadRef]
    func videoDetails(ids: [String]) async throws -> [VideoDetails]
    /// Current view count and description by video ID (at most 50 IDs).
    func videoExtras(ids: [String]) async throws -> [String: VideoExtras]
    /// True if `youtube.com/shorts/<id>` serves a Short (PLAN §3.2).
    func isShort(videoID: String) async throws -> Bool
}

extension YouTubeAPI {
    /// Resolves whatever was typed or pasted into the Following search field (D27).
    func lookUp(_ query: ChannelQuery) async throws -> [ChannelSummary] {
        switch query {
        case .search(let text):
            return try await searchChannels(text)
        case .handle(let handle):
            return [try await channel(handle: handle)]
        case .channelID(let id):
            return try await channels(ids: [id])
        case .videoID(let id):
            return try await channels(ids: [channelID(ofVideo: id)])
        }
    }
}

struct LiveYouTubeClient: YouTubeAPI {
    static let maxSearchResults = 10

    let apiKey: String
    var session: URLSession = .shared
    /// Simulator checks only: every Data API call fails this way.
    var failure: YouTubeError?

    func searchChannels(_ text: String) async throws -> [ChannelSummary] {
        let results: APIList<APISearchResult> = try await get("search", [
            "part": "snippet", "type": "channel", "q": text, "maxResults": "\(Self.maxSearchResults)",
        ])
        let ids = (results.items ?? []).compactMap(\.id.channelId)
        guard !ids.isEmpty else { return [] }
        // search.list has no subscriber counts or handles; fetch them, keeping search order.
        let byID = Dictionary(try await channels(ids: ids).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return ids.compactMap { byID[$0] }
    }

    func channels(ids: [String]) async throws -> [ChannelSummary] {
        let list: APIList<APIChannel> = try await get("channels", [
            "part": "snippet,statistics", "id": ids.joined(separator: ","),
        ])
        let channels = (list.items ?? []).map(\.summary)
        if channels.isEmpty { throw YouTubeError.notFound }
        return channels
    }

    func channel(handle: String) async throws -> ChannelSummary {
        let list: APIList<APIChannel> = try await get("channels", [
            "part": "snippet,statistics", "forHandle": "@" + handle,
        ])
        guard let channel = list.items?.first else { throw YouTubeError.notFound }
        return channel.summary
    }

    func channelID(ofVideo videoID: String) async throws -> String {
        guard let video = try await videoDetails(ids: [videoID]).first else { throw YouTubeError.notFound }
        return video.channelID
    }

    func recentUploads(channelID: String, limit: Int) async throws -> [UploadRef] {
        // A channel's uploads playlist is its ID with "UC" swapped for "UU".
        let playlistID = "UU" + channelID.dropFirst(2)
        let list: APIList<APIPlaylistItem> = try await get("playlistItems", [
            "part": "contentDetails", "playlistId": playlistID, "maxResults": "\(min(limit, 50))",
        ])
        return (list.items ?? [])
            .map { UploadRef(videoID: $0.contentDetails.videoId, publishedAt: $0.contentDetails.videoPublishedAt ?? .distantPast) }
            .sorted { $0.publishedAt > $1.publishedAt }
    }

    func videoDetails(ids: [String]) async throws -> [VideoDetails] {
        guard !ids.isEmpty else { return [] }
        let list: APIList<APIVideo> = try await get("videos", [
            "part": "snippet,contentDetails,status,liveStreamingDetails", "id": ids.prefix(50).joined(separator: ","),
        ])
        return (list.items ?? []).map(\.details)
    }

    func videoExtras(ids: [String]) async throws -> [String: VideoExtras] {
        guard !ids.isEmpty else { return [:] }
        let list: APIList<APIVideoExtras> = try await get("videos", [
            "part": "snippet,statistics", "id": ids.prefix(50).joined(separator: ","),
        ])
        return Dictionary((list.items ?? []).map { ($0.id, $0.extras) }, uniquingKeysWith: { a, _ in a })
    }

    func isShort(videoID: String) async throws -> Bool {
        var request = URLRequest(url: URL(string: "https://www.youtube.com/shorts/\(videoID)")!)
        request.httpMethod = "HEAD"
        do {
            let (_, response) = try await session.data(for: request)
            return Self.isShortsPage(response)
        } catch let error as URLError {
            throw Self.map(error)
        }
    }

    /// After redirects, a Short stays on a `/shorts/` page (www or m.youtube.com, depending on
    /// the user agent); a normal video ends up on `/watch`.
    static func isShortsPage(_ response: URLResponse) -> Bool {
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return false }
        return http.url?.path().hasPrefix("/shorts/") ?? false
    }

    // MARK: - Plumbing

    private func get<T: Decodable>(_ endpoint: String, _ params: [String: String]) async throws -> T {
        if let failure { throw failure }
        guard !apiKey.isEmpty else { throw YouTubeError.missingAPIKey }
        var components = URLComponents(string: "https://www.googleapis.com/youtube/v3/\(endpoint)")!
        components.queryItems = params.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
            + [URLQueryItem(name: "key", value: apiKey)]
        var request = URLRequest(url: components.url!)
        // Lets the key stay restricted to this app in Google Cloud.
        // "KJ Tube Dev" is the same app with ".dev" on the end, so it sends the real ID.
        if let bundleID = Bundle.main.bundleIdentifier {
            // "KJ Tube Public" does the same until it has its own key.
            let keyBundleID = [".dev", ".public"].first(where: bundleID.hasSuffix).map { String(bundleID.dropLast($0.count)) } ?? bundleID
            request.setValue(keyBundleID, forHTTPHeaderField: "X-Ios-Bundle-Identifier")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            throw Self.map(error)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let body = try? JSONDecoder.youTube.decode(APIErrorResponse.self, from: data)
            let reasons = body?.error.errors?.compactMap(\.reason) ?? []
            if reasons.contains(where: { $0 == "quotaExceeded" || $0 == "dailyLimitExceeded" }) {
                throw YouTubeError.quotaExceeded
            }
            if status == 404 { throw YouTubeError.notFound }
            throw YouTubeError.server(body?.error.message ?? "HTTP \(status)")
        }
        return try JSONDecoder.youTube.decode(T.self, from: data)
    }

    private static func map(_ error: URLError) -> YouTubeError {
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost, .cannotConnectToHost, .dataNotAllowed:
            return .offline
        default:
            return .server(error.localizedDescription)
        }
    }
}
