import Foundation
import SwiftData

/// A followed creator. `rank` 0 = served first (Following tab order).
@Model
final class Creator {
    enum LoadState: String, Codable {
        case loading, ready, noEligible, failed
    }

    @Attribute(.unique) var channelID: String
    var title: String
    var handle: String?
    var avatarURL: URL?
    var rank: Int
    var lastUploadAt: Date?
    var loadStateRaw: String

    var loadState: LoadState {
        get { LoadState(rawValue: loadStateRaw) ?? .ready }
        set { loadStateRaw = newValue.rawValue }
    }

    init(channel: ChannelSummary, rank: Int) {
        channelID = channel.id
        title = channel.title
        handle = channel.handle
        avatarURL = channel.avatarURL
        self.rank = rank
        loadStateRaw = LoadState.loading.rawValue
    }
}

/// The engine's state and settings, stored as one JSON blob (single row).
@Model
final class EngineRecord {
    var stateData: Data
    var settingsData: Data

    init(state: ShipmentState, settings: ShipmentSettings) {
        stateData = (try? JSONEncoder().encode(state)) ?? Data()
        settingsData = (try? JSONEncoder().encode(settings)) ?? Data()
    }
}
