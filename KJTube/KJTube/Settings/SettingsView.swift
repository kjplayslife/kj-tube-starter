import SwiftUI

/// Budgets, shipment time and refreshes, with friction on loosening
/// (docs/specs/settings.md, docs/specs/settings-revamp.md).
struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @Binding var tab: AppTab
    @State private var prompt: Prompt?
    @State private var showsTipJar = false
    @AppStorage(Appearance.key) private var appearance = Appearance.system

    /// A pending confirmation or a "locked" notice.
    struct Prompt: Identifiable {
        let id = UUID()
        let title: String
        let message: String
        let confirm: (() -> Void)?
        var confirmLabel = "Confirm"
    }

    static let budgetOptions: [Double] = [30, 60, 90]
    private static let refreshOptions: [Double] = [0, 1, 2]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    limitPicker("Weekdays", .weekdayBudget, options: Self.budgetOptions) { "\(Int($0)) min" }
                    limitPicker("Weekends", .weekendBudget, options: Self.budgetOptions) { "\(Int($0)) min" }
                    Toggle("Friday is weekend", isOn: fridayIsWeekend)
                    Picker("New videos arrive", selection: shipmentHour) { // plain words, never "shipment" (D202, D203)
                        ForEach(0..<24, id: \.self) { hour in
                            Text(Self.hourLabel(hour)).tag(hour)
                        }
                    }
                    limitPicker("Refreshes per day", .refreshesPerDay, options: Self.refreshOptions) { "\(Int($0))" }
                } header: {
                    Text("Limits")
                } footer: {
                    Text(footerText)
                }

                Section {
                    LabeledContent("Creator order") {
                        Picker("Creator order", selection: creatorOrder) {
                            Text("Ranked").tag(CreatorOrder.ranked)
                            Text("Random").tag(CreatorOrder.random)
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 180)
                    }
                } footer: {
                    Text(store.creatorOrder == .ranked
                         ? "Your top creators (in Following) are served first."
                         : "Newest videos first, from any creator.")
                }

                // Follows the phone unless one is picked (D223).
                Section {
                    LabeledContent("Appearance") {
                        Picker("Appearance", selection: $appearance) {
                            ForEach(Appearance.allCases) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 220)
                    }
                }

                if AppConfig.googleClientID != nil {
                    Section {
                        ImportButton { Label("Import YouTube subscriptions", systemImage: "square.and.arrow.down") }
                    } footer: {
                        Text("Sign in with Google once, then pick which creators to follow here.")
                    }
                }

                // Not in the public version: its button would sit over YouTube's player (D179).
                if !AppConfig.isPublic {
                Section {
                    Toggle(isOn: skipAd) {
                        HStack(spacing: 8) {
                            Text("Skip in-video ads")
                            Text("Beta")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.quaternary, in: .capsule)
                        }
                    }
                    .disabled(!store.ads.hasFinder)
                } footer: {
                    Text(store.ads.hasFinder
                         ? "Shows a Skip Ad button when the creator reads a sponsor or promo inside the video. An AI finds them, so it can be wrong."
                         : "Skip Ad isn't available in this build.")
                }
                }

                // Only KJ Tube Dev has this: empty the app to try first run again (D175).
                // Never the public version, not even its test install on KJ's phone (D179).
                if AppConfig.devBuildLabel != nil, !AppConfig.isPublic {
                    Section {
                        // Try following from the "No new videos" Inbox (D218).
                        Button("Empty the Inbox (no new videos)", role: .destructive) {
                            prompt = Prompt(
                                title: "Empty the Inbox?",
                                message: "Marks today's videos in KJ Tube Dev as watched and shows \"No new videos from your creators\". Your creators stay.",
                                confirm: {
                                    NowPlaying.shared.close()
                                    store.emptyInboxForTesting()
                                }
                            )
                        }
                        Button("Start over (first run)", role: .destructive) {
                            prompt = Prompt(
                                title: "Start over?",
                                message: "Removes every creator and video from KJ Tube Dev and shows the first-run steps again.",
                                confirm: {
                                    NowPlaying.shared.close()
                                    store.startOver()
                                }
                            )
                        }
                    }
                }

                // Credits a public app has to show, like Crossway's line for the verses (D177).
                Section {
                    NavigationLink("About") { AboutView() }
                }

                // The tip jar: one calm row, in every version of the app (D181).
                Section {
                    Button {
                        showsTipJar = true
                    } label: {
                        HStack {
                            Text("Buy KJ a coffee 😄").foregroundStyle(Color.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Color(.tertiaryLabel))
                        }
                        .contentShape(.rect)
                    }
                }

                // The last video that left the Inbox, in every version of the app (D225).
                PutBackSection { tab = .home }

                Section {
                } footer: {
                    VStack(spacing: 4) {
                        Text(Self.versionLine)
                        // Only KJ Tube Dev has this: which change is on the phone, and since when (D128).
                        if let label = AppConfig.devBuildLabel {
                            Text("Dev build: \(label)")
                                .multilineTextAlignment(.center)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
                }
            }
            .pageTitle("Settings")
        }
        .sheet(isPresented: $showsTipJar) { TipJarSheet() }
        .alert(item: $prompt) { prompt in
            if let confirm = prompt.confirm {
                Alert(
                    title: Text(prompt.title), message: Text(prompt.message),
                    primaryButton: .default(Text(prompt.confirmLabel), action: confirm),
                    secondaryButton: .cancel()
                )
            } else {
                Alert(title: Text(prompt.title), message: Text(prompt.message), dismissButton: .default(Text("OK")))
            }
        }
    }

    // MARK: - Pickers

    private func limitPicker(
        _ title: String, _ limit: AppStore.Limit, options: [Double], label: @escaping (Double) -> String
    ) -> some View {
        LabeledContent(title) {
            Picker(title, selection: limitBinding(limit, label: label)) {
                ForEach(options, id: \.self) { Text(label($0)).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 180)
        }
    }

    private func limitBinding(_ limit: AppStore.Limit, label: @escaping (Double) -> String) -> Binding<Double> {
        Binding {
            store.value(of: limit)
        } set: { new in
            switch store.evaluate(limit, to: new) {
            case .apply:
                // Lowering a daily limit asks first, because coming back up costs the weekly raise (D210).
                guard let warning = store.lowerWarning(limit, to: new) else {
                    store.set(limit, to: new)
                    return
                }
                prompt = Prompt(
                    title: "Are you sure you want to lower your daily limit to \(SettingsPolicy.spelledOut(minutes: new))?",
                    message: warning,
                    confirm: { store.set(limit, to: new) },
                    confirmLabel: "Yes"
                )
            case .confirm(let lockUntil):
                prompt = Prompt(
                    title: "Raise to \(label(new))?",
                    message: "You can't raise this again until \(Self.day(lockUntil)). Starts the next time new videos arrive.",
                    confirm: { store.set(limit, to: new, lockUntil: lockUntil) }
                )
            case .locked(let until):
                prompt = Prompt(title: "Not yet", message: "You can raise this again on \(Self.day(until)).", confirm: nil)
            }
        }
    }

    private var creatorOrder: Binding<CreatorOrder> {
        Binding { store.creatorOrder } set: { store.creatorOrder = $0 }
    }

    /// Turning it on starts checking today's videos; off hides the button at once (S11).
    private var skipAd: Binding<Bool> {
        Binding { store.ads.isOn } set: { on in
            store.ads.isOn = on
            if on { store.ads.check(store.engine.state.home.map(\.video)) }
        }
    }

    private var fridayIsWeekend: Binding<Bool> {
        Binding {
            store.engine.settings.fridayIsWeekend
        } set: { on in
            switch store.evaluateFridayIsWeekend(on) {
            case .apply:
                store.setFridayIsWeekend(on)
            case .confirm(let lockUntil):
                prompt = Prompt(
                    title: "Count Friday as weekend?",
                    message: "Fridays get your weekend minutes. You can't turn this on again until \(Self.day(lockUntil)) if you switch it off. Starts the next time new videos arrive.",
                    confirm: { store.setFridayIsWeekend(on, lockUntil: lockUntil) }
                )
            case .locked(let until):
                prompt = Prompt(title: "Not yet", message: "You can change this again on \(Self.day(until)).", confirm: nil)
            }
        }
    }

    private var shipmentHour: Binding<Int> {
        Binding {
            store.engine.settings.shipmentHour
        } set: { hour in
            switch store.evaluateShipmentHour(hour) {
            case .apply:
                break
            case .confirm(let lockUntil):
                prompt = Prompt(
                    title: "Get new videos at \(Self.hourLabel(hour))?",
                    message: "You can change this again on \(Self.day(lockUntil)). Starts the next time new videos arrive.",
                    confirm: { store.setShipmentHour(hour, lockUntil: lockUntil) }
                )
            case .locked(let until):
                prompt = Prompt(title: "Not yet", message: "You can change when new videos arrive again on \(Self.day(until)).", confirm: nil)
            }
        }
    }

    /// One footer for the whole box; lock dates appear only while something is locked.
    private var footerText: String {
        let locks: [(Date?, String)] = [
            (store.lockedUntil(.weekdayBudget), "raise weekdays"),
            (store.lockedUntil(.weekendBudget), "raise weekends"),
            (store.engine.settings.fridayLockedUntil, "add Friday"),
            (store.engine.settings.shipmentHourLockedUntil, "move when new videos arrive"),
            (store.lockedUntil(.refreshesPerDay), "raise refreshes"),
        ]
        let notes = locks.compactMap { date, what in
            date.flatMap { $0 > .now ? "Can \(what) again on \(Self.day($0))." : nil }
        }
        return (["Each limit can be loosened once a week. Changes start the next time new videos arrive."] + notes).joined(separator: " ")
    }

    // MARK: - Formatting

    static func hourLabel(_ hour: Int) -> String {
        let date = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: .now)!
        return date.formatted(date: .omitted, time: .shortened)
    }

    static func day(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day())
    }

    static var versionLine: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "KJ Tube \(version) (\(build))"
    }
}
