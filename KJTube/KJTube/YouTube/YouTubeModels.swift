import Foundation

/// A channel as shown in Following search results.
struct ChannelSummary: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let handle: String?
    let avatarURL: URL?
    let subscriberCount: Int?
}

/// A recent upload from a channel's uploads playlist.
struct UploadRef: Hashable, Sendable {
    let videoID: String
    let publishedAt: Date
}

/// The facts about a video that decide eligibility (PLAN §3.2).
struct VideoDetails: Hashable, Sendable {
    let id: String
    let channelID: String
    let title: String
    let publishedAt: Date
    let duration: TimeInterval
    /// "none", "live" or "upcoming".
    let liveBroadcastContent: String
    /// Set for live streams and their replays.
    let wasLivestream: Bool
    let embeddable: Bool
    let isPublic: Bool

    var asVideo: Video {
        Video(id: id, creatorID: channelID, title: title, duration: duration, publishedAt: publishedAt)
    }
}

enum YouTubeError: Error, Equatable, Sendable {
    case offline
    case quotaExceeded
    case notFound
    case missingAPIKey
    case server(String)
}

// MARK: - API responses (only the fields we use)

struct APIList<Item: Decodable & Sendable>: Decodable, Sendable {
    let items: [Item]?
}

struct APIThumbnails: Decodable, Sendable {
    struct Thumbnail: Decodable, Sendable { let url: URL }
    let `default`: Thumbnail?
    let medium: Thumbnail?
    let high: Thumbnail?

    var best: URL? { (high ?? medium ?? `default`)?.url }
}

struct APIChannel: Decodable, Sendable {
    struct Snippet: Decodable, Sendable {
        let title: String
        let customUrl: String?
        let thumbnails: APIThumbnails?
    }
    struct Statistics: Decodable, Sendable {
        let subscriberCount: String?
        let hiddenSubscriberCount: Bool?
    }
    let id: String
    let snippet: Snippet?
    let statistics: Statistics?

    var summary: ChannelSummary {
        let hidden = statistics?.hiddenSubscriberCount ?? false
        return ChannelSummary(
            id: id,
            title: snippet?.title ?? id,
            handle: snippet?.customUrl.map { $0.hasPrefix("@") ? $0 : "@" + $0 },
            avatarURL: snippet?.thumbnails?.best,
            subscriberCount: hidden ? nil : statistics?.subscriberCount.flatMap(Int.init)
        )
    }
}

struct APISearchResult: Decodable, Sendable {
    struct ID: Decodable, Sendable { let channelId: String? }
    let id: ID
}

struct APIPlaylistItem: Decodable, Sendable {
    struct ContentDetails: Decodable, Sendable {
        let videoId: String
        let videoPublishedAt: Date?
    }
    let contentDetails: ContentDetails
}

struct APIVideo: Decodable, Sendable {
    struct Snippet: Decodable, Sendable {
        let title: String
        let channelId: String
        let publishedAt: Date
        let liveBroadcastContent: String?
    }
    struct ContentDetails: Decodable, Sendable { let duration: String }
    struct Status: Decodable, Sendable {
        let embeddable: Bool?
        let privacyStatus: String?
    }
    struct LiveStreamingDetails: Decodable, Sendable {}

    let id: String
    let snippet: Snippet
    let contentDetails: ContentDetails?
    let status: Status?
    let liveStreamingDetails: LiveStreamingDetails?

    var details: VideoDetails {
        VideoDetails(
            id: id,
            channelID: snippet.channelId,
            title: snippet.title,
            publishedAt: snippet.publishedAt,
            duration: contentDetails.map { ISO8601Duration.seconds($0.duration) } ?? 0,
            liveBroadcastContent: snippet.liveBroadcastContent ?? "none",
            wasLivestream: liveStreamingDetails != nil,
            embeddable: status?.embeddable ?? true,
            isPublic: (status?.privacyStatus ?? "public") == "public"
        )
    }
}

/// What the cards and player show beyond what decides eligibility. Fetched fresh; the last
/// answer is kept only so a relaunch shows it right away (AppStore).
struct VideoExtras: Hashable, Codable, Sendable {
    /// Nil when the creator hides it.
    let viewCount: Int?
    let description: String
}

struct APIVideoExtras: Decodable, Sendable {
    struct Snippet: Decodable, Sendable { let description: String? }
    struct Statistics: Decodable, Sendable { let viewCount: String? }
    let id: String
    let snippet: Snippet?
    let statistics: Statistics?

    var extras: VideoExtras {
        VideoExtras(viewCount: statistics?.viewCount.flatMap(Int.init), description: snippet?.description ?? "")
    }
}

struct APIErrorResponse: Decodable, Sendable {
    struct Body: Decodable, Sendable {
        struct Detail: Decodable, Sendable { let reason: String? }
        let code: Int
        let message: String?
        let errors: [Detail]?
    }
    let error: Body
}

extension JSONDecoder {
    static let youTube: JSONDecoder = {
        let decoder = JSONDecoder()
        // YouTube usually omits fractional seconds, but not always.
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            if let date = try? Date(text, strategy: .iso8601) { return date }
            if let date = try? Date(text, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Bad date \(text)"))
        }
        return decoder
    }()
}

/// Parses YouTube's ISO 8601 durations ("PT1H2M3S", "P1DT2H", "P0D").
enum ISO8601Duration {
    static func seconds(_ text: String) -> TimeInterval {
        var total: TimeInterval = 0
        var number = ""
        for char in text {
            if char.isNumber || char == "." {
                number.append(char)
                continue
            }
            let value = Double(number) ?? 0
            number = ""
            switch char {
            case "D": total += value * 86_400
            case "H": total += value * 3_600
            case "M": total += value * 60
            case "S": total += value
            default: break // "P", "T"
            }
        }
        return total
    }
}
