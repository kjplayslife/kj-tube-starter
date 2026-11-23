import Foundation

/// Where a new person is in first run (docs/specs/first-run.md, D175).
enum FirstRunStep: Equatable, Sendable {
    /// No creators yet: the welcome, with Import and Find creators.
    case welcome
    /// Creators are in: rank them, set the amount, then load the first Inbox.
    case setup
    /// The first Inbox was loaded (or the app was in use before first run existed).
    case done
}

/// The first-run sheet's two pages.
enum FirstRunPage: Equatable, Sendable {
    /// The daily amount. `thenCheck`: it came up from "Load my Inbox", so the check follows.
    case amount(thenCheck: Bool)
    /// "Ready for your first Inbox?"
    case check
}

/// The words and rules of first run. Pure, so they are unit tested.
enum FirstRun {
    struct Summary: Equatable, Sendable {
        let amount: String
        let creators: String
        /// "Watch in Order: …" and "Any Length: …", only for switches that are on.
        let switches: [String]
    }

    static func step(done: Bool, hasCreators: Bool) -> FirstRunStep {
        if done { return .done }
        return hasCreators ? .setup : .welcome
    }

    /// The bar on Following. Ranking only matters in Ranked order (D74).
    static func barText(ranked: Bool) -> String {
        let switches = "Swipe a creator right for Watch in Order or Any Length."
        return ranked ? "Hold and drag to rank. Top creators come first. " + switches : switches
    }

    static func summary(
        weekdayMinutes: Int, weekendMinutes: Int, fridayIsWeekend: Bool = false, creators: [String], ranked: Bool,
        inOrder: [String], anyLength: [String]
    ) -> Summary {
        let count = creators.count == 1 ? "1 creator" : "\(creators.count) creators"
        let line: String
        if !ranked {
            line = count + ", newest videos first."
        } else if creators.count <= 3 {
            line = creators.isEmpty ? count + "." : count + ": " + creators.joined(separator: ", ") + "."
        } else {
            line = count + ". First up: " + creators.prefix(3).joined(separator: ", ") + "."
        }
        var switches: [String] = []
        if !inOrder.isEmpty { switches.append("Watch in Order: " + inOrder.joined(separator: ", ") + ".") }
        if !anyLength.isEmpty { switches.append("Any Length: " + anyLength.joined(separator: ", ") + ".") }
        return Summary(
            amount: "\(weekdayMinutes) min on weekdays, \(weekendMinutes) on weekends."
                + (fridayIsWeekend ? " Friday counts as weekend." : ""),
            creators: line,
            switches: switches
        )
    }
}
