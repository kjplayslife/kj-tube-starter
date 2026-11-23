import SwiftUI

/// Light or dark (D223): follows the phone unless KJ picks one in Settings.
enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark

    /// Where the pick is saved.
    static let key = "appearance"

    var id: Self { self }

    var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// What to force the app to; nil follows the phone.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    /// The saved pick. Anything missing or unknown follows the phone.
    static func saved(in defaults: UserDefaults = .standard) -> Appearance {
        defaults.string(forKey: key).flatMap(Appearance.init(rawValue:)) ?? .system
    }
}
