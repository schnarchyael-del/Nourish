import AppIntents
import WidgetKit
import Foundation

// MARK: - Helpers shared by all intents

private let suiteName = "group.com.yael.nourish"

private func sharedDefaults() -> UserDefaults? {
    UserDefaults(suiteName: suiteName)
}

// MARK: - Architecture
//
// Shared UserDefaults (group.com.yael.nourish) is the SINGLE source of truth
// for active session state. The app and the widget extension both read and
// write through it. Intents NEVER touch SwiftData or Firestore directly —
// those side effects happen exclusively on the app side when it sees a state
// change (via Darwin notification or scene-phase). This avoids divergence,
// race conditions, and ghost sessions caused by partial computations.
//
// Order inside every perform():
//   1. Mutate shared UserDefaults (the source of truth)
//   2. WidgetCenter.shared.reloadAllTimelines()   ← refresh widget NOW
//   3. WidgetSyncBridge.postChanged()             ← ping the app NOW

// MARK: - End Sleep

struct EndSleepIntent: AppIntent {
    static var title: LocalizedStringResource = "Baby woke up"
    static var description = IntentDescription("End the current nap and save it.")
    static var isDiscoverable = false
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult {
        guard let d = sharedDefaults() else { return .result() }
        let now = Date.now.timeIntervalSince1970

        // Flip the sleep flag + record when it happened. The app reads
        // these on next active and saves the nap as a FeedingSession.
        d.set(false, forKey: "widget.isBabySleeping")
        d.set(true,  forKey: "widget.sleepEndedFromWidget")
        d.set(now,   forKey: "widget.sleepEndTime")

        WidgetCenter.shared.reloadAllTimelines()
        WidgetSyncBridge.postChanged()
        return .result()
    }
}

// MARK: - End Feed

struct EndFeedIntent: AppIntent {
    static var title: LocalizedStringResource = "End feed"
    static var description = IntentDescription("End the current feeding session and save it.")
    static var isDiscoverable = false
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult {
        guard let d = sharedDefaults() else { return .result() }
        let now = Date.now.timeIntervalSince1970

        // Don't compute splits or save anything here — the widget process
        // only has partial state. Just record that the session ended.
        // The app's WidgetEndProcessor will use the FULL shared state
        // (accumulators + start side + current side's pending segment)
        // to create an accurate FeedingSession.
        d.set(false, forKey: "widget.isSessionActive")
        d.set(true,  forKey: "widget.sessionEndedFromWidget")
        d.set(now,   forKey: "widget.sessionEndTime")
        // Clear timer-display fields so the widget reverts to "last feed"
        // mode. The accumulator + start/side fields are intentionally kept
        // so the app has the data it needs to save the session.
        d.set(0.0, forKey: "widget.activeSessionPausedAt")
        d.set(0,   forKey: "widget.activeSessionPausedSideSeconds")

        WidgetCenter.shared.reloadAllTimelines()
        WidgetSyncBridge.postChanged()
        return .result()
    }
}

// MARK: - Pause / Resume

struct PauseFeedIntent: AppIntent {
    static var title: LocalizedStringResource = "Pause / resume feed"
    static var description = IntentDescription("Pause or resume the current feeding session.")
    static var isDiscoverable = false
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult {
        guard let d = sharedDefaults() else { return .result() }
        let pausedAt = d.double(forKey: "widget.activeSessionPausedAt")
        let now = Date.now

        if pausedAt > 0 {
            // Resume — shift side-start forward by pause duration so the
            // live timer picks up where it left off.
            let pauseDuration = now.timeIntervalSince1970 - pausedAt
            let sideStart = d.double(forKey: "widget.activeSessionSideStart")
            if sideStart > 0 {
                d.set(sideStart + pauseDuration, forKey: "widget.activeSessionSideStart")
            }
            d.set(0.0, forKey: "widget.activeSessionPausedAt")
            d.set(0,   forKey: "widget.activeSessionPausedSideSeconds")
        } else {
            // Pause — freeze the per-side elapsed reading.
            let sideStart = d.double(forKey: "widget.activeSessionSideStart")
            if sideStart > 0 {
                let frozen = max(0, Int(now.timeIntervalSince1970 - sideStart))
                d.set(frozen, forKey: "widget.activeSessionPausedSideSeconds")
            }
            d.set(now.timeIntervalSince1970, forKey: "widget.activeSessionPausedAt")
        }

        WidgetCenter.shared.reloadAllTimelines()
        WidgetSyncBridge.postChanged()
        return .result()
    }
}

// MARK: - Switch Side

struct SwitchSideIntent: AppIntent {
    static var title: LocalizedStringResource = "Switch side"
    static var description = IntentDescription("Switch the breast being fed.")
    static var isDiscoverable = false
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult {
        guard let d = sharedDefaults() else { return .result() }
        let currentSide = d.string(forKey: "widget.activeSessionSide") ?? "left"
        let newSide = (currentSide == "left") ? "right" : "left"
        let now = Date.now

        // Compute the current segment's elapsed seconds and COMMIT them to
        // the appropriate accumulator. This is what keeps L/R totals
        // accurate when the user switches from the widget.
        let sideStart = d.double(forKey: "widget.activeSessionSideStart")
        let pausedSec = d.integer(forKey: "widget.activeSessionPausedSideSeconds")
        let segmentSec: Int = {
            if pausedSec > 0 { return pausedSec }      // session was paused — segment is frozen
            guard sideStart > 0 else { return 0 }
            return max(0, Int(now.timeIntervalSince1970 - sideStart))
        }()

        if currentSide == "left" {
            let left = d.integer(forKey: "widget.leftAccumulatedSeconds")
            d.set(left + segmentSec, forKey: "widget.leftAccumulatedSeconds")
        } else {
            let right = d.integer(forKey: "widget.rightAccumulatedSeconds")
            d.set(right + segmentSec, forKey: "widget.rightAccumulatedSeconds")
        }

        // Flip the side and reset the segment clock.
        d.set(newSide,                   forKey: "widget.activeSessionSide")
        d.set(now.timeIntervalSince1970, forKey: "widget.activeSessionSideStart")
        d.set(0.0, forKey: "widget.activeSessionPausedAt")
        d.set(0,   forKey: "widget.activeSessionPausedSideSeconds")

        WidgetCenter.shared.reloadAllTimelines()
        WidgetSyncBridge.postChanged()
        return .result()
    }
}
