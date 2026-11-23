import SwiftUI

/// The ⓘ page on Following: what you can do with the list (D162). Built like `InboxInfoView`.
struct FollowingInfoView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    /// Closed every time the page opens; a tap opens it, like on the Inbox page (D209).
    @State private var showsTips = false

    struct Tip: Equatable {
        let icon: String
        let text: String
    }

    /// The "How it works" lines. Ranking lines show only in Ranked order (D74), and the import
    /// line only when this build can import (D152).
    static func tips(ranked: Bool, canImport: Bool) -> [Tip] {
        var tips = [Tip(icon: "magnifyingglass", text: "Search, or paste a channel or video link, to follow a creator.")]
        if canImport {
            tips.append(Tip(icon: "square.and.arrow.down", text: "Import YouTube subscriptions, below, brings over creators you already follow there."))
        }
        tips.append(Tip(icon: "tray.and.arrow.down", text: "A new creator's latest videos wait until new videos next arrive."))
        if ranked {
            tips.append(Tip(icon: "line.3.horizontal", text: "Hold a creator, then drag to rank. Top creators are served first."))
            tips.append(Tip(icon: "arrow.up.to.line", text: "Hold › Move to Top or Move to Bottom jumps a creator to either end."))
        } else {
            tips.append(Tip(icon: "shuffle", text: "Creator order is Random: newest videos first, from any creator. Switch to Ranked to rank them."))
        }
        tips.append(Tip(icon: "list.number", text: "Swipe right, or Hold › Watch in Order, serves that creator's waiting videos oldest first. Good for a series."))
        tips.append(Tip(icon: "hourglass.badge.plus", text: "Swipe right, or Hold › Any Length, means that creator's videos are never too long. A long one comes only when it is first in line, and is the only new video that day."))
        tips.append(Tip(icon: "person.badge.minus", text: "Swipe left, or Hold › Unfollow, to unfollow. Their waiting videos go too. Undo shows for 5 seconds."))
        return tips
    }

    var body: some View {
        let ranked = store.creatorOrder == .ranked
        NavigationStack {
            List {
                Section {
                    DisclosureGroup("How it works", isExpanded: $showsTips) {
                        ForEach(Self.tips(ranked: ranked, canImport: AppConfig.googleClientID != nil), id: \.icon) { tip in
                            Label {
                                Text(tip.text).fixedSize(horizontal: false, vertical: true)
                            } icon: {
                                Image(systemName: tip.icon).foregroundStyle(.secondary)
                            }
                            .font(.subheadline)
                        }
                    }
                }

                // The same button as in Settings; hidden when this build can't import (D152).
                if AppConfig.googleClientID != nil {
                    Section {
                        ImportButton { Label("Import YouTube subscriptions", systemImage: "square.and.arrow.down") }
                    } footer: {
                        Text("Sign in with Google once, then pick which creators to follow here.")
                    }
                }
            }
            // An import just finished: close, so the new creators and the note show (D158).
            .onChange(of: store.importedCount) { _, count in
                if count != nil { dismiss() }
            }
            .navigationTitle("Following info")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { dismiss() }
                }
            }
        }
    }
}
