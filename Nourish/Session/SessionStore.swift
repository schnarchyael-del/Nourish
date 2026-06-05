import SwiftUI
import Observation
import UIKit

@Observable
final class SessionStore {
    var currentSide: FeedSide? = nil
    var startSide: FeedSide? = nil
    var elapsedSeconds: Int = 0
    var isPaused: Bool = false
    /// Elapsed seconds at the FIRST switch, or nil if no switch has happened.
    /// Used only as a "has the user switched at least once?" flag for UI
    /// affordances. Per-side totals come from `leftActiveSeconds` /
    /// `rightActiveSeconds`, which accumulate across every switch.
    var switchedAtSeconds: Int? = nil

    /// Total active feeding seconds on the LEFT side, accumulated across
    /// every segment of the current session. Paused time is excluded
    /// because we tick `elapsedSeconds` from wall clock minus paused.
    private(set) var leftActiveSeconds: Int = 0
    /// Total active feeding seconds on the RIGHT side, accumulated across
    /// every segment of the current session.
    private(set) var rightActiveSeconds: Int = 0
    /// `elapsedSeconds` at the moment the current segment started (i.e. at
    /// session start or at the most recent switchSide). The current
    /// segment's runtime is `elapsedSeconds - currentSideStartedAtElapsed`.
    private var currentSideStartedAtElapsed: Int = 0

    private var timer: Timer? = nil
    private var sessionStartDate: Date? = nil
    private var pauseStartDate: Date? = nil
    private var accumulatedPausedSeconds: Int = 0

    // UserDefaults keys for session recovery across kills / backgrounding
    private enum PKey {
        static let startTimestamp     = "session_startTimestamp"
        static let currentSide        = "session_currentSide"
        static let startSide          = "session_startSide"
        static let switchedAt         = "session_switchedAt"       // -1 encodes nil
        static let pausedTimestamp    = "session_pausedTimestamp"  // 0  encodes nil
        static let accumulatedPause   = "session_accumulatedPause"
        static let leftActiveSeconds  = "session_leftActiveSeconds"
        static let rightActiveSeconds = "session_rightActiveSeconds"
        static let currentSideStart   = "session_currentSideStartedAtElapsed"
    }

    var isActive: Bool { currentSide != nil }

