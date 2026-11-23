import SwiftUI

/// Credits the app has to show (D177). Reached from the About row in Settings.
struct AboutView: View {
    /// The credit line Crossway asks for when ESV verses are quoted in a public work.
    static let esvCredit = """
    Scripture quotations are from the ESV® Bible (The Holy Bible, English Standard Version®), \
    © 2001 by Crossway, a publishing ministry of Good News Publishers. ESV Text Edition: 2025. \
    The ESV text may not be quoted in any publication made available to the public by a \
    Creative Commons license. The ESV may not be translated in whole or in part into any other \
    language. Used by permission. All rights reserved.
    """

    /// KJ Tube's own pages (D180). Their source is `site/` in this repo.
    static let privacyPolicy = URL(string: "https://example.com/privacy")!
    static let terms = URL(string: "https://example.com/terms")!
    static let support = URL(string: "https://example.com/support")!
    static let contact = URL(string: "mailto:you@example.com")!
    static let youTubeTerms = URL(string: "https://www.youtube.com/t/terms")!
    static let googlePrivacy = URL(string: "https://www.google.com/policies/privacy")!

    var body: some View {
        Form {
            Section {
                Link("Privacy Policy", destination: Self.privacyPolicy)
                Link("Terms of Service", destination: Self.terms)
                Link("Support", destination: Self.support)
                Link("Contact: you@example.com", destination: Self.contact)
            }
            // YouTube asks every app that uses its API to say so and link these two pages.
            Section {
                Link("YouTube Terms of Service", destination: Self.youTubeTerms)
                Link("Google Privacy Policy", destination: Self.googlePrivacy)
            } header: {
                Text("YouTube")
            } footer: {
                Text("KJ Tube uses YouTube API Services to find creators and play their videos. By using KJ Tube you agree to be bound by the YouTube Terms of Service.")
            }
            Section {
                Text(Self.esvCredit)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Bible verses")
            }
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }
}
