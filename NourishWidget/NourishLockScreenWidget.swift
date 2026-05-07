import WidgetKit
import SwiftUI

struct NourishLockScreenWidget: Widget {
    let kind = "NourishLockScreenWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NourishProvider()) { entry in
            LockScreenView(snapshot: entry.snapshot, now: entry.date)
                .containerBackground(.clear, for: .widget)
                .widgetURL(URL(string: "nourish://home"))
        }
        .configurationDisplayName("Nourish — Last feed")
        .description("Quick glance at the last feed.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

private struct LockScreenView: View {
    @Environment(\.widgetFamily) private var family
    let snapshot: FeedSnapshot
    let now: Date

    var body: some View {
        switch family {
        case .accessoryCircular:    CircularLockView(snapshot: snapshot, now: now)
        case .accessoryRectangular: RectangularLockView(snapshot: snapshot, now: now)
        case .accessoryInline:      InlineLockView(snapshot: snapshot, now: now)
        default:                    InlineLockView(snapshot: snapshot, now: now)
        }
    }
}

// MARK: - Circular

private struct CircularLockView: View {
    let snapshot: FeedSnapshot
    let now: Date

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            if snapshot.isActuallyActive, let start = snapshot.activeSessionStart {
                VStack(spacing: 0) {
                    HStack(spacing: 2) {
                        Circle().frame(width: 5, height: 5)
                        Text(FeedFormat.sideLetter(from: snapshot.activeSessionSide))
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                    }
                    Text(start, style: .timer)
                        .font(.system(size: 9, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            } else if snapshot.lastFeedTime != nil {
                VStack(spacing: 0) {
                    Text(FeedFormat.sideLetter(from: snapshot.lastFeedSide))
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.5)
                    Text(FeedFormat.timeAgoCompact(from: snapshot.lastFeedTime, reference: now))
                        .font(.system(size: 9, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
            } else {
                Text("—")
                    .font(.system(size: 22, weight: .bold))
            }
        }
    }
}

// MARK: - Rectangular

private struct RectangularLockView: View {
    let snapshot: FeedSnapshot
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            if snapshot.isActuallyActive, let start = snapshot.activeSessionStart {
                HStack(spacing: 4) {
                    Circle().frame(width: 6, height: 6)
                    Text("Nourish · Feeding now")
                        .font(.system(size: 11, weight: .bold))
                }
                Text("\(FeedFormat.sideLetter(from: snapshot.activeSessionSide))  ")
                    .font(.system(size: 14, weight: .semibold))
                + Text(start, style: .timer)
                    .font(.system(size: 14, weight: .semibold))
            } else {
                Text("Nourish · Last feed")
                    .font(.system(size: 11, weight: .bold))
                if snapshot.lastFeedTime != nil {
                    let letter = FeedFormat.sideLetter(from: snapshot.lastFeedSide)
                    let ago = FeedFormat.timeAgo(from: snapshot.lastFeedTime, reference: now)
                    Text("\(letter) · \(ago)")
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                    if !breakdown.isEmpty {
                        Text(breakdown)
                            .font(.system(size: 12))
                            .lineLimit(1)
                    }
                } else {
                    Text("Tap to start your first feed")
                        .font(.system(size: 12))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var breakdown: String {
        if snapshot.isBottle {
            return snapshot.lastFeedBottleMl > 0 ? "\(snapshot.lastFeedBottleMl) ml" : ""
        }
        var parts: [String] = []
        if snapshot.lastFeedLeftMinutes > 0  { parts.append("L \(snapshot.lastFeedLeftMinutes)m") }
        if snapshot.lastFeedRightMinutes > 0 { parts.append("R \(snapshot.lastFeedRightMinutes)m") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Inline

private struct InlineLockView: View {
    let snapshot: FeedSnapshot
    let now: Date

    var body: some View {
        if snapshot.isActuallyActive, let start = snapshot.activeSessionStart {
            Text("Nourish · Feeding \(FeedFormat.sideLetter(from: snapshot.activeSessionSide)) · ")
            + Text(start, style: .timer)
        } else if snapshot.lastFeedTime != nil {
            Text("Nourish · \(FeedFormat.sideLetter(from: snapshot.lastFeedSide)) · \(FeedFormat.timeAgo(from: snapshot.lastFeedTime, reference: now))")
        } else {
            Text("Nourish · tap to start")
        }
    }
}
