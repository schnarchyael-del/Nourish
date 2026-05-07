import Foundation

/// Snapshot of the most recent feeding state, shared between the main app and
/// the widget extension via the App Group UserDefaults suite.
struct FeedSnapshot {
    let lastFeedTime: Date?
    let lastFeedDurationSeconds: Int
    let lastFeedSide: String      // "left" / "right" / "bottle" / ""
    let lastFeedType: String      // "breast" / "bottle" / ""
    let lastFeedLeftMinutes: Int
    let lastFeedRightMinutes: Int
    let lastFeedBottleMl: Int
    let todaySessionCount: Int
    let todayTotalMinutes: Int
    let todayLeftMinutes: Int
    let todayRightMinutes: Int

    let isSessionActive: Bool
    let activeSessionStart: Date?
    let activeSessionSide: String   // "left" / "right" / ""

    static let empty = FeedSnapshot(
        lastFeedTime: nil,
        lastFeedDurationSeconds: 0,
        lastFeedSide: "",
        lastFeedType: "",
        lastFeedLeftMinutes: 0,
        lastFeedRightMinutes: 0,
        lastFeedBottleMl: 0,
        todaySessionCount: 0,
        todayTotalMinutes: 0,
        todayLeftMinutes: 0,
        todayRightMinutes: 0,
        isSessionActive: false,
        activeSessionStart: nil,
        activeSessionSide: ""
    )

    static let placeholder = FeedSnapshot(
        lastFeedTime: Date.now.addingTimeInterval(-2 * 3600 - 15 * 60),
        lastFeedDurationSeconds: 12 * 60,
        lastFeedSide: "left",
        lastFeedType: "breast",
        lastFeedLeftMinutes: 8,
        lastFeedRightMinutes: 4,
        lastFeedBottleMl: 0,
        todaySessionCount: 6,
        todayTotalMinutes: 92,
        todayLeftMinutes: 52,
        todayRightMinutes: 40,
        isSessionActive: false,
        activeSessionStart: nil,
        activeSessionSide: ""
    )

    static let placeholderActive = FeedSnapshot(
        lastFeedTime: Date.now.addingTimeInterval(-2 * 3600),
        lastFeedDurationSeconds: 12 * 60,
        lastFeedSide: "right",
        lastFeedType: "breast",
        lastFeedLeftMinutes: 8,
        lastFeedRightMinutes: 4,
        lastFeedBottleMl: 0,
        todaySessionCount: 6,
        todayTotalMinutes: 92,
        todayLeftMinutes: 52,
        todayRightMinutes: 40,
        isSessionActive: true,
        activeSessionStart: Date.now.addingTimeInterval(-3 * 60 - 42),
        activeSessionSide: "left"
    )

    var hasData: Bool { lastFeedTime != nil }
    var isBreast: Bool { lastFeedType == "breast" }
    var isBottle: Bool { lastFeedType == "bottle" }

    /// True only if the snapshot says a session is active AND the start time
    /// is recent. Treats stale active flags (force-quit during a session,
    /// app crash, slow widget reload after end) as "not active" so the
    /// widget can never get permanently stuck on "Feeding now".
    var isActuallyActive: Bool {
        guard isSessionActive, let start = activeSessionStart else { return false }
        // 6-hour ceiling — no real feeding session lasts that long.
        return Date.now.timeIntervalSince(start) < 6 * 3600
    }
}

enum SharedKey {
    static let suiteName = "group.com.yael.nourish"

    static let lastFeedTime          = "widget.lastFeedTime"
    static let lastFeedDuration      = "widget.lastFeedDurationSeconds"
    static let lastFeedSide          = "widget.lastFeedSide"
    static let lastFeedType          = "widget.lastFeedType"
    static let lastFeedLeftMinutes   = "widget.lastFeedLeftMinutes"
    static let lastFeedRightMinutes  = "widget.lastFeedRightMinutes"
    static let lastFeedBottleMl      = "widget.lastFeedBottleMl"
    static let todaySessionCount     = "widget.todaySessionCount"
    static let todayTotalMinutes     = "widget.todayTotalMinutes"
    static let todayLeftMinutes      = "widget.todayLeftMinutes"
    static let todayRightMinutes     = "widget.todayRightMinutes"
    static let isSessionActive       = "widget.isSessionActive"
    static let activeSessionStart    = "widget.activeSessionStart"
    static let activeSessionSide     = "widget.activeSessionSide"
}

