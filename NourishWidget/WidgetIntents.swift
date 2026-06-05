import AppIntents
import WidgetKit
import Foundation

// MARK: - Helpers shared by all intents

private let suiteName = "group.com.yael.nourish"

private func sharedDefaults() -> UserDefaults? {
    UserDefaults(suiteName: suiteName)
}

// Order of operations inside every perform():
//   1. Update the user-visible state in shared UserDefaults
//   2. WidgetCenter.shared.reloadAllTimelines()  ← refresh the widget NOW
//   3. Append the action to the persistence queue (for the app to drain
//      on next foreground — SwiftData + Firestore writes happen there,
//      never inside the intent)

// MARK: - End Sleep

struct EndSleepIntent: AppIntent {
    static var title: LocalizedStringResource = "Baby woke up"
    static var description = IntentDescription("End the current nap and save it.")
    static var isDiscoverable = false
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult {
        guard let d = sharedDefaults() else { return .result() }
        let startTs = d.double(forKey: "widget.sleepStartedAt")

        // 1. Update visible state.
        d.set(false, forKey: "widget.isBabySleeping")
        d.removeObject(forKey: "widget.sleepStartedAt")

        // 2. Refresh widgets + ping the app (if it's running) so it can
        //    reconcile its in-memory state in real time.
        WidgetCenter.shared.reloadAllTimelines()
        WidgetSyncBridge.postChanged()

        // 3. Queue for app to persist on next foreground.
        if startTs > 0 {
            WidgetActionQueue.append(WidgetAction(
                kind: .endSleep,
                timestamp: Date.now.timeIntervalSince1970,
                sleepStartTs: startTs
            ))
        }
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
        let startTs    = d.double(forKey: "widget.activeSessionStart")
        let currentSide = d.string(forKey: "widget.activeSessionSide") ?? ""
        let (left, right) = currentSideMinutes(from: d)

        // 1. Clear visible state.
        d.set(false, forKey: "widget.isSessionActive")
        d.removeObject(forKey: "widget.activeSessionStart")
        d.removeObject(forKey: "widget.activeSessionSide")
        d.removeObject(forKey: "widget.activeSessionSideStart")
        d.removeObject(forKey: "widget.activeSessionPausedSideSeconds")
        d.removeObject(forKey: "widget.activeSessionPausedAt")

        // 2. Refresh widgets + ping the app (if it's running) so it can
        //    reconcile its in-memory state in real time.
        WidgetCenter.shared.reloadAllTimelines()
        WidgetSyncBridge.postChanged()

        // 3. Queue.
        if startTs > 0 {
            WidgetActionQueue.append(WidgetAction(
                kind: .endFeed,
                timestamp: Date.now.timeIntervalSince1970,
                leftMinutes: left,
                rightMinutes: right,
                newSide: nil,
                feedStartTs: startTs,
                currentSide: currentSide
            ))
        }
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

        // 1. Toggle visible state.
        if pausedAt > 0 {
            // Resume — shift side-start forward by the pause duration so
            // the live timer picks up where it left off.
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

        // 2. Refresh widgets + ping the app (if it's running) so it can
        //    reconcile its in-memory state in real time.
        WidgetCenter.shared.reloadAllTimelines()
        WidgetSyncBridge.postChanged()

        // 3. Queue.
        WidgetActionQueue.append(WidgetAction(
            kind: .pauseToggleFeed,
            timestamp: now.timeIntervalSince1970
        ))
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
        let (left, right) = currentSideMinutes(from: d)

        // 1. Flip side; reset the per-side virtual clock.
        d.set(now.timeIntervalSince1970, forKey: "widget.activeSessionSideStart")
        d.set(newSide,                   forKey: "widget.activeSessionSide")
        d.set(0.0, forKey: "widget.activeSessionPausedAt")
        d.set(0,   forKey: "widget.activeSessionPausedSideSeconds")

        // 2. Refresh widgets + ping the app (if it's running) so it can
        //    reconcile its in-memory state in real time.
        WidgetCenter.shared.reloadAllTimelines()
        WidgetSyncBridge.postChanged()

        // 3. Queue.
        WidgetActionQueue.append(WidgetAction(
            kind: .switchSide,
            timestamp: now.timeIntervalSince1970,
            leftMinutes: left,
            rightMinutes: right,
            newSide: newSide
        ))
        return .result()
    }
}

// MARK: - Shared helper

private func currentSideMinutes(from d: UserDefaults) -> (left: Int, right: Int) {
    let sideStart = d.double(forKey: "widget.activeSessionSideStart")
    let pausedSec = d.integer(forKey: "widget.activeSessionPausedSideSeconds")
    let side      = d.string(forKey: "widget.activeSessionSide") ?? "left"

    let elapsedSec: Int = {
        if pausedSec > 0 { return pausedSec }
        guard sideStart > 0 else { return 0 }
        return max(0, Int(Date.now.timeIntervalSince1970 - sideStart))
    }()
    let mins = elapsedSec / 60

    return side == "left" ? (mins, 0) : (0, mins)
}
