import AppIntents
import ActivityKit
import WidgetKit
import Foundation
import SwiftData
import os.log

// App-target copy of the Live Activity intents.
//
// `LiveActivityIntent.perform()` always runs in the main app's process.
// AppIntents discovers the type by scanning the app binary, so the type
// must exist here (not just the widget extension). The widget extension
// has the same struct names so `Button(intent:)` call sites in the
// Live Activity UI compile against the widget binary.
//
// Shared-state model (mirrored in SessionStore.publishActiveSnapshot
// and reconcileFromSharedSnapshot):
//
//   widget.activeSessionStart           Date — wall-clock session start
//   widget.activeSessionStartSide       "left" / "right" — first side
//   widget.activeSessionSide            "left" / "right" — current side
//   widget.activeSessionSideStart       Double timestamp — wall-clock
//                                       start of the CURRENT segment.
//                                       0 ⇒ paused (no segment in flight).
//   widget.activeSessionPausedAt        Double timestamp — moment paused,
//                                       0 ⇒ running.
//   widget.leftAccumulatedSeconds       Int — TOTAL committed time on left,
//                                       including any segment that's been
//                                       committed by pause/switch/end.
//   widget.rightAccumulatedSeconds      Int — same for right.
//
// Pause/Switch/End COMMIT the in-flight segment by adding
// `now − activeSessionSideStart` to the current side's accumulator before
// flipping any flags. Display while paused = accumulator (no addition).

private let suiteName = "group.com.yael.nourish"
private func sharedDefaults() -> UserDefaults? { UserDefaults(suiteName: suiteName) }

/// Bumped on every intent write so the SessionStore's 1Hz poll can
/// detect external mutations without comparing every key.
private func bumpSnapshotVersion() {
    sharedDefaults()?.set(Date.now.timeIntervalSince1970, forKey: "widget.snapshotVersion")
}

// MARK: - Pause / Resume

