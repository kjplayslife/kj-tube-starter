import Foundation
import Testing
@testable import KJTube

struct ChannelQueryTests {
    @Test("Pasted links, @handles and channel IDs resolve directly (following AC2)", arguments: [
        ("@veritasium", ChannelQuery.handle("veritasium")),
        ("  @veritasium  ", .handle("veritasium")),
        ("https://www.youtube.com/@veritasium", .handle("veritasium")),
        ("youtube.com/@veritasium/videos", .handle("veritasium")),
        ("https://m.youtube.com/@veritasium?si=abc", .handle("veritasium")),
        ("https://www.youtube.com/channel/UCHnyfMqiRRG1u-2MsSQLbXA", .channelID("UCHnyfMqiRRG1u-2MsSQLbXA")),
        ("UCHnyfMqiRRG1u-2MsSQLbXA", .channelID("UCHnyfMqiRRG1u-2MsSQLbXA")),
        ("https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=42", .videoID("dQw4w9WgXcQ")),
        ("https://youtu.be/dQw4w9WgXcQ?si=xyz", .videoID("dQw4w9WgXcQ")),
        ("https://www.youtube.com/shorts/dQw4w9WgXcQ", .videoID("dQw4w9WgXcQ")),
        ("https://www.youtube.com/live/dQw4w9WgXcQ", .videoID("dQw4w9WgXcQ")),
        ("Veritasium", .search("Veritasium")),
        ("@a", .search("@a")),
    ])
    func parses(input: String, expected: ChannelQuery) {
        #expect(ChannelQuery.parse(input) == expected)
    }

    @Test("Blank input is not a query")
    func blank() {
        #expect(ChannelQuery.parse("   ") == nil)
    }

    @Test("Only URL-ish text auto-resolves while typing")
    func looksLikeLink() {
        #expect(ChannelQuery.looksLikeLink("youtu.be/abc"))
        #expect(!ChannelQuery.looksLikeLink("@veritasium"))
    }
}

struct YouTubeDecodingTests {
    @Test("ISO 8601 durations", arguments: [
        ("PT12M3S", 723.0), ("PT1H", 3_600.0), ("PT45S", 45.0), ("P1DT2H", 93_600.0), ("P0D", 0.0),
    ])
    func durations(text: String, seconds: Double) {
        #expect(ISO8601Duration.seconds(text) == seconds)
    }

    @Test("videos.list response maps to eligibility facts")
    func decodesVideo() throws {
        let json = """
        {"items":[{"id":"abc12345678",
          "snippet":{"title":"Hi","channelId":"UC1","publishedAt":"2026-10-20T15:00:00Z","liveBroadcastContent":"none"},
          "contentDetails":{"duration":"PT10M"},
          "status":{"embeddable":false,"privacyStatus":"public"},
          "liveStreamingDetails":{"actualStartTime":"2026-10-20T14:00:00.000Z"}}]}
        """
        let list = try JSONDecoder.youTube.decode(APIList<APIVideo>.self, from: Data(json.utf8))
        let video = try #require(list.items?.first?.details)
        #expect(video.duration == 600)
        #expect(video.wasLivestream)
        #expect(!video.embeddable)
        #expect(video.channelID == "UC1")
    }

    @Test("channels.list response maps to a summary with @handle and subscribers")
    func decodesChannel() throws {
        let json = """
        {"items":[{"id":"UC1","snippet":{"title":"Veritasium","customUrl":"@veritasium",
          "thumbnails":{"default":{"url":"https://example.com/a.jpg"}}},
          "statistics":{"subscriberCount":"17900000","hiddenSubscriberCount":false}}]}
        """
        let list = try JSONDecoder.youTube.decode(APIList<APIChannel>.self, from: Data(json.utf8))
        let channel = try #require(list.items?.first?.summary)
        #expect(channel.handle == "@veritasium")
        #expect(channel.subscriberCount == 17_900_000)
        #expect(channel.avatarURL?.absoluteString == "https://example.com/a.jpg")
    }
}

struct UploadsLoaderTests {
    @Test("Following AC3: picks the newest 3 eligible, skipping Shorts, live, replays, unembeddable and private")
    func newestThreeEligible() async throws {
        let ch = "UCaaaaaaaaaaaaaaaaaaaaaa"
        var api = FakeYouTubeAPI()
        api.uploads[ch] = [
            details("short", minutes: 0.5, daysAgo: 1),
            details("live", daysAgo: 2, live: "live"),
            details("premiere", daysAgo: 3, live: "upcoming"),
            details("replay", daysAgo: 4, wasLivestream: true),
            details("locked", daysAgo: 5, embeddable: false),
            details("private", daysAgo: 6, isPublic: false),
            details("ok1", daysAgo: 7),
            details("shortish", minutes: 2, daysAgo: 8), // ≤ 3 min but not a Short
            details("ok3", daysAgo: 9),
            details("ok4", daysAgo: 10),
        ]
        api.shorts = ["short"]
        let result = try await UploadsLoader(api: api).latestEligible(channelID: ch, count: 3)
        #expect(result.videos.map(\.id) == ["ok1", "shortish", "ok3"])
        #expect(result.newestUploadAt == details("short", daysAgo: 1).publishedAt)
        // D230: "Last upload" skips the Short, the live ones and the private one. A video that
        // can't be played in the app is still a long-form upload.
        #expect(result.lastLongFormAt == details("locked", daysAgo: 5).publishedAt)
    }

    @Test("A creator with nothing eligible returns no videos")
    func nothingEligible() async throws {
        let ch = "UCaaaaaaaaaaaaaaaaaaaaaa"
        var api = FakeYouTubeAPI()
        api.uploads[ch] = [details("live", live: "live")]
        let result = try await UploadsLoader(api: api).latestEligible(channelID: ch, count: 3)
        #expect(result.videos.isEmpty)
    }
}

struct ShortsCheckTests {
    func response(_ url: String, status: Int = 200) -> HTTPURLResponse {
        HTTPURLResponse(url: URL(string: url)!, statusCode: status, httpVersion: nil, headerFields: nil)!
    }

    @Test("A Short stays on /shorts/ after redirects, on desktop or mobile hosts")
    func shortsDetected() {
        #expect(LiveYouTubeClient.isShortsPage(response("https://www.youtube.com/shorts/Kap7mRzr13w")))
        #expect(LiveYouTubeClient.isShortsPage(response("https://m.youtube.com/shorts/Kap7mRzr13w")))
    }

    @Test("A normal video redirects to /watch; errors are not Shorts")
    func normalVideos() {
        #expect(!LiveYouTubeClient.isShortsPage(response("https://m.youtube.com/watch?v=eyZEqSPeMwg")))
        #expect(!LiveYouTubeClient.isShortsPage(response("https://www.youtube.com/shorts/x", status: 404)))
    }
}
