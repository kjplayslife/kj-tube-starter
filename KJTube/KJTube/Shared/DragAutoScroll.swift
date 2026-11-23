import SwiftUI
import UIKit

extension View {
    /// While a List row is being dragged to reorder, scrolls the list when the row is anywhere in a
    /// tall band near its top or bottom edge. iOS only scrolls inside a thin strip right under the
    /// search bar, so reaching #1 in a long list took a precise hold (D84). Put it on the `List`.
    ///
    /// `onDropAboveList` runs when the row is let go above the list, over the title or the search
    /// bar. iOS alone throws that drop away and the row flies back to where it started. It gets
    /// the row's place in the list when it was picked up (D221). `onDropLanded` runs once the
    /// card has glided to the top of the list. Nothing else about the drag changes.
    func dragAutoScroll(onDropAboveList: @escaping (_ from: Int) -> Void = { _ in },
                        onDropLanded: @escaping () -> Void = {}) -> some View {
        background(DragAutoScrollProbe(onDropAboveList: onDropAboveList, onDropLanded: onDropLanded))
    }
}

private struct DragAutoScrollProbe: UIViewRepresentable {
    let onDropAboveList: (Int) -> Void
    let onDropLanded: () -> Void

    func makeUIView(context: Context) -> ProbeView { ProbeView() }
    func updateUIView(_ view: ProbeView, context: Context) {
        view.onDropAboveList = onDropAboveList
        view.onDropLanded = onDropLanded
    }

    final class ProbeView: UIView, UIDropInteractionDelegate {
        var onDropAboveList: (Int) -> Void = { _ in }
        var onDropLanded: () -> Void = {}
        /// Catches the drag while it is off the list: the list's own catcher only sees it over
        /// the list. On the window, so it covers the title and the search bar (D221).
        private lazy var outside = UIDropInteraction(delegate: self)
        private weak var outsideHost: UIView?
        /// The dragged row's place in the list when it was picked up.
        private var lifted: Int?
        private var link: CADisplayLink?
        private weak var list: UICollectionView?
        /// Whether the gap was last seen in the list's top half, to keep going once the row leaves it.
        private var lastGapInTopHalf: Bool?
        /// How far into the list from each edge the band reaches.
        private static let band: CGFloat = 170

        override func didMoveToWindow() {
            super.didMoveToWindow()
            link?.invalidate()
            link = nil
            outsideHost?.removeInteraction(outside)
            outsideHost = nil
            guard let window else { return }
            window.addInteraction(outside)
            outsideHost = window
            link = CADisplayLink(target: self, selector: #selector(step))
            link?.add(to: .main, forMode: .common)
        }

        @objc private func step(_ link: CADisplayLink) {
            if list == nil { list = findList() }
            // iOS takes the finger away from the app once a drag lifts, so follow the gap the list
            // opens for the dragged row instead: it sits where the row would drop, under the finger.
            guard let list, list.hasActiveDrag, let window else {
                lastGapInTopHalf = nil
                lifted = nil
                return
            }
            if lifted == nil {
                // iOS doesn't say which row is being dragged, but it hides that row's cell (the
                // gap) or, while the finger is off the list, dims it.
                let marked = list.visibleCells.first { $0.isHidden || $0.alpha < 0.99 }
                lifted = marked.flatMap { list.indexPath(for: $0)?.item }
            }
            var speed: CGFloat = 0 // points per second; negative scrolls up
            if let gap = list.visibleCells.first(where: \.isHidden) {
                let y = gap.convert(CGPoint(x: gap.bounds.midX, y: gap.bounds.midY), to: window).y
                let frame = list.convert(list.bounds, to: window)
                let top = frame.minY + list.adjustedContentInset.top
                let bottom = frame.maxY - list.adjustedContentInset.bottom
                lastGapInTopHalf = y < (top + bottom) / 2
                if y < top + Self.band {
                    speed = -Self.speed(depth: (top + Self.band - y) / Self.band)
                } else if y > bottom - Self.band {
                    speed = Self.speed(depth: (y - (bottom - Self.band)) / Self.band)
                }
            } else {
                // The row was dragged off the list (over the search bar or tab bar), so the list
                // closed its gap. The finger is past that edge: keep going that way at full speed.
                if let up = lastGapInTopHalf { speed = (up ? -1 : 1) * Self.speed(depth: 1.5) }
            }
            guard speed != 0 else { return }
            let minY = -list.adjustedContentInset.top
            let maxY = max(minY, list.contentSize.height + list.adjustedContentInset.bottom - list.bounds.height)
            let offset = min(max(list.contentOffset.y + speed * CGFloat(link.duration), minY), maxY)
            if offset != list.contentOffset.y { list.contentOffset.y = offset }
        }

        // MARK: Let go above the list (D221)

        /// Where the list's rows start showing, top to bottom in the window: under the search bar.
        private var listTop: CGFloat? {
            guard let list, let window else { return nil }
            return list.convert(list.bounds, to: window).minY + list.adjustedContentInset.top
        }

        private func isAboveList(_ session: UIDropSession) -> Bool {
            guard let window, let listTop else { return false }
            return session.location(in: window).y < listTop
        }

        func dropInteraction(_ interaction: UIDropInteraction, canHandle session: UIDropSession) -> Bool {
            list?.hasActiveDrag == true // only this list's own rows
        }

        /// Above the list the drop is taken; anywhere else iOS carries on as before.
        func dropInteraction(_ interaction: UIDropInteraction, sessionDidUpdate session: UIDropSession) -> UIDropProposal {
            UIDropProposal(operation: isAboveList(session) && lifted != nil ? .move : .cancel)
        }

        func dropInteraction(_ interaction: UIDropInteraction, performDrop session: UIDropSession) {
            guard isAboveList(session), let from = lifted else { return }
            onDropAboveList(from)
        }

        /// The card glides onto the first row's spot, where its row is headed, instead of
        /// fading out under the finger.
        func dropInteraction(_ interaction: UIDropInteraction, previewForDropping item: UIDragItem,
                             withDefault defaultPreview: UITargetedDragPreview) -> UITargetedDragPreview? {
            guard let list, let window, let listTop else { return nil }
            var center = CGPoint(x: list.convert(list.bounds, to: window).midX, y: listTop + defaultPreview.size.height / 2)
            if let first = list.indexPathsForVisibleItems.filter({ $0.item == 0 }).min(), let cell = list.cellForItem(at: first) {
                center = cell.convert(CGPoint(x: cell.bounds.midX, y: cell.bounds.midY), to: window)
            }
            return defaultPreview.retargetedPreview(with: UIDragPreviewTarget(container: window, center: center))
        }

        func dropInteraction(_ interaction: UIDropInteraction, item: UIDragItem, willAnimateDropWith animator: any UIDragAnimating) {
            animator.addCompletion { [weak self] _ in self?.onDropLanded() }
        }

        /// Steady at the band's inner edge, faster closer to the screen edge.
        private static func speed(depth: CGFloat) -> CGFloat {
            let d = min(max(depth, 0), 1.5)
            return 220 + 700 * d * d
        }

        /// The List's collection view: the nearest one that shares an ancestor with this probe.
        private func findList() -> UICollectionView? {
            var node: UIView? = superview
            while let current = node {
                if let found = Self.firstCollectionView(in: current) { return found }
                node = current.superview
            }
            return nil
        }

        private static func firstCollectionView(in view: UIView) -> UICollectionView? {
            if let collection = view as? UICollectionView { return collection }
            for sub in view.subviews {
                if let found = firstCollectionView(in: sub) { return found }
            }
            return nil
        }
    }
}
