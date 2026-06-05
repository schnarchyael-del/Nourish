import AppIntents
import WidgetKit
import Foundation

// MARK: - Helpers shared by all intents

private let suiteName = "group.com.yael.nourish"

private func sharedDefaults() -> UserDefaults? {
    UserDefaults(suiteName: suiteName)
}

// MARK: - End Sleep

/// "Baby woke up" from the widget. Saves the end timestamp to the queue,
/// clears the active-sleep flags so the widget refreshes immediately.
struct EndSleepIntent: AppIntent {
    static var title: LocalizedStringResource = "Baby woke up"
    static var description = IntentDescription("End the current nap and save it.")
    static var isDiscoverable = false
    /// Critical: without this, iOS opens the app on every tap and the
    /// widget never gets a chance to refresh in place.
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult {
        guard let d = sharedDefaults() else { return .result() }
        let startTs = d.double(forKey: "widget.sleepStartedAt")

        if startTs > 0 {
            WidgetActionQueue.append(WidgetAction(
                kind: .endSleep,
                timestamp: Date.now.timeIntervalSince1970,
                sleepStartTs: startTs
            ))
        }

        d.set(false, forKey: "widget.isBabySleeping")
        d.removeObject(forKey: "widget.sleepStartedAt")

        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

// MARK: - End Feed

/// Ends and saves the currently-active feed session. Pulls the active
/// session metadata (start, side, per-side minutes accumulated so far)
/// out of shared UserDefaults and queues an action for the main app to
/// persist on next foreground.
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

        // Clear active-session flags so the widget reverts to "last feed" mode.
        d.set(false, forKey: "widget.isSessionActive")
        d.removeObject(forKey: "widget.activeSessionStart")
        d.removeObject(forKey: "widget.activeSessionSide")
        d.removeObject(forKey: "widget.activeSessionSideStart")
        d.removeObject(forKey: "widget.activeSessionPausedSideSeconds")
        d.removeObject(forKey: "widget.activeSessionPausedAt")

        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

// MARK: - Pause / Resume

/// Toggles the active-session pause flag. The widget timer reads from
/// `widget.activeSessionPausedAt` to render the static paused timer.
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
            // Currently paused — resume. Shift the virtual side-start so the
            // elapsed time picks up where it left off.
            let pauseDuration = now.timeIntervalSince1970 - pausedAt
            let sideStart = d.double(forKey: "widget.activeSessionSideStart")
            if sideStart > 0 {
                d.set(sideStart + pauseDuration, forKey: "widget.activeSessionSideStart")
            }
            d.set(0.0, forKey: "widget.activeSessionPausedAt")
            d.set(0,   forKey: "widget.activeSessionPausedSideSeconds")
        } else {
            // Currently running — pause. Freeze the per-side elapsed
            // seconds so the static readout is correct.
            let sideStart = d.double(forKey: "widget.activeSessionSideStart")
            if sideStart > 0 {
                let frozen = max(0, Int(now.timeIntervalSince1970 - sideStart))
                d.set(frozen, forKey: "widget.activeSessionPausedSideSeconds")
            }
            d.set(now.timeIntervalSince1970, forKey: "widget.activeSessionPausedAt")
        }

        WidgetActionQueue.append(WidgetAction(
            kind: .pauseToggleFeed,
            timestamp: now.timeIntervalSince1970
        ))

        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

// MARK: - Switch Side

/// Switches the active side. Records elapsed minutes on the side being
/// left so the app can save the correct split when the session ends.
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

        // Snapshot the current side's accumulated minutes BEFORE the switch.
        let (left, right) = currentSideMinutes(from: d)

        // Reset the virtual side-start clock so the timer for the new side
        // begins from zero.
        d.set(now.timeIntervalSince1970, forKey: "widget.activeSessionSideStart")
        d.set(newSide,                   forKey: "widget.activeSessionSide")
        d.set(0.0, forKey: "widget.activeSessionPausedAt")
        d.set(0,   forKey: "widget.activeSessionPausedSideSeconds")

        WidgetActionQueue.append(WidgetAction(
            kind: .switchSide,
            timestamp: now.timeIntervalSince1970,
            leftMinutes: left,
            rightMinutes: right,
            newSide: newSide
        ))

        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

// MARK: - Shared helper

/// Best-effort current per-side minutes derived from the live side
/// snapshot. The widget doesn't have full session history, just the
/// currently-active side's start; this gives one decent component.
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
