import Foundation
import SwiftData

/// Processes "session ended from widget" flags that the widget extension
/// sets in shared UserDefaults. Reads the FULL session state from shared
/// (start time, start side, current side, L/R accumulators, current
/// segment's elapsed time) and turns it into a SwiftData `FeedingSession`
/// + Firestore push.
///
/// Replaces the old queue-based drainer. There's no queue anymore — the
/// shared snapshot IS the queue, and it always has the most accurate
/// state because both the app and the widget intents commit accumulators
/// to it on every change.
enum WidgetActionDrainer {

    @MainActor
    static func drainPending(modelContainer: ModelContainer) {
        guard let d = UserDefaults(suiteName: "group.com.yael.nourish") else { return }
        let context = ModelContext(modelContainer)
        var didMutate = false

        // Feed ended from widget?
        if d.bool(forKey: "widget.sessionEndedFromWidget") {
            applyEndFeed(d: d, context: context)
            didMutate = true
        }

        // Sleep ended from widget?
        if d.bool(forKey: "widget.sleepEndedFromWidget") {
            applyEndSleep(d: d, context: context)
            didMutate = true
        }

        if didMutate {
            try? context.save()
            SharedFeedSnapshot.refresh(modelContainer: modelContainer)
        }
    }

    // MARK: - End feed

    @MainActor
    private static func applyEndFeed(d: UserDefaults, context: ModelContext) {
        let startTs = d.double(forKey: "widget.activeSessionStart")
        let endTs   = d.double(forKey: "widget.sessionEndTime")
        guard startTs > 0 else { clearFeedKeys(d); return }

        let endTime = endTs > 0 ? endTs : Date.now.timeIntervalSince1970
        let startSide   = d.string(forKey: "widget.activeSessionStartSide") ?? "left"
        let currentSide = d.string(forKey: "widget.activeSessionSide") ?? startSide

        // Committed accumulators (set by the app + by SwitchSide intent).
        let leftAccum  = d.integer(forKey: "widget.leftAccumulatedSeconds")
        let rightAccum = d.integer(forKey: "widget.rightAccumulatedSeconds")

        // The current segment's elapsed time was never committed (the user
        // tapped End mid-segment). Roll it into the right accumulator now.
        let sideStart = d.double(forKey: "widget.activeSessionSideStart")
        let pausedSec = d.integer(forKey: "widget.activeSessionPausedSideSeconds")
        let segmentSec: Int = {
            if pausedSec > 0 { return pausedSec }
            guard sideStart > 0 else { return 0 }
            return max(0, Int(endTime - sideStart))
        }()
        let finalLeftSec  = currentSide == "left"  ? leftAccum + segmentSec : leftAccum
        let finalRightSec = currentSide == "right" ? rightAccum + segmentSec : rightAccum

        let feedType: FeedType = (startSide == "right") ? .right : .left

        let session = FeedingSession(
            startTime: Date(timeIntervalSince1970: startTs),
            feedType: feedType,
            endTime: Date(timeIntervalSince1970: endTime),
            leftDurationMins:  finalLeftSec  / 60,
            rightDurationMins: finalRightSec / 60
        )
        context.insert(session)
        Task { await FirestoreService.shared.pushSession(session) }
        AnalyticsService.sessionCompleted(
            totalSeconds: finalLeftSec + finalRightSec,
            leftSeconds:  finalLeftSec,
            rightSeconds: finalRightSec,
            feedType: "breast"
        )

        // Clear EVERY active-session key so the app's SessionStore can
        // recover into a clean "no active session" state on next access.
        clearFeedKeys(d)
    }

    private static func clearFeedKeys(_ d: UserDefaults) {
        d.set(false, forKey: "widget.isSessionActive")
        d.set(false, forKey: "widget.sessionEndedFromWidget")
        d.removeObject(forKey: "widget.sessionEndTime")
        d.removeObject(forKey: "widget.activeSessionStart")
        d.removeObject(forKey: "widget.activeSessionStartSide")
        d.removeObject(forKey: "widget.activeSessionSide")
        d.removeObject(forKey: "widget.activeSessionSideStart")
        d.removeObject(forKey: "widget.activeSessionPausedAt")
        d.removeObject(forKey: "widget.activeSessionPausedSideSeconds")
        d.removeObject(forKey: "widget.leftAccumulatedSeconds")
        d.removeObject(forKey: "widget.rightAccumulatedSeconds")
        // Clear SessionStore's own legacy persistence so it doesn't
        // recover a phantom session next launch.
        let std = UserDefaults.standard
        for key in [
            "session_startTimestamp", "session_currentSide", "session_startSide",
            "session_switchedAt", "session_pausedTimestamp", "session_accumulatedPause",
            "session_leftActiveSeconds", "session_rightActiveSeconds",
            "session_currentSideStartedAtElapsed",
        ] {
            std.removeObject(forKey: key)
        }
    }

    // MARK: - End sleep

    @MainActor
    private static func applyEndSleep(d: UserDefaults, context: ModelContext) {
        let startTs = d.double(forKey: "widget.sleepStartedAt")
        let endTs   = d.double(forKey: "widget.sleepEndTime")
        guard startTs > 0 else { clearSleepKeys(d); return }
        let endTime = endTs > 0 ? endTs : Date.now.timeIntervalSince1970

        let session = FeedingSession(
            startTime: Date(timeIntervalSince1970: startTs),
            feedType: .sleep,
            endTime: Date(timeIntervalSince1970: endTime)
        )
        context.insert(session)
        Task { await FirestoreService.shared.pushSession(session) }
        AnalyticsService.sleepEnded(durationSeconds: max(0, Int(endTime - startTs)))

        clearSleepKeys(d)
    }

    private static func clearSleepKeys(_ d: UserDefaults) {
        d.set(false, forKey: "widget.isBabySleeping")
        d.set(false, forKey: "widget.sleepEndedFromWidget")
        d.removeObject(forKey: "widget.sleepStartedAt")
        d.removeObject(forKey: "widget.sleepEndTime")
        // Local AppStorage mirror used by SleepView.
        UserDefaults.standard.set(0.0, forKey: "activeSleepStartedAt")
    }
}
