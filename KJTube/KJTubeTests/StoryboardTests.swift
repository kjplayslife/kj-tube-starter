import Foundation
import Testing
@testable import KJTube

/// Seek-bar preview pictures (D134).
@MainActor
struct StoryboardTests {
    /// The shape of a real spec from YouTube (signatures shortened).
    static let spec = "https://i.ytimg.com/sb/abc/storyboard3_L$L/$N.jpg?sqp=-oaymwGh"
        + "|48#27#100#10#10#0#default#rs$A0"
        + "|80#45#108#10#10#2000#M$M#rs$A1"
        + "|160#90#108#5#5#2000#M$M#rs$A2"
        + "|320#180#108#3#3#2000#M$M#rs$A3"

    @Test func picksTheSharpestSize() throws {
        let board = try #require(Storyboard(spec: Self.spec, duration: 213))
        #expect(board.level.index == 3)
        #expect(board.level.width == 320)
        #expect(board.level.sheets == 12)
        #expect(board.sheetURLs.count == 12)
    }

    @Test func findsTheFrameForATime() throws {
        let board = try #require(Storyboard(spec: Self.spec, duration: 213))
        // 2 s apart, 3 × 3 a sheet: 41 s is frame 20, the third frame on sheet 2.
        let tile = try #require(board.tile(at: 41))
        #expect(tile.sheet.absoluteString == "https://i.ytimg.com/sb/abc/storyboard3_L3/M2.jpg?sqp=-oaymwGh&sigh=rs$A3")
        #expect(tile.rect == CGRect(x: 640, y: 0, width: 320, height: 180))
        // Past either end stays inside the video: 213 s is frame 106.
        #expect(board.frameIndex(at: -5) == 0)
        #expect(board.frameIndex(at: 9999) == 106)
    }

    @Test func evenlySpreadFramesWhenThereIsNoInterval() throws {
        let board = try #require(Storyboard(spec: "https://i.ytimg.com/sb/abc/storyboard3_L$L/$N.jpg?sqp=x|48#27#100#10#10#0#default#rs$A0", duration: 200))
        #expect(board.frameIndex(at: 100) == 50)
        #expect(board.tile(at: 100)?.sheet.absoluteString == "https://i.ytimg.com/sb/abc/storyboard3_L0/default.jpg?sqp=x&sigh=rs$A0")
    }

    @Test func aLongVideoUsesASmallerSizeToKeepDownloadsDown() throws {
        // 900 frames: 100 sheets at the sharpest size, 36 at the one below.
        let spec = "https://i.ytimg.com/sb/abc/storyboard3_L$L/$N.jpg?sqp=x|160#90#900#5#5#10000#M$M#rs$A0|320#180#900#3#3#10000#M$M#rs$A1"
        let board = try #require(Storyboard(spec: spec, duration: 9000))
        #expect(board.level.index == 0)
    }

    @Test func aSpecThatChangedShapeGivesNoPreview() {
        #expect(Storyboard(spec: "", duration: 100) == nil)
        #expect(Storyboard(spec: "nonsense", duration: 100) == nil)
        #expect(Storyboard(spec: "https://i.ytimg.com/x|oops", duration: 100) == nil)
        #expect(Storyboard(spec: Self.spec, duration: 0) == nil)
    }
}
