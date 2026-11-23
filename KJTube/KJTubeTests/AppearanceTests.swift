import Foundation
import SwiftUI
import Testing
@testable import KJTube

/// The appearance setting (D223): System, Light or Dark.
struct AppearanceTests {
    @Test func systemFollowsThePhone() {
        #expect(Appearance.system.colorScheme == nil)
        #expect(Appearance.light.colorScheme == .light)
        #expect(Appearance.dark.colorScheme == .dark)
    }

    @Test func savedPick() {
        let defaults = UserDefaults(suiteName: "AppearanceTests-\(UUID().uuidString)")!
        #expect(Appearance.saved(in: defaults) == .system) // nothing picked yet
        defaults.set("light", forKey: Appearance.key)
        #expect(Appearance.saved(in: defaults) == .light)
        defaults.set("dark", forKey: Appearance.key)
        #expect(Appearance.saved(in: defaults) == .dark)
        defaults.set("sepia", forKey: Appearance.key) // from some other version
        #expect(Appearance.saved(in: defaults) == .system)
    }

    @Test func settingsOrder() {
        #expect(Appearance.allCases.map(\.label) == ["System", "Light", "Dark"])
    }
}
