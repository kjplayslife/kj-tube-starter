import CoreGraphics
import Foundation
import Testing
@testable import KJTube

struct BackgroundRefreshTests {
    @Test("Wakes 30 minutes before the next shipment")
    func thirtyMinutesEarly() {
        let engine = makeEngine(lastShipment: date(10, 27, 6))
        #expect(engine.backgroundRefreshDate(after: date(10, 27, 12)) == date(10, 28, 5, 30))
    }

    @Test("Never schedules in the past (inside the last 30 minutes)")
    func notInPast() {
        let engine = makeEngine(lastShipment: date(10, 27, 6))
        #expect(engine.backgroundRefreshDate(after: date(10, 28, 5, 45)) == date(10, 28, 5, 45))
    }

    @Test("Works across the DST change")
    func dst() {
        let engine = makeEngine(lastShipment: date(10, 31, 6))
        #expect(engine.backgroundRefreshDate(after: date(10, 31, 20)) == date(11, 1, 5, 30))
    }

    @Test("Prefetch targets what the next shipment would pick")
    func upcomingPick() {
        let engine = makeEngine(backlog: [video("a", minutes: 20), video("b", minutes: 15), video("c", minutes: 10)])
        #expect(engine.upcomingPick(at: date(10, 28, 6)).map(\.id) == ["a", "b"])
    }
}

struct AdCornerTests {
    let video = CGRect(x: 0, y: 0, width: 402, height: 226)

    @Test("Taps in the bottom-right 96 × 56 pt pass through to YouTube (D51)")
    func corner() {
        #expect(AdCorner.passesThrough(CGPoint(x: 395, y: 220), in: video))
        #expect(AdCorner.passesThrough(CGPoint(x: 310, y: 175), in: video))
    }

    @Test("Everywhere else stays covered")
    func elsewhere() {
        #expect(!AdCorner.passesThrough(CGPoint(x: 300, y: 220), in: video)) // just left of the corner
        #expect(!AdCorner.passesThrough(CGPoint(x: 395, y: 160), in: video)) // just above it
        #expect(!AdCorner.passesThrough(CGPoint(x: 200, y: 113), in: video))
    }

    @Test("The touch-layer shape leaves a hole exactly at the corner (even-odd)")
    func shapeHole() {
        let path = TouchLayerShape().path(in: video).cgPath
        #expect(!path.contains(CGPoint(x: 395, y: 220), using: .evenOdd))
        #expect(path.contains(CGPoint(x: 200, y: 113), using: .evenOdd))
    }
}
