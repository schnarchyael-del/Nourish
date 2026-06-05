import WidgetKit
import SwiftUI
import AppIntents

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
            // Sleep takes the circular slot exclusively when active —
            // it's too small to show both sleep and feed legibly.
            if snapshot.isBabySleeping {
                VStack(spacing: 0) {
                    Image(systemName: "moon.fill")
                        .font(.system(size: 16, weight: .semibold))
                    Text(FeedFormat.sleepElapsed(from: snapshot.sleepStartedAt, reference: now))
                        .font(.system(size: 10, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if snapshot.isActuallyActive {
                VStack(spacing: 0) {
                    HStack(spacing: 2) {
                        Circle().frame(width: 5, height: 5)
                        Text(FeedFormat.sideLetter(from: snapshot.activeSessionSide))
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                    }
                    Group {
                        if snapshot.isActivePaused {
                            Text(FeedFormat.elapsedTimer(snapshot.pausedElapsedSeconds))
                        } else if let effective = snapshot.effectiveActiveStart {
                            Text(effective, style: .timer)
                        }
                    }
                    .font(.system(size: 9, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if snapshot.lastFeedTime != nil {
                VStack(spacing: 0) {
                    Text(FeedFormat.sideLetter(from: snapshot.lastFeedSide))
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.5)
                        .frame(maxWidth: .infinity)
                    Text(FeedFormat.timeAgoCompact(from: snapshot.lastFeedTime, reference: now))
                        .font(.system(size: 9, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        if snapshot.isBabySleeping {
            sleepingLayout
        } else if snapshot.isActuallyActive {
            activeFeedLayout
        } else {
            displayOnlyLayout
        }
    }

    // MARK: Sleeping — info on the left, ONE big "Woke up" button on the right.

    @ViewBuilder private var sleepingLayout: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Image(systemName: "moon.fill").font(.system(size: 11, weight: .semibold))
                    Text("Sleeping · \(FeedFormat.sleepElapsed(from: snapshot.sleepStartedAt, reference: now))")
                        .font(.system(size: 13, weight: .bold))
                        .lineLimit(1)
                }
                if snapshot.lastFeedTime != nil {
                    let letter = FeedFormat.sideLetter(from: snapshot.lastFeedSide)
                    let ago    = FeedFormat.timeAgo(from: snapshot.lastFeedTime, reference: now)
                    Text("Last feed: \(ago) · \(letter)")
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            // One large, square tap target — iOS vibrancy will tint it,
            // but the size + icon makes it obvious you can tap.
            Button(intent: EndSleepIntent()) {
                Image(systemName: "sun.max.fill")
                    .font(.system(size: 20, weight: .bold))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Baby woke up")
        }
    }

    // MARK: Active feed — compact status line on top, three icon-only
    // buttons below (Pause/Resume, Switch, End). Two-row layout buys each
    // button enough width for a clean tap target despite the cramped strip.

    @ViewBuilder private var activeFeedLayout: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Circle().frame(width: 5, height: 5)
                if snapshot.isActivePaused {
                    Text("Paused \(FeedFormat.sideLetter(from: snapshot.activeSessionSide))  \(FeedFormat.elapsedTimer(snapshot.pausedElapsedSeconds))")
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                } else if let effective = snapshot.effectiveActiveStart {
                    Text("Feeding \(FeedFormat.sideLetter(from: snapshot.activeSessionSide))  ")
                        .font(.system(size: 12, weight: .semibold))
                    + Text(effective, style: .timer)
                        .font(.system(size: 12, weight: .semibold))
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 6) {
                Button(intent: PauseFeedIntent()) {
                    Image(systemName: snapshot.isActivePaused ? "play.fill" : "pause.fill")
                        .font(.system(size: 14, weight: .bold))
                        .frame(maxWidth: .infinity, minHeight: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(snapshot.isActivePaused ? "Resume feed" : "Pause feed")

                Button(intent: SwitchSideIntent()) {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 14, weight: .bold))
                        .frame(maxWidth: .infinity, minHeight: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Switch side")

                Button(intent: EndFeedIntent()) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 14, weight: .bold))
                        .frame(maxWidth: .infinity, minHeight: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("End feed")
            }
        }
    }

    // MARK: Idle — display only, unchanged from before.

    @ViewBuilder private var displayOnlyLayout: some View {
        VStack(alignment: .leading, spacing: 1) {
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
        if snapshot.isBabySleeping {
            let sleep = FeedFormat.sleepElapsed(from: snapshot.sleepStartedAt, reference: now)
            if snapshot.lastFeedTime != nil {
                let letter = FeedFormat.sideLetter(from: snapshot.lastFeedSide)
                let ago    = FeedFormat.timeAgo(from: snapshot.lastFeedTime, reference: now)
                Text("🌙 \(sleep) · Fed \(ago) · \(letter)")
            } else {
                Text("🌙 \(sleep)")
            }
        } else if snapshot.isActuallyActive {
            if snapshot.isActivePaused {
                Text("Nourish · Paused \(FeedFormat.sideLetter(from: snapshot.activeSessionSide)) · \(FeedFormat.elapsedTimer(snapshot.pausedElapsedSeconds))")
            } else if let effective = snapshot.effectiveActiveStart {
                Text("Nourish · Feeding \(FeedFormat.sideLetter(from: snapshot.activeSessionSide)) · ")
                + Text(effective, style: .timer)
            }
        } else if snapshot.lastFeedTime != nil {
            Text("Nourish · \(FeedFormat.sideLetter(from: snapshot.lastFeedSide)) · \(FeedFormat.timeAgo(from: snapshot.lastFeedTime, reference: now))")
        } else {
            Text("Nourish · tap to start")
        }
    }
}
