import Foundation

/// What the Following search field should look up (D27).
enum ChannelQuery: Hashable, Sendable {
    case handle(String)     // "@veritasium", without the @
    case channelID(String)  // "UC…"
    case videoID(String)    // resolve to that video's channel
    case search(String)     // free text → search.list

    /// Parses pasted links, @handles and channel IDs; anything else is a text search.
    static func parse(_ raw: String) -> ChannelQuery? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        if text.hasPrefix("@"), let handle = validHandle(String(text.dropFirst())) {
            return .handle(handle)
        }
        if isChannelID(text) { return .channelID(text) }
        if let url = youTubeURL(text), let query = parse(url: url) { return query }
        return .search(text)
    }

    /// True when the query names one exact channel or video (not a free-text search).
    var isDirectLookup: Bool {
        if case .search = self { return false }
        return true
    }

    /// True for input that looks like a link, so the UI can resolve it without waiting for Return.
    static func looksLikeLink(_ raw: String) -> Bool {
        let text = raw.lowercased()
        return text.contains("youtube.com/") || text.contains("youtu.be/")
    }

    private static func parse(url: URL) -> ChannelQuery? {
        let host = (url.host() ?? "").lowercased()
        let parts = url.pathComponents.filter { $0 != "/" }

        if host == "youtu.be" || host.hasSuffix(".youtu.be") {
            return parts.first.flatMap(validVideoID).map(ChannelQuery.videoID)
        }
        guard host == "youtube.com" || host.hasSuffix(".youtube.com") else { return nil }
        guard let first = parts.first else { return nil }

        if first.hasPrefix("@") {
            return validHandle(String(first.dropFirst())).map(ChannelQuery.handle)
        }
        switch first {
        case "channel":
            return parts.dropFirst().first.flatMap { isChannelID($0) ? .channelID($0) : nil }
        case "watch":
            let v = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "v" }?.value
            return v.flatMap(validVideoID).map(ChannelQuery.videoID)
        case "shorts", "live", "embed":
            return parts.dropFirst().first.flatMap(validVideoID).map(ChannelQuery.videoID)
        default:
            return nil
        }
    }

    private static func youTubeURL(_ text: String) -> URL? {
        guard looksLikeLink(text) else { return nil }
        let withScheme = text.contains("://") ? text : "https://" + text
        return URL(string: withScheme)
    }

    private static func validHandle(_ handle: String) -> String? {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        guard (3...30).contains(handle.count),
              handle.unicodeScalars.allSatisfy(allowed.contains) else { return nil }
        return handle
    }

    private static func isChannelID(_ text: String) -> Bool {
        text.count == 24 && text.hasPrefix("UC") && text.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
    }

    private static func validVideoID(_ id: String) -> String? {
        id.count == 11 && id.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }) ? id : nil
    }
}
