import AppIntents
import ActivityKit
import WidgetKit
import Foundation
import os.log

// Widget-target copy. iOS routes LiveActivityIntent execution to the main
// app's binary at runtime — this file exists so `Button(intent:)` call
// sites compile. Logic mirrors Nourish/Activity/NourishLiveActivityIntents.swift
// as a defensive fallback.

private let suiteName = "group.com.yael.nourish"
private func sharedDefaults() -> UserDefaults? { UserDefaults(suiteName: suiteName) }
private let widgetLiveLog = Logger(subsystem: "com.yael.nourish", category: "LiveActivity.widget")

private func bumpSnapshotVersion() {
    sharedDefaults()?.set(Date.now.timeIntervalSince1970, forKey: "widget.snapshotVersion")
}

// MARK: - Pause / Resume

@available(iOS 17.0, *)
struct PauseFeedLiveIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Pause feed"
    static var description = IntentDescription("Pause or resume the active feed.")

    @MainActor func perform() async throws -> some IntentResult {
        widgetLiveLog.notice("INTENT FIRED (widget copy): PauseFeedLiveIntent")
        guard let d = sharedDefaults() else { return .result() }
        let now = Date.now
        let pausedAt = d.double(forKey: "widget.activeSessionPausedAt")

        if pausedAt > 0 {
            d.set(now.timeIntervalSince1970, forKey: "widget.activeSessionSideStart")
            d.set(0.0, forKey: "widget.activeSessionPausedAt")
        } else {
            let currentSide = d.string(forKey: "widget.activeSessionSide") ?? "left"
            let sideStart   = d.double(forKey: "widget.activeSessionSideStart")
            let accKey      = (currentSide == "left") ? "widget.leftAccumulatedSeconds" : "widget.rightAccumulatedSeconds"
            let accBefore   = d.integer(forKey: accKey)
            let segment: Int = (sideStart > 0)
                ? max(0, Int(now.timeIntervalSince1970 - sideStart))
                : 0
            d.set(accBefore + segment, forKey: accKey)
            d.set(now.timeIntervalSince1970, forKey: "widget.activeSessionPausedAt")
            d.set(0.0, forKey: "widget.activeSessionSideStart")
        }

        bumpSnapshotVersion()
        await updateFeedActivityFromShared()
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

// MARK: - Switch Side

@available(iOS 17.0, *)
struct SwitchSideLiveIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Switch side"
    static var description = IntentDescription("Switch the breast being fed.")

    @MainActor func perform() async throws -> some IntentResult {
        widgetLiveLog.notice("INTENT FIRED (widget copy): SwitchSideLiveIntent")
        guard let d = sharedDefaults() else { return .result() }
        let now = Date.now
        let currentSide = d.string(forKey: "widget.activeSessionSide") ?? "left"
        let newSide = (currentSide == "left") ? "right" : "left"
        let pausedAt = d.double(forKey: "widget.activeSessionPausedAt")

        if pausedAt == 0 {
            let sideStart = d.double(forKey: "widget.activeSessionSideStart")
            let outgoingKey = (currentSide == "left") ? "widget.leftAccumulatedSeconds" : "widget.rightAccumulatedSeconds"
            let accBefore = d.integer(forKey: outgoingKey)
            let segment: Int = (sideStart > 0)
                ? max(0, Int(now.timeIntervalSince1970 - sideStart))
                : 0
            d.set(accBefore + segment, forKey: outgoingKey)
        }

        // Switch always resumes — matches in-app behaviour.
        d.set(newSide, forKey: "widget.activeSessionSide")
        d.set(now.timeIntervalSince1970, forKey: "widget.activeSessionSideStart")
        d.set(0.0, forKey: "widget.activeSessionPausedAt")

        bumpSnapshotVersion()
        await updateFeedActivityFromShared()
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

// MARK: - End Feed

@available(iOS 17.0, *)
struct EndFeedLiveIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "End feed"
    static var description = IntentDescription("End the current feeding session.")

    @MainActor func perform() async throws -> some IntentResult {
        widgetLiveLog.notice("INTENT FIRED (widget copy): EndFeedLiveIntent")
        guard let d = sharedDefaults() else { return .result() }
        let now = Date.now.timeIntervalSince1970

        d.set(false, forKey: "widget.isSessionActive")
        d.set(true,  forKey: "widget.sessionEndedFromWidget")
        d.set(now,   forKey: "widget.sessionEndTime")
        d.set(0.0, forKey: "widget.activeSessionPausedAt")
        d.set(0.0, forKey: "widget.activeSessionSideStart")

        for activity in Activity<NourishFeedActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        bumpSnapshotVersion()
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

// MARK: - End Sleep

@available(iOS 17.0, *)
struct EndSleepLiveIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Baby woke up"
    static var description = IntentDescription("End the current nap.")

    @MainActor func perform() async throws -> some IntentResult {
        widgetLiveLog.notice("INTENT FIRED (widget copy): EndSleepLiveIntent")
        guard let d = sharedDefaults() else { return .result() }
        let now = Date.now.timeIntervalSince1970

        d.set(false, forKey: "widget.isBabySleeping")
        d.set(true,  forKey: "widget.sleepEndedFromWidget")
        d.set(now,   forKey: "widget.sleepEndTime")

        for activity in Activity<NourishSleepActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        bumpSnapshotVersion()
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

// MARK: - Helpers

@available(iOS 16.2, *)
@MainActor
private func updateFeedActivityFromShared() async {
    guard let d = sharedDefaults(),
          let activity = Activity<NourishFeedActivityAttributes>.activities.first
    else { return }
    let now = Date.now

    let currentSide = d.string(forKey: "widget.activeSessionSide") ?? "left"
    let startTs     = d.double(forKey: "widget.activeSessionStart")
    let sideStart   = d.double(forKey: "widget.activeSessionSideStart")
    let leftAccum   = d.integer(forKey: "widget.leftAccumulatedSeconds")
    let rightAccum  = d.integer(forKey: "widget.rightAccumulatedSeconds")
    let pausedAt    = d.double(forKey: "widget.activeSessionPausedAt")
    let isPaused    = pausedAt > 0
    let currentSideAcc = (currentSide == "left") ? leftAccum : rightAccum
    let sessionStart = startTs > 0 ? Date(timeIntervalSince1970: startTs) : now

    let virtualSideStart: Date
    if isPaused {
        virtualSideStart = now
    } else if sideStart > 0 {
        virtualSideStart = Date(timeIntervalSince1970: sideStart - TimeInterval(currentSideAcc))
    } else {
        virtualSideStart = now
    }

    let newState = NourishFeedActivityAttributes.ContentState(
        currentSide: currentSide,
        sessionStartDate: sessionStart,
        currentSideStartDate: virtualSideStart,
        leftAccumulatedSeconds: leftAccum,
        rightAccumulatedSeconds: rightAccum,
        isPaused: isPaused,
        pausedSideElapsedSeconds: isPaused ? currentSideAcc : 0
    )
    await activity.update(using: newState)
}
