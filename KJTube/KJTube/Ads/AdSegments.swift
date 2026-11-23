import Foundation

/// One in-video promotion: a sponsor read or the creator's own promo (D112).
struct AdSegment: Codable, Equatable, Sendable {
    var start: TimeInterval
    var end: TimeInterval
}

/// The Skip Ad rules (docs/specs/skip-ad.md). Pure Swift, no UI or network.
enum AdSegments {
    /// Shorter than this isn't worth a button.
    static let shortest: TimeInterval = 5

    /// Tidies whatever the AI said: trims to the video's length, drops broken and tiny ones,
    /// and joins ads that touch or overlap (S9).
    static func clean(_ raw: [AdSegment], duration: TimeInterval) -> [AdSegment] {
        let trimmed = raw
            .map { AdSegment(start: max($0.start, 0), end: duration > 0 ? min($0.end, duration) : $0.end) }
            .filter { $0.end > $0.start }
            .sorted { $0.start < $1.start }
        var joined: [AdSegment] = []
        for ad in trimmed {
            if let last = joined.last, ad.start <= last.end {
                joined[joined.count - 1].end = max(last.end, ad.end)
            } else {
                joined.append(ad)
            }
        }
        return joined.filter { $0.end - $0.start >= shortest }
    }

    /// The ad playing at `time`, if any: from its first second up to (not including) its end.
    static func active(in ads: [AdSegment], at time: TimeInterval) -> AdSegment? {
        ads.first { time >= $0.start && time < $0.end }
    }

    /// "MM:SS" or "H:MM:SS" (how an AI may write times), or plain seconds.
    static func seconds(_ text: String) -> TimeInterval? {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: ":", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count) else { return nil }
        var total: TimeInterval = 0
        for part in parts {
            guard let value = Double(part), value >= 0 else { return nil }
            total = total * 60 + value
        }
        return total
    }
}
