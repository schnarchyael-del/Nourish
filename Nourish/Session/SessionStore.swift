import SwiftUI
import Observation
import UIKit

@Observable
final class SessionStore {
    var currentSide: FeedSide? = nil
    var startSide: FeedSide? = nil
    var elapsedSeconds: Int = 0
    var isPaused: Bool = false
    var switchedAtSeconds: Int? = nil

    private var timer: Timer? = nil
    private var sessionStartDate: Date? = nil
    private var pauseStartDate: Date? = nil
    private var accumulatedPausedSeconds: Int = 0

    // UserDefaults keys for session recovery across kills / backgrounding
    private enum PKey {
        static let startTimestamp   = "session_startTimestamp"
        static let currentSide      = "session_currentSide"
        static let startSide        = "session_startSide"
        static let switchedAt       = "session_switchedAt"       // -1 encodes nil
        static let pausedTimestamp  = "session_pausedTimestamp"  // 0  encodes nil
        static let accumulatedPause = "session_accumulatedPause"
    }

    var isActive: Bool { currentSide != nil }

    init() {
        recoverSession()
        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.syncToWallClock()
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
        persist()
        startTimer()
    }

    func pause() {
        guard !isPaused else { return }
        isPaused = true
        pauseStartDate = .now
        stopTimer()
        persist()
    }

    func resume() {
        guard isPaused else { return }
        if let pausedAt = pauseStartDate {
            accumulatedPausedSeconds += Int(Date.now.timeIntervalSince(pausedAt))
        }
        pauseStartDate = nil
        isPaused = false
        persist()
        startTimer()
    }

    func switchSide() {
        guard let side = currentSide else { return }
        if switchedAtSeconds == nil {
            switchedAtSeconds = elapsedSeconds
        }
        currentSide = side.opposite
        if isPaused { resume() } else { persist() }
    }

    /// Recalculate elapsed time from wall clock. Safe to call any time.
    func syncToWallClock() {
        guard isActive, !isPaused, let start = sessionStartDate else { return }
        let wallElapsed = Int(Date.now.timeIntervalSince(start)) - accumulatedPausedSeconds
        elapsedSeconds = max(elapsedSeconds, wallElapsed)
    }

    func end() -> (startTime: Date, feedType: FeedType, endTime: Date, leftMins: Int, rightMins: Int) {
        stopTimer()
        let endTime = Date.now
        let startTime = sessionStartDate ?? endTime.addingTimeInterval(-TimeInterval(elapsedSeconds))
        let start = startSide ?? .left
        let split = Self.splitMinutes(startSide: start,
                                      switchedAtSeconds: switchedAtSeconds,
                                      totalSeconds: elapsedSeconds)
        clearPersisted()
        reset()
        return (startTime, start.feedType, endTime, split.left, split.right)
    }

    /// Splits a session's total elapsed seconds into left/right minutes based on
    /// when (if ever) the user switched sides.
    static func splitMinutes(startSide: FeedSide,
                             switchedAtSeconds: Int?,
                             totalSeconds: Int) -> (left: Int, right: Int) {
        let total = max(0, totalSeconds)
        let startSeconds: Int
        let oppositeSeconds: Int
        if let switchAt = switchedAtSeconds {
            let clamped = min(max(0, switchAt), total)
            startSeconds = clamped
            oppositeSeconds = total - clamped
        } else {
            startSeconds = total
            oppositeSeconds = 0
        }
        let startMins = startSeconds / 60
        let oppositeMins = oppositeSeconds / 60
        return startSide == .left
            ? (left: startMins, right: oppositeMins)
            : (left: oppositeMins, right: startMins)
    }

    func cancel() {
        stopTimer()
        clearPersisted()
        reset()
    }

    var formattedTime: String {
        let mins = String(format: "%02d", elapsedSeconds / 60)
        let secs = String(format: "%02d", elapsedSeconds % 60)
        return "\(mins):\(secs)"
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
    }

    private func clearPersisted() {
        let d = UserDefaults.standard
        for key in [PKey.startTimestamp, PKey.currentSide, PKey.startSide,
                    PKey.switchedAt, PKey.pausedTimestamp, PKey.accumulatedPause] {
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

        let switchedRaw = d.integer(forKey: PKey.switchedAt)
        switchedAtSeconds = switchedRaw >= 0 ? switchedRaw : nil

        let pauseTs = d.double(forKey: PKey.pausedTimestamp)
        if pauseTs > 0 {
            pauseStartDate = Date(timeIntervalSince1970: pauseTs)
            isPaused = true
        }

        syncToWallClock()
        if !isPaused { startTimer() }
    }
}
