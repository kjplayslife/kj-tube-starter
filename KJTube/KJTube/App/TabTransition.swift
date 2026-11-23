import SwiftUI
import UIKit

/// How switching tabs looks (D83). iOS's own cross-fade showed both pages through each other for a
/// few frames, so the old page always disappears at once and only the new one moves.
enum TabTransitionStyle: String {
    /// Pages slide left or right, following the tab order (KJ's pick).
    case slide
    /// The new page fades in while rising a few points, like the YouTube app.
    case rise
    /// No animation.
    case none

    static var current: TabTransitionStyle {
        #if DEBUG
        // `-tabTransition slide` tries another style in the Simulator.
        if let raw = UserDefaults.standard.string(forKey: "tabTransition"), let style = Self(rawValue: raw) {
            return style
        }
        #endif
        return .slide
    }
}

extension View {
    /// Put on the content of each tab inside a `TabView`. `position` is where this tab sits in the
    /// tab bar, counting from 0 at the left, out of `total` tabs.
    func customTabTransition(position: Int, of total: Int) -> some View {
        background(TabControllerFinder(position: position, total: total))
    }
}

/// Which way a tab switch slides (D83). Kept apart from UIKit so it can be unit-tested.
enum TabSlideDirection {
    /// `true` when the tab being opened sits to the right of the one being left, `nil` when that
    /// can't be told. `from` and `to` are positions in the tab bar, when known. `known` holds the
    /// positions of the tabs whose pages have been seen so far, out of `total` tabs.
    ///
    /// A tab opened for the first time has no known position yet. It must be one of the positions
    /// not seen so far, and when those all lie on one side of `from` the answer is still certain.
    static func isForward(from: Int?, to: Int?, known: Set<Int>, total: Int) -> Bool? {
        if let from, let to { return from == to ? nil : to > from }
        guard let from, to == nil else { return nil }
        let unseen = (0..<total).filter { !known.contains($0) && $0 != from }
        guard !unseen.isEmpty else { return nil }
        if unseen.allSatisfy({ $0 > from }) { return true }
        if unseen.allSatisfy({ $0 < from }) { return false }
        return nil
    }
}

/// Where each tab's page sits in the tab bar, as told by our own `TabView` (D206). On some iOS
/// versions the tab bar controller's own list of pages comes back empty, and going by it alone
/// made every switch slide as if it were going left.
@MainActor
enum TabPagePositions {
    private static let table = NSMapTable<UIViewController, NSNumber>.weakToStrongObjects()
    private(set) static var total = 0

    static func set(_ position: Int, of total: Int, for page: UIViewController) {
        table.setObject(NSNumber(value: position), forKey: page)
        self.total = max(self.total, total)
    }

    static func position(of page: UIViewController) -> Int? {
        table.object(forKey: page)?.intValue
    }

    static var known: Set<Int> {
        Set((table.objectEnumerator()?.allObjects as? [NSNumber] ?? []).map(\.intValue))
    }
}

/// Finds the `UITabBarController` behind SwiftUI's `TabView` and wraps its delegate to supply our
/// transition. Everything else is forwarded to SwiftUI's own delegate.
private struct TabControllerFinder: UIViewControllerRepresentable {
    let position: Int
    let total: Int

    func makeUIViewController(context: Context) -> Probe { Probe() }

    func updateUIViewController(_ probe: Probe, context: Context) {
        probe.position = position
        probe.total = total
        probe.install()
    }

    final class Probe: UIViewController {
        var position = 0
        var total = 0

        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            install()
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            install()
        }

        func install() {
            guard let tabs = tabBarController else { return }
            if total > 0, let page = page(under: tabs) {
                TabPagePositions.set(position, of: total, for: page)
            }
            if tabs.delegate is TabTransitionDelegate { return }
            tabs.delegate = TabTransitionDelegate.wrapping(tabs.delegate)
        }

        /// This tab's page: the controller directly under the tab bar controller, which is the one
        /// iOS hands to the transition.
        private func page(under tabs: UITabBarController) -> UIViewController? {
            var current: UIViewController? = self
            while let controller = current {
                if controller.parent === tabs { return controller }
                current = controller.parent
            }
            return nil
        }
    }
}

private final class TabTransitionDelegate: NSObject, UITabBarControllerDelegate {
    private var original: UITabBarControllerDelegate?
    /// Keeps the proxy alive: `UITabBarController.delegate` is weak.
    private static var current: TabTransitionDelegate?

    static func wrapping(_ original: UITabBarControllerDelegate?) -> TabTransitionDelegate {
        let proxy = TabTransitionDelegate()
        proxy.original = original
        current = proxy
        return proxy
    }

