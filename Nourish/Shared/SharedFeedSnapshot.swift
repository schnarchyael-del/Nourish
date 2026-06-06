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
        // Session start — used by widget for the 6-hour stale-session guard.
        static let activeSessionStart    = "widget.activeSessionStart"
        // Current side letter ("left"/"right") — updated on every switch.
        static let activeSessionSide     = "widget.activeSessionSide"
        // Virtual start date for the current side's live timer.
        // Computed as (now - currentSideSeconds) so Text(..., style:.timer)
        // shows the correct per-side elapsed time, including accumulated time
        // from previous segments on this side.
        static let activeSessionSideStart      = "widget.activeSessionSideStart"
        // Frozen side-elapsed seconds written only when pausing; cleared on resume.
        static let activeSessionPausedSideSeconds = "widget.activeSessionPausedSideSeconds"
        // Pause timestamp (non-zero = paused).
        static let activePausedAt        = "widget.activeSessionPausedAt"
        // Sleep — written when "Baby fell asleep" is tapped; cleared on "Baby woke up".
        // The widget composes its own elapsed string from `now - sleepStartedAt`.
        static let isBabySleeping        = "widget.isBabySleeping"
        static let sleepStartedAt        = "widget.sleepStartedAt"

        // Single-source-of-truth additions for widget-driven mutations.
        // Without these, widget intents would have no idea what the
        // SessionStore's per-side accumulators actually contain.
        static let leftAccumSeconds      = "widget.leftAccumulatedSeconds"
        static let rightAccumSeconds     = "widget.rightAccumulatedSeconds"
        static let startSide             = "widget.activeSessionStartSide"

        // End-of-session flags set by widget intents. The app reads these on
        // launch / foreground / Darwin notification and translates them into
        // a real SwiftData FeedingSession — using the shared accumulators,
        // never any data the intent itself computed.
        static let sessionEndedFromWidget = "widget.sessionEndedFromWidget"
        static let sessionEndTime         = "widget.sessionEndTime"
        static let sleepEndedFromWidget   = "widget.sleepEndedFromWidget"
        static let sleepEndTime           = "widget.sleepEndTime"
    }

    /// Mark a session as active in the shared snapshot and reload widgets.
    ///
    /// - Parameters:
    ///   - sessionStart: True wall-clock start of the session (used for stale check).
    ///   - currentSide: The side currently being fed ("left" or "right").
    ///   - sideEffectiveStart: Virtual start date such that `now − sideEffectiveStart`
    ///     equals the total accumulated seconds on `currentSide`. Used by the widget's
    ///     `.timer` style to show per-side elapsed time.
    ///   - pausedAt: The moment the session was paused, or `nil` if not paused.
    ///   - pausedSideSeconds: Frozen side-elapsed seconds written when pausing so the
    ///     widget can show a static readout. Pass 0 when not paused.
    static func setActiveSession(
        sessionStart: Date,
        startSide: String,
        currentSide: String,
        sideEffectiveStart: Date,
        leftAccumulatedSeconds: Int,
        rightAccumulatedSeconds: Int,
        pausedAt: Date? = nil,
        pausedSideSeconds: Int = 0
    ) {
        guard let defaults = UserDefaults(suiteName: Key.suiteName) else { return }
        defaults.set(true,                                     forKey: Key.isSessionActive)
        defaults.set(sessionStart.timeIntervalSince1970,       forKey: Key.activeSessionStart)
        defaults.set(startSide,                                forKey: Key.startSide)
        defaults.set(currentSide,                              forKey: Key.activeSessionSide)
        defaults.set(sideEffectiveStart.timeIntervalSince1970, forKey: Key.activeSessionSideStart)
        defaults.set(leftAccumulatedSeconds,                   forKey: Key.leftAccumSeconds)
        defaults.set(rightAccumulatedSeconds,                  forKey: Key.rightAccumSeconds)
        defaults.set(pausedAt?.timeIntervalSince1970 ?? 0,     forKey: Key.activePausedAt)
        defaults.set(pausedSideSeconds,                        forKey: Key.activeSessionPausedSideSeconds)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Mark a sleep in progress so the widget can overlay "Sleeping · 1h 23m".
    /// Composes alongside existing feed info — never replaces it.
    static func setActiveSleep(startedAt: Date) {
        guard let defaults = UserDefaults(suiteName: Key.suiteName) else { return }
        defaults.set(true, forKey: Key.isBabySleeping)
        defaults.set(startedAt.timeIntervalSince1970, forKey: Key.sleepStartedAt)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Clear sleep flags (baby woke up or session was discarded).
    static func clearActiveSleep() {
        guard let defaults = UserDefaults(suiteName: Key.suiteName) else { return }
        defaults.set(false, forKey: Key.isBabySleeping)
        defaults.removeObject(forKey: Key.sleepStartedAt)
        defaults.set(false, forKey: Key.sleepEndedFromWidget)
        defaults.removeObject(forKey: Key.sleepEndTime)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Clear active-session flags (session ended or was discarded). Reload widgets.
    static func clearActiveSession() {
        guard let defaults = UserDefaults(suiteName: Key.suiteName) else { return }
        defaults.set(false, forKey: Key.isSessionActive)
        defaults.removeObject(forKey: Key.activeSessionStart)
        defaults.removeObject(forKey: Key.startSide)
        defaults.removeObject(forKey: Key.activeSessionSide)
        defaults.removeObject(forKey: Key.activeSessionSideStart)
        defaults.removeObject(forKey: Key.activeSessionPausedSideSeconds)
        defaults.removeObject(forKey: Key.activePausedAt)
        defaults.removeObject(forKey: Key.leftAccumSeconds)
        defaults.removeObject(forKey: Key.rightAccumSeconds)
        defaults.set(false, forKey: Key.sessionEndedFromWidget)
        defaults.removeObject(forKey: Key.sessionEndTime)
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

        // Last FEED (breast or bottle only — pump and sleep sessions don't
        // tell the user when the baby last ate, which is what the widget shows).
        let lastFeed = sessions.first(where: { $0.feedType != .pump && $0.feedType != .sleep })
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

        // Today's feed totals (since startOfDay, breast+bottle only — pumps and sleep excluded)
        let dayStart = Calendar.current.startOfDay(for: .now)
        let today = sessions.filter { $0.startTime >= dayStart && $0.feedType != .pump && $0.feedType != .sleep }
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
            Key.activeSessionSideStart, Key.activeSessionPausedSideSeconds,
            Key.activePausedAt,
        ] {
            defaults.removeObject(forKey: key)
        }
        WidgetCenter.shared.reloadAllTimelines()
    }
}
