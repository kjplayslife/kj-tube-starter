import Foundation
import SwiftData
import Testing
@testable import KJTube

/// Following spec AC3–AC10 at the store level (in-memory SwiftData, fake YouTube).
@MainActor
struct AppStoreTests {
    let container: ModelContainer
    let a = channel("UCaaaaaaaaaaaaaaaaaaaaaa", "Alpha")
    let b = channel("UCbbbbbbbbbbbbbbbbbbbbbb", "Beta")
    let c = channel("UCcccccccccccccccccccccc", "Gamma")

    init() throws {
        container = try ModelContainer(
            for: Creator.self, EngineRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    func makeStore(_ api: FakeYouTubeAPI? = nil) -> AppStore {
        var fake = api ?? FakeYouTubeAPI()
        if api == nil {
            for ch in [a, b, c] {
                fake.channelsByID[ch.id] = ch
                fake.uploads[ch.id] = (1...5).map { details("\(ch.title)\($0)", channel: ch.id, daysAgo: $0) }
            }
        }
        return AppStore(context: container.mainContext, api: fake)
    }

    @Test("AC3: following adds the creator at the bottom and their latest video to the backlog (D79)")
    func followAddsAtBottom() async {
        let store = makeStore()
        await store.follow(a)
        await store.follow(b)
        #expect(store.creators().map(\.title) == ["Alpha", "Beta"])
        #expect(store.creators().allSatisfy { $0.loadState == .ready })
        #expect(store.engine.state.backlog.map(\.id) == ["Alpha1", "Beta1"])
        #expect(store.engine.creatorRank == [a.id, b.id])
    }

    @Test("AC4: a channel can't be followed twice")
    func noDuplicates() async {
        let store = makeStore()
        await store.follow(a)
        await store.follow(a)
        #expect(store.creators().count == 1)
        #expect(store.engine.state.backlog.count == 1)
    }

    @Test("AC5: reordering changes rank and survives a relaunch")
    func reorderPersists() async {
        let store = makeStore()
        for ch in [a, b, c] { await store.follow(ch) }
        store.moveCreators(fromOffsets: [2], toOffset: 0)
        #expect(store.creators().map(\.title) == ["Gamma", "Alpha", "Beta"])

        let relaunched = makeStore()
        #expect(relaunched.creators().map(\.title) == ["Gamma", "Alpha", "Beta"])
        #expect(relaunched.engine.creatorRank == [c.id, a.id, b.id])
    }

    @Test("AC6: unfollow removes the creator and their backlog; Undo restores both in place")
    func unfollowUndo() async throws {
        let store = makeStore()
        for ch in [a, b, c] { await store.follow(ch) }
        let beta = try #require(store.creators().first { $0.title == "Beta" })
        store.unfollow(beta)
        #expect(store.creators().map(\.title) == ["Alpha", "Gamma"])
        #expect(!store.engine.state.backlog.contains { $0.creatorID == b.id })

        store.undoUnfollow()
        #expect(store.creators().map(\.title) == ["Alpha", "Beta", "Gamma"])
        #expect(store.engine.state.backlog.filter { $0.creatorID == b.id }.count == 1)
        #expect(store.lastUnfollow == nil)
    }

    @Test("W7: Watch in Order is off by default and survives a relaunch")
    func inOrderPersists() async throws {
        let store = makeStore()
        for ch in [a, b] { await store.follow(ch) }
        let beta = try #require(store.creators().first { $0.title == "Beta" })
        #expect(!store.isInOrder(beta))
        store.setInOrder(true, for: beta)

        let relaunched = makeStore()
        let again = try #require(relaunched.creators().first { $0.title == "Beta" })
        #expect(relaunched.isInOrder(again))
        #expect(relaunched.engine.state.inOrderCreators == [b.id])
    }

    @Test("W8: Undo after unfollowing brings Watch in Order back; a later follow starts with it off")
    func inOrderUndo() async throws {
        let store = makeStore()
        for ch in [a, b] { await store.follow(ch) }
        var beta = try #require(store.creators().first { $0.title == "Beta" })
        store.setInOrder(true, for: beta)
        store.unfollow(beta)
        #expect(!store.engine.isInOrder(b.id))

        store.undoUnfollow()
        beta = try #require(store.creators().first { $0.title == "Beta" })
        #expect(store.isInOrder(beta))

        store.unfollow(beta)
        store.clearUndo()
        await store.follow(b)
        #expect(!store.engine.isInOrder(b.id))
    }

    @Test("L7: Any Length is off by default, survives a relaunch, and comes back with Undo")
    func anyLengthPersists() async throws {
        let store = makeStore()
        for ch in [a, b] { await store.follow(ch) }
        var beta = try #require(store.creators().first { $0.title == "Beta" })
        #expect(!store.isAnyLength(beta))
        store.setAnyLength(true, for: beta)

        let relaunched = makeStore()
        beta = try #require(relaunched.creators().first { $0.title == "Beta" })
        #expect(relaunched.isAnyLength(beta))

        relaunched.unfollow(beta)
        #expect(!relaunched.engine.isAnyLength(b.id))
        relaunched.undoUnfollow()
        #expect(relaunched.engine.isAnyLength(b.id))

        beta = try #require(relaunched.creators().first { $0.title == "Beta" })
        relaunched.unfollow(beta)
        relaunched.clearUndo()
        await relaunched.follow(b)
        #expect(!relaunched.engine.isAnyLength(b.id))
    }

    @Test("AC7: Ranked/Random survives a relaunch")
    func orderPersists() {
        let store = makeStore()
        store.creatorOrder = .random
        #expect(makeStore().creatorOrder == .random)
    }

    @Test("AC9: following while offline keeps the creator and marks it for retry")
    func offlineFollow() async {
        var api = FakeYouTubeAPI()
        api.failWith = .offline
        let store = makeStore(api)
        await store.follow(a)
        #expect(store.creators().first?.loadState == .failed)
        #expect(store.engine.state.backlog.isEmpty)
    }

    @Test("AC10: following mid-day doesn't change today's Home list")
    func followKeepsHome() async {
        let store = makeStore()
        await store.follow(a)
        let home = store.engine.state.home
        await store.follow(b)
        #expect(store.engine.state.home == home)
    }

    @Test("Backlog survives a relaunch")
    func backlogPersists() async {
        let store = makeStore()
        await store.follow(a)
        #expect(makeStore().engine.state.backlog.count == 1)
    }
}
