import SwiftUI

/// A followed creator. Tapping does nothing (D25): rows are only for reordering and unfollowing.
struct CreatorRow: View {
    let creator: Creator
    /// Shown faintly in Ranked mode; nil in Random mode.
    let rank: Int?
    /// "Watch in Order" is on (D150).
    var inOrder = false
    /// "Any Length" is on (D151).
    var anyLength = false
    /// The small icons beside the name were tapped (D174).
    var onTagsTap: () -> Void = {}

    var body: some View {
        HStack(spacing: 12) {
            if let rank {
                Text("\(rank)")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .frame(width: 20)
            }
            Avatar(url: creator.avatarURL, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(creator.title)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                    // Small icons beside the name, not words on the date line (D172).
                    if inOrder || anyLength {
                        // Tap the icons (or near them) for a reminder of what they mean (D174).
                        HStack(spacing: 6) {
                            if inOrder { icon(.inOrder) }
                            if anyLength { icon(.anyLength) }
                        }
                        .padding(12)
                        .contentShape(.rect)
                        .onTapGesture { onTagsTap() }
                        .padding(-12)
                        .accessibilityAddTraits(.isButton)
                    }
                }
                .imageScale(.small)
                .font(.footnote.weight(.semibold))
                status
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if rank != nil {
                Spacer(minLength: 8)
                // Only a hint: long-press the row to drag it (rank order only matters in Ranked).
                Image(systemName: "line.3.horizontal")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 2)
    }

    private func icon(_ kind: CreatorSwitch) -> some View {
        Image(systemName: kind.icon)
            .foregroundStyle(kind.tint)
            .accessibilityLabel(kind.title)
    }

    @ViewBuilder
    private var status: some View {
        switch creator.loadState {
        case .loading:
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text("Finding videos…")
            }
        case .noEligible:
            Text("No eligible videos yet")
        case .failed:
            Text("Couldn't load videos. Will retry.")
        case .ready:
            if let date = creator.lastUploadAt {
                Text("Last upload \(date, format: .relative(presentation: .named))")
            } else {
                Text(creator.handle ?? "")
            }
        }
    }
}

/// The two per-creator switches (D150, D151): how each looks on Following (D172) and the words
/// shown the first time it is turned on (D173).
enum CreatorSwitch: String, CaseIterable, Identifiable {
    case inOrder, anyLength

    var id: String { rawValue }

    var title: String {
        switch self {
        case .inOrder: "Watch in Order"
        case .anyLength: "Any Length"
        }
    }

    /// On the swipe button, where there is little room.
    var shortTitle: String {
        switch self {
        case .inOrder: "In Order"
        case .anyLength: "Any Length"
        }
    }

    var icon: String {
        switch self {
        case .inOrder: "list.number"
        case .anyLength: "hourglass"
        }
    }

    /// The swipe button and the row's icon share one color: the system colors Apple Notes
    /// uses on its own swipe buttons (D190).
    var tint: Color {
        switch self {
        case .inOrder: .blue
        case .anyLength: .indigo // Apple Notes' Move purple; Unfollow is Notes' Delete red (D190)
        }
    }

    /// What it does, and which creators it is for. Shown once, before the first turn-on.
    var explainer: String {
        switch self {
        case .inOrder:
            "This creator's waiting videos come oldest first.\n\nUse it for creators who post a series, where each video follows the last."
        case .anyLength:
            "This creator's videos are never too long for your day. A long one comes only when it is first in line, and it is the only new video that day.\n\nUse it for creators whose long videos you don't want to miss."
        }
    }

    /// One line on what it does, for the reminder shown when a row's icons are tapped (D174).
    var reminder: String {
        switch self {
        case .inOrder: "Watch in Order: this creator's waiting videos come oldest first."
        case .anyLength: "Any Length: this creator's videos are never too long for your day."
        }
    }

    /// Where "the explainer was read" is saved.
    var explainedKey: String { "\(rawValue)Explained" }
}

/// A channel in search results, with its Follow button.
struct ChannelResultRow: View {
    let channel: ChannelSummary
    let isFollowing: Bool
    let onFollow: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Avatar(url: channel.avatarURL, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(channel.title)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if isFollowing {
                Label("Following", systemImage: "checkmark")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
            } else {
                Button("Follow", action: onFollow)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
    }

    private var subtitle: String {
        let subscribers = channel.subscriberCount.map {
            "\($0.formatted(.number.notation(.compactName))) subscribers"
        }
        return [channel.handle, subscribers].compactMap(\.self).joined(separator: " · ")
    }
}

struct Avatar: View {
    let url: URL?
    let size: CGFloat

    var body: some View {
        CachedImage(url: url)
            .background(Color.secondary.opacity(0.2))
            .frame(width: size, height: size)
        .clipShape(.circle)
    }
}
