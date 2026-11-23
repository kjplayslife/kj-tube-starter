import SwiftUI

/// The bottom-right corner of the video passes taps through to YouTube so "Skip ad" works (D51).
/// Everywhere else our touch layer keeps YouTube's links out of reach.
enum AdCorner {
    static let size = CGSize(width: 96, height: 56)

    static func rect(in bounds: CGRect) -> CGRect {
        CGRect(x: bounds.maxX - size.width, y: bounds.maxY - size.height, width: size.width, height: size.height)
    }

    static func passesThrough(_ point: CGPoint, in bounds: CGRect) -> Bool {
        rect(in: bounds).contains(point)
    }
}

/// A rectangle with the ad corner cut out, used as a hit-test shape.
struct TouchLayerShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        path.addRect(AdCorner.rect(in: rect))
        return path
    }
}
