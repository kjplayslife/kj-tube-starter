import Foundation

/// An ESV verse about work and rest, shown when the day's shipment is done (D15, D40).
struct Verse: Codable, Hashable, Sendable {
    let reference: String
    let text: String
    let theme: String
}

enum VerseLibrary {
    /// Bundled from docs/specs/verses.md by scripts/build_verses.py (D43).
    static let all: [Verse] = {
        guard let url = Bundle.main.url(forResource: "verses", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let verses = try? JSONDecoder().decode([Verse].self, from: data) else { return [] }
        return verses
    }()
}

/// Every verse once, in random order, before any repeats (D41). Never shows the same verse twice
/// in a row, even across a reshuffle.
struct VerseBag: Codable, Equatable, Sendable {
    private(set) var order: [Int] = []
    private(set) var position = 0

    mutating func next<R: RandomNumberGenerator>(count: Int, using rng: inout R) -> Int? {
        guard count > 0 else { return nil }
        if order.count != count || position >= order.count {
            let last = order.indices.contains(position - 1) ? order[position - 1] : nil
            order = Array(0..<count).shuffled(using: &rng)
            if count > 1, order.first == last { order.swapAt(0, 1) }
            position = 0
        }
        defer { position += 1 }
        return order[position]
    }

    mutating func next(count: Int) -> Int? {
        var rng = SystemRandomNumberGenerator()
        return next(count: count, using: &rng)
    }
}
