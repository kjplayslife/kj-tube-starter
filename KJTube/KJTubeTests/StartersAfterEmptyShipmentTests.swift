import Foundation
import Testing
@testable import KJTube

/// D92: a new follow brings its latest video until something has been served. A first follow
/// whose only video is too old must not end that: nothing was served, so the next follows
/// still bring theirs. (Found while staging App Store screenshots: the Inbox stayed empty.)
struct StartersAfterEmptyShipmentTests {
    let day = date(10, 27, 7) // Tuesday, 30-min budget

    @Test("An old first starter expires without being served, and later follows still bring starters")
    func oldStarterDoesNotEndStarters() {
        var engine = makeEngine(rank: ["A", "B"])
        engine.addStarters([video("a-old", creator: "A", minutes: 15, published: date(9, 1))])
        engine.shipNow(at: day)
        #expect(engine.homeIDs.isEmpty) // too old to serve (D8)
        #expect(engine.wantsStarters)   // nothing has been served yet
        engine.addStarters([video("b", creator: "B", minutes: 15, published: date(10, 26))])
        engine.shipNow(at: day)
        #expect(engine.homeIDs == ["b"])
    }

    @Test("The old starter does not come back")
    func oldStarterStaysOut() {
        var engine = makeEngine(rank: ["A"])
        let old = video("a-old", creator: "A", minutes: 15, published: date(9, 1))
        engine.addStarters([old])
        engine.shipNow(at: day)
        engine.addStarters([old])
        engine.shipNow(at: day)
        #expect(engine.homeIDs.isEmpty)
    }

    @Test("A new upload that expires unwatched is still SEEN, as before")
    func expiredUploadsAreStillSeen() {
        var engine = makeEngine(rank: ["A"])
        engine.addNewUploads([video("a-old", creator: "A", minutes: 15, published: date(9, 1))])
        engine.shipNow(at: day)
        #expect(engine.state.seen.contains("a-old"))
    }

    @Test("Once a video has been served, a new follow brings no starter, as before")
    func afterServingNoStarters() {
        var engine = makeEngine(rank: ["A", "B"])
        engine.addStarters([video("a", creator: "A", minutes: 30, published: date(10, 26))])
        engine.shipNow(at: day)
        #expect(engine.homeIDs == ["a"])
        #expect(!engine.wantsStarters)
    }
}
