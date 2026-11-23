import SwiftUI

/// Where the small player is, and where it goes when the finger lets go (D186). `x` runs from
/// `leftX` (left corners) to 0 (right corners); `y` from `topY` to `bottomY`.
struct MiniSpot: Equatable {
    var x: CGFloat
    var y: CGFloat

    struct Bounds {
        let leftX: CGFloat
        let topY: CGFloat
        let bottomY: CGFloat
        /// The small player's own size.
        let width: CGFloat
        let height: CGFloat
    }

    enum Landing: Equatable {
        case corner(x: CGFloat, y: CGFloat)
        /// Slides off the screen past this edge and closes.
        case off(Edge)
    }

    /// `flick` is how much farther the drag would carry on by itself.
    ///
    /// It closes only when it has been pushed out past the corners (so toward the screen's
    /// edge), either 40% of its size or a little with a flick on top. A hard flick from one
    /// corner toward another never closes it: it is still between the corners when let go.
    func landing(flick: CGSize, in b: Bounds) -> Landing {
        // How far past the corners it is now, on each side.
        let out: [(edge: Edge, now: CGFloat, flick: CGFloat, size: CGFloat)] = [
            (.trailing, x, flick.width, b.width),
            (.leading, b.leftX - x, -flick.width, b.width),
            (.bottom, y - b.bottomY, flick.height, b.height),
            (.top, b.topY - y, -flick.height, b.height),
        ]
        let leaving = out
            .filter { $0.now > $0.size * 0.4 || ($0.now > 8 && $0.now + $0.flick > $0.size) }
            .max { $0.now / $0.size < $1.now / $1.size }
        if let leaving { return .off(leaving.edge) }
        // Otherwise the nearest corner to where the flick would carry it.
        let endX = x + flick.width
        let endY = y + flick.height
        return .corner(x: endX < b.leftX / 2 ? b.leftX : 0,
                       y: endY < (b.topY + b.bottomY) / 2 ? b.topY : b.bottomY)
    }
}
