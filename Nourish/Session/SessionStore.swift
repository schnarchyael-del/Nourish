import SwiftUI
import Observation
import UIKit
import os.log

private let sessionLog = Logger(subsystem: "com.yael.nourish", category: "SessionStore")

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
    /// 1Hz polling timer that re-reads the shared App Group snapshot.
    /// Brute-force fallback for cases where the NotificationCenter bridge
    /// from LiveActivityIntent.perform() doesn't reach this observer
    /// (foregrounding race, MainActor hop, etc.). Active only while a
    /// session is running, so cost is negligible.
    private var sharedPollTimer: Timer? = nil
    /// `widget.snapshotVersion` value that the in-memory state already
    /// reflects. Used by BOTH the foreground catch-up and the 1Hz poll so
    /// neither path reconciles when nothing has actually changed — keeps
    /// the live timer from stuttering on every app-open.
    private var lastReconciledVersion: Double = 0
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
        // Overlay any newer widget-process writes the intents may have made
        // while the app was killed. Reconcile is the canonical source —
        // recoverSession only seeds in-memory state from session_* so the
        // app can render its UI before the (synchronous) reconcile finishes.
        reconcileFromSharedSnapshot()
        // Side effects that depend on the FINAL state (post-reconcile).
        if isActive {
            if #available(iOS 16.2, *) { startOrUpdateLiveActivity() }
            rescheduleSessionAlarmForCurrentSide()
            UIApplication.shared.isIdleTimerDisabled = true
        } else {
            UIApplication.shared.isIdleTimerDisabled = false
        }
        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleForeground()
        }
        // Live Activity intents post this immediately after mutating the
        // shared snapshot. Because LiveActivityIntent.perform() runs in the
        // app process, an alive SessionStore receives this on main queue
        // and reconciles its in-memory state in-line — UI re-renders via
        // @Observable without any further plumbing.
        NotificationCenter.default.addObserver(
            forName: .liveActivityStateChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.reconcileFromSharedSnapshot()
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
        startOrUpdateLiveActivity()
        startSharedPolling()
        UIApplication.shared.isIdleTimerDisabled = true
    }

    func pause() {
        guard !isPaused else { return }
        // Commit the in-flight segment so leftActiveSeconds/rightActiveSeconds
        // include it. The Live Activity displays the accumulator value as
        // the frozen time, so this commit makes the frozen value correct.
        commitCurrentSegment()
        isPaused = true
        pauseStartDate = .now
        stopTimer()
        persist()
        publishActiveSnapshot()
        updateLiveActivity()
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
        // Start a fresh segment relative to the current elapsedSeconds so
        // accumulators stay correct on the next pause/switch.
        currentSideStartedAtElapsed = elapsedSeconds
        persist()
        startTimer()
        publishActiveSnapshot()
        updateLiveActivity()
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
            updateLiveActivity()
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
        if #available(iOS 16.2, *) { LiveActivityManager.shared.endFeed() }
        stopSharedPolling()
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
        if #available(iOS 16.2, *) { LiveActivityManager.shared.endFeed() }
        stopSharedPolling()
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

        // NOTE: Intentionally do not call publishActiveSnapshot / start the
        // Live Activity here. `init()` runs reconcileFromSharedSnapshot
        // immediately after this — that's the canonical place to overlay
        // any widget-intent writes that happened while the app was killed.
        // Publishing here would overwrite them.
    }

    /// Push the FULL active-session state to the shared snapshot. Shared
    /// UserDefaults is the single source of truth — every widget intent
    /// reads from these keys and the app's `WidgetEndProcessor` saves
    /// FeedingSession entries from them when the widget ends a session.
    /// Anything not written here is invisible to the widget process.
    private func publishActiveSnapshot() {
        guard let sessionStart = sessionStartDate,
              let side = currentSide,
              let startS = startSide
        else { return }
        // Real wall-clock start of the current segment, or nil when paused
        // (no segment is in flight). The intent reads (now - sideStart) and
        // adds that to the side's accumulator on its next commit, so writing
        // segmentStart as a real timestamp keeps semantics consistent across
        // both the in-app code and the lock-screen buttons.
        let segmentStart: Date?
        if isPaused {
            segmentStart = nil
        } else {
            let segment = max(0, elapsedSeconds - currentSideStartedAtElapsed)
            segmentStart = Date.now.addingTimeInterval(-TimeInterval(segment))
        }
        SharedFeedSnapshot.setActiveSession(
            sessionStart: sessionStart,
            startSide: startS.rawValue,
            currentSide: side.rawValue,
            segmentStart: segmentStart,
            // pause() commits the in-flight segment before writing here, so
            // when paused these already include the just-finished segment.
            leftAccumulatedSeconds: leftActiveSeconds,
            rightAccumulatedSeconds: rightActiveSeconds,
            pausedAt: pauseStartDate
        )
        // We just wrote the snapshot, so our in-memory state already matches
        // it. Pin the version so the poll won't trigger a redundant
        // reconcile a beat later (which would stop+restart the timer).
        lastReconciledVersion = UserDefaults(suiteName: "group.com.yael.nourish")?
            .double(forKey: "widget.snapshotVersion") ?? 0
    }

    // MARK: - Reconcile from shared snapshot
    //
    // Called when a Live Activity intent has mutated the shared App Group
    // snapshot. Recomputes every in-memory @Observable property from those
    // keys so the in-app UI matches the lock screen. If the snapshot says
    // the session was ended via the widget, tears down in-memory state.

    private func reconcileFromSharedSnapshot() {
        guard let d = UserDefaults(suiteName: "group.com.yael.nourish") else { return }
        sessionLog.notice("RECONCILE: wasActive=\(self.isActive) wasPaused=\(self.isPaused) wasSide=\(self.currentSide?.rawValue ?? "nil")")

        let widgetActive = d.bool(forKey: "widget.isSessionActive")
        if !widgetActive {
            // Session was ended (or was never live) — tear down if we still
            // think we're active. The intent already saved the FeedingSession
            // and refreshed the snapshot, so there's nothing else to commit.
            if isActive {
                stopTimer()
                clearPersisted()
                reset()
                NotificationManager.shared.cancelSessionAlarm()
                UIApplication.shared.isIdleTimerDisabled = false
                sessionLog.notice("RECONCILE: shared says inactive → torn down in-memory session")
            }
            stopSharedPolling()
            // Pin the version so the next foreground/poll skips this branch
            // until something actually changes shared state again.
            lastReconciledVersion = d.double(forKey: "widget.snapshotVersion")
            return
        }

        let startTs = d.double(forKey: "widget.activeSessionStart")
        guard startTs > 0,
              let curRaw = d.string(forKey: "widget.activeSessionSide"),
              let curSide = FeedSide(rawValue: curRaw)
        else { return }
        let stRaw = d.string(forKey: "widget.activeSessionStartSide") ?? curRaw
        let stSide = FeedSide(rawValue: stRaw) ?? curSide

        let sessionStart  = Date(timeIntervalSince1970: startTs)
        let leftAcc       = d.integer(forKey: "widget.leftAccumulatedSeconds")
        let rightAcc      = d.integer(forKey: "widget.rightAccumulatedSeconds")
        let pausedTs      = d.double(forKey: "widget.activeSessionPausedAt")
        let sideStartTs   = d.double(forKey: "widget.activeSessionSideStart")

        let now = Date.now
        let paused = pausedTs > 0
        // sideStartTs is the REAL wall-clock start of the current segment
        // (0 when paused). Accumulators include any segment committed by
        // pause/switch/end. So the current segment is just `now - sideStart`
        // while running, and 0 while paused.
        let currentSegment: Int
        if paused {
            currentSegment = 0
        } else if sideStartTs > 0 {
            currentSegment = max(0, Int(now.timeIntervalSince1970 - sideStartTs))
        } else {
            currentSegment = 0
        }
        let totalActive = leftAcc + rightAcc + currentSegment
        let totalWall   = max(0, Int(now.timeIntervalSince(sessionStart)))
        let currentPauseChunk = paused ? max(0, Int(now.timeIntervalSince1970 - pausedTs)) : 0
        let accumPause = max(0, totalWall - totalActive - currentPauseChunk)

        stopTimer()
        self.sessionStartDate           = sessionStart
        self.startSide                  = stSide
        self.currentSide                = curSide
        self.leftActiveSeconds          = leftAcc
        self.rightActiveSeconds         = rightAcc
        self.elapsedSeconds             = totalActive
        self.currentSideStartedAtElapsed = leftAcc + rightAcc
        self.accumulatedPausedSeconds   = accumPause
        self.isPaused                   = paused
        self.pauseStartDate             = paused ? Date(timeIntervalSince1970: pausedTs) : nil
        if leftAcc + rightAcc > 0 || curSide != stSide {
            if switchedAtSeconds == nil { switchedAtSeconds = totalActive }
        }

        persist()
        if !paused { startTimer() }
        startSharedPolling()
        rescheduleSessionAlarmForCurrentSide()
        UIApplication.shared.isIdleTimerDisabled = true
        // Mark the snapshot version we just absorbed so neither the poll
        // nor the foreground handler re-reconciles this same state.
        lastReconciledVersion = d.double(forKey: "widget.snapshotVersion")
        sessionLog.notice("RECONCILE: applied side=\(curSide.rawValue) paused=\(paused) elapsed=\(totalActive)s version=\(self.lastReconciledVersion)")
    }

    /// Called once when the app enters the foreground. We only call the
    /// full reconcile (which stops & restarts the 1Hz timer) when a Live
    /// Activity intent actually mutated the shared snapshot — otherwise
    /// we just nudge `elapsedSeconds` up to wall clock, leaving the timer
    /// running. This eliminates the visible stutter on every app-open.
    private func handleForeground() {
        let d = UserDefaults(suiteName: "group.com.yael.nourish")
        let version = d?.double(forKey: "widget.snapshotVersion") ?? 0
        if version != lastReconciledVersion {
            sessionLog.notice("FOREGROUND: snapshot changed \(self.lastReconciledVersion) → \(version), reconciling")
            reconcileFromSharedSnapshot()
        } else {
            sessionLog.notice("FOREGROUND: snapshot unchanged, smooth sync")
            syncToWallClock()
        }
    }

    // MARK: - Brute-force shared-defaults polling

    private func startSharedPolling() {
        guard sharedPollTimer == nil else { return }
        let d = UserDefaults(suiteName: "group.com.yael.nourish")
        lastReconciledVersion = d?.double(forKey: "widget.snapshotVersion") ?? 0
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            guard let d = UserDefaults(suiteName: "group.com.yael.nourish") else { return }
            let current = d.double(forKey: "widget.snapshotVersion")
            if current != self.lastReconciledVersion {
                self.lastReconciledVersion = current
                sessionLog.notice("POLL: snapshotVersion changed → reconciling")
                self.reconcileFromSharedSnapshot()
            }
        }
        // .common mode so the poll keeps ticking during scroll / touch handling.
        RunLoop.main.add(t, forMode: .common)
        sharedPollTimer = t
        sessionLog.notice("POLL started")
    }

    private func stopSharedPolling() {
        sharedPollTimer?.invalidate()
        sharedPollTimer = nil
        sessionLog.notice("POLL stopped")
    }

    // MARK: - Live Activity bridge
    //
    // ActivityKit's content state mirrors the same values we push to the
    // shared snapshot. We resolve them in one place so the manager call
    // sites stay terse.

    private func liveActivityState() -> (
        side: String,
        sessionStart: Date,
        sideStart: Date,
        leftAccum: Int,
        rightAccum: Int,
        paused: Bool,
        pausedSec: Int
    )? {
        guard let sessionStart = sessionStartDate, let side = currentSide else { return nil }
        let sideSecs = currentSideSeconds
        let sideEffectiveStart = Date.now.addingTimeInterval(-TimeInterval(sideSecs))
        return (
            side: side.rawValue,
            sessionStart: sessionStart,
            sideStart: sideEffectiveStart,
            leftAccum: leftActiveSeconds,
            rightAccum: rightActiveSeconds,
            paused: isPaused,
            pausedSec: isPaused ? sideSecs : 0
        )
    }

    private func startOrUpdateLiveActivity() {
        guard #available(iOS 16.2, *), let s = liveActivityState() else { return }
        LiveActivityManager.shared.startFeed(
            currentSide: s.side,
            sessionStartDate: s.sessionStart,
            currentSideStartDate: s.sideStart,
            leftAccumulatedSeconds: s.leftAccum,
            rightAccumulatedSeconds: s.rightAccum,
            isPaused: s.paused,
            pausedSideElapsedSeconds: s.pausedSec
        )
    }

    private func updateLiveActivity() {
        guard #available(iOS 16.2, *), let s = liveActivityState() else { return }
        LiveActivityManager.shared.updateFeed(
            currentSide: s.side,
            sessionStartDate: s.sessionStart,
            currentSideStartDate: s.sideStart,
            leftAccumulatedSeconds: s.leftAccum,
            rightAccumulatedSeconds: s.rightAccum,
            isPaused: s.paused,
            pausedSideElapsedSeconds: s.pausedSec
        )
    }
}
