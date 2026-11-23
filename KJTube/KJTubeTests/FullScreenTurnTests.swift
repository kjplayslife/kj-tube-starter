import Testing
import UIKit
@testable import KJTube

/// The full screen button's first tap after the player opened did nothing: iOS still thought
/// the app was portrait-only and refused the turn (D176).
@MainActor
struct FullScreenTurnTests {
    @Test func firstRequestAfterLandscapeIsAllowedTurnsTheScreen() async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        try await Task.sleep(for: .seconds(1))
        #expect(scene.interfaceOrientation == .portrait)

        AppDelegate.allowsLandscape = true // the player opens
        Orientation.request(.landscapeRight) // the first tap
        try await Task.sleep(for: .seconds(2))
        #expect(scene.interfaceOrientation == .landscapeRight)

        Orientation.request(.portrait)
        AppDelegate.allowsLandscape = false
        try await Task.sleep(for: .seconds(2))
        #expect(scene.interfaceOrientation == .portrait)
    }
}