@available(iOS 17.0, *)
struct PauseFeedLiveIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Pause feed"
    static var description = IntentDescription("Pause or resume the active feed.")

    @MainActor func perform() async throws -> some IntentResult {
        liveActivityLog.notice("INTENT FIRED: PauseFeedLiveIntent")
        guard let d = sharedDefaults() else { return .result() }
        let now = Date.now
        let pausedAt = d.double(forKey: "widget.activeSessionPausedAt")

        if pausedAt > 0 {
            // RESUME — start a fresh segment. Accumulators stay as-is;
            // the segment that was committed at pause time is already there.
            d.set(now.timeIntervalSince1970, forKey: "widget.activeSessionSideStart")
            d.set(0.0, forKey: "widget.activeSessionPausedAt")
            liveActivityLog.notice("PauseFeedLiveIntent: RESUMED — sideStart=\(now.timeIntervalSince1970)")
        } else {
            // PAUSE — exact 6-step sequence:
            // 1. Read current state BEFORE changing anything.
            let currentSide = d.string(forKey: "widget.activeSessionSide") ?? "left"
            let sideStart   = d.double(forKey: "widget.activeSessionSideStart")
            let accKey      = (currentSide == "left") ? "widget.leftAccumulatedSeconds" : "widget.rightAccumulatedSeconds"
            let accBefore   = d.integer(forKey: accKey)

            // 2. Calculate elapsed on current side RIGHT NOW.
            let segment: Int = (sideStart > 0)
                ? max(0, Int(now.timeIntervalSince1970 - sideStart))
                : 0

            // 3. Add elapsed to the correct side's accumulator.
            let accAfter = accBefore + segment
            d.set(accAfter, forKey: accKey)

            // 4. Set paused.
            d.set(now.timeIntervalSince1970, forKey: "widget.activeSessionPausedAt")

            // 5. Clear the side start date (clock stopped).
            d.set(0.0, forKey: "widget.activeSessionSideStart")

            liveActivityLog.notice("PauseFeedLiveIntent: PAUSED \(currentSide) — \(accBefore) + \(segment) = \(accAfter)s")
        }

        // 6. Sync and update.
        bumpSnapshotVersion()
        NotificationCenter.default.post(name: .liveActivityStateChanged, object: nil)
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
        liveActivityLog.notice("INTENT FIRED: SwitchSideLiveIntent")
        guard let d = sharedDefaults() else { return .result() }
        let now = Date.now
        let currentSide = d.string(forKey: "widget.activeSessionSide") ?? "left"
        let newSide = (currentSide == "left") ? "right" : "left"
        let pausedAt = d.double(forKey: "widget.activeSessionPausedAt")

        // Commit current segment to outgoing side's accumulator (only when
        // running — when paused, the segment was already committed at pause).
        if pausedAt == 0 {
            let sideStart = d.double(forKey: "widget.activeSessionSideStart")
            let outgoingKey = (currentSide == "left") ? "widget.leftAccumulatedSeconds" : "widget.rightAccumulatedSeconds"
            let accBefore = d.integer(forKey: outgoingKey)
            let segment: Int = (sideStart > 0)
                ? max(0, Int(now.timeIntervalSince1970 - sideStart))
                : 0
            d.set(accBefore + segment, forKey: outgoingKey)
        }

        // Switch ALWAYS resumes feeding — mirrors in-app SessionStore.switchSide()
        // which auto-resumes if paused. Staying paused on a new side is a
        // confusing intermediate state with no real user benefit.
        d.set(newSide, forKey: "widget.activeSessionSide")
        d.set(now.timeIntervalSince1970, forKey: "widget.activeSessionSideStart")
        d.set(0.0, forKey: "widget.activeSessionPausedAt")

        liveActivityLog.notice("SwitchSideLiveIntent: \(currentSide) → \(newSide)")
        bumpSnapshotVersion()
        NotificationCenter.default.post(name: .liveActivityStateChanged, object: nil)
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
        liveActivityLog.notice("INTENT FIRED: EndFeedLiveIntent")
        guard let d = sharedDefaults() else { return .result() }
        let now = Date.now

        let currentSide = d.string(forKey: "widget.activeSessionSide") ?? "left"
        let startSide   = d.string(forKey: "widget.activeSessionStartSide") ?? currentSide
        let sessionTs   = d.double(forKey: "widget.activeSessionStart")
        let pausedAt    = d.double(forKey: "widget.activeSessionPausedAt")
        var leftAccum   = d.integer(forKey: "widget.leftAccumulatedSeconds")
        var rightAccum  = d.integer(forKey: "widget.rightAccumulatedSeconds")

        // Commit current segment to outgoing side (only when running).
        if pausedAt == 0 {
            let sideStart = d.double(forKey: "widget.activeSessionSideStart")
            let segment: Int = (sideStart > 0)
                ? max(0, Int(now.timeIntervalSince1970 - sideStart))
                : 0
            if currentSide == "left" { leftAccum += segment }
            else                     { rightAccum += segment }
        }

        if sessionTs > 0 {
            let startDate = Date(timeIntervalSince1970: sessionTs)
            let feedType: FeedType = (startSide == "right") ? .right : .left
            let session = FeedingSession(
                startTime: startDate,
                feedType: feedType,
                endTime: now,
                leftDurationMins:  leftAccum  / 60,
                rightDurationMins: rightAccum / 60
            )
            let context = ModelContext(NourishApp.modelContainer)
            context.insert(session)
            do {
                try context.save()
                await FirestoreService.shared.pushSession(session)
                AnalyticsService.sessionCompleted(
                    totalSeconds: max(0, Int(now.timeIntervalSince(startDate))),
                    leftSeconds:  leftAccum,
                    rightSeconds: rightAccum,
                    feedType: feedType.rawValue
                )
            } catch {
                liveActivityLog.error("EndFeedLiveIntent: save failed: \(error.localizedDescription)")
            }
        }

        d.set(false, forKey: "widget.isSessionActive")
        d.removeObject(forKey: "widget.activeSessionStart")
        d.removeObject(forKey: "widget.activeSessionSide")
        d.removeObject(forKey: "widget.activeSessionSideStart")
        d.removeObject(forKey: "widget.activeSessionStartSide")
        d.removeObject(forKey: "widget.leftAccumulatedSeconds")
        d.removeObject(forKey: "widget.rightAccumulatedSeconds")
        d.set(0.0, forKey: "widget.activeSessionPausedAt")

        SharedFeedSnapshot.refresh(modelContainer: NourishApp.modelContainer)

        for activity in Activity<NourishFeedActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        bumpSnapshotVersion()
        NotificationCenter.default.post(name: .liveActivityStateChanged, object: nil)
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
        liveActivityLog.notice("INTENT FIRED: EndSleepLiveIntent")
        let ts = UserDefaults.standard.double(forKey: "activeSleepStartedAt")
        let now = Date.now
        if ts > 0 {
            let start = Date(timeIntervalSince1970: ts)
            let session = FeedingSession(startTime: start, feedType: .sleep, endTime: now)
            let context = ModelContext(NourishApp.modelContainer)
            context.insert(session)
            do {
                try context.save()
                await FirestoreService.shared.pushSession(session)
                AnalyticsService.sleepEnded(durationSeconds: max(0, Int(now.timeIntervalSince(start))))
            } catch {
                liveActivityLog.error("EndSleepLiveIntent: save failed: \(error.localizedDescription)")
            }
            UserDefaults.standard.set(0.0, forKey: "activeSleepStartedAt")
        }

        SharedFeedSnapshot.clearActiveSleep()
        SharedFeedSnapshot.refresh(modelContainer: NourishApp.modelContainer)

        for activity in Activity<NourishSleepActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        bumpSnapshotVersion()
        NotificationCenter.default.post(name: .liveActivityStateChanged, object: nil)
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

    // Virtual start such that `now - virtualStart` = currentSideTotal.
    // Running:  currentSideTotal = accumulator + (now − sideStart)
    //           ⇒ virtualStart = sideStart − accumulator
    // Paused:   virtualStart is unused (display reads pausedSideElapsedSeconds).
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
