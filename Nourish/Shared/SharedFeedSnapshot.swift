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
        static let isSessionActive       = "widget.isSessionActive"
        static let activeSessionStart    = "widget.activeSessionStart"
        static let activeSessionSide     = "widget.activeSessionSide"
        static let activePausedAt        = "widget.activeSessionPausedAt"      // 0 = not paused
        static let activeAccumulatedPause = "widget.activeSessionAccumulatedPause"
    }

    /// Mark a session as active in the shared snapshot and reload widgets.
    /// Pause state is included so the widget can freeze its live timer.
    static func setActiveSession(
        side: String,
        start: Date,
        pausedAt: Date? = nil,
        accumulatedPausedSeconds: Int = 0
    ) {
        guard let defaults = UserDefaults(suiteName: Key.suiteName) else { return }
        defaults.set(true, forKey: Key.isSessionActive)
        defaults.set(side, forKey: Key.activeSessionSide)
        defaults.set(start.timeIntervalSince1970, forKey: Key.activeSessionStart)
        defaults.set(pausedAt?.timeIntervalSince1970 ?? 0, forKey: Key.activePausedAt)
        defaults.set(accumulatedPausedSeconds, forKey: Key.activeAccumulatedPause)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Clear active-session flags (session ended or was discarded). Reload widgets.
    static func clearActiveSession() {
        guard let defaults = UserDefaults(suiteName: Key.suiteName) else { return }
        defaults.set(false, forKey: Key.isSessionActive)
        defaults.removeObject(forKey: Key.activeSessionStart)
        defaults.removeObject(forKey: Key.activeSessionSide)
        defaults.removeObject(forKey: Key.activePausedAt)
        defaults.removeObject(forKey: Key.activeAccumulatedPause)
        WidgetCenter.shared.reloadAllTimelines()
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

        // Last FEED (breast or bottle only — pump sessions don't tell the user
        // when the baby last ate, which is what the widget shows).
        let lastFeed = sessions.first(where: { $0.feedType != .pump })
        if let last = lastFeed {
            let lastSide = last.feedType.rawValue
            let durationSeconds = last.feedType == .bottle
                ? 0
                : (last.leftMinutesResolved + last.rightMinutesResolved) * 60

            defaults.set(last.startTime.timeIntervalSince1970, forKey: Key.lastFeedTime)
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

        // Today's feed totals (since startOfDay, breast+bottle only — pumps excluded)
        let dayStart = Calendar.current.startOfDay(for: .now)
        let today = sessions.filter { $0.startTime >= dayStart && $0.feedType != .pump }
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
            Key.isSessionActive, Key.activeSessionStart, Key.activeSessionSide,
            Key.activePausedAt, Key.activeAccumulatedPause,
        ] {
            defaults.removeObject(forKey: key)
        }
        WidgetCenter.shared.reloadAllTimelines()
    }
}
