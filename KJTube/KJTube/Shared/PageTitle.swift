import SwiftUI

extension View {
    /// The big top-left page title on every tab (D71), drawn in the top bar itself so it sits
    /// higher than iOS's own large title, which leaves an empty bar above it (D72).
    /// `hidden` keeps the title invisible (while the search bar is in use). When it comes back it
    /// fades in as the search bar slides down under it, instead of popping in on top of the bar.
    func pageTitle(_ title: String, hidden: Bool = false) -> some View {
        navigationTitle(title) // still names the screen for VoiceOver
            .toolbarTitleDisplayMode(.inline)
            .toolbar(removing: .title)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Text(title)
                        .font(.largeTitle.weight(.bold))
                        .lineLimit(1)
                        .dynamicTypeSize(...DynamicTypeSize.xLarge) // has to fit in the bar
                        .fixedSize()
                        .accessibilityAddTraits(.isHeader)
                        .opacity(hidden ? 0 : 1)
                        .animation(hidden ? nil : .easeIn(duration: 0.22).delay(0.12), value: hidden)
                }
                .sharedBackgroundVisibility(.hidden)
            }
    }
}
