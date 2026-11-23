import Foundation
import SwiftData
import Testing
@testable import KJTube

/// docs/specs/import-subscriptions.md
@MainActor
struct ImportSubscriptionsTests {
    let container = try! ModelContainer(
        for: Creator.self, EngineRecord.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )

    func channel(_ id: String, _ title: String) -> ChannelSummary {
        ChannelSummary(id: id, title: title, handle: nil, avatarURL: nil, subscriberCount: nil)
    }

    func details(_ id: String, channel: String, daysAgo: Double) -> VideoDetails {
        VideoDetails(id: id, channelID: channel, title: id, publishedAt: Date(timeIntervalSinceNow: -daysAgo * 86_400),
                     duration: 600, liveBroadcastContent: "none", wasLivestream: false, embeddable: true, isPublic: true)
    }

    func loader(_ pages: [String?: SubscriptionPage]) -> SubscriptionsLoader {
        SubscriptionsLoader { token in
            guard let page = pages[token] else { throw YouTubeError.server("no page") }
            return page
        }
    }

    // MARK: - Reading the list

    @Test("subscriptions.list response maps to channels and the next page")
    func decodesPage() throws {
        let json = """
        {"nextPageToken": "P2", "items": [
          {"snippet": {"title": "Veritasium", "resourceId": {"kind": "youtube#channel", "channelId": "UC1"},
                       "thumbnails": {"default": {"url": "https://img.example/v.jpg"}}}},
          {"snippet": {"title": "No channel"}}
        ]}
        """
        let page = try JSONDecoder.youTube.decode(APISubscriptionList.self, from: Data(json.utf8)).page
        #expect(page.nextPageToken == "P2")
        #expect(page.channels == [ChannelSummary(id: "UC1", title: "Veritasium", handle: nil,
                                                 avatarURL: URL(string: "https://img.example/v.jpg"), subscriberCount: nil)])
    }

    @Test("AC3: every page is read, the list is A to Z, and a channel shows once")
    func pagesAndSorts() async throws {
        let all = try await loader([
            nil: SubscriptionPage(channels: [channel("c", "cherry"), channel("a", "Apple")], nextPageToken: "2"),
            "2": SubscriptionPage(channels: [channel("b", "Banana"), channel("a", "Apple")], nextPageToken: "3"),
            "3": SubscriptionPage(channels: [channel("d", "Date")], nextPageToken: nil),
        ]).all()
        #expect(all.map(\.title) == ["Apple", "Banana", "cherry", "Date"])
    }

    @Test("AC10: an error while loading shows as failed, and Retry can load")
    func failedLoad() async {
        let model = ImportModel(loader: SubscriptionsLoader { _ in throw YouTubeError.offline })
        await model.load()
        #expect(model.phase == .failed(.offline))
        #expect(model.channels.isEmpty)
    }

    @Test("AC11: an account with no subscriptions loads as an empty list")
    func emptyAccount() async {
        let model = ImportModel(loader: loader([nil: SubscriptionPage(channels: [], nextPageToken: nil)]))
        await model.load()
        #expect(model.phase == .loaded)
        #expect(model.channels.isEmpty)
    }

    // MARK: - Picking

    func loadedModel() async -> ImportModel {
        let model = ImportModel(loader: loader([nil: SubscriptionPage(
            channels: [channel("a", "Apple"), channel("b", "Banana"), channel("c", "Cherry")], nextPageToken: nil
        )]))
        await model.load()
        return model
    }

    @Test("AC3, AC6: nothing is ticked to start (D153)")
    func nothingTicked() async {
        let model = await loadedModel()
        #expect(model.picked.isEmpty)
        #expect(model.pickedChannels().isEmpty)
    }

    @Test("AC4: the search box filters by name and keeps ticks")
    func filterKeepsTicks() async {
        let model = await loadedModel()
        model.toggle(channel("a", "Apple"))
        model.filter = "an"
        #expect(model.visible.map(\.title) == ["Banana"])
        model.toggle(channel("b", "Banana"))
        model.filter = ""
        #expect(model.visible.count == 3)
        #expect(model.pickedChannels().map(\.id) == ["a", "b"])
    }

    @Test("AC7: picks come out in the order they were ticked; unticking removes one")
    func tickOrder() async {
        let model = await loadedModel()
        for id in ["c", "a", "b"] { model.toggle(channel(id, id)) }
        model.toggle(channel("a", "a"))
        #expect(model.pickedChannels().map(\.id) == ["c", "b"])
    }

    @Test("AC5: a creator already followed is never picked again")
    func skipsFollowed() async {
        let model = await loadedModel()
        model.toggle(channel("a", "Apple"))
        model.toggle(channel("b", "Banana"))
        #expect(model.pickedChannels(alreadyFollowing: ["a"]).map(\.id) == ["b"])
    }

    @Test("AC12: Select all ticks everyone not yet followed, A to Z after earlier ticks; Deselect all clears")
    func selectAll() async {
        let model = await loadedModel()
        #expect(!model.allVisiblePicked(alreadyFollowing: ["a"]))
        model.toggle(channel("c", "Cherry"))
        model.selectAllVisible(alreadyFollowing: ["a"])
        #expect(model.pickedChannels(alreadyFollowing: ["a"]).map(\.id) == ["c", "b"])
        #expect(model.allVisiblePicked(alreadyFollowing: ["a"]))
        model.deselectAllVisible()
        #expect(model.picked.isEmpty)
    }

    @Test("AC12: with a search typed, Select all and Deselect all touch only the creators shown")
    func selectAllFiltered() async {
        let model = await loadedModel()
        model.toggle(channel("a", "Apple"))
        model.filter = "an"
        model.selectAllVisible()
        #expect(model.picked == ["a", "b"])
        model.deselectAllVisible()
        #expect(model.picked == ["a"])
    }

    @Test("AC14: the success note counts the creators and invites ranking only in Ranked mode")
    func successMessage() {
        #expect(AppStore.importMessage(count: 12, ranked: true) == "12 creators added. Hold and drag to rank them.")
        #expect(AppStore.importMessage(count: 1, ranked: true) == "1 creator added. Hold and drag to rank them.")
        #expect(AppStore.importMessage(count: 3, ranked: false) == "3 creators added.")
    }

    // MARK: - Following the picks

    @Test("AC5, AC7, AC8: picks join the bottom of Following in tick order, with a normal follow's videos")
    func followsPicks() async {
        var fake = FakeYouTubeAPI()
        let (a, b, c) = (channel("UCa", "A"), channel("UCb", "B"), channel("UCc", "C"))
        for ch in [a, b, c] {
            fake.channelsByID[ch.id] = ch
            fake.uploads[ch.id] = [details("\(ch.title)1", channel: ch.id, daysAgo: 1)]
        }
        let store = AppStore(context: container.mainContext, api: fake)
        await store.follow(a)
        await store.follow([c, a, b])
        #expect(store.creators().map(\.channelID) == ["UCa", "UCc", "UCb"])
        #expect(store.creators().allSatisfy { $0.loadState == .ready })
        // Day one: one starter video each, same as following one at a time (D79).
        #expect(Set(store.engine.state.backlog.map(\.id)) == ["A1", "B1", "C1"])
    }

    // MARK: - Google sign-in

    let signIn = GoogleSignIn(clientID: "123-abc.apps.googleusercontent.com", state: "st", verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")

    @Test("The sign-in link asks only to view YouTube, with PKCE")
    func signInLink() {
        let items = URLComponents(url: signIn.signInURL, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let value = { (name: String) in items.first { $0.name == name }?.value }
        #expect(signIn.signInURL.absoluteString.hasPrefix("https://accounts.google.com/o/oauth2/v2/auth?"))
        #expect(value("client_id") == "123-abc.apps.googleusercontent.com")
        #expect(value("redirect_uri") == "com.googleusercontent.apps.123-abc:/oauth2redirect")
        #expect(value("response_type") == "code")
        #expect(value("scope") == "https://www.googleapis.com/auth/youtube.readonly")
        #expect(value("state") == "st")
        #expect(value("code_challenge_method") == "S256")
        // The example pair from the PKCE standard (RFC 7636, appendix B).
        #expect(value("code_challenge") == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    @Test("The code is read from Google's answer; a refusal or a wrong state is denied")
    func readsCode() throws {
        let base = "com.googleusercontent.apps.123-abc:/oauth2redirect"
        #expect(try signIn.code(from: URL(string: "\(base)?state=st&code=4/abc")!) == "4/abc")
        #expect(throws: GoogleSignIn.Failure.denied) { try signIn.code(from: URL(string: "\(base)?state=st&error=access_denied")!) }
        #expect(throws: GoogleSignIn.Failure.denied) { try signIn.code(from: URL(string: "\(base)?state=other&code=4/abc")!) }
        #expect(throws: GoogleSignIn.Failure.denied) { try signIn.code(from: URL(string: base)!) }
    }

    @Test("The token request sends the code and the PKCE secret, and no client secret")
    func tokenRequest() {
        let request = signIn.tokenRequest(code: "4/abc")
        let body = String(decoding: request.httpBody ?? Data(), as: UTF8.self)
        #expect(request.url?.absoluteString == "https://oauth2.googleapis.com/token")
        #expect(request.httpMethod == "POST")
        #expect(body.contains("grant_type=authorization_code"))
        #expect(body.contains("code_verifier=dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"))
        #expect(body.contains("client_id=123-abc.apps.googleusercontent.com"))
        #expect(!body.contains("client_secret"))
    }

    @Test("The access token is read from Google's answer; anything else is denied")
    func readsToken() throws {
        #expect(try GoogleSignIn.accessToken(from: Data(#"{"access_token":"ya29.x","expires_in":3599}"#.utf8)) == "ya29.x")
        #expect(throws: GoogleSignIn.Failure.denied) { try GoogleSignIn.accessToken(from: Data(#"{"error":"invalid_grant"}"#.utf8)) }
    }

    @Test("Two sign-ins never share a state or PKCE secret")
    func freshSecrets() {
        let one = GoogleSignIn(clientID: "x"), two = GoogleSignIn(clientID: "x")
        #expect(one.state != two.state)
        #expect(one.verifier != two.verifier)
        #expect(one.verifier.count >= 43)
    }

    @Test("AC1: no client ID in the build means no import buttons")
    func clientIDConfig() {
        #expect(AppConfig.googleClientID(from: nil) == nil)
        #expect(AppConfig.googleClientID(from: " ") == nil)
        #expect(AppConfig.googleClientID(from: "$(GOOGLE_CLIENT_ID)") == nil)
        #expect(AppConfig.googleClientID(from: "123-abc.apps.googleusercontent.com") == "123-abc.apps.googleusercontent.com")
    }
}
