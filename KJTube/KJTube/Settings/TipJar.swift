import Foundation
import Observation
import StoreKit

/// The tip jar: three one-time tips paid through Apple. A tip unlocks nothing
/// (docs/specs/tip-jar.md, D181).
enum TipJar {
    /// The three tips, smallest first. The price comes from Apple.
    static let sizes: [(key: String, name: String)] = [
        ("small", "Small coffee"),
        ("medium", "Big coffee"),
        ("large", "Coffee and a snack"),
    ]

    /// Apple wants every tip to have its own ID and no two apps can share one, so each app's
    /// tips are named after the app: KJ Tube and KJ Tube Public each have their own set (T12).
    /// KJ Tube Dev gets names Apple has never heard of, so it shows no tips.
    static func productIDs(bundleID: String? = Bundle.main.bundleIdentifier) -> [String] {
        sizes.map { "\(bundleID ?? "").tip.\($0.key)" }
    }

    static func name(for productID: String) -> String {
        sizes.first { productID.hasSuffix(".tip.\($0.key)") }?.name ?? "Tip"
    }

    /// A tip Apple finished after the app was closed (or a parent approved later) is marked
    /// done quietly. Listening doesn't ask the store for anything (T9, T11).
    static func finishLateTips() {
        Task.detached(priority: .background) {
            for await update in Transaction.updates {
                if case .verified(let transaction) = update { await transaction.finish() }
            }
        }
    }
}

/// One tip as the sheet shows it.
struct Tip: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    /// Apple's price in the buyer's own currency, like "$1.99".
    let price: String
}

enum TipOutcome: Equatable, Sendable {
    case thanks, cancelled, waitingForApproval, failed
}

/// Apple's store, or a fake one in tests.
@MainActor
protocol TipStore {
    /// The tips Apple knows, in the order asked for. Empty or a throw means none can be shown.
    func tips(ids: [String]) async throws -> [Tip]
    func buy(_ id: String) async -> TipOutcome
}

/// The real store (StoreKit).
@MainActor
final class AppleTipStore: TipStore {
    private var products: [String: Product] = [:]

    func tips(ids: [String]) async throws -> [Tip] {
        let found = try await Product.products(for: ids)
        products = Dictionary(found.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return ids.compactMap { id in
            products[id].map { Tip(id: id, name: TipJar.name(for: id), price: $0.displayPrice) }
        }
    }

    func buy(_ id: String) async -> TipOutcome {
        guard let product = products[id] else { return .failed }
        do {
            switch try await product.purchase() {
            case .success(.verified(let transaction)):
                await transaction.finish() // a tip is used up at once, so it can be bought again (T4)
                return .thanks
            case .success(.unverified):
                return .failed
            case .userCancelled:
                return .cancelled
            case .pending:
                return .waitingForApproval
            @unknown default:
                return .failed
            }
        } catch {
            return .failed
        }
    }
}

/// What the tip sheet is showing. Nothing here touches shipments, limits or the Inbox (T10).
@MainActor
@Observable
final class TipJarModel {
    enum Phase: Equatable {
        case loading
        /// The three buttons. `failed` adds the "didn't go through" line above them (T6).
        case ready(failed: Bool)
        /// Apple's payment sheet is up: the buttons are grayed out (T8).
        case buying
        case thanks
        case waitingForApproval
        case unavailable
    }

    static let thanksText = "Thank you! ☕️"
    static let failedText = "That didn't go through. You weren't charged."
    static let unavailableText = "Tips aren't available right now."
    static let waitingText = "Waiting for approval."

    private(set) var phase: Phase = .loading
    private(set) var tips: [Tip] = []
    private let store: any TipStore
    private let ids: [String]

    init(store: any TipStore = AppleTipStore(), ids: [String] = TipJar.productIDs()) {
        self.store = store
        self.ids = ids
    }

    /// The sheet closes by itself after these (T3, T9).
    var closesSoon: Bool { phase == .thanks || phase == .waitingForApproval }

    /// Called when the sheet opens, never before (T11).
    func load() async {
        guard phase == .loading else { return }
        tips = (try? await store.tips(ids: ids)) ?? []
        phase = tips.isEmpty ? .unavailable : .ready(failed: false)
    }

    func buy(_ tip: Tip) async {
        guard case .ready = phase else { return } // a double tap can't buy twice (T8)
        phase = .buying
        switch await store.buy(tip.id) {
        case .thanks: phase = .thanks
        case .cancelled: phase = .ready(failed: false) // quiet (T5)
        case .waitingForApproval: phase = .waitingForApproval
        case .failed: phase = .ready(failed: true)
        }
    }
}
