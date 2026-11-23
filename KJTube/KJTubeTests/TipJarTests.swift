import StoreKitTest
import Testing
@testable import KJTube

/// The tip jar's sheet, with a fake store standing in for Apple (docs/specs/tip-jar.md).
@MainActor
struct TipJarTests {
    final class FakeStore: TipStore {
        var tips: [Tip] = TipJar.productIDs(bundleID: "app").map { Tip(id: $0, name: TipJar.name(for: $0), price: "$1") }
        var loadFails = false
        var outcome: TipOutcome = .thanks
        var loads = 0
        var bought: [String] = []
        /// Lets a test look at the sheet while Apple's payment sheet is "up".
        var duringPurchase: (() async -> Void)?

        func tips(ids: [String]) async throws -> [Tip] {
            loads += 1
            if loadFails { throw URLError(.notConnectedToInternet) }
            return ids.compactMap { id in tips.first { $0.id == id } }
        }

        func buy(_ id: String) async -> TipOutcome {
            bought.append(id)
            await duringPurchase?()
            return outcome
        }
    }

    private func model(_ store: FakeStore) -> TipJarModel {
        TipJarModel(store: store, ids: TipJar.productIDs(bundleID: "app"))
    }

    // T12
    @Test func eachAppAsksForItsOwnTips() {
        #expect(TipJar.productIDs(bundleID: "com.example.kjtube") == [
            "com.example.kjtube.tip.small", "com.example.kjtube.tip.medium", "com.example.kjtube.tip.large",
        ])
        #expect(TipJar.productIDs(bundleID: "com.example.kjtube.public") == [
            "com.example.kjtube.public.tip.small", "com.example.kjtube.public.tip.medium",
            "com.example.kjtube.public.tip.large",
        ])
    }

    // T2
    @Test func threeTipsSmallestFirstWithTheirNames() async {
        let store = FakeStore()
        store.tips.reverse() // Apple can answer in any order
        let model = model(store)
        await model.load()
        #expect(model.phase == .ready(failed: false))
        #expect(model.tips.map(\.name) == ["Small coffee", "Big coffee", "Coffee and a snack"])
    }

    // T11
    @Test func nothingIsAskedOfTheStoreUntilTheSheetOpens() async {
        let store = FakeStore()
        let model = model(store)
        #expect(store.loads == 0)
        #expect(model.phase == .loading)
        await model.load()
        await model.load()
        #expect(store.loads == 1)
    }

    // T3, T4
    @Test func aTipSaysThanksAndASecondOneWorks() async {
        let store = FakeStore()
        let first = model(store)
        await first.load()
        await first.buy(first.tips[0])
        #expect(first.phase == .thanks)
        #expect(first.closesSoon)

        let again = model(store) // the sheet opened again
        await again.load()
        #expect(again.tips.count == 3)
        await again.buy(again.tips[0])
        #expect(again.phase == .thanks)
        #expect(store.bought.count == 2)
    }

    // T5
    @Test func cancelIsQuiet() async {
        let store = FakeStore()
        store.outcome = .cancelled
        let model = model(store)
        await model.load()
        await model.buy(model.tips[1])
        #expect(model.phase == .ready(failed: false))
        #expect(!model.closesSoon)
    }

    // T6
    @Test func aFailedTipSaysSoAndTheButtonsWorkAgain() async {
        let store = FakeStore()
        store.outcome = .failed
        let model = model(store)
        await model.load()
        await model.buy(model.tips[2])
        #expect(model.phase == .ready(failed: true))
        store.outcome = .thanks
        await model.buy(model.tips[2])
        #expect(model.phase == .thanks)
    }

    // T7
    @Test func noTipsWhenTheStoreCantBeReachedOrHasNone() async {
        let offline = FakeStore()
        offline.loadFails = true
        let first = model(offline)
        await first.load()
        #expect(first.phase == .unavailable)

        let empty = FakeStore()
        empty.tips = []
        let second = model(empty)
        await second.load()
        #expect(second.phase == .unavailable)
    }

    // T8
    @Test func buttonsAreLockedWhileBuying() async {
        let store = FakeStore()
        let model = model(store)
        await model.load()
        store.duringPurchase = {
            #expect(model.phase == .buying)
            await model.buy(model.tips[1]) // a second tap does nothing
        }
        await model.buy(model.tips[0])
        #expect(store.bought.count == 1)
    }

    // T9
    @Test func askToBuyWaitsAndCloses() async {
        let store = FakeStore()
        store.outcome = .waitingForApproval
        let model = model(store)
        await model.load()
        await model.buy(model.tips[0])
        #expect(model.phase == .waitingForApproval)
        #expect(model.closesSoon)
    }
}

