import SwiftUI
import UIKit

/// Downloads a video's preview sheets and cuts out the frame for a time (D134). Sheets are only
/// fetched once a finger lands on the seek bar, so a video that's never scrubbed costs nothing.
@MainActor
@Observable
final class ScrubPreview {
    /// The frame to show. Stays on the last one while the next sheet is still downloading.
    private(set) var image: UIImage?

    @ObservationIgnored private var storyboard: Storyboard?
    @ObservationIgnored private var sheets: [URL: CGImage] = [:]
    @ObservationIgnored private var loading: Set<URL> = []
    @ObservationIgnored private var wanted: Storyboard.Tile?
    @ObservationIgnored private var shown: Storyboard.Tile?

    /// A finger is on the seek bar: get every sheet, so the drag never waits for one.
    func warm(_ storyboard: Storyboard?) {
        use(storyboard)
        storyboard?.sheetURLs.forEach(load)
    }

    func show(time: TimeInterval, in storyboard: Storyboard?) {
        use(storyboard)
        guard let tile = storyboard?.tile(at: time) else { return }
        wanted = tile
        load(tile.sheet)
        cut()
    }

    func clear() {
        image = nil
        wanted = nil
        shown = nil
    }

    private func use(_ new: Storyboard?) {
        guard new != storyboard else { return }
        storyboard = new
        sheets.removeAll()
        loading.removeAll()
        clear()
    }

    private func cut() {
        guard let tile = wanted, tile != shown, let sheet = sheets[tile.sheet],
              let frame = sheet.cropping(to: tile.rect) else { return }
        shown = tile
        image = UIImage(cgImage: frame)
    }

    private func load(_ url: URL) {
        guard sheets[url] == nil, !loading.contains(url) else { return }
        loading.insert(url)
        let current = storyboard
        Task {
            let data = try? await URLSession.shared.data(from: url).0
            guard current == storyboard else { return } // another video by now
            loading.remove(url)
            guard let data, let sheet = UIImage(data: data)?.cgImage else { return }
            sheets[url] = sheet
            cut()
        }
    }
}
