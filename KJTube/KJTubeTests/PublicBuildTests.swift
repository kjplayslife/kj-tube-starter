import Testing
@testable import KJTube

/// The public version of the app follows YouTube's rules for apps (D179).
@MainActor
struct PublicBuildTests {
    @Test func onlyYesTurnsThePublicVersionOn() {
        #expect(AppConfig.isPublic(from: "YES"))
        #expect(AppConfig.isPublic(from: " yes\n"))
        #expect(!AppConfig.isPublic(from: nil))
        #expect(!AppConfig.isPublic(from: ""))
        #expect(!AppConfig.isPublic(from: "NO"))
        #expect(!AppConfig.isPublic(from: "$(PUBLIC_BUILD)"))
    }

    @Test func publicPlayerShowsYouTubesOwnControls() {
        let vars = YouTubeIFramePlayer.playerVars(public: true)
        #expect(vars.contains("controls: 1"))
        #expect(!vars.contains("modestbranding"))
        #expect(!vars.contains("disablekb"))
        #expect(YouTubeIFramePlayer.html(public: true).contains("controls: 1"))
    }

    @Test func kjsOwnPlayerIsUnchanged() {
        let vars = YouTubeIFramePlayer.playerVars(public: false)
        #expect(vars.contains("controls: 0"))
        #expect(YouTubeIFramePlayer.html(public: false).contains("controls: 0"))
    }

    /// The tests run as KJ's own app, never the public one.
    @Test func testsRunAsThePrivateApp() {
        #expect(!AppConfig.isPublic)
    }
}
