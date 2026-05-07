import Foundation
import SwiftData
import WidgetKit

/// Writes the current "feeding state" snapshot to the App Group
/// UserDefaults so the widget extension can render it. Also kicks
/// `WidgetCenter` to reload all timelines.
///
/// Keys here must stay in sync with `NourishWidget/SharedFeedSnapshot.swift`.
enum SharedFeedSnapshot {

    private enum Key {
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
    }

    /// Read the latest sessions out of SwiftData, compute the snapshot
    /// fields, persist them, and reload widgets.
    static func refresh(modelContainer: ModelContainer) {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<FeedingSession>(
            sortBy: [SortDescriptor(\.startTime, order: .reverse)]
        )
        guard let sessions = try? context.fetch(descriptor) else {
            clear()
            return
        }
        guard let defaults = UserDefaults(suiteName: Key.suiteName) else { return }

        // Last feed
        if let last = sessions.first {
            let endOrNow = last.endTime ?? last.startTime
            let lastSide = last.feedType.rawValue
            let durationSeconds = last.feedType == .bottle
                ? 0
                : (last.leftMinutesResolved + last.rightMinutesResolved) * 60

            defaults.set(endOrNow.timeIntervalSince1970, forKey: Key.lastFeedTime)
            defaults.set(durationSeconds, forKey: Key.lastFeedDuration)
            defaults.set(lastSide, forKey: Key.lastFeedSide)
            defaults.set(last.feedType == .bottle ? "bottle" : "breast", forKey: Key.lastFeedType)
            defaults.set(last.leftMinutesResolved,  forKey: Key.lastFeedLeftMinutes)
            defaults.set(last.rightMinutesResolved, forKey: Key.lastFeedRightMinutes)
            defaults.set(last.bottleAmountMl ?? 0,  forKey: Key.lastFeedBottleMl)
        } else {
            defaults.removeObject(forKey: Key.lastFeedTime)
            defaults.set(0, forKey: Key.lastFeedDuration)
            defaults.set("", forKey: Key.lastFeedSide)
            defaults.set("", forKey: Key.lastFeedType)
            defaults.set(0, forKey: Key.lastFeedLeftMinutes)
            defaults.set(0, forKey: Key.lastFeedRightMinutes)
            defaults.set(0, forKey: Key.lastFeedBottleMl)
        }

        // Today's totals (since startOfDay)
        let dayStart = Calendar.current.startOfDay(for: .now)
        let today = sessions.filter { $0.startTime >= dayStart }
        let leftToday  = today.reduce(0) { $0 + $1.leftMinutesResolved }
        let rightToday = today.reduce(0) { $0 + $1.rightMinutesResolved }
        defaults.set(today.count, forKey: Key.todaySessionCount)
        defaults.set(leftToday + rightToday, forKey: Key.todayTotalMinutes)
        defaults.set(leftToday, forKey: Key.todayLeftMinutes)
        defaults.set(rightToday, forKey: Key.todayRightMinutes)

        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Clears all snapshot keys (used when local data is wiped — e.g. account
    /// switch with destructive replacement).
    static func clear() {
        guard let defaults = UserDefaults(suiteName: Key.suiteName) else { return }
        for key in [
            Key.lastFeedTime, Key.lastFeedDuration, Key.lastFeedSide,
            Key.lastFeedType, Key.lastFeedLeftMinutes, Key.lastFeedRightMinutes,
            Key.lastFeedBottleMl, Key.todaySessionCount, Key.todayTotalMinutes,
            Key.todayLeftMinutes, Key.todayRightMinutes,
        ] {
            defaults.removeObject(forKey: key)
        }
        WidgetCenter.shared.reloadAllTimelines()
    }
}
