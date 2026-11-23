import Testing
@testable import KJTube

/// Which way a tab switch slides (D83, D206): right-hand tabs come in from the right.
struct TabSlideDirectionTests {
    @Test func bothPositionsKnown() {
        #expect(TabSlideDirection.isForward(from: 0, to: 1, known: [0, 1, 2], total: 3) == true)
        #expect(TabSlideDirection.isForward(from: 1, to: 2, known: [0, 1, 2], total: 3) == true)
        #expect(TabSlideDirection.isForward(from: 0, to: 2, known: [0, 2], total: 3) == true)
        #expect(TabSlideDirection.isForward(from: 2, to: 1, known: [0, 1, 2], total: 3) == false)
        #expect(TabSlideDirection.isForward(from: 1, to: 0, known: [0, 1, 2], total: 3) == false)
        #expect(TabSlideDirection.isForward(from: 2, to: 0, known: [0, 2], total: 3) == false)
    }

    /// The bug a friend of KJ's saw: with nothing known, every switch slid as if going left.
    /// A tab opened for the first time is still placed by what has been seen so far.
    @Test func firstVisitToATab() {
        // From Inbox (leftmost), any tab not seen yet is to the right.
        #expect(TabSlideDirection.isForward(from: 0, to: nil, known: [0], total: 3) == true)
        // From Following, with Inbox seen, the only tab left is Settings, to the right.
        #expect(TabSlideDirection.isForward(from: 1, to: nil, known: [0, 1], total: 3) == true)
        // From Settings (rightmost), with Inbox seen, the only tab left is Following, to the left.
        #expect(TabSlideDirection.isForward(from: 2, to: nil, known: [0, 2], total: 3) == false)
        // From Settings with nothing else seen, every other tab is to the left.
        #expect(TabSlideDirection.isForward(from: 2, to: nil, known: [2], total: 3) == false)
    }

    @Test func cannotTell() {
        // From the middle tab with both neighbors unseen: could be either side.
        #expect(TabSlideDirection.isForward(from: 1, to: nil, known: [1], total: 3) == nil)
        // The tab being left is unknown.
        #expect(TabSlideDirection.isForward(from: nil, to: 2, known: [2], total: 3) == nil)
        #expect(TabSlideDirection.isForward(from: nil, to: nil, known: [], total: 3) == nil)
        // Same tab, or every tab already seen yet the target is unknown.
        #expect(TabSlideDirection.isForward(from: 1, to: 1, known: [0, 1, 2], total: 3) == nil)
        #expect(TabSlideDirection.isForward(from: 0, to: nil, known: [0, 1, 2], total: 3) == nil)
    }
}
