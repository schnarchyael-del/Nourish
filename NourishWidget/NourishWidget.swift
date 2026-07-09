import WidgetKit
import SwiftUI
import UIKit
import AppIntents

// MARK: - Nourish palette (mirrors main app — adapts to system dark mode)

private func dynamic(_ light: UIColor, _ dark: UIColor) -> Color {
    Color(UIColor { trait in
        trait.userInterfaceStyle == .dark ? dark : light
    })
}

private func uiColor(_ r: Int, _ g: Int, _ b: Int, _ a: CGFloat = 1) -> UIColor {
    UIColor(red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: a)
}

enum NourishWidgetColor {
    static let bg = dynamic(uiColor(250, 247, 242), uiColor(28, 25, 23))
    static let ink = dynamic(uiColor(44, 24, 16), uiColor(250, 247, 242))
    static let muted = dynamic(uiColor(158, 142, 134), uiColor(168, 162, 158))
    static let border = dynamic(uiColor(44, 24, 16, 0.10), UIColor.white.withAlphaComponent(0.10))

    // Accents stay the same in both modes; only the tinted backgrounds shift.
    static let leftFg   = Color(red: 192/255, green:  88/255, blue:  64/255)  // terra
    static let rightFg  = Color(red:  72/255, green: 116/255, blue: 154/255)  // blue
    static let bottleFg = Color(red: 196/255, green: 162/255, blue: 101/255)
    static let sleepFg  = Color(red:  83/255, green:  74/255, blue: 183/255)  // muted indigo

    static let leftBg = dynamic(
        uiColor(247, 232, 224),
        uiColor(192, 88, 64, 0.20)
    )
    static let rightBg = dynamic(
        uiColor(226, 235, 240),
        uiColor(72, 116, 154, 0.20)
    )
    static let bottleBg = dynamic(
        uiColor(245, 235, 215),
        uiColor(196, 162, 101, 0.20)
    )
    /// Soft lavender — mirrors SleepView.sleepBg on the main app side.
    static let sleepBg = dynamic(
        uiColor(238, 237, 254),
        uiColor(83, 74, 183, 0.22)
    )
}

private extension String {
    var sideForegroundColor: Color {
        switch self {
        case "left":   return NourishWidgetColor.leftFg
        case "right":  return NourishWidgetColor.rightFg
        case "bottle": return NourishWidgetColor.bottleFg
        default:       return NourishWidgetColor.muted
        }
    }
    var sideBackgroundColor: Color {
        switch self {
        case "left":   return NourishWidgetColor.leftBg
        case "right":  return NourishWidgetColor.rightBg
        case "bottle": return NourishWidgetColor.bottleBg
        default:       return NourishWidgetColor.bg
        }
    }
}

// MARK: - Side badge (used everywhere)

struct SideBadge: View {
    let side: String
    var size: CGFloat = 32

