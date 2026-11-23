import SwiftUI

/// Full-width YouTube-style card (D32): rounded thumbnail with duration badge and white
/// progress bar, then the creator's avatar, title, "Creator · 59K views · 2d ago", and on the
/// right either a ⋯ menu (Inbox) or up/down arrows (the player's list) (D69).
struct VideoCard: View {
    /// What sits on the right of the card. A nil move action means it can't move that way.
    enum Trailing {
        case menu(moveUp: (() -> Void)?, moveDown: (() -> Void)?, swap: () -> Void, remove: () -> Void)
        case arrows(moveUp: (() -> Void)?, moveDown: (() -> Void)?)
    }

    @Environment(\.dynamicTypeSize) private var typeSize
    let entry: HomeEntry
    let creator: String
    let avatarURL: URL?
    let views: Int?
    let trailing: Trailing
    @State private var confirmingRemove = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            thumbnail
            HStack(alignment: .top, spacing: 12) {
                Avatar(url: avatarURL, size: 36)
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.video.title)
                        .font(.body.weight(.medium))
                        .lineLimit(typeSize.isAccessibilitySize ? 4 : 2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(meta)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
                }
                Spacer(minLength: 0)
                trailingControls
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 20)
        .contentShape(.rect) // blank space (beside the title, under the thumbnail) is tappable too
        .alert("Remove this video?", isPresented: $confirmingRemove) {
            Button("Remove", role: .destructive) {
                if case .menu(_, _, _, let remove) = trailing { remove() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("It won't be shown again, and you won't get another video in its place.")
        }
    }

    @ViewBuilder
    private var trailingControls: some View {
        switch trailing {
        case .menu(let moveUp, let moveDown, let swap, _):
            Menu {
                Button("Move up", systemImage: "arrow.up") { moveUp?() }
                    .disabled(moveUp == nil)
                Button("Move down", systemImage: "arrow.down") { moveDown?() }
                    .disabled(moveDown == nil)
                Divider()
                Button("Swap this video", systemImage: "arrow.triangle.2.circlepath") { swap() }
                Button("Remove video", systemImage: "trash", role: .destructive) { confirmingRemove = true }
            } label: {
                // Color and size live on the label itself, so the dots keep their look and place
                // while the menu opens and closes (no tint flash, no jump).
                Image(systemName: "ellipsis")
                    .foregroundStyle(Color.primary)
                    .frame(width: 32, height: 32)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .frame(width: 32, height: 32)
            .padding(.top, -6)
        case .arrows(let moveUp, let moveDown):
            // The only video in the list has nowhere to go: no arrows (D139).
            if moveUp != nil || moveDown != nil {
                VStack(spacing: 0) {
                    arrow("chevron.up", "Move up", moveUp)
                    arrow("chevron.down", "Move down", moveDown)
                }
                .padding(.top, -8)
            }
        }
    }

    private func arrow(_ icon: String, _ label: String, _ action: (() -> Void)?) -> some View {
        Button(label, systemImage: icon) { action?() }
            .labelStyle(.iconOnly)
            .font(.body.weight(.semibold))
            .frame(width: 40, height: 36)
            .contentShape(.rect)
            .buttonStyle(.borderless) // its own tap target inside a tappable list row
            // Gray, so they're there but not a main thing; fainter when there's nowhere to move (D139).
            .foregroundStyle(.secondary)
            .opacity(action == nil ? 0.35 : 1)
            .disabled(action == nil)
    }

    private var meta: String {
        [creator, views.map { "\(Format.views($0)) views" }, Format.age(entry.video.publishedAt)]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    private var thumbnail: some View {
        Color.secondary.opacity(0.15)
            .aspectRatio(16 / 9, contentMode: .fit)
            .overlay {
                CachedImage(urls: Thumbnail.urls(entry.video.id))
            }
            // Where the picture sits on screen, so the player can open from there (D138).
            // Kept outside SwiftUI state: scrolling must not redraw the card.
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { [id = entry.video.id] top in
                CardOrigins.top[id] = top
            }
            .overlay(alignment: .bottomTrailing) {
                Text(Format.clock(entry.video.duration))
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge) // a badge, not body text
                    .foregroundStyle(.white) // on a dark badge in light mode too (D223)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(.black.opacity(0.75), in: .rect(cornerRadius: 4))
                    .padding(8)
                    // Always room for the progress line, so the badge never jumps when it comes and goes (D100).
                    .padding(.bottom, 3)
            }
            .overlay(alignment: .bottomLeading) {
                if entry.progress > 0 {
                    // Scaled, not measured with a GeometryReader: cheaper while scrolling.
                    Rectangle()
                        .fill(.white)
                        .frame(height: 3)
                        .scaleEffect(x: min(entry.progress / max(entry.video.duration, 1), 1), anchor: .leading)
                }
            }
            .clipShape(.rect(cornerRadius: 12))
    }
}

/// Screen position (top edge) of each Inbox card's picture, by video ID. The player starts its
/// opening slide from the tapped card's picture, like YouTube (D138).
@MainActor
enum CardOrigins {
    static var top: [String: CGFloat] = [:]
}
