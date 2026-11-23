import SwiftUI

/// The ⓘ page on Home: when the next shipment comes, refreshes and waiting videos (D58, D148).
struct InboxInfoView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Binding var tab: AppTab
    /// Closed every time the page opens; a tap opens it (D209, changes D148).
    @State private var showsTips = false

    var body: some View {
        NavigationStack {
            // Ticks every second so the countdown stays live (it shows seconds in the last minute).
            TimelineView(.periodic(from: .now, by: 1)) { context in
                list(now: context.date)
            }
            .navigationTitle("Inbox info")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { dismiss() }
                }
            }
        }
    }

    private func tip(_ icon: String, _ text: String) -> some View {
        Label {
            Text(text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: icon).foregroundStyle(.secondary)
        }
        .font(.subheadline)
    }

    private func list(now: Date) -> some View {
        let engine = store.engine
        let next = engine.nextShipment(after: max(now, engine.state.lastShipment ?? now))
        let refreshesLeft = engine.refreshesRemaining(at: now)
        return List {
            Section {
                DisclosureGroup("How it works", isExpanded: $showsTips) {
                    tip("hand.tap", "Tap a video to watch.")
                    tip("arrow.down", "Pull down to swap today's videos. Uses 1 refresh, only before you start watching.")
                    tip("line.3.horizontal", "Hold a video, then drag to reorder.")
                    tip("arrow.triangle.2.circlepath", "⋯ › Swap this video trades one video for a new one. Uses 1 refresh, any time.")
                    tip("trash", "⋯ › Remove video drops it for good, with no replacement.")
                    tip("checkmark.circle", "Watched if you leave it in the last minute. Leave early and it keeps your place.")
                    tip("tray.full", "Unfinished videos stay for tomorrow.")
                }
            }

            Section {
                StatsChart()
            }

            Section {
                LabeledContent {
                    Text(Format.countdown(next.timeIntervalSince(now))).monospacedDigit()
                } label: {
                    Text("Next new videos")
                    Text(Self.when(next, calendar: engine.calendar))
                }
                LabeledContent("Refreshes left", value: "\(refreshesLeft) of \(engine.settings.refreshesPerDay) today")
                LabeledContent("Videos waiting", value: "\(engine.state.backlog.count)")
            } footer: {
                Text("Waiting videos come on later days, or expire after 30 days.")
            }

            Section {
                Button("Change budgets and arrival time") {
                    dismiss()
                    tab = .settings
                }
            }

            // Back to the Inbox, where the video is showing again.
            PutBackSection { dismiss() }
        }
    }

    /// "Today at 6 AM" or "Tomorrow at 6 AM" (shipments are on whole hours, D45).
    static func when(_ date: Date, calendar: Calendar) -> String {
        var style = Date.FormatStyle.dateTime.hour()
        style.timeZone = calendar.timeZone
        let day = calendar.isDateInToday(date) ? "Today" : "Tomorrow"
        return "\(day) at \(date.formatted(style))"
    }
}

/// "Put back last video" (D104, D225): the last video that left the Inbox (watched, removed or
/// switched away) goes back to its old spot. At the bottom of the Inbox ⓘ page and of Settings,
/// in every version of the app. Hidden when there is nothing to put back.
struct PutBackSection: View {
    @Environment(AppStore.self) private var store
    /// Runs after the video is back, to show the Inbox.
    let onPutBack: () -> Void

    var body: some View {
        if let last = store.engine.puttableBack {
            Section {
                Button("Put back last video", systemImage: "arrow.uturn.backward") {
                    store.putBackLastVideo()
                    onPutBack()
                }
            } footer: {
                Text("“\(last.video.title)” goes back in your Inbox.")
            }
        }
    }
}
