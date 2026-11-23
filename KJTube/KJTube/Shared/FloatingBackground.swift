import SwiftUI

/// The solid background of a bar that floats over a page: the undo bar, the good-news bar, the
/// first-run bar. In dark mode it is one shade lighter than the page's cards. In light mode that
/// shade is white, the same as the page, so a soft shadow sets it apart instead (D224).
private struct FloatingBackground<S: Shape>: ViewModifier {
    let shape: S
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content.background {
            shape.fill(Color(.tertiarySystemBackground))
                .shadow(color: .black.opacity(colorScheme == .light ? 0.16 : 0), radius: 10, y: 3)
        }
    }
}

extension View {
    func floatingBackground(_ shape: some Shape) -> some View {
        modifier(FloatingBackground(shape: shape))
    }
}