/// The same sheet against Apple's real StoreKit code, with the local test store in
/// `Tips.storekit` (no network, no money).
///
/// Xcode's test store doesn't start from the command line on the iOS 26.5 Simulator (Apple bug
/// FB22237318: "Error saving configuration file", SKInternalErrorDomain 3), so until Apple fixes
/// it these run for real only from Xcode and are logged as a known issue by `scripts/sim.sh`.
@MainActor
@Suite(.serialized)
struct TipJarStoreKitTests {
    private static let bug: Comment = "Xcode's StoreKit test store doesn't start from the command line on iOS 26.5 (FB22237318)"

    private func session() throws -> SKTestSession {
        let session = try SKTestSession(configurationFileNamed: "Tips")
        session.disableDialogs = true
        session.clearTransactions()
        return session
    }

    /// True only when the local test store answered. `Tips.storekit` holds one product Apple's
    /// real store has never heard of; if it doesn't load, the app is talking to Apple's real
    /// test servers, and these tests must not go on (a "buy" there waits for a sign-in forever).
    private func localStoreIsRunning() async -> Bool {
        let marker = (try? await Product.products(for: ["local.test.store.marker"])) ?? []
        if marker.isEmpty { withKnownIssue(Self.bug) { Issue.record("local test store not running") } }
        return !marker.isEmpty
    }

    @Test func bothAppsTipsLoadWithApplesPrices() async throws {
        _ = try session()
        guard await localStoreIsRunning() else { return }
        do {
            for app in ["com.example.kjtube", "com.example.kjtube.public"] {
                let tips = try await AppleTipStore().tips(ids: TipJar.productIDs(bundleID: app))
                #expect(tips.map(\.price) == ["$1.99", "$4.99", "$9.99"])
                #expect(tips.map(\.name) == ["Small coffee", "Big coffee", "Coffee and a snack"])
            }
        }
    }

    @Test func kjTubeDevHasNoTips() async throws {
        _ = try session()
        guard await localStoreIsRunning() else { return }
        let model = TipJarModel(ids: TipJar.productIDs(bundleID: "com.example.kjtube.dev"))
        await model.load()
        #expect(model.phase == .unavailable)
    }

    @Test func aRealTipGoesThroughTwice() async throws {
        let session = try session()
        guard await localStoreIsRunning() else { return }
        do {
            for count in 1...2 { // the sheet opened, a tip bought; then once more (T4)
                let model = TipJarModel(ids: TipJar.productIDs(bundleID: "com.example.kjtube"))
                await model.load()
                try #require(model.tips.count == 3)
                await model.buy(model.tips[0])
                #expect(model.phase == .thanks)
                #expect(session.allTransactions().count == count)
            }
        }
    }

    @Test func aFailedPurchaseShowsTheFailureLine() async throws {
        let session = try session()
        guard await localStoreIsRunning() else { return }
        do {
            try await session.setSimulatedError(.generic(.networkError(URLError(.notConnectedToInternet))), forAPI: .purchase)
            let model = TipJarModel(ids: TipJar.productIDs(bundleID: "com.example.kjtube.public"))
            await model.load()
            try #require(model.tips.count == 3)
            await model.buy(model.tips[1])
            #expect(model.phase == .ready(failed: true))
            #expect(session.allTransactions().isEmpty)
        }
    }
}
