import Foundation

enum Format {
    /// Video length badge: "12:34" or "1:02:03".
    static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    /// Amount of content: "42 min" or "1 h 5 min".
    static func minutes(_ seconds: TimeInterval) -> String {
        let total = Int((seconds / 60).rounded(.up))
        return total >= 60 ? "\(total / 60) h \(total % 60) min" : "\(total) min"
    }

    /// Spelled out for the Inbox title: "1 minute", "44 minutes", "1 hour 5 minutes".
    static func minutesLong(_ seconds: TimeInterval) -> String {
        let total = Int((seconds / 60).rounded(.up))
        func unit(_ n: Int, _ word: String) -> String { "\(n) \(word)\(n == 1 ? "" : "s")" }
        guard total >= 60 else { return unit(total, "minute") }
        return total % 60 == 0 ? unit(total / 60, "hour") : "\(unit(total / 60, "hour")) \(unit(total % 60, "minute"))"
    }

    /// Countdown: "9h 12m", "42m", or "37s" in the final minute.
    static func countdown(_ seconds: TimeInterval) -> String {
        let total = Int(seconds) / 60
        if total < 1 { return "\(max(Int(seconds), 0))s" }
        return total >= 60 ? "\(total / 60)h \(total % 60)m" : "\(total)m"
    }

    /// YouTube-style view count: "940", "59K", "1.2M".
    static func views(_ count: Int) -> String {
        count.formatted(.number.notation(.compactName))
    }

    /// YouTube-style age: "5m ago", "3h ago", "2d ago", "3w ago", "4mo ago", "1y ago".
    static func age(_ date: Date, now: Date = .now) -> String {
        let seconds = max(now.timeIntervalSince(date), 0)
        let minute = 60.0, hour = 60 * minute, day = 24 * hour
        let (value, unit): (Double, String) = switch seconds {
        case ..<hour: (max(seconds / minute, 1), "m")
        case ..<day: (seconds / hour, "h")
        case ..<(7 * day): (seconds / day, "d")
        case ..<(30 * day): (seconds / (7 * day), "w")
        case ..<(365 * day): (seconds / (30 * day), "mo")
        default: (seconds / (365 * day), "y")
        }
        return "\(Int(value))\(unit) ago"
    }

    /// The text with every web address turned into a tappable link.
    static func linked(_ text: String) -> AttributedString {
        var result = AttributedString(text)
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return result }
        for match in detector.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let url = match.url,
                  let range = Range(match.range, in: text),
                  let lower = AttributedString.Index(range.lowerBound, within: result),
                  let upper = AttributedString.Index(range.upperBound, within: result) else { continue }
            result[lower..<upper].link = url
        }
        return result
    }
}
