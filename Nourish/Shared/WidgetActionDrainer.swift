import Foundation
import SwiftData

/// Reads the pending-action queue the widget extension wrote into shared
/// UserDefaults and converts each action into a real SwiftData
/// `FeedingSession` (or in-app state change), then pushes to Firestore.
/// Called from `NourishApp` on launch + every foreground transition.
enum WidgetActionDrainer {

    @MainActor
    static func drainPending(modelContainer: ModelContainer) {
        let actions = WidgetActionQueue.drain()
        guard !actions.isEmpty else { return }

        let context = ModelContext(modelContainer)

        for action in actions {
            switch action.kind {
            case .endSleep:
                applyEndSleep(action, context: context)
            case .endFeed:
                applyEndFeed(action, context: context)
            case .pauseToggleFeed, .switchSide:
                // Widget already mutated the shared snapshot for these.
                // The in-app SessionStore will pick up the changes if the
                // user opens the active-session screen, via its own
                // snapshot-restore path. No SwiftData write needed here.
                break
            }
        }

        try? context.save()
        SharedFeedSnapshot.refresh(modelContainer: modelContainer)
    }

    @MainActor
    private static func applyEndSleep(_ action: WidgetAction, context: ModelContext) {
        guard let startTs = action.sleepStartTs, startTs > 0 else { return }
        let start = Date(timeIntervalSince1970: startTs)
        let end   = Date(timeIntervalSince1970: action.timestamp)
        let duration = max(0, Int(end.timeIntervalSince(start)))

        let session = FeedingSession(
            startTime: start,
            feedType: .sleep,
            endTime: end
        )
        context.insert(session)
        Task { await FirestoreService.shared.pushSession(session) }
        AnalyticsService.sleepEnded(durationSeconds: duration)

        // Make sure the in-app AppStorage flag matches the cleared shared state.
        UserDefaults.standard.set(0.0, forKey: "activeSleepStartedAt")
    }

    @MainActor
    private static func applyEndFeed(_ action: WidgetAction, context: ModelContext) {
        guard let startTs = action.feedStartTs, startTs > 0 else { return }
        let start = Date(timeIntervalSince1970: startTs)
        let end   = Date(timeIntervalSince1970: action.timestamp)

        let currentSide = action.currentSide ?? "left"
        let feedType: FeedType = currentSide == "right" ? .right : .left

        let session = FeedingSession(
            startTime: start,
            feedType: feedType,
            endTime: end,
            leftDurationMins: action.leftMinutes,
            rightDurationMins: action.rightMinutes
        )
        context.insert(session)
        Task { await FirestoreService.shared.pushSession(session) }

        let totalSecs = ((action.leftMinutes ?? 0) + (action.rightMinutes ?? 0)) * 60
        AnalyticsService.sessionCompleted(
            totalSeconds: totalSecs,
            leftSeconds:  (action.leftMinutes  ?? 0) * 60,
            rightSeconds: (action.rightMinutes ?? 0) * 60,
            feedType: "breast"
        )
    }
}