    init() {
        recoverSession()
        // If recovery didn't restore a session but the widget snapshot still
        // claims one is active (e.g. force-quit mid-session, never reopened
        // until now), clear it so the widget doesn't get stuck on
        // "Feeding now" indefinitely.
        if !isActive {
            SharedFeedSnapshot.clearActiveSession()
            UIApplication.shared.isIdleTimerDisabled = false
        } else {
            // App just came back with an in-progress session — the widget may
            // have mutated pause / side while we were backgrounded.
            absorbWidgetMutations()
        }
        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.syncToWallClock()
            self?.absorbWidgetMutations()
        }
    }

    /// Reconcile the in-memory session state with whatever the widget
    /// extension wrote into the shared snapshot while we were backgrounded.
    /// Specifically: pause-toggle and switch-side actions fire AppIntents
    /// inside the widget process, which writes the new state to
    /// `group.com.yael.nourish` without ever waking the main app. Without
    /// this sync, opening the app would show stale (pre-widget-tap) state.
    func absorbWidgetMutations() {
        guard isActive,
              let d = UserDefaults(suiteName: "group.com.yael.nourish")
        else { return }

        // Pause / resume.
        let widgetPausedAt = d.double(forKey: "widget.activeSessionPausedAt")
        let widgetIsPaused = widgetPausedAt > 0
        if widgetIsPaused, !isPaused {
            pause()
        } else if !widgetIsPaused, isPaused {
            resume()
        }

        // Switch side.
        if let raw = d.string(forKey: "widget.activeSessionSide"),
           let widgetSide = FeedSide(rawValue: raw),
           let here = currentSide,
           widgetSide != here {
            switchSide()
        }
    }

    // MARK: Public API

    func start(side: FeedSide) {
        stopTimer()
        currentSide = side
        startSide = side
        elapsedSeconds = 0
        isPaused = false
        switchedAtSeconds = nil
        sessionStartDate = .now
        pauseStartDate = nil
        accumulatedPausedSeconds = 0
        leftActiveSeconds = 0
        rightActiveSeconds = 0
        currentSideStartedAtElapsed = 0
        persist()
        startTimer()

        // Active feed in progress — pull any pending feed reminder so it doesn't
        // fire mid-session. It'll be re-scheduled when the session is saved.
        NotificationManager.shared.cancelReminder()

        // Schedule a background notification mirroring the in-app alarm.
        // Threshold is per-side, so we re-evaluate on switch/pause/resume below.
        rescheduleSessionAlarmForCurrentSide()

        // Push live state to widgets and keep the screen awake.
        publishActiveSnapshot()
        UIApplication.shared.isIdleTimerDisabled = true
    }

    func pause() {
        guard !isPaused else { return }
        isPaused = true
        pauseStartDate = .now
        stopTimer()
        persist()
        publishActiveSnapshot()
        // Cancel the background alarm; resume() will reschedule with the
        // remaining current-side time.
        NotificationManager.shared.cancelSessionAlarm()
    }

    func resume() {
        guard isPaused else { return }
        if let pausedAt = pauseStartDate {
            accumulatedPausedSeconds += Int(Date.now.timeIntervalSince(pausedAt))
        }
        pauseStartDate = nil
        isPaused = false
        syncToWallClock()
        persist()
        startTimer()
        publishActiveSnapshot()
        rescheduleSessionAlarmForCurrentSide()
    }

    func switchSide() {
        guard let side = currentSide else { return }
        // Commit the current segment's time to the accumulator for whatever
        // side we're leaving, BEFORE we flip currentSide.
        commitCurrentSegment()
        if switchedAtSeconds == nil {
            switchedAtSeconds = elapsedSeconds
        }
        currentSide = side.opposite
        // resume() already calls publishActiveSnapshot(); in the non-paused
        // branch we must call it explicitly so the widget updates immediately.
        if isPaused {
            resume()
        } else {
            persist()
            publishActiveSnapshot()
        }
        rescheduleSessionAlarmForCurrentSide()
    }

    /// Add the time spent on `currentSide` since the segment started to the
    /// appropriate per-side accumulator, then reset the segment marker. Call
    /// this before flipping sides or ending the session.
    private func commitCurrentSegment() {
        guard let side = currentSide else { return }
        let segment = max(0, elapsedSeconds - currentSideStartedAtElapsed)
        if side == .left {
            leftActiveSeconds += segment
        } else {
            rightActiveSeconds += segment
        }
        currentSideStartedAtElapsed = elapsedSeconds
    }

    /// Schedule the background session alarm so it fires when the CURRENT
    /// side reaches `alarmMinutes`. No-op when not active, paused, or alarm
    /// disabled. Cancels any previously-scheduled alarm.
    private func rescheduleSessionAlarmForCurrentSide() {
        NotificationManager.shared.cancelSessionAlarm()
        guard isActive, !isPaused else { return }
        let alarmEnabled = (UserDefaults.standard.object(forKey: "alarmEnabled") as? Bool) ?? true
        let alarmMinutes = (UserDefaults.standard.object(forKey: "alarmMinutes") as? Int) ?? 45
        guard alarmEnabled, alarmMinutes > 0 else { return }
        let remaining = (alarmMinutes * 60) - currentSideSeconds
        guard remaining > 0 else { return }
        NotificationManager.shared.scheduleSessionAlarm(seconds: TimeInterval(remaining))
    }

    /// Recalculate elapsed time from wall clock. Safe to call any time.
    func syncToWallClock() {
        guard isActive, !isPaused, let start = sessionStartDate else { return }
        let wallElapsed = Int(Date.now.timeIntervalSince(start)) - accumulatedPausedSeconds
        elapsedSeconds = max(elapsedSeconds, wallElapsed)
    }

    func end() -> (startTime: Date, feedType: FeedType, endTime: Date, leftMins: Int, rightMins: Int) {
        stopTimer()
        // Roll the final active segment into the per-side accumulator before
        // we read them out.
        commitCurrentSegment()
        let endTime = Date.now
        let startTime = sessionStartDate ?? endTime.addingTimeInterval(-TimeInterval(elapsedSeconds))
        let start = startSide ?? .left
        let leftMins  = leftActiveSeconds  / 60
        let rightMins = rightActiveSeconds / 60
        clearPersisted()
        reset()
        NotificationManager.shared.cancelSessionAlarm()
        SharedFeedSnapshot.clearActiveSession()
        UIApplication.shared.isIdleTimerDisabled = false
        return (startTime, start.feedType, endTime, leftMins, rightMins)
    }

    /// Convert in-flight per-side seconds to (leftMins, rightMins) without
    /// mutating session state. Useful when the alarm modal needs to save a
    /// session that's still active (so we can't call `end()` first).
    func currentSplitMinutes() -> (left: Int, right: Int) {
        let inFlight = max(0, elapsedSeconds - currentSideStartedAtElapsed)
        var left  = leftActiveSeconds
        var right = rightActiveSeconds
        if currentSide == .left {
            left += inFlight
        } else if currentSide == .right {
            right += inFlight
        }
        return (left: left / 60, right: right / 60)
    }

    func cancel() {
        stopTimer()
        clearPersisted()
        reset()
        NotificationManager.shared.cancelSessionAlarm()
        SharedFeedSnapshot.clearActiveSession()
        UIApplication.shared.isIdleTimerDisabled = false
    }

    var formattedTime: String {
        Self.formatMMSS(elapsedSeconds)
    }

    /// Total seconds accumulated on the current side, including all previous
    /// segments on that side plus the current running segment. Resuming a side
    /// (L→R→L) continues from where that side left off rather than resetting.
    var currentSideSeconds: Int {
        let segment = max(0, elapsedSeconds - currentSideStartedAtElapsed)
        guard let side = currentSide else { return segment }
        let accumulated = side == .left ? leftActiveSeconds : rightActiveSeconds
        return accumulated + segment
    }

    /// Accumulated total seconds on the side the user is NOT currently on,
    /// or nil if no switch has happened yet. After multiple switches this
    /// stays accurate (e.g. L→R→L → reports R's full total).
    var completedSideSeconds: Int? {
        guard switchedAtSeconds != nil, let cur = currentSide else { return nil }
        return cur == .left ? rightActiveSeconds : leftActiveSeconds
    }

    /// The side `completedSideSeconds` refers to (i.e. the opposite of the
    /// currently-active side, only when a switch has happened). Used by the
    /// UI so the small "L: 8:00" line above the big timer always names the
    /// side that's NOT actively ticking.
    var completedSideLabel: FeedSide? {
        guard switchedAtSeconds != nil, let cur = currentSide else { return nil }
        return cur.opposite
    }

    var formattedCurrentSideTime: String { Self.formatMMSS(currentSideSeconds) }
    var formattedTotalTime: String { Self.formatMMSS(elapsedSeconds) }
    var formattedCompletedSideTime: String? {
        completedSideSeconds.map(Self.formatMMSS)
    }

    static func formatMMSS(_ seconds: Int) -> String {
        let m = max(0, seconds) / 60
        let s = max(0, seconds) % 60
        return String(format: "%02d:%02d", m, s)
    }

    // MARK: Private

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self, let start = self.sessionStartDate, !self.isPaused else { return }
            // Always recalculate from wall clock — missed ticks (background, lock) are free
            self.elapsedSeconds = max(0, Int(Date.now.timeIntervalSince(start)) - self.accumulatedPausedSeconds)
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func reset() {
        currentSide = nil
        startSide = nil
        elapsedSeconds = 0
        isPaused = false
        switchedAtSeconds = nil
        sessionStartDate = nil
        pauseStartDate = nil
        accumulatedPausedSeconds = 0
        leftActiveSeconds = 0
        rightActiveSeconds = 0
        currentSideStartedAtElapsed = 0
    }

    // MARK: Persistence

    private func persist() {
        guard let start = sessionStartDate,
              let current = currentSide,
              let startS = startSide else {
            clearPersisted()
            return
        }
        let d = UserDefaults.standard
        d.set(start.timeIntervalSince1970,                          forKey: PKey.startTimestamp)
        d.set(current.rawValue,                                     forKey: PKey.currentSide)
        d.set(startS.rawValue,                                      forKey: PKey.startSide)
        d.set(accumulatedPausedSeconds,                             forKey: PKey.accumulatedPause)
        d.set(switchedAtSeconds ?? -1,                              forKey: PKey.switchedAt)
        d.set(pauseStartDate?.timeIntervalSince1970 ?? 0,           forKey: PKey.pausedTimestamp)
        d.set(leftActiveSeconds,                                    forKey: PKey.leftActiveSeconds)
        d.set(rightActiveSeconds,                                   forKey: PKey.rightActiveSeconds)
        d.set(currentSideStartedAtElapsed,                          forKey: PKey.currentSideStart)
    }

    private func clearPersisted() {
        let d = UserDefaults.standard
        for key in [PKey.startTimestamp, PKey.currentSide, PKey.startSide,
                    PKey.switchedAt, PKey.pausedTimestamp, PKey.accumulatedPause,
                    PKey.leftActiveSeconds, PKey.rightActiveSeconds, PKey.currentSideStart] {
            d.removeObject(forKey: key)
        }
    }

    private func recoverSession() {
        let d = UserDefaults.standard
        guard d.object(forKey: PKey.startTimestamp) != nil else { return }

        let ts = d.double(forKey: PKey.startTimestamp)
        guard ts > 0,
              let curRaw  = d.string(forKey: PKey.currentSide),
              let curSide = FeedSide(rawValue: curRaw),
              let stRaw   = d.string(forKey: PKey.startSide),
              let stSide  = FeedSide(rawValue: stRaw)
        else {
            clearPersisted()
            return
        }

        sessionStartDate         = Date(timeIntervalSince1970: ts)
        currentSide              = curSide
        startSide                = stSide
        accumulatedPausedSeconds = d.integer(forKey: PKey.accumulatedPause)
        leftActiveSeconds        = d.integer(forKey: PKey.leftActiveSeconds)
        rightActiveSeconds       = d.integer(forKey: PKey.rightActiveSeconds)
        currentSideStartedAtElapsed = d.integer(forKey: PKey.currentSideStart)

        let switchedRaw = d.integer(forKey: PKey.switchedAt)
        switchedAtSeconds = switchedRaw >= 0 ? switchedRaw : nil

        let pauseTs = d.double(forKey: PKey.pausedTimestamp)
        if pauseTs > 0 {
            pauseStartDate = Date(timeIntervalSince1970: pauseTs)
            isPaused = true
        }

        syncToWallClock()
        if !isPaused { startTimer() }

        // Recovered an in-progress session — re-enable the keep-awake flag,
        // republish the active state, and reschedule the per-side alarm
        // based on how long the current side has already been running.
        if sessionStartDate != nil {
            publishActiveSnapshot()
            rescheduleSessionAlarmForCurrentSide()
            UIApplication.shared.isIdleTimerDisabled = true
        }
    }

    /// Push the current active-session state to the widget snapshot.
    /// Writes the CURRENT side (not start side) and a virtual effective-start
    /// date that makes the widget's .timer display show this side's total time.
    private func publishActiveSnapshot() {
        guard let sessionStart = sessionStartDate, let side = currentSide else { return }
        let sideSecs = currentSideSeconds
        // Virtual start: a date such that (now - sideEffectiveStart) == sideSecs.
        // Widget uses Text(sideEffectiveStart, style: .timer) for live display.
        let sideEffectiveStart = Date.now.addingTimeInterval(-TimeInterval(sideSecs))
        SharedFeedSnapshot.setActiveSession(
            sessionStart: sessionStart,
            currentSide: side.rawValue,
            sideEffectiveStart: sideEffectiveStart,
            pausedAt: pauseStartDate,
            pausedSideSeconds: isPaused ? sideSecs : 0
        )
    }
}
