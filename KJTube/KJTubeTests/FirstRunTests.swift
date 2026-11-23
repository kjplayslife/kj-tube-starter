import Foundation
import SwiftData
import Testing
@testable import KJTube

/// docs/specs/first-run.md
@MainActor
struct FirstRunTests {
    let container = try! ModelContainer(
        for: Creator.self, EngineRecord.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )

    func api(_ channels: ChannelSummary...) -> FakeYouTubeAPI {
        var fake = FakeYouTubeAPI()
        for ch in channels {
            fake.channelsByID[ch.id] = ch
            fake.uploads[ch.id] = [details("\(ch.title)1", channel: ch.id, daysAgo: 1)]
        }
        return fake
    }

    func newStore(_ fake: FakeYouTubeAPI) -> AppStore {
        AppStore(context: container.mainContext, api: fake, calendar: testCalendar, firstRun: true)
    }

    // MARK: - Steps and words

    @Test("The step comes from what is saved")
    func steps() {
        #expect(FirstRun.step(done: false, hasCreators: false) == .welcome)
        #expect(FirstRun.step(done: false, hasCreators: true) == .setup)
        #expect(FirstRun.step(done: true, hasCreators: false) == .done)
        #expect(FirstRun.step(done: true, hasCreators: true) == .done)
    }

    @Test("AC6: the check names the minutes, the count, the top three and the switches")
    func summary() {
        let many = FirstRun.summary(
            weekdayMinutes: 30, weekendMinutes: 60, creators: ["A", "B", "C", "D"], ranked: true,
            inOrder: ["B"], anyLength: ["C", "D"]
        )
        #expect(many.amount == "30 min on weekdays, 60 on weekends.")
        #expect(many.creators == "4 creators. First up: A, B, C.")
        #expect(many.switches == ["Watch in Order: B.", "Any Length: C, D."])

        let few = FirstRun.summary(weekdayMinutes: 60, weekendMinutes: 90, creators: ["A"], ranked: true, inOrder: [], anyLength: [])
        #expect(few.creators == "1 creator: A.")
        #expect(few.amount == "60 min on weekdays, 90 on weekends.")
        let friday = FirstRun.summary(weekdayMinutes: 30, weekendMinutes: 60, fridayIsWeekend: true, creators: ["A"], ranked: true, inOrder: [], anyLength: [])
        #expect(friday.amount == "30 min on weekdays, 60 on weekends. Friday counts as weekend.")
        #expect(few.switches.isEmpty)

        let random = FirstRun.summary(weekdayMinutes: 30, weekendMinutes: 60, creators: ["A", "B"], ranked: false, inOrder: [], anyLength: [])
        #expect(random.creators == "2 creators, newest videos first.")
    }

    @Test("The Following bar leaves out ranking in Random order")
    func barText() {
        #expect(FirstRun.barText(ranked: true).hasPrefix("Hold and drag to rank."))
        #expect(!FirstRun.barText(ranked: false).contains("rank"))
    }

    // MARK: - The gate

    @Test("The engine serves nothing during first run")
    func engineGate() {
        var engine = makeEngine(backlog: [video("v1", minutes: 10)])
        engine.state.firstRunDone = false
        engine.shipNow(at: date(10, 26, 9))
        #expect(engine.state.home.isEmpty)
        engine.state.firstRunDone = true
        engine.shipNow(at: date(10, 26, 9))
        #expect(engine.homeIDs == ["v1"])
    }

    @Test("AC1, AC4, AC8, AC9: a new install waits for Load my Inbox, then serves by the current rank")
    func holdsFirstInbox() async {
        let (a, b) = (channel("UCa", "A"), channel("UCb", "B"))
        let store = newStore(api(a, b))
        #expect(store.firstRunStep == .welcome)

        await store.follow([a, b])
        #expect(store.firstRunStep == .setup)
        store.applyShipmentsIfChecked()
        store.applyShipments()
        #expect(store.engine.state.home.isEmpty)

        store.moveCreators(fromOffsets: [1], toOffset: 0) // B first
        store.finishFirstRun()
        #expect(store.firstRunStep == .done)
        #expect(store.engine.state.home.map(\.id) == ["B1", "A1"])

        // Still done after a relaunch.
        #expect(newStore(api(a, b)).firstRunStep == .done)
    }

    @Test("AC11: quitting part way comes back to the same step")
    func resumes() async {
        let a = channel("UCa", "A")
        let store = newStore(api(a))
        await store.follow(a)
        store.firstRunAmountShown()
        let relaunched = newStore(api(a))
        #expect(relaunched.firstRunStep == .setup)
        #expect(relaunched.engine.state.firstRunAmountPicked == true)
        #expect(relaunched.engine.state.home.isEmpty)
    }

    @Test("Unfollowing everyone during first run goes back to the welcome")
    func backToWelcome() async {
        let a = channel("UCa", "A")
        let store = newStore(api(a))
        await store.follow(a)
        store.unfollow(store.creators()[0])
        #expect(store.firstRunStep == .welcome)
    }

    @Test("AC10: an install already in use never sees first run")
    func existingInstall() async {
        let a = channel("UCa", "A")
        let old = AppStore(context: container.mainContext, api: api(a), calendar: testCalendar)
        await old.follow(a)
        let updated = newStore(api(a))
        #expect(updated.firstRunStep == .done)
        updated.applyShipments()
        #expect(updated.engine.state.home.map(\.id) == ["A1"])
    }

    @Test("AC2, AC7: Load my Inbox asks the amount first if it wasn't picked, then the check")
    func pages() async {
        let a = channel("UCa", "A")
        let store = newStore(api(a))
        await store.follow(a)
        store.askToLoadInbox()
        #expect(store.firstRunPage == .amount(thenCheck: true))
        store.firstRunAmountShown()
        store.askToLoadInbox()
        #expect(store.firstRunPage == .check)
        // After an import the amount is asked once, and not again once it was shown.
        store.firstRunPage = nil
        store.askAmountAfterImport()
        #expect(store.firstRunPage == nil)
    }

    @Test("AC3, AC12: minutes picked in first run set no lock; a raise afterwards is confirmed")
    func noLock() async {
        let a = channel("UCa", "A")
        let store = newStore(api(a))
        await store.follow(a)
        store.set(.weekdayBudget, to: 90)
        #expect(store.value(of: .weekdayBudget) == 90)
        #expect(store.lockedUntil(.weekdayBudget) == nil)
        store.setFridayIsWeekend(true)
        #expect(store.engine.settings.fridayIsWeekend)
        #expect(store.engine.settings.fridayLockedUntil == nil)
        #expect(store.firstRunSummary().amount.hasSuffix("Friday counts as weekend."))
        store.set(.weekdayBudget, to: 60)
        store.finishFirstRun()
        if case .confirm = store.evaluate(.weekdayBudget, to: 90) {} else { Issue.record("a raise should ask first") }
    }
}
