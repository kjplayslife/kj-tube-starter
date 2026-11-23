import Foundation

/// Finds a creator's newest eligible uploads (PLAN §3.2–3.3, following spec).
struct UploadsLoader: Sendable {
    /// How far back to look for eligible videos (following spec ⚙︎).
    static let scanLimit = 50
    /// Shorts are at most 3 minutes, so only those need the extra Shorts check.
    static let shortsMaxDuration: TimeInterval = 180

    let api: any YouTubeAPI

    struct Result: Sendable {
        /// Newest first.
        let videos: [Video]
        /// Newest upload of any kind, Shorts and live streams included. Only for the fetch
        /// cursor, so the same uploads aren't looked at twice.
        let newestUploadAt: Date?
        /// Newest long-form video among the uploads looked at, for "Last upload 3d ago" (D230):
        /// never a Short, a live stream or a premiere. Nil when none was found.
        let lastLongFormAt: Date?
    }

    func latestEligible(channelID: String, count: Int) async throws -> Result {
        let uploads = try await api.recentUploads(channelID: channelID, limit: Self.scanLimit)
        let details = try await api.videoDetails(ids: uploads.map(\.videoID))
            .filter(Self.isRegularVideo)
            .sorted { $0.publishedAt > $1.publishedAt }

        var picked: [Video] = []
        var lastLongFormAt: Date?
        for video in details where picked.count < count || lastLongFormAt == nil {
            if video.duration <= Self.shortsMaxDuration, try await api.isShort(videoID: video.id) { continue }
            lastLongFormAt = lastLongFormAt ?? video.publishedAt
            if video.embeddable, picked.count < count { picked.append(video.asVideo) }
        }
        return Result(videos: picked, newestUploadAt: uploads.first?.publishedAt, lastLongFormAt: lastLongFormAt)
    }

    /// One creator to check for uploads published after `since`.
    struct Job: Sendable {
        let channelID: String
        let since: Date
    }

    /// Eligible uploads published after each job's `since`, for the twice-a-day check
    /// (PLAN §3.3, D231). Answers come back in the order of `jobs`; one creator failing
    /// doesn't fail the others. Costs one quota unit per creator to list uploads, then one
    /// per 50 new videos for their details, asked for all creators together (D232).
    func eligibleUploads(for jobs: [Job], atOnce: Int, limit: Int = 15) async -> [Swift.Result<Result, YouTubeError>] {
        let api = api
        // 1. Each creator's newest uploads, a few creators at a time.
        let listings: [Swift.Result<[UploadRef], YouTubeError>] = await Self.inParallel(jobs.count, atOnce: atOnce) { index in
            try await api.recentUploads(channelID: jobs[index].channelID, limit: limit)
        }
        let fresh: [[UploadRef]] = zip(jobs, listings).map { job, listing in
            ((try? listing.get()) ?? []).filter { $0.publishedAt > job.since }
        }

        // 2. Details for every new video, 50 per call across all creators.
        let ids = fresh.flatMap { $0.map(\.videoID) }
        var detailsByID: [String: VideoDetails] = [:]
        var failedIDs: [String: YouTubeError] = [:]
        for start in stride(from: 0, to: ids.count, by: Self.detailsBatch) {
            let batch = Array(ids[start..<min(start + Self.detailsBatch, ids.count)])
            do {
                for video in try await api.videoDetails(ids: batch) { detailsByID[video.id] = video }
            } catch {
                let problem = (error as? YouTubeError) ?? .server(error.localizedDescription)
                for id in batch { failedIDs[id] = problem }
            }
        }

        // 3. Per creator: the rules, then the Shorts check for the short ones.
        let details = detailsByID, failed = failedIDs
        return await Self.inParallel(jobs.count, atOnce: atOnce) { index in
            let uploads = try listings[index].get()
            if let problem = fresh[index].lazy.compactMap({ failed[$0.videoID] }).first { throw problem }
            let candidates = fresh[index].compactMap { details[$0.videoID] }
                .filter(Self.isRegularVideo)
                .sorted { $0.publishedAt > $1.publishedAt }
            var picked: [Video] = []
            var lastLongFormAt: Date?
            for video in candidates {
                if video.duration <= Self.shortsMaxDuration, try await api.isShort(videoID: video.id) { continue }
                lastLongFormAt = lastLongFormAt ?? video.publishedAt
                if video.embeddable { picked.append(video.asVideo) }
            }
            return Result(videos: picked, newestUploadAt: uploads.first?.publishedAt, lastLongFormAt: lastLongFormAt)
        }
    }

    /// videos.list takes at most 50 IDs.
    static let detailsBatch = 50

    /// Runs `work` for 0..<count, at most `atOnce` at a time (gentle on a weak connection).
    /// Answers come back in index order.
    private static func inParallel<T: Sendable>(
        _ count: Int, atOnce: Int, _ work: @escaping @Sendable (Int) async throws -> T
    ) async -> [Swift.Result<T, YouTubeError>] {
        let run: @Sendable (Int) async -> (Int, Swift.Result<T, YouTubeError>) = { index in
            do {
                return (index, .success(try await work(index)))
            } catch {
                return (index, .failure((error as? YouTubeError) ?? .server(error.localizedDescription)))
            }
        }
        return await withTaskGroup(of: (Int, Swift.Result<T, YouTubeError>).self) { group in
            var answers = [Swift.Result<T, YouTubeError>](repeating: .failure(.server("not asked")), count: count)
            var next = 0
            while next < min(max(atOnce, 1), count) {
                let index = next
                group.addTask { await run(index) }
                next += 1
            }
            for await (index, answer) in group {
                answers[index] = answer
                if next < count {
                    let index = next
                    group.addTask { await run(index) }
                    next += 1
                }
            }
            return answers
        }
    }

    /// Everything in PLAN §3.2 that the Data API can tell us directly (D13).
    static func passesMetadataRules(_ video: VideoDetails) -> Bool {
        isRegularVideo(video) && video.embeddable
    }

    /// A normal public upload: not live, not a premiere still to come, not a replay of either.
    /// Shorts still pass here; they need the separate Shorts check.
    static func isRegularVideo(_ video: VideoDetails) -> Bool {
        video.liveBroadcastContent == "none"
            && !video.wasLivestream
            && video.isPublic
            && video.duration > 0
    }
}
