import ActivityKit
import Foundation

// Shared between the app and the widget extension — mirrored verbatim in
// /Nourish/Shared/NourishActivityAttributes.swift. ActivityKit requires the
// attributes type to be in scope for both targets so the widget can register
// the configuration and the app can request the activity.

struct NourishFeedActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var currentSide: String          // "left" / "right"
        var sessionStartDate: Date
        /// Virtual start for `Text(_, style: .timer)` — so the live timer
        /// ticks at the right elapsed value when re-rendered.
        var currentSideStartDate: Date
        var leftAccumulatedSeconds: Int
        var rightAccumulatedSeconds: Int
        var isPaused: Bool
        /// Equals `currentSide`'s accumulator at the moment of pause.
        /// `accumulator` already includes the just-committed segment, so the
        /// paused lock-screen display is simply this value.
        var pausedSideElapsedSeconds: Int
    }

    var babyName: String
}

struct NourishSleepActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var sleepStartDate: Date
    }

    var babyName: String
}
