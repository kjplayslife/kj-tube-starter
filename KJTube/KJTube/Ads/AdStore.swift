import Foundation
import Observation

/// The Skip Ad beta (D111): the on/off switch, the saved ad times per video, and the
/// background checks that fill them in. The player only ever reads `ads(for:)`.
@MainActor
@Observable
final class AdStore {
    /// What is known about one video. `ads == nil` means no answer yet.
    struct Record: Codable, Equatable {
        var ads: [AdSegment]?
        var tries = 0
    }

    static let switchKey = "skipAdBeta"
    static let recordsKey = "skipAdRecords"
    /// A video whose check keeps failing is left alone after this many tries (S10).
    static let maxTries = 3

    /// Off until KJ turns it on in Settings.
    var isOn: Bool {
        didSet {
            defaults.set(isOn, forKey: Self.switchKey)
            if !isOn { wanted = [] }
        }
    }

    /// False when the build is missing a Skip Ad key: the switch is grayed out (S12).
    var hasFinder: Bool { finder != nil }

    private(set) var records: [String: Record]

    @ObservationIgnored private let finder: (any AdFinder)?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var wanted: [Video] = []
    /// One try per video per app launch, so a failing video isn't hammered.
    @ObservationIgnored private var triedThisLaunch: Set<String> = []
    @ObservationIgnored private(set) var worker: Task<Void, Never>?

    init(finder: (any AdFinder)?, defaults: UserDefaults = .standard) {
        self.finder = finder
        self.defaults = defaults
        isOn = finder != nil && defaults.bool(forKey: Self.switchKey)
        records = defaults.data(forKey: Self.recordsKey)
            .flatMap { try? JSONDecoder().decode([String: Record].self, from: $0) } ?? [:]
    }

    /// The saved ads for a video; empty while the switch is off or nothing is known.
    func ads(for videoID: String) -> [AdSegment] {
        isOn ? records[videoID]?.ads ?? [] : []
    }

    /// Asks about every Inbox video that has no answer yet, one at a time, in the background.
    /// Safe to call often: each video is asked once, and nothing waits on it (S10).
    func check(_ videos: [Video]) {
        guard isOn, finder != nil else { return }
        wanted = videos
        // Forget videos that left the Inbox.
        let keep = Set(videos.map(\.id))
        if records.keys.contains(where: { !keep.contains($0) }) {
            records = records.filter { keep.contains($0.key) }
            persist()
        }
        guard worker == nil else { return }
        worker = Task { [weak self] in
            await self?.work()
            self?.worker = nil
        }
    }

    private func nextVideo() -> Video? {
        wanted.first { video in
            let record = records[video.id]
            return record?.ads == nil && (record?.tries ?? 0) < Self.maxTries && !triedThisLaunch.contains(video.id)
        }
    }

    private func work() async {
        guard let finder else { return }
        while isOn, let video = nextVideo() {
            triedThisLaunch.insert(video.id)
            var record = records[video.id] ?? Record()
            record.tries += 1
            do {
                let raw = try await finder.findAds(videoID: video.id)
                record.ads = AdSegments.clean(raw, duration: video.duration)
            } catch {
                // No answer: no button on this video. Tried again on the next app open.
            }
            guard wanted.contains(where: { $0.id == video.id }) else { continue } // left the Inbox meanwhile
            records[video.id] = record
            persist()
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(records) { defaults.set(data, forKey: Self.recordsKey) }
    }

    #if DEBUG
    /// Simulator checks: pretend the AI already answered for this video.
    func seed(_ ads: [AdSegment], for videoID: String) {
        records[videoID] = Record(ads: ads, tries: 1)
    }
    #endif
}
