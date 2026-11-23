import UIKit

/// The app is portrait-only except while the player is open (fullscreen by rotating, D34).
final class AppDelegate: NSObject, UIApplicationDelegate {
    /// iOS remembers the last answer it got. Without telling it to ask again, the first tap on
    /// the full screen button after the player opened was refused ("Supported: portrait") and
    /// did nothing; only the second tap turned the screen (D176).
    @MainActor static var allowsLandscape = false {
        didSet { if allowsLandscape != oldValue { Orientation.refreshSupported() } }
    }

    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        MainActor.assumeIsolated { Self.allowsLandscape ? .allButUpsideDown : .portrait }
    }
}

@MainActor
enum Orientation {
    private static var scene: UIWindowScene? {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
    }

    /// Makes iOS ask again which ways the screen may turn.
    static func refreshSupported() {
        scene?.windows.forEach { $0.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations() }
    }

    static func request(_ mask: UIInterfaceOrientationMask) {
        guard let scene else { return }
        // Before the request, not after: the request is checked against what iOS last heard.
        refreshSupported()
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { _ in
            // Refused all the same: ask once more now that iOS has caught up.
            refreshSupported()
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask))
        }
    }
}
