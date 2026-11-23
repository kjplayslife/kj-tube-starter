import Testing
@testable import KJTube

struct AppConfigTests {
    @Test("Walking skeleton smoke test: the app bundle loads its config")
    func configLoads() {
        // Empty is allowed (no Secrets.xcconfig, e.g. on CI), but never the raw build-setting placeholder.
        #expect(!AppConfig.youTubeAPIKey.hasPrefix("$("))
    }

    @Test("Dev build label shows only when the phone script set it (D128)")
    func devBuildLabel() {
        #expect(AppConfig.devBuildLabel(from: nil) == nil)
        #expect(AppConfig.devBuildLabel(from: "") == nil)
        #expect(AppConfig.devBuildLabel(from: "  ") == nil)
        #expect(AppConfig.devBuildLabel(from: "$(DEV_BUILD_LABEL)") == nil)
        #expect(AppConfig.devBuildLabel(from: "Skip Ad fix · my-branch @ abc1234 · Nov 10, 10:57 AM")
                == "Skip Ad fix · my-branch @ abc1234 · Nov 10, 10:57 AM")
    }
}
