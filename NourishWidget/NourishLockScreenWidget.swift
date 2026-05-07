import WidgetKit
import SwiftUI

struct NourishLockScreenWidget: Widget {
    let kind = "NourishLockScreenWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NourishProvider()) { entry in
            LockScreenView(snapshot: entry.snapshot)
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

    var body: some View {
        switch family {
        case .accessoryCircular:    CircularLockView(snapshot: snapshot)
        case .accessoryRectangular: RectangularLockView(snapshot: snapshot)
        case .accessoryInline:      InlineLockView(snapshot: snapshot)
        default:                    InlineLockView(snapshot: snapshot)
        }
    }
}

// MARK: - Circular

/// Side letter big in the middle, time-ago below.
private struct CircularLockView: View {
    let snapshot: FeedSnapshot

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Text(letter)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.5)
                Text(timeAgoCompact)
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
    }

    private var letter: String {
        snapshot.hasData ? FeedFormat.sideLetter(from: snapshot.lastFeedSide) : "—"
    }

    /// Compact form fits the circular gauge: "2h", "45m", "now", "—"
    private var timeAgoCompact: String {
        guard let date = snapshot.lastFeedTime else { return "—" }
        let secs = max(0, Int(Date.now.timeIntervalSince(date)))
        if secs < 60 { return "now" }
        let mins = secs / 60
        if mins < 60 { return "\(mins)m" }
        return "\(mins / 60)h"
    }
}

// MARK: - Rectangular

/// Three lines: "Nourish · Last feed" header, side + time, per-side breakdown.
private struct RectangularLockView: View {
    let snapshot: FeedSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("Nourish · Last feed")
                .font(.system(size: 11, weight: .bold))
            if snapshot.hasData {
                Text(line1)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                if !line2.isEmpty {
                    Text(line2)
                        .font(.system(size: 12))
                        .lineLimit(1)
                }
            } else {
                Text("Tap to start your first feed")
                    .font(.system(size: 12))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var line1: String {
        let letter = FeedFormat.sideLetter(from: snapshot.lastFeedSide)
        let ago = FeedFormat.timeAgo(from: snapshot.lastFeedTime)
        return "\(letter) · \(ago)"
    }

    private var line2: String {
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

    var body: some View {
        Text(text)
    }

    private var text: String {
        guard snapshot.hasData else { return "Nourish · tap to start" }
        let letter = FeedFormat.sideLetter(from: snapshot.lastFeedSide)
        let ago = FeedFormat.timeAgo(from: snapshot.lastFeedTime)
        let dur = snapshot.isBottle
            ? (snapshot.lastFeedBottleMl > 0 ? "\(snapshot.lastFeedBottleMl) ml" : "")
            : "\(snapshot.lastFeedLeftMinutes + snapshot.lastFeedRightMinutes)m"
        if dur.isEmpty {
            return "Nourish · \(letter) · \(ago)"
        }
        return "Nourish · \(letter) · \(ago) · \(dur)"
    }
}
