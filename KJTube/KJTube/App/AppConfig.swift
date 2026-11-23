import Foundation

/// Values injected at build time from Config/App.xcconfig → Secrets.xcconfig.
enum AppConfig {
    /// YouTube Data API v3 key. Empty when Secrets.xcconfig is missing.
    static var youTubeAPIKey: String {
        let value = Bundle.main.object(forInfoDictionaryKey: "YouTubeAPIKey") as? String ?? ""
        return value.hasPrefix("$(") ? "" : value
    }

    /// Google "iOS" client ID for importing subscriptions (D152). Nil when Secrets.xcconfig has
    /// none: the import buttons are hidden.
    static var googleClientID: String? {
        googleClientID(from: Bundle.main.object(forInfoDictionaryKey: "GoogleClientID") as? String)
    }

    static func googleClientID(from raw: String?) -> String? {
        let value = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty || value.hasPrefix("$(") ? nil : value
    }

    /// Which change this build is, set by a `DEV_BUILD_LABEL` build setting.
    /// Nil when nothing sets it.
    static var devBuildLabel: String? {
        devBuildLabel(from: Bundle.main.object(forInfoDictionaryKey: "DevBuildLabel") as? String)
    }

    static func devBuildLabel(from raw: String?) -> String? {
        let value = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty || value.hasPrefix("$(") ? nil : value
    }

    /// True in the public version of the app, which follows YouTube's rules for apps (D179):
    /// YouTube's own player and controls with nothing hidden and nothing drawn over them, no
    /// small player, no seek-bar pictures and no Skip Ad. Set by `PUBLIC_BUILD = YES` at build
    /// time (Config/App.xcconfig).
    static let isPublic = isPublic(from: Bundle.main.object(forInfoDictionaryKey: "PublicBuild") as? String)

    static func isPublic(from raw: String?) -> Bool {
        (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == "YES"
    }

    /// Skip Ad: the player can show a "Skip Ad" button over sponsor reads when something tells
    /// it where they are. The public starter ships with no finder, so the feature is off.
    /// Return your own `AdFinder` here to turn it on.
    static var adFinder: (any AdFinder)? { nil }
}
