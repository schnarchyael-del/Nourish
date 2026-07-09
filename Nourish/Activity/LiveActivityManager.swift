import Foundation
import ActivityKit

// Single entry point for starting / updating / ending the Feed and Sleep
// Live Activities from the main app. The widget extension separately
// runs LiveActivityIntents that mutate shared UserDefaults and call
// Activity.update / .end against the same activity instances — both
// processes see the same ActivityKit records because they share the
// App Group entitlement.
//
// `.liveActivityStateChanged` and `liveActivityLog` live in
// LiveActivityNotifications.swift so they're reachable even if this
// file fails to compile under @available gating.

@available(iOS 16.2, *)
internal final class LiveActivityManager {
    static let shared = LiveActivityManager()
    private init() {}

    private var babyName: String {
        UserDefaults.standard.string(forKey: "babyName") ?? "Baby"
    }

    // MARK: - Feed

    /// Start (or refresh) the feed Live Activity from the SessionStore's
    /// in-memory state. If one is already running, reuses it via update.
    func startFeed(
        currentSide: String,
        sessionStartDate: Date,
        currentSideStartDate: Date,
        leftAccumulatedSeconds: Int,
        rightAccumulatedSeconds: Int,
        isPaused: Bool,
        pausedSideElapsedSeconds: Int
    ) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let state = NourishFeedActivityAttributes.ContentState(
            currentSide: currentSide,
            sessionStartDate: sessionStartDate,
            currentSideStartDate: currentSideStartDate,
            leftAccumulatedSeconds: leftAccumulatedSeconds,
            rightAccumulatedSeconds: rightAccumulatedSeconds,
            isPaused: isPaused,
            pausedSideElapsedSeconds: pausedSideElapsedSeconds
        )

        if let existing = Activity<NourishFeedActivityAttributes>.activities.first {
            Task { await existing.update(using: state) }
            return
        }

        do {
            _ = try Activity.request(
                attributes: NourishFeedActivityAttributes(babyName: babyName),
                contentState: state,
                pushType: nil
            )
        } catch {
            // Authorization or system limits — log to console only; the
            // app remains functional without the Live Activity.
            print("[LiveActivityManager] startFeed failed: \(error)")
        }
    }

    /// Push fresh feed state to the running activity, if any.
    func updateFeed(
        currentSide: String,
        sessionStartDate: Date,
        currentSideStartDate: Date,
        leftAccumulatedSeconds: Int,
        rightAccumulatedSeconds: Int,
        isPaused: Bool,
        pausedSideElapsedSeconds: Int
    ) {
        let state = NourishFeedActivityAttributes.ContentState(
            currentSide: currentSide,
            sessionStartDate: sessionStartDate,
            currentSideStartDate: currentSideStartDate,
            leftAccumulatedSeconds: leftAccumulatedSeconds,
            rightAccumulatedSeconds: rightAccumulatedSeconds,
            isPaused: isPaused,
            pausedSideElapsedSeconds: pausedSideElapsedSeconds
        )
        Task {
            for activity in Activity<NourishFeedActivityAttributes>.activities {
                await activity.update(using: state)
            }
        }
    }

    /// End every running feed activity immediately.
    func endFeed() {
        Task {
            for activity in Activity<NourishFeedActivityAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    // MARK: - Sleep

    func startSleep(startDate: Date) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let state = NourishSleepActivityAttributes.ContentState(sleepStartDate: startDate)

        if let existing = Activity<NourishSleepActivityAttributes>.activities.first {
            Task { await existing.update(using: state) }
            return
        }

        do {
            _ = try Activity.request(
                attributes: NourishSleepActivityAttributes(babyName: babyName),
                contentState: state,
                pushType: nil
            )
        } catch {
            print("[LiveActivityManager] startSleep failed: \(error)")
        }
    }

    func endSleep() {
        Task {
            for activity in Activity<NourishSleepActivityAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    // MARK: - Restore on launch

    /// Called from NourishApp.onAppear. If the app was killed mid-session
    /// but the Live Activity is still on the lock screen, ActivityKit will
    /// retain the instance for us — we just need to refresh its state from
    /// the persisted truth in @AppStorage / shared UserDefaults so the UI
    /// reflects current values rather than the snapshot from before kill.
    func restoreOnLaunch() {
        refreshFeedFromPersistedState()
        refreshSleepFromPersistedState()
    }

    private func refreshFeedFromPersistedState() {
        guard let activity = Activity<NourishFeedActivityAttributes>.activities.first else { return }

        let d = UserDefaults(suiteName: "group.com.yael.nourish")
        let std = UserDefaults.standard

        let currentSide = d?.string(forKey: "widget.activeSessionSide")
            ?? std.string(forKey: "session_currentSide")
            ?? "left"
        let startTs = d?.double(forKey: "widget.activeSessionStart")
            ?? std.double(forKey: "session_startTimestamp")
        // sideStart is REAL wall-clock segment start (0 when paused).
        let sideStart  = d?.double(forKey: "widget.activeSessionSideStart") ?? 0
        let leftAccum  = d?.integer(forKey: "widget.leftAccumulatedSeconds") ?? 0
        let rightAccum = d?.integer(forKey: "widget.rightAccumulatedSeconds") ?? 0
        let pausedAt   = d?.double(forKey: "widget.activeSessionPausedAt") ?? 0
        let isPaused   = pausedAt > 0
        let currentSideAcc = (currentSide == "left") ? leftAccum : rightAccum

        let now = Date.now
        let sessionStart = startTs > 0 ? Date(timeIntervalSince1970: startTs) : now

        // virtualStart = sideStart − accumulator (running) — so the
        // Live Activity's .timer style shows currentSide total. Unused
        // when paused (the view reads pausedSideElapsedSeconds instead).
        let virtualSideStart: Date
        if isPaused {
            virtualSideStart = now
        } else if sideStart > 0 {
            virtualSideStart = Date(timeIntervalSince1970: sideStart - TimeInterval(currentSideAcc))
        } else {
            virtualSideStart = now
        }

        let state = NourishFeedActivityAttributes.ContentState(
            currentSide: currentSide,
            sessionStartDate: sessionStart,
            currentSideStartDate: virtualSideStart,
            leftAccumulatedSeconds: leftAccum,
            rightAccumulatedSeconds: rightAccum,
            isPaused: isPaused,
            // Accumulator already includes any committed segment when paused.
            pausedSideElapsedSeconds: isPaused ? currentSideAcc : 0
        )
        Task { await activity.update(using: state) }
    }

    private func refreshSleepFromPersistedState() {
        guard let activity = Activity<NourishSleepActivityAttributes>.activities.first else { return }

        let ts = UserDefaults.standard.double(forKey: "activeSleepStartedAt")
        guard ts > 0 else {
            // Sleep is no longer active but the activity is still on screen
            // (force-quit while sleeping, ended elsewhere). Dismiss it.
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
            return
        }
        let state = NourishSleepActivityAttributes.ContentState(
            sleepStartDate: Date(timeIntervalSince1970: ts)
        )
        Task { await activity.update(using: state) }
    }
}
