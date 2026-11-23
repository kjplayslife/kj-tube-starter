import Foundation

/// What a Settings change needs before it can happen (PLAN §3.6).
enum SettingChange: Equatable, Sendable {
    /// Tightening (or no change): apply right away.
    case apply
    /// Loosening: ask first; confirming locks that limit until `lockUntil`.
    case confirm(lockUntil: Date)
    /// Loosening isn't allowed again until `until`.
    case locked(until: Date)
}

/// Each limit can be loosened once a week, on its own clock. Tightening is always allowed (D145).
enum SettingsPolicy {
    static let lockDays = 7

    /// Budgets, refreshes and the Friday switch: `loosens` says whether the change allows more watching.
    static func change(loosens: Bool, lockedUntil: Date?, now: Date, calendar: Calendar) -> SettingChange {
        guard loosens else { return .apply }
        if let lockedUntil, lockedUntil > now { return .locked(until: lockedUntil) }
        return .confirm(lockUntil: calendar.date(byAdding: .day, value: lockDays, to: now)!)
    }

    /// Budgets and refreshes: a higher number loosens.
    static func raise(from current: Double, to new: Double, lockedUntil: Date?, now: Date, calendar: Calendar) -> SettingChange {
        change(loosens: new > current, lockedUntil: lockedUntil, now: now, calendar: calendar)
    }

    /// Lowering a daily limit is always allowed, but it asks first: the way back up costs the
    /// once-a-week raise, or is closed until the lock runs out (D210). `day` writes the date.
    static func lowerWarning(lockedUntil: Date?, now: Date, day: (Date) -> String) -> String {
        if let lockedUntil, lockedUntil > now {
            return "You already used this week's raise, so you can't go back up until \(day(lockedUntil))."
        }
        return "Going back up will use your once-a-week raise for this limit."
    }

    /// "30 minutes", for the lowering question.
    static func spelledOut(minutes: Double) -> String {
        Int(minutes) == 1 ? "1 minute" : "\(Int(minutes)) minutes"
    }

    /// Shipment time: any move counts.
    static func shipmentTime(from current: Int, to new: Int, lockedUntil: Date?, now: Date, calendar: Calendar) -> SettingChange {
        change(loosens: new != current, lockedUntil: lockedUntil, now: now, calendar: calendar)
    }
}
