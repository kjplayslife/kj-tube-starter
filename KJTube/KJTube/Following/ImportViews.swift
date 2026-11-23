import AuthenticationServices
import SwiftData
import SwiftUI

/// Starts the import: Google sign-in, then the pick list (docs/specs/import-subscriptions.md).
/// Shown only when the build has a Google client ID (AC1). The sign-in is used once and then
/// dropped: nothing about the Google account is saved (D154).
struct ImportButton<Label: View>: View {
    @Environment(\.webAuthenticationSession) private var webAuth
    @State private var model: ImportModel?
    @State private var signingIn = false
    @State private var signInFailed = false
    @ViewBuilder let label: () -> Label

    var body: some View {
        if let clientID = AppConfig.googleClientID {
            // Not grayed out while Google's page opens: a second tap is ignored in `start`.
            Button { start(clientID) } label: { label() }
                .sheet(item: $model) { ImportSheet(model: $0) }
                .alert("Couldn't sign in to Google.", isPresented: $signInFailed) {
                    Button("Try again") { start(clientID) }
                    Button("Cancel", role: .cancel) {}
                }
        }
    }

    private func start(_ clientID: String) {
        guard !signingIn else { return }
        signingIn = true
        Task {
            defer { signingIn = false }
            let signIn = GoogleSignIn(clientID: clientID)
            let callback: URL
            do {
                callback = try await webAuth.authenticate(
                    using: signIn.signInURL, callback: .customScheme(signIn.callbackScheme), additionalHeaderFields: [:]
                )
            } catch {
                // Closing the sheet is not an error (AC2).
                if (error as? ASWebAuthenticationSessionError)?.code != .canceledLogin { signInFailed = true }
                return
            }
            do {
                let token = try await signIn.accessToken(callback: callback)
                model = ImportModel(loader: .live(accessToken: token))
            } catch {
                signInFailed = true
            }
        }
    }
}

/// The pick list: tick the creators to bring over, then Follow.
struct ImportSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Query private var creators: [Creator]
    @Bindable var model: ImportModel

    var body: some View {
        let following = Set(creators.map(\.channelID))
        let picks = model.pickedChannels(alreadyFollowing: following)
        NavigationStack {
            content(following: following)
                .navigationTitle("Pick creators")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    // A round tick with "All" at the top right: ticks everyone, then unticks everyone (D156).
                    ToolbarItem(placement: .topBarTrailing) {
                        let allPicked = model.allVisiblePicked(alreadyFollowing: following)
                        Button {
                            if allPicked {
                                model.deselectAllVisible()
                            } else {
                                model.selectAllVisible(alreadyFollowing: following)
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: allPicked ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(allPicked ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                                Text("All")
                            }
                        }
                        .disabled(model.phase != .loaded || model.visible.allSatisfy { following.contains($0.id) })
                        .accessibilityLabel(allPicked ? "Deselect all" : "Select all")
                    }
                }
                // Blue Continue at the bottom right, once at least one creator is ticked (D157).
                // It floats over the list and only fades, so the list never jumps when it comes or goes.
                .overlay(alignment: .bottomTrailing) {
                    Button(picks.isEmpty ? "Continue" : "Continue (\(picks.count))") {
                        dismiss()
                        store.importedCount = picks.count // opens Following with a success note (D158)
                        Task { await store.follow(picks) }
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .fontWeight(.semibold)
                    .padding(.trailing, 20)
                    .padding(.bottom, 12)
                    // Gone while the search box has text: a tick is already kept, and Continue there
                    // looked like it was needed to save that one creator. Clearing the search brings
                    // it back (D175).
                    .opacity(showsContinue(picks) ? 1 : 0)
                    .allowsHitTesting(showsContinue(picks))
                    .animation(.easeOut(duration: 0.15), value: showsContinue(picks))
                }
        }
        // Scrolling back to the top kept pulling the whole list closed. Cancel closes it (D160).
        .interactiveDismissDisabled()
        .sensoryFeedback(.selection, trigger: model.picked)
        .task { if model.phase == .loading { await model.load() } }
    }

    private func showsContinue(_ picks: [ChannelSummary]) -> Bool {
        !picks.isEmpty && model.filter.trimmingCharacters(in: .whitespaces).isEmpty
    }

    @ViewBuilder
    private func content(following: Set<String>) -> some View {
        switch model.phase {
        case .loading:
            VStack(spacing: 12) {
                ProgressView()
                Text("Getting your subscriptions…")
                    .foregroundStyle(.secondary)
            }
        case .failed(let error):
            VStack(spacing: 12) {
                Text(message(for: error))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                if error != .quotaExceeded {
                    Button("Retry") { Task { await model.load() } }
                        .buttonStyle(.bordered)
                }
            }
            .padding()
        case .loaded where model.channels.isEmpty:
            Text("No subscriptions found on this account.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding()
        case .loaded:
            List {
                ForEach(model.visible) { channel in
                    ImportRow(channel: channel, isFollowing: following.contains(channel.id), isPicked: model.isPicked(channel)) {
                        model.toggle(channel)
                    }
                }
            }
            .listStyle(.plain)
            .contentMargins(.bottom, 80, for: .scrollContent) // the last rows can scroll clear of Continue
            .searchable(text: $model.filter, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search your subscriptions")
            .autocorrectionDisabled()
        }
    }

    private func message(for error: YouTubeError) -> String {
        switch error {
        case .offline: "You're offline. Importing needs the internet."
        case .quotaExceeded: "YouTube is resting until tomorrow."
        default: "YouTube didn't answer. Try again."
        }
    }
}

private struct ImportRow: View {
    let channel: ChannelSummary
    let isFollowing: Bool
    let isPicked: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Avatar(url: channel.avatarURL, size: 44)
                Text(channel.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if isFollowing {
                    // Plain text and icon, not a Label: a Label moved the divider under itself.
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark")
                        Text("Following")
                    }
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
                } else {
                    Image(systemName: isPicked ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundStyle(isPicked ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        // Not `.disabled`: that grayed out the name and picture too.
        .allowsHitTesting(!isFollowing)
        // Every divider starts under the name, the same on all rows.
        .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] + 56 }
        .accessibilityAddTraits(isPicked ? .isSelected : [])
    }
}