extension FeedSnapshot {
    /// Read the latest snapshot from the App Group UserDefaults.
    static func load() -> FeedSnapshot {
        guard let d = UserDefaults(suiteName: SharedKey.suiteName) else {
            return .empty
        }
        let lastFeedTime = (d.object(forKey: SharedKey.lastFeedTime) as? Double)
            .map { Date(timeIntervalSince1970: $0) }

        let activeStart = (d.object(forKey: SharedKey.activeSessionStart) as? Double)
            .map { Date(timeIntervalSince1970: $0) }

        return FeedSnapshot(
            lastFeedTime: lastFeedTime,
            lastFeedDurationSeconds: d.integer(forKey: SharedKey.lastFeedDuration),
            lastFeedSide: d.string(forKey: SharedKey.lastFeedSide) ?? "",
            lastFeedType: d.string(forKey: SharedKey.lastFeedType) ?? "",
            lastFeedLeftMinutes: d.integer(forKey: SharedKey.lastFeedLeftMinutes),
            lastFeedRightMinutes: d.integer(forKey: SharedKey.lastFeedRightMinutes),
            lastFeedBottleMl: d.integer(forKey: SharedKey.lastFeedBottleMl),
            todaySessionCount: d.integer(forKey: SharedKey.todaySessionCount),
            todayTotalMinutes: d.integer(forKey: SharedKey.todayTotalMinutes),
            todayLeftMinutes: d.integer(forKey: SharedKey.todayLeftMinutes),
            todayRightMinutes: d.integer(forKey: SharedKey.todayRightMinutes),
            isSessionActive: d.bool(forKey: SharedKey.isSessionActive),
            activeSessionStart: activeStart,
            activeSessionSide: d.string(forKey: SharedKey.activeSessionSide) ?? ""
        )
    }
}

// MARK: - Display helpers (also used by the main-app side)

enum FeedFormat {
    /// "2h 15m ago" / "45m ago" / "Just now"
    static func timeAgo(from date: Date?, reference: Date = .now) -> String {
        guard let date else { return "—" }
        let secs = max(0, Int(reference.timeIntervalSince(date)))
        if secs < 60 { return "Just now" }
        let mins = secs / 60
        if mins < 60 { return "\(mins)m ago" }
        let hours = mins / 60
        let remMins = mins % 60
        if hours < 24 {
            return remMins > 0 ? "\(hours)h \(remMins)m ago" : "\(hours)h ago"
        }
        let days = hours / 24
        return "\(days)d ago"
    }

    /// "1h 45m" / "45m" / "0m"
    static func countdown(to date: Date?, reference: Date = .now) -> String {
        guard let date, date > reference else { return "0m" }
        let secs = Int(date.timeIntervalSince(reference))
        let mins = secs / 60
        if mins < 60 { return "\(mins)m" }
        let hours = mins / 60
        let remMins = mins % 60
        return remMins > 0 ? "\(hours)h \(remMins)m" : "\(hours)h"
    }

    /// "12 min" / "1h 5m"
    static func durationFromSeconds(_ seconds: Int) -> String {
        let mins = max(0, seconds) / 60
        if mins < 60 { return "\(mins) min" }
        let h = mins / 60
        let m = mins % 60
        return m > 0 ? "\(h)h \(m)m" : "\(h)h"
    }

    static func sideLetter(from side: String) -> String {
        switch side {
        case "left":   return "L"
        case "right":  return "R"
        case "bottle": return "🍼"
        default:       return "—"
        }
    }
}
