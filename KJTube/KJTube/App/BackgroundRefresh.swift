import BackgroundTasks
import Foundation

/// Wakes the app ~30 min before shipment time so the shipment is ready the moment it opens
/// (speed-and-polish ⚙︎). iOS decides the exact time; opening the app still catches up.
enum BackgroundRefresh {
    static let identifier = "com.example.kjtube.refresh"

    @MainActor
    static func schedule(for store: AppStore, now: Date = .now) {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = store.engine.backgroundRefreshDate(after: now)
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
        try? BGTaskScheduler.shared.submit(request)
    }
}

extension AppStore {
    /// The background task: new uploads, any owed shipment, warm thumbnails for what's next.
    func backgroundRefresh(now: Date = .now) async {
        // Nobody has opened the app in over a week: spend no YouTube quota on it (D235). No
        // check, no pictures, and no next wake-up. Opening the app starts everything again,
        // and its own check then brings in what was posted meanwhile.
        if isDormant(at: now) { return }
        await catchUp(now: now)
        let next = engine.nextShipment(after: max(now, engine.state.lastShipment ?? now))
        let ids = engine.state.home.map(\.id) + engine.upcomingPick(at: next).map(\.id)
        ImageCache.shared.prefetch(ids.map(Thumbnail.urls))
        BackgroundRefresh.schedule(for: self, now: now)
    }
}
