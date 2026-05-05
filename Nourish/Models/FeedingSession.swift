import SwiftData
import Foundation

enum FeedType: String, Codable, CaseIterable {
    case left    = "left"
    case right   = "right"
    case bottle  = "bottle"

    var displayName: String {
        switch self {
        case .left:   "Left"
        case .right:  "Right"
        case .bottle: "Bottle"
        }
    }

    var shortLabel: String {
        switch self {
        case .left:   "L"
        case .right:  "R"
        case .bottle: "B"
        }
    }
}

enum BottleContentType: String, Codable, CaseIterable {
    case breastmilk = "breastmilk"
    case formula    = "formula"

    var displayName: String {
        switch self {
        case .breastmilk: "Breastmilk"
        case .formula:    "Formula"
        }
    }

    var icon: String {
        switch self {
        case .breastmilk: "🤱"
        case .formula:    "🥛"
        }
    }
}

@Model
final class FeedingSession {
    var id: UUID
    var startTime: Date
    var endTime: Date?
    var feedType: FeedType
    var bottleContentType: BottleContentType?
    var bottleAmountMl: Int?
    var leftDurationMins: Int?
    var rightDurationMins: Int?
    var loggedByDeviceID: String?

    init(
        startTime: Date = .now,
        feedType: FeedType,
        endTime: Date? = nil,
        bottleContentType: BottleContentType? = nil,
        bottleAmountMl: Int? = nil,
        leftDurationMins: Int? = nil,
        rightDurationMins: Int? = nil,
        loggedByDeviceID: String? = nil
    ) {
        self.id = UUID()
        self.startTime = startTime
        self.feedType = feedType
        self.endTime = endTime
        self.bottleContentType = bottleContentType
        self.bottleAmountMl = bottleAmountMl
        self.leftDurationMins = leftDurationMins
        self.rightDurationMins = rightDurationMins
        self.loggedByDeviceID = loggedByDeviceID
    }

    /// Wall-clock duration including pauses. Kept for legacy fallback only.
    var durationSeconds: Int {
        max(0, Int((endTime ?? .now).timeIntervalSince(startTime)))
    }

    var durationMinutes: Int { durationSeconds / 60 }

    /// Active feeding time = leftDuration + rightDuration (excludes pauses/gaps).
    /// Falls back to wall-clock for legacy sessions that don't have splits.
    var totalActiveMinutes: Int {
        leftMinutesResolved + rightMinutesResolved
    }

    var formattedDuration: String {
        let mins = totalActiveMinutes
        if mins > 0 { return "\(mins) min" }
        // Sessions under a minute (rare): show seconds from wall clock.
        let secs = durationSeconds
        if secs > 0 && secs < 60 { return "\(secs) sec" }
        return "0 min"
    }

    var formattedTime: String {
        startTime.formatted(date: .omitted, time: .shortened)
    }

    var timeAgoString: String {
        let interval = Date.now.timeIntervalSince(startTime)
        let hours = Int(interval) / 3600
        let mins  = (Int(interval) % 3600) / 60
        if hours > 0 && mins > 0 { return "\(hours)h \(mins)m ago" }
        if hours > 0              { return "\(hours)h ago" }
        return "\(mins)m ago"
    }

    // Time on each side, using stored splits when available and falling back to
    // attributing full duration to the starting side for legacy sessions.
    var leftMinutesResolved: Int {
        if feedType == .bottle { return 0 }
        if let m = leftDurationMins { return m }
        return feedType == .left ? durationMinutes : 0
    }

    var rightMinutesResolved: Int {
        if feedType == .bottle { return 0 }
        if let m = rightDurationMins { return m }
        return feedType == .right ? durationMinutes : 0
    }
}
