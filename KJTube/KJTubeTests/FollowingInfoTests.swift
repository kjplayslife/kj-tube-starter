import Testing
@testable import KJTube

/// The "How it works" lines on the Following ⓘ page (D162).
struct FollowingInfoTests {
    private func text(ranked: Bool, canImport: Bool) -> String {
        FollowingInfoView.tips(ranked: ranked, canImport: canImport).map(\.text).joined(separator: "\n")
    }

    @Test func rankedExplainsEveryFeature() {
        let text = text(ranked: true, canImport: true)
        for word in ["paste", "Import YouTube subscriptions", "drag to rank", "Move to Top", "Move to Bottom",
                     "Watch in Order", "Any Length", "Unfollow"] {
            #expect(text.contains(word), "missing \(word)")
        }
    }

    @Test func randomLeavesOutRanking() {
        let text = text(ranked: false, canImport: true)
        #expect(!text.contains("drag to rank"))
        #expect(!text.contains("Move to Top"))
        #expect(text.contains("Random"))
        #expect(text.contains("Watch in Order"))
    }

    @Test func importLineNeedsAnImportBuild() {
        #expect(!text(ranked: true, canImport: false).contains("Import"))
    }

    @Test func iconsAreUnique() { // the list uses the icon as each line's id
        for ranked in [true, false] {
            let icons = FollowingInfoView.tips(ranked: ranked, canImport: true).map(\.icon)
            #expect(Set(icons).count == icons.count)
        }
    }

    /// Each switch has its own one-time note, saved under its own key (D173).
    @Test func eachSwitchHasItsOwnFirstTimeNote() {
        #expect(CreatorSwitch.inOrder.explainer.contains("oldest first"))
        #expect(CreatorSwitch.inOrder.explainer.contains("series"))
        #expect(CreatorSwitch.anyLength.explainer.contains("never too long"))
        #expect(CreatorSwitch.inOrder.explainedKey != CreatorSwitch.anyLength.explainedKey)
    }
}
