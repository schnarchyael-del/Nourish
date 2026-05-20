import SwiftUI
import Observation
import UIKit

@Observable
final class PumpStore {
    var isActive: Bool = false
    var isPaused: Bool = false
    var pumpSide: PumpSide = .both
    var elapsedSeconds: Int = 0

    private var timer: Timer? = nil
    private var sessionStartDate: Date? = nil
    private var pauseStartDate: Date? = nil
    private var accumulatedPausedSeconds: Int = 0

    var formattedTime: String {
        let m = max(0, elapsedSeconds) / 60
        let s = max(0, elapsedSeconds) % 60
        return String(format: "%02d:%02d", m, s)
    }

    func start(side: PumpSide) {
        stopTimer()
        pumpSide = side
        isActive = true
        isPaused = false
        elapsedSeconds = 0
        sessionStartDate = .now
        pauseStartDate = nil
        accumulatedPausedSeconds = 0
        startTimer()
        UIApplication.shared.isIdleTimerDisabled = true
    }

    func pause() {
        guard !isPaused else { return }
        isPaused = true
        pauseStartDate = .now
        stopTimer()
    }

    func resume() {
        guard isPaused else { return }
        if let p = pauseStartDate {
            accumulatedPausedSeconds += Int(Date.now.timeIntervalSince(p))
        }
        pauseStartDate = nil
        isPaused = false
        startTimer()
    }

    /// Returns session data and resets store state. Call before creating FeedingSession.
    func end() -> (startTime: Date, endTime: Date, side: PumpSide, elapsedSeconds: Int) {
        stopTimer()
        let endTime = Date.now
        let startTime = sessionStartDate ?? endTime.addingTimeInterval(-TimeInterval(elapsedSeconds))
        let side = pumpSide
        let elapsed = elapsedSeconds
        reset()
        return (startTime, endTime, side, elapsed)
    }

    func cancel() {
        stopTimer()
        reset()
    }

    private func reset() {
        isActive = false
        isPaused = false
        elapsedSeconds = 0
        sessionStartDate = nil
        pauseStartDate = nil
        accumulatedPausedSeconds = 0
        UIApplication.shared.isIdleTimerDisabled = false
    }

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self, let start = self.sessionStartDate, !self.isPaused else { return }
            self.elapsedSeconds = max(0, Int(Date.now.timeIntervalSince(start)) - self.accumulatedPausedSeconds)
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}