    func tabBarController(
        _ tabBarController: UITabBarController,
        animationControllerForTransitionFrom fromVC: UIViewController,
        to toVC: UIViewController
    ) -> UIViewControllerAnimatedTransitioning? {
        // Our own record of the tab order comes first; iOS's list is the fallback (D206).
        let controllers = tabBarController.viewControllers ?? []
        let position = { (page: UIViewController) in
            TabPagePositions.position(of: page) ?? controllers.firstIndex(of: page)
        }
        let forward = TabSlideDirection.isForward(
            from: position(fromVC), to: position(toVC),
            known: TabPagePositions.known, total: max(TabPagePositions.total, controllers.count)
        ) ?? false
        return TabAnimator(style: .current, forward: forward)
    }

    override func responds(to selector: Selector!) -> Bool {
        super.responds(to: selector) || (original?.responds(to: selector) ?? false)
    }

    override func forwardingTarget(for selector: Selector!) -> Any? {
        original?.responds(to: selector) == true ? original : super.forwardingTarget(for: selector)
    }
}

private final class TabAnimator: NSObject, UIViewControllerAnimatedTransitioning {
    let style: TabTransitionStyle
    /// Moving to a tab further right.
    let forward: Bool

    init(style: TabTransitionStyle, forward: Bool) {
        self.style = style
        self.forward = forward
    }

    func transitionDuration(using context: UIViewControllerContextTransitioning?) -> TimeInterval {
        switch style {
        case .rise: 0.22
        case .slide: 0.3
        case .none: 0
        }
    }

    /// The animation still playing from the last switch. Jumped to its end when another tab is picked.
    private static var running: UIViewPropertyAnimator?

    /// The switch itself completes at once and only the picture keeps moving, so a tab tapped (or
    /// swiped to) mid-animation takes on the first try instead of being dropped by UIKit.
    func animateTransition(using context: UIViewControllerContextTransitioning) {
        Self.running?.stopAnimation(false)
        Self.running?.finishAnimation(at: .end)
        Self.running = nil

        guard let toVC = context.viewController(forKey: .to), let to = context.view(forKey: .to) else {
            context.completeTransition(!context.transitionWasCancelled)
            return
        }
        let container = context.containerView
        let from = context.view(forKey: .from)
        let frame = context.finalFrame(for: toVC)
        to.frame = frame
        to.transform = .identity
        to.accessibilityElementsHidden = false
        container.addSubview(to)

        // The page being left stays loaded, out of sight under the new one. Taken out and put
        // back, iOS draws its glass (the search bar on Following) a shade too dark over the
        // rows behind it and corrects it about 0.3 s later, every time the tab opens (D198).
        let park = {
            guard let from, from !== to, from.superview == nil else { return }
            from.transform = .identity
            from.frame = frame
            from.accessibilityElementsHidden = true // VoiceOver reads only the page on top
            container.insertSubview(from, at: 0)
        }
        let animator: UIViewPropertyAnimator?
        switch style {
        case .none:
            animator = nil
            from?.removeFromSuperview()
            park()
        case .rise:
            // The old page goes at once, so the two never show through each other.
            from?.removeFromSuperview()
            to.alpha = 0
            to.transform = CGAffineTransform(translationX: 0, y: 14)
            let rise = UIViewPropertyAnimator(duration: transitionDuration(using: context), curve: .easeOut) {
                to.alpha = 1
                to.transform = .identity
            }
            rise.addCompletion { _ in
                to.alpha = 1
                to.transform = .identity
                park()
            }
            animator = rise
        case .slide:
            // Slide a picture of the old page: the live one's images lag behind its text when moved.
            let snapshot = from?.snapshotView(afterScreenUpdates: false)
            if let snapshot {
                snapshot.frame = from?.frame ?? frame
                snapshot.isUserInteractionEnabled = false
                container.insertSubview(snapshot, belowSubview: to)
            }
            from?.removeFromSuperview()
            let width = frame.width * (forward ? 1 : -1)
            to.transform = CGAffineTransform(translationX: width, y: 0)
            let slide = UIViewPropertyAnimator(duration: transitionDuration(using: context), dampingRatio: 1) {
                to.transform = .identity
                snapshot?.transform = CGAffineTransform(translationX: -width, y: 0)
            }
            slide.addCompletion { _ in
                to.transform = .identity
                snapshot?.removeFromSuperview()
                park()
            }
            animator = slide
        }
        from?.transform = .identity
        context.completeTransition(!context.transitionWasCancelled)
        if let animator {
            animator.isUserInteractionEnabled = true
            Self.running = animator
            animator.addCompletion { _ in
                if Self.running === animator { Self.running = nil }
            }
            animator.startAnimation()
        }
    }
}
