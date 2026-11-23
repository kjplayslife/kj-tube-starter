import SwiftUI

/// The Inbox during first run (docs/specs/first-run.md): the welcome before any creator is
/// followed, then "Almost ready" until the first Inbox is loaded on purpose (D175).
struct FirstRunInbox: View {
    @Environment(AppStore.self) private var store
    let hasCreators: Bool
    let findCreators: () -> Void
    let rankCreators: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text(hasCreators ? "Almost ready" : "Welcome to KJ Tube")
                .font(.title2.weight(.semibold))
            Text(hasCreators
                 ? "Rank your creators, then load your first Inbox."
                 : "Follow a few creators you trust. Each morning you'll get a few of their new videos, sized to your time.")
                .foregroundStyle(.secondary)
            VStack(spacing: 14) {
                if hasCreators {
                    Button { store.askToLoadInbox() } label: { roomy(Text("Load my Inbox")) }
                        .buttonStyle(.glassProminent)
                    Button("Rank creators", action: rankCreators)
                } else if AppConfig.googleClientID != nil {
                    // The quick win: bring over the creators already followed on YouTube (D152).
                    ImportButton { roomy(Label("Import from YouTube", systemImage: "square.and.arrow.down")) }
                        .buttonStyle(.glassProminent)
                    Button("Find creators myself", action: findCreators)
                } else {
                    Button(action: findCreators) { roomy(Text("Find creators")) }
                        .buttonStyle(.glassProminent)
                }
            }
            .padding(.top, 8)
        }
        .multilineTextAlignment(.center)
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension FirstRunInbox {
    /// A little more room around the words on the blue buttons: between the normal and large sizes.
    fileprivate func roomy(_ label: some View) -> some View {
        label
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
    }
}

/// The bar on Following during first run: how to rank, and the button that loads the first Inbox.
struct FirstRunBar: View {
    let ranked: Bool
    /// Off for the same bar after first run, on the "No new videos" Inbox (D218).
    var offersImport = true
    let load: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(FirstRun.barText(ranked: ranked))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: load) {
                Text("Load my Inbox")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            // Started by hand? Import is still on offer until the first Inbox loads (KJ, 2026-11-16).
            // Hidden in a build with no Google client ID, like every Import button (D152).
            if offersImport {
                ImportButton {
                    Label("Import from YouTube", systemImage: "square.and.arrow.down")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .controlSize(.large)
            }
        }
        .padding(16)
        // One shade lighter than the page's cards, like the note after an import (D158).
        .floatingBackground(.rect(cornerRadius: 24))
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }
}

/// One small sheet with two pages: the daily amount, and the check before the first Inbox.
struct FirstRunSheet: View {
    @Environment(AppStore.self) private var store
    /// The page being shown. Kept here so the sheet doesn't go blank while it slides away.
    @State private var page: FirstRunPage
    /// Called once the first Inbox is loaded, to open the Inbox tab.
    let loaded: () -> Void

    init(start: FirstRunPage, loaded: @escaping () -> Void) {
        _page = State(initialValue: start)
        self.loaded = loaded
    }

    var body: some View {
        Group {
            switch page {
            case .amount(let thenCheck):
                amountPage(thenCheck: thenCheck)
            case .check:
                checkPage
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 32)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.default, value: page)
        .onChange(of: store.firstRunPage) { _, new in
            if let new { page = new }
        }
        .presentationDetents([.fraction(0.6)])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Daily amount

    private func amountPage(thenCheck: Bool) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("How much content per day?")
                    .font(.title2.weight(.semibold))
                Text("Each morning you get about this many minutes of video. Then that's it for the day.")
                    .foregroundStyle(.secondary)
            }
            VStack(spacing: 14) {
                budgetRow("Weekdays", .weekdayBudget)
                budgetRow("Weekends", .weekendBudget)
                // Yes or no: Friday's shipment uses the weekend minutes (D146). No lock here either.
                Toggle("Friday is weekend", isOn: Binding {
                    store.engine.settings.fridayIsWeekend
                } set: {
                    store.setFridayIsWeekend($0)
                })
            }
            Text("You can tighten this any time. Loosening is allowed once a week.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            mainButton("Continue") {
                store.firstRunPage = thenCheck ? .check : nil
            }
        }
        // Seeing the sheet counts: swiping it away keeps the minutes shown, like Continue.
        .onAppear { store.firstRunAmountShown() }
    }

    /// The same choices as in Settings. Nothing is locked: nothing has been loosened yet (D175).
    private func budgetRow(_ title: String, _ limit: AppStore.Limit) -> some View {
        LabeledContent(title) {
            Picker(title, selection: Binding { store.value(of: limit) } set: { store.set(limit, to: $0) }) {
                ForEach(SettingsView.budgetOptions, id: \.self) { Text("\(Int($0)) min").tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 220)
        }
    }

    // MARK: - The check

    private var checkPage: some View {
        let summary = store.firstRunSummary()
        return VStack(alignment: .leading, spacing: 20) {
            Text("Ready for your first Inbox?")
                .font(.title2.weight(.semibold))
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Label(summary.amount, systemImage: "clock")
                    Spacer(minLength: 8)
                    Button("Change") { store.firstRunPage = .amount(thenCheck: true) }
                        .font(.subheadline)
                }
                Label(summary.creators, systemImage: "person.2")
                ForEach(summary.switches, id: \.self) { line in
                    Label(line, systemImage: line.hasPrefix("Watch") ? "list.number" : "hourglass.badge.plus")
                }
            }
            .font(.subheadline)
            .labelStyle(SummaryLabelStyle())
            Text("Your first videos are picked from this order.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            VStack(spacing: 14) {
                mainButton("Load my Inbox") {
                    store.finishFirstRun()
                    loaded()
                    Task { await store.catchUp() } // any first video still loading is served once it lands
                }
                Button("Keep editing") { store.firstRunPage = nil }
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func mainButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glassProminent)
        .controlSize(.large)
    }
}

/// Icon in a fixed column, text wrapping beside it.
private struct SummaryLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            configuration.icon
                .foregroundStyle(.secondary)
                .frame(width: 22)
            configuration.title
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
