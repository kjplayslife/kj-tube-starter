import SwiftUI
import Testing
@testable import KJTube

/// Where the small player lands when it is let go (D186).
struct MiniSpotTests {
    let b = MiniSpot.Bounds(leftX: -200, topY: 8, bottomY: 600, width: 180, height: 100)

    @Test("Let go without a flick: the nearest of the four corners")
    func nearestCorner() {
        #expect(MiniSpot(x: -30, y: 500).landing(flick: .zero, in: b) == .corner(x: 0, y: 600))
        #expect(MiniSpot(x: -150, y: 500).landing(flick: .zero, in: b) == .corner(x: -200, y: 600))
        #expect(MiniSpot(x: -30, y: 100).landing(flick: .zero, in: b) == .corner(x: 0, y: 8))
        #expect(MiniSpot(x: -150, y: 100).landing(flick: .zero, in: b) == .corner(x: -200, y: 8))
    }

    @Test("A flick carries it to the corner it was thrown at")
    func flickToCorner() {
        let spot = MiniSpot(x: -20, y: 580)
        #expect(spot.landing(flick: CGSize(width: -300, height: 0), in: b) == .corner(x: -200, y: 600))
        #expect(spot.landing(flick: CGSize(width: 0, height: -500), in: b) == .corner(x: 0, y: 8))
        #expect(spot.landing(flick: CGSize(width: -300, height: -500), in: b) == .corner(x: -200, y: 8))
    }

    @Test("A hard flick from one corner toward another never closes it")
    func hardFlickAcrossStays() {
        #expect(MiniSpot(x: -60, y: 600).landing(flick: CGSize(width: -2000, height: 0), in: b) == .corner(x: -200, y: 600))
        #expect(MiniSpot(x: 0, y: 400).landing(flick: CGSize(width: 0, height: -3000), in: b) == .corner(x: 0, y: 8))
    }

    @Test("Pushed out past an edge far enough, or a little with a flick, it slides off that edge")
    func slidesOff() {
        #expect(MiniSpot(x: 80, y: 600).landing(flick: .zero, in: b) == .off(.trailing))
        #expect(MiniSpot(x: 20, y: 600).landing(flick: CGSize(width: 400, height: 0), in: b) == .off(.trailing))
        #expect(MiniSpot(x: -220, y: 8).landing(flick: CGSize(width: -400, height: 0), in: b) == .off(.leading))
        #expect(MiniSpot(x: 0, y: 650).landing(flick: .zero, in: b) == .off(.bottom))
        #expect(MiniSpot(x: -200, y: -10).landing(flick: CGSize(width: 0, height: -300), in: b) == .off(.top))
    }

    @Test("A small push past the edge with no flick springs back to the corner")
    func smallPushSpringsBack() {
        #expect(MiniSpot(x: 30, y: 610).landing(flick: .zero, in: b) == .corner(x: 0, y: 600))
    }
}
