import Foundation

/// YouTube's own preview pictures for a video: sheets of tiny frames, a few seconds apart.
/// KJ Tube shows the frame under the finger while the seek bar is dragged (D134).
///
/// This reads YouTube's "storyboard spec", which is not part of the official API. If YouTube
/// changes it, `init` returns nil and the seek bar simply has no preview.
struct Storyboard: Equatable, Sendable {
    /// One frame: which sheet it is on, and where on that sheet.
    struct Tile: Equatable, Sendable {
        let sheet: URL
        let rect: CGRect
    }

    struct Level: Equatable, Sendable {
        let index: Int
        let width: Int
        let height: Int
        let count: Int
        let columns: Int
        let rows: Int
        /// Milliseconds between frames. 0 means the frames are spread evenly over the video.
        let interval: Int
        let name: String
        let signature: String

        var perSheet: Int { columns * rows }
        var sheets: Int { (count + perSheet - 1) / perSheet }
    }

    let base: String
    let level: Level
    let duration: TimeInterval

    /// More sheets than this would be a lot to download for one drag, so a smaller level is used.
    static let maxSheets = 80

    /// `spec` looks like `https://…/storyboard3_L$L/$N.jpg?sqp=…|48#27#100#10#10#0#default#rs$…|80#45#…`:
    /// the address pattern, then one part per size, smallest first.
    init?(spec: String, duration: TimeInterval) {
        let parts = spec.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 2, parts[0].hasPrefix("https://"), duration > 0 else { return nil }
        let levels: [Level] = parts.dropFirst().enumerated().compactMap { index, part in
            let f = part.split(separator: "#", omittingEmptySubsequences: false).map(String.init)
            guard f.count >= 8,
                  let width = Int(f[0]), let height = Int(f[1]), let count = Int(f[2]),
                  let columns = Int(f[3]), let rows = Int(f[4]), let interval = Int(f[5]),
                  width > 0, height > 0, count > 0, columns > 0, rows > 0, interval >= 0
            else { return nil }
            return Level(index: index, width: width, height: height, count: count, columns: columns,
                         rows: rows, interval: interval, name: f[6], signature: f[7])
        }
        // The sharpest size that isn't too many sheets; else the sharpest of all.
        guard let best = levels.last(where: { $0.sheets <= Self.maxSheets }) ?? levels.last else { return nil }
        base = parts[0]
        level = best
        self.duration = duration
    }

    /// Which frame shows the video at `time`.
    func frameIndex(at time: TimeInterval) -> Int {
        let t = min(max(time, 0), duration)
        let raw = level.interval > 0
            ? Int(t * 1000 / Double(level.interval))
            : Int(t / duration * Double(level.count))
        return min(max(raw, 0), level.count - 1)
    }

    func sheetURL(_ sheet: Int) -> URL? {
        let address = base
            .replacingOccurrences(of: "$L", with: String(level.index))
            .replacingOccurrences(of: "$N", with: level.name)
            .replacingOccurrences(of: "$M", with: String(sheet))
        guard var parts = URLComponents(string: address) else { return nil }
        // The signature goes in as it is: it can hold characters that must not be encoded twice.
        let query = parts.percentEncodedQuery.map { $0 + "&" } ?? ""
        parts.percentEncodedQuery = query + "sigh=" + (level.signature.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? level.signature)
        return parts.url
    }

    var sheetURLs: [URL] { (0..<level.sheets).compactMap(sheetURL) }

    func tile(at time: TimeInterval) -> Tile? {
        let frame = frameIndex(at: time)
        guard let url = sheetURL(frame / level.perSheet) else { return nil }
        let onSheet = frame % level.perSheet
        return Tile(sheet: url, rect: CGRect(
            x: (onSheet % level.columns) * level.width, y: (onSheet / level.columns) * level.height,
            width: level.width, height: level.height
        ))
    }
}
