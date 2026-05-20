import SwiftData
import Foundation

enum FeedType: String, Codable, CaseIterable {
    case left    = "left"
    case right   = "right"
    case bottle  = "bottle"
    case pump    = "pump"

    var displayName: String {
        switch self {
        case .left:   "Left"
        case .right:  "Right"
        case .bottle: "Bottle"
        case .pump:   "Pump"
        }
    }

    var shortLabel: String {
        switch self {
        case .left:   "L"
        case .right:  "R"
        case .bottle: "B"
        case .pump:   "P"
        }
    }
}

enum PumpSide: String, Codable, CaseIterable {
    case left  = "left"
    case right = "right"
    case both  = "both"

    var displayName: String {
        switch self {
        case .left:  "Left"
        case .right: "Right"
        case .both:  "Both"
        }
    }

    var shortLabel: String {
        switch self {
        case .left:  "L"
        case .right: "R"
        case .both:  "Both"
        }
    }

    var icon: String {
        switch self {
        case .left:  "L"
        case .right: "R"
        case .both:  "⇄"
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
    // Pump-specific fields
    var pumpSide: PumpSide?
    var pumpVolumeMl: Int?
    // Universal notes field (all session types)
    var notes: String?

    init(
        startTime: Date = .now,
        feedType: FeedType,
        endTime: Date? = nil,
        bottleContentType: BottleContentType? = nil,
        bottleAmountMl: Int? = nil,
        leftDurationMins: Int? = nil,
        rightDurationMins: Int? = nil,
        loggedByDeviceID: String? = nil,
        pumpSide: PumpSide? = nil,
        pumpVolumeMl: Int? = nil,
        notes: String? = nil
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
        self.pumpSide = pumpSide
        self.pumpVolumeMl = pumpVolumeMl
        self.notes = notes
    }

    /// Wall-clock duration including pauses. Used for pump sessions and legacy fallback.
    var durationSeconds: Int {
        max(0, Int((endTime ?? .now).timeIntervalSince(startTime)))
    }

    var durationMinutes: Int { durationSeconds / 60 }

    /// Active feeding time. For pump sessions uses wall-clock (left+right split not applicable).
    var totalActiveMinutes: Int {
        if feedType == .pump { return durationMinutes }
        return leftMinutesResolved + rightMinutesResolved
    }

    var formattedDuration: String {
        let mins = totalActiveMinutes
        if mins > 0 { return "\(mins) min" }
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

    var leftMinutesResolved: Int {
        if feedType == .bottle || feedType == .pump { return 0 }
        if let m = leftDurationMins { return m }
        return feedType == .left ? durationMinutes : 0
    }

    var rightMinutesResolved: Int {
        if feedType == .bottle || feedType == .pump { return 0 }
        if let m = rightDurationMins { return m }
        return feedType == .right ? durationMinutes : 0
    }
}
