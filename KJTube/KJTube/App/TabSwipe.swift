import SwiftUI
import UIKit

extension View {
    /// Swipe sideways anywhere on a page to move to the next or previous tab, in tab-bar order (D89).
    /// Swipes that start on a control (a slider, a switch) are left alone. Put it on the content of
    /// each tab inside a `TabView` that should have it (not Following, D93).
    func tabSwipe(_ selection: Binding<AppTab>, order: [AppTab]) -> some View {
        background(TabSwipeProbe(selection: selection, order: order))
    }
}

private struct TabSwipeProbe: UIViewRepresentable {
    let selection: Binding<AppTab>
    let order: [AppTab]

    func makeUIView(context: Context) -> ProbeView { ProbeView() }

    func updateUIView(_ view: ProbeView, context: Context) {
        view.move = { step in
            guard let index = order.firstIndex(of: selection.wrappedValue) else { return }
            let next = index + step
            guard order.indices.contains(next) else { return }
            selection.wrappedValue = order[next]
        }
    }

    /// Adds left and right swipe recognizers to the page this probe sits in.
    final class ProbeView: UIView, UIGestureRecognizerDelegate {
        var move: ((Int) -> Void)?
        private var installed: UIView?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil, let page = pageView(), page !== installed else { return }
            installed = page
            for direction in [UISwipeGestureRecognizer.Direction.left, .right] {
                let swipe = UISwipeGestureRecognizer(target: self, action: #selector(swiped))
                swipe.direction = direction
                swipe.cancelsTouchesInView = true
                swipe.delegate = self
                page.addGestureRecognizer(swipe)
            }
        }

        /// The tab's root view: the view of the controller just below the tab bar controller.
        private func pageView() -> UIView? {
            var responder: UIResponder? = self
            while let current = responder {
                if let controller = current as? UIViewController, controller.parent is UITabBarController {
                    return controller.view
                }
                responder = current.next
            }
            return nil
        }

        @objc private func swiped(_ swipe: UISwipeGestureRecognizer) {
            // Finger moving left shows the page to the right, like turning a page.
            move?(swipe.direction == .left ? 1 : -1)
        }

        func gestureRecognizer(_ g: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            var view = touch.view
            while let current = view {
                if current is UIControl || current is UISlider { return false }
                view = current.superview
            }
            return true
        }

        /// Only alongside scrolling. Any other gesture (a card's tap) is cancelled once the swipe is
        /// recognized, so a swipe across a card doesn't also open it.
        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            other is UIPanGestureRecognizer
        }

        /// A card's tap waits for the swipe to fail (it fails as soon as the finger lifts without
        /// sliding), so a tap still opens the card at once and a swipe never does.
        func gestureRecognizer(_ g: UIGestureRecognizer, shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
            !(other is UIPanGestureRecognizer) && !(other is UISwipeGestureRecognizer)
        }
    }
}