    var body: some View {
        ZStack {
            Circle()
                .fill(side.sideBackgroundColor)
                .overlay(Circle().stroke(side.sideForegroundColor.opacity(0.25), lineWidth: 1))
            Text(FeedFormat.sideLetter(from: side))
                .font(.system(size: size * 0.5, weight: .bold, design: .rounded))
                .foregroundStyle(side.sideForegroundColor)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Brand header

struct NourishBrand: View {
    var iconSize: CGFloat = 14
    var showWordmark: Bool = true

    var body: some View {
        HStack(spacing: 5) {
            Image("NourishLogo")
                .resizable()
                .interpolation(.high)
                .frame(width: iconSize, height: iconSize)
                .clipShape(RoundedRectangle(cornerRadius: iconSize * 0.22, style: .continuous))
            if showWordmark {
                Text("Nourish")
                    .font(.system(size: 11, weight: .bold, design: .serif))
                    .foregroundStyle(NourishWidgetColor.ink)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
    }
}

// MARK: - Sleep overlay row (used by every home-screen size when sleeping)

struct SleepStatusRow: View {
    let snapshot: FeedSnapshot
    let now: Date
    var compact: Bool = false

    var body: some View {
        HStack(spacing: compact ? 6 : 8) {
            Image(systemName: "moon.fill")
                .font(.system(size: compact ? 10 : 12, weight: .semibold))
                .foregroundStyle(NourishWidgetColor.sleepFg)
            Text("Sleeping · \(FeedFormat.sleepElapsed(from: snapshot.sleepStartedAt, reference: now))")
                .font(.system(size: compact ? 11 : 12, weight: .semibold))
                .foregroundStyle(NourishWidgetColor.sleepFg)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, compact ? 8 : 10)
        .padding(.vertical, compact ? 4 : 6)
        .background(NourishWidgetColor.sleepBg)
        .clipShape(Capsule())
    }
}

// MARK: - Home Screen Widget

struct NourishHomeWidget: Widget {
    let kind = "NourishHomeWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NourishProvider()) { entry in
            HomeWidgetView(snapshot: entry.snapshot, now: entry.date)
                .containerBackground(NourishWidgetColor.bg, for: .widget)
                .widgetURL(URL(string: "nourish://home"))
        }
        .configurationDisplayName("Nourish — Last feed")
        .description("Your last feed and current sleep status.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

private struct HomeWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let snapshot: FeedSnapshot
    let now: Date

    var body: some View {
        switch family {
        case .systemMedium:
            MediumHomeView(snapshot: snapshot, now: now)
        case .systemLarge:
            LargeHomeView(snapshot: snapshot, now: now)
        default:
            if snapshot.isActuallyActive {
                ActiveSmallHomeView(snapshot: snapshot, now: now)
            } else if snapshot.hasData || snapshot.isBabySleeping {
                SmallHomeView(snapshot: snapshot, now: now)
            } else {
                EmptyHomeView()
            }
        }
    }
}

// MARK: - Active session

private struct ActiveSmallHomeView: View {
    let snapshot: FeedSnapshot
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if snapshot.isBabySleeping {
                SleepStatusRow(snapshot: snapshot, now: now, compact: true)
            } else {
                NourishBrand(iconSize: 14)
            }

            HStack(spacing: 10) {
                SideBadge(side: snapshot.activeSessionSide, size: 36)
                VStack(alignment: .leading, spacing: 1) {
                    Text(snapshot.isActivePaused ? "Paused" : "Feeding")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(NourishWidgetColor.muted)
                    Text("\(snapshot.activeSessionSide.capitalized) breast")
                        .font(.system(size: 18, weight: .bold, design: .serif))
                        .foregroundStyle(snapshot.activeSessionSide.sideForegroundColor)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: 4) {
                Circle()
                    .fill(snapshot.isActivePaused ? NourishWidgetColor.muted : NourishWidgetColor.leftFg)
                    .frame(width: 6, height: 6)
                Text(snapshot.isActivePaused ? "Paused" : "Live")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(snapshot.isActivePaused ? NourishWidgetColor.muted : NourishWidgetColor.leftFg)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct EmptyHomeView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            NourishBrand()
            Spacer()
            Text("🌱")
                .font(.system(size: 32))
            Text("Start your first feed")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(NourishWidgetColor.ink)
            Text("Tap to open Nourish")
                .font(.system(size: 11))
                .foregroundStyle(NourishWidgetColor.muted)
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Per-side line (helper used in multiple sizes)

private struct SidesBreakdown: View {
    let snapshot: FeedSnapshot
    var compact: Bool = false

    var body: some View {
        HStack(spacing: compact ? 8 : 12) {
            if snapshot.isBottle {
                Text(snapshot.lastFeedBottleMl > 0 ? "\(snapshot.lastFeedBottleMl) ml" : "Bottle feed")
                    .font(.system(size: compact ? 12 : 13, weight: .semibold))
                    .foregroundStyle(NourishWidgetColor.bottleFg)
            } else {
                if snapshot.lastFeedLeftMinutes > 0 {
                    sidePill("L \(snapshot.lastFeedLeftMinutes)m",
                             color: NourishWidgetColor.leftFg)
                }
                if snapshot.lastFeedRightMinutes > 0 {
                    sidePill("R \(snapshot.lastFeedRightMinutes)m",
                             color: NourishWidgetColor.rightFg)
                }
            }
        }
    }

    private func sidePill(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: compact ? 12 : 13, weight: .semibold))
            .foregroundStyle(color)
    }
}

// MARK: - Small

private struct SmallHomeView: View {
    let snapshot: FeedSnapshot
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Sleep on top (when active) replaces the brand line so both
            // sleep and feed info fit. When not sleeping, brand stays put
            // and the widget renders exactly as before.
            if snapshot.isBabySleeping {
                SleepStatusRow(snapshot: snapshot, now: now, compact: true)
            } else {
                NourishBrand(iconSize: 14)
            }

            HStack(spacing: 10) {
                SideBadge(side: snapshot.lastFeedSide,
                          size: snapshot.isBabySleeping ? 30 : 36)
                Text(FeedFormat.timeAgo(from: snapshot.lastFeedTime, reference: now))
                    .font(.system(size: snapshot.isBabySleeping ? 14 : 16,
                                  weight: .bold, design: .serif))
                    .foregroundStyle(NourishWidgetColor.ink)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            }

            SidesBreakdown(snapshot: snapshot, compact: true)

            Spacer(minLength: 0)

            HStack(spacing: 4) {
                Text("Today:")
                    .font(.system(size: 10))
                    .foregroundStyle(NourishWidgetColor.muted)
                Text("\(snapshot.todaySessionCount) feeds · \(snapshot.todayTotalMinutes)m")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(NourishWidgetColor.ink)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Medium

private struct MediumHomeView: View {
    let snapshot: FeedSnapshot
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if snapshot.isBabySleeping {
                SleepStatusRow(snapshot: snapshot, now: now)
            } else {
                NourishBrand(iconSize: 14)
            }

            if snapshot.isActuallyActive {
                activeFeedRow
            } else {
                feedRow
                Spacer(minLength: 0)
                todayLine
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var activeFeedRow: some View {
        // Counter intentionally omitted — the Live Activity is the source
        // of truth for the live timer.
        HStack(spacing: 12) {
            SideBadge(side: snapshot.activeSessionSide, size: 42)
            VStack(alignment: .leading, spacing: 2) {
                Text(snapshot.isActivePaused ? "Paused" : "Feeding now")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(NourishWidgetColor.muted)
                Text("\(snapshot.activeSessionSide.capitalized) breast")
                    .font(.system(size: 22, weight: .bold, design: .serif))
                    .foregroundStyle(snapshot.activeSessionSide.sideForegroundColor)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }

    private var todayLine: some View {
        HStack(spacing: 4) {
            Text("Today:")
                .font(.system(size: 11))
                .foregroundStyle(NourishWidgetColor.muted)
            Text("\(snapshot.todaySessionCount) feeds · \(snapshot.todayTotalMinutes)m")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(NourishWidgetColor.ink)
        }
    }

    @ViewBuilder
    private var feedRow: some View {
        if snapshot.hasData {
            HStack(spacing: 12) {
                SideBadge(side: snapshot.lastFeedSide, size: 42)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Last feed")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(NourishWidgetColor.muted)
                    Text(FeedFormat.timeAgo(from: snapshot.lastFeedTime, reference: now))
                        .font(.system(size: 18, weight: .bold, design: .serif))
                        .foregroundStyle(NourishWidgetColor.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    SidesBreakdown(snapshot: snapshot, compact: false)
                }
                Spacer(minLength: 0)
            }
        } else {
            Text("No feeds yet")
                .font(.system(size: 14))
                .foregroundStyle(NourishWidgetColor.muted)
        }
    }
}

// MARK: - Large

private struct LargeHomeView: View {
    let snapshot: FeedSnapshot
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if snapshot.isBabySleeping {
                SleepStatusRow(snapshot: snapshot, now: now)
            } else {
                NourishBrand(iconSize: 16)
            }

            if snapshot.isActuallyActive {
                activeFeedBlock
            } else if snapshot.hasData {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Last feed")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(NourishWidgetColor.muted)
                    HStack(spacing: 14) {
                        SideBadge(side: snapshot.lastFeedSide, size: 50)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(FeedFormat.timeAgo(from: snapshot.lastFeedTime, reference: now))
                                .font(.system(size: 22, weight: .bold, design: .serif))
                                .foregroundStyle(NourishWidgetColor.ink)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                            SidesBreakdown(snapshot: snapshot, compact: false)
                        }
                        Spacer(minLength: 0)
                    }
                }
            } else {
                Text("No feeds yet")
                    .font(.system(size: 16))
                    .foregroundStyle(NourishWidgetColor.muted)
            }

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 4) {
                Text("Today")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(NourishWidgetColor.muted)
                Text("\(snapshot.todaySessionCount) feeds · \(snapshot.todayTotalMinutes) min")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(NourishWidgetColor.ink)
                if snapshot.todayLeftMinutes > 0 || snapshot.todayRightMinutes > 0 {
                    HStack(spacing: 10) {
                        if snapshot.todayLeftMinutes > 0 {
                            Text("L \(snapshot.todayLeftMinutes)m")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(NourishWidgetColor.leftFg)
                        }
                        if snapshot.todayRightMinutes > 0 {
                            Text("R \(snapshot.todayRightMinutes)m")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(NourishWidgetColor.rightFg)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var activeFeedBlock: some View {
        HStack(spacing: 14) {
            SideBadge(side: snapshot.activeSessionSide, size: 50)
            VStack(alignment: .leading, spacing: 3) {
                Text(snapshot.isActivePaused ? "Paused" : "Feeding now")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(NourishWidgetColor.muted)
                Text("\(snapshot.activeSessionSide.capitalized) breast")
                    .font(.system(size: 26, weight: .bold, design: .serif))
                    .foregroundStyle(snapshot.activeSessionSide.sideForegroundColor)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }

}

