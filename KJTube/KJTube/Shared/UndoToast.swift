import SwiftUI

/// "Unfollowed Veritasium · Undo" bar that disappears after 5 seconds.
struct UndoToast: View {
    static var duration: Duration {
        #if DEBUG
        // `-undoSeconds 60` keeps it up longer for Simulator testing.
        let override = UserDefaults.standard.integer(forKey: "undoSeconds")
        if override > 0 { return .seconds(override) }
        #endif
        return .seconds(5)
    }

    let message: String
    let onUndo: () -> Void
    let onExpire: () -> Void

    var body: some View {
        HStack {
            Text(message)
                .lineLimit(1)
            Spacer()
            Button("Undo", action: onUndo)
                .fontWeight(.semibold)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        // Solid, so a newer one fully covers the last. One shade lighter than the page's cards,
        // like the good-news bar, so it stands out on every page (D187).
        .floatingBackground(.capsule)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .task(id: message) {
            try? await Task.sleep(for: Self.duration)
            if !Task.isCancelled { onExpire() }
        }
    }
}

extension View {
    /// Floats an Undo bar above the tab bar, over the content, so the list never jumps (D81).
    /// A new one (different `id`) slides up and covers the last one, which then fades out.
    func undoToast(id: String?, message: String, onUndo: @escaping () -> Void, onExpire: @escaping () -> Void) -> some View {
        modifier(UndoToastHost(id: id, message: message, onUndo: onUndo, onExpire: onExpire))
    }
}

private struct UndoToastHost: ViewModifier {
    let id: String?
    let message: String
    let onUndo: () -> Void
    let onExpire: () -> Void
    /// Bumped for each new toast so it stacks above the one fading out.
    @State private var layer = 0.0

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                ZStack {
                    if let id {
                        UndoToast(message: message, onUndo: onUndo, onExpire: onExpire)
                            .id(id)
                            .zIndex(layer)
                            .transition(.asymmetric(
                                insertion: .move(edge: .bottom).combined(with: .opacity),
                                removal: .opacity.animation(.easeOut(duration: 0.2).delay(0.25))
                            ))
                    }
                }
                .animation(.snappy, value: id)
            }
            .onChange(of: id) { layer += 1 }
    }
}

extension View {
    /// A short good-news bar in the same spot and style as the Undo bar, with a green tick and
    /// no button. It leaves on a tap, or by itself after 5 seconds (D158).
    func noticeToast(_ message: String?, onExpire: @escaping () -> Void) -> some View {
        overlay(alignment: .bottom) {
            ZStack {
                if let message {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text(message)
                            .lineLimit(2)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    // One shade lighter than the page's cards, so it stands out; a tap sends it away (D158).
                    .floatingBackground(.capsule)
                    .contentShape(.capsule)
                    .onTapGesture(perform: onExpire)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task(id: message) {
                        try? await Task.sleep(for: UndoToast.duration)
                        if !Task.isCancelled { onExpire() }
                    }
                }
            }
            .animation(.snappy, value: message)
        }
    }
}
