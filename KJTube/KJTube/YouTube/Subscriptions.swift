import Foundation

/// One page of the signed-in person's YouTube subscriptions.
struct SubscriptionPage: Sendable {
    let channels: [ChannelSummary]
    /// Nil on the last page.
    let nextPageToken: String?
}

/// Reads the whole subscription list, 50 at a time (import spec AC3).
struct SubscriptionsLoader: Sendable {
    /// A safety stop: 40 pages is 2,000 subscriptions.
    static let maxPages = 40

    /// Fetches the page for a token (nil = first page).
    let page: @Sendable (String?) async throws -> SubscriptionPage

    /// Every subscription, A to Z, each channel once.
    func all() async throws -> [ChannelSummary] {
        var channels: [ChannelSummary] = []
        var seen: Set<String> = []
        var token: String?
        for _ in 0..<Self.maxPages {
            let next = try await page(token)
            for channel in next.channels where seen.insert(channel.id).inserted {
                channels.append(channel)
            }
            guard let nextToken = next.nextPageToken, !nextToken.isEmpty else { break }
            token = nextToken
        }
        return channels.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }
}

extension SubscriptionsLoader {
    /// The live list from the Data API, as the person who just signed in.
    static func live(accessToken: String, session: URLSession = .shared) -> SubscriptionsLoader {
        SubscriptionsLoader { pageToken in
            var components = URLComponents(string: "https://www.googleapis.com/youtube/v3/subscriptions")!
            components.queryItems = [
                URLQueryItem(name: "part", value: "snippet"),
                URLQueryItem(name: "mine", value: "true"),
                URLQueryItem(name: "maxResults", value: "50"),
                URLQueryItem(name: "order", value: "alphabetical"),
            ] + (pageToken.map { [URLQueryItem(name: "pageToken", value: $0)] } ?? [])
            var request = URLRequest(url: components.url!)
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

            let data: Data
            let response: URLResponse
            do {
                (data, response) = try await session.data(for: request)
            } catch let error as URLError {
                switch error.code {
                case .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost, .cannotConnectToHost, .dataNotAllowed:
                    throw YouTubeError.offline
                default:
                    throw YouTubeError.server(error.localizedDescription)
                }
            }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(status) else {
                let body = try? JSONDecoder.youTube.decode(APIErrorResponse.self, from: data)
                let reasons = body?.error.errors?.compactMap(\.reason) ?? []
                if reasons.contains(where: { $0 == "quotaExceeded" || $0 == "dailyLimitExceeded" }) {
                    throw YouTubeError.quotaExceeded
                }
                throw YouTubeError.server(body?.error.message ?? "HTTP \(status)")
            }
            return try JSONDecoder.youTube.decode(APISubscriptionList.self, from: data).page
        }
    }
}

struct APISubscriptionList: Decodable, Sendable {
    struct Item: Decodable, Sendable {
        struct Snippet: Decodable, Sendable {
            struct Resource: Decodable, Sendable { let channelId: String? }
            let title: String?
            let resourceId: Resource?
            let thumbnails: APIThumbnails?
        }
        let snippet: Snippet?
    }
    let items: [Item]?
    let nextPageToken: String?

    var page: SubscriptionPage {
        SubscriptionPage(
            channels: (items ?? []).compactMap { item in
                guard let id = item.snippet?.resourceId?.channelId else { return nil }
                return ChannelSummary(id: id, title: item.snippet?.title ?? id, handle: nil,
                                      avatarURL: item.snippet?.thumbnails?.best, subscriberCount: nil)
            },
            nextPageToken: nextPageToken
        )
    }
}
