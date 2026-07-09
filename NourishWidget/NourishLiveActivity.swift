import ActivityKit
import WidgetKit
import SwiftUI
import AppIntents

// Theme — colors are dynamic so the lock-screen banner follows the user's
// system appearance. Light: warm cream + ink. Dark: warm dark brown
// (#1C1917) + cream text. Accents stay constant for brand consistency;
// their tinted backgrounds shift opacity for dark mode.
//
// On the Dynamic Island the system always renders against a dark
// background, so DI views use the `…OnDark` variants (white / near-white)
// explicitly rather than relying on the dynamic palette.
private enum LATheme {
    static let cream = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 28/255, green: 25/255, blue: 23/255, alpha: 1.0)
            : UIColor(red: 250/255, green: 247/255, blue: 242/255, alpha: 1.0)
    })
    static let ink = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 250/255, green: 247/255, blue: 242/255, alpha: 1.0)
            : UIColor(red: 44/255, green: 24/255, blue: 16/255, alpha: 1.0)
    })
    static let muted = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 250/255, green: 247/255, blue: 242/255, alpha: 0.65)
            : UIColor(red: 44/255, green: 24/255, blue: 16/255, alpha: 0.55)
    })

    static let leftAccent  = Color(red: 192/255, green:  88/255, blue:  64/255) // terra cotta
    static let rightAccent = Color(red:  72/255, green: 116/255, blue: 154/255) // slate blue
    static let leftBg = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 192/255, green: 88/255, blue: 64/255, alpha: 0.22)
            : UIColor(red: 247/255, green: 232/255, blue: 224/255, alpha: 1.0)
    })
    static let rightBg = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 72/255, green: 116/255, blue: 154/255, alpha: 0.22)
            : UIColor(red: 226/255, green: 235/255, blue: 240/255, alpha: 1.0)
    })

    static let lavender = Color(red: 83/255, green: 74/255, blue: 183/255)
    static let lavenderBg = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 83/255, green: 74/255, blue: 183/255, alpha: 0.22)
            : UIColor(red: 238/255, green: 237/255, blue: 254/255, alpha: 1.0)
    })

    // Dynamic Island is always dark — explicit light tones for use there.
    static let onDarkPrimary = Color.white
    static let onDarkMuted   = Color.white.opacity(0.7)
}

// MARK: - Feed Live Activity

@available(iOS 16.2, *)
struct NourishFeedLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: NourishFeedActivityAttributes.self) { context in
            FeedLockScreenView(state: context.state)
                .activityBackgroundTint(LATheme.cream)
                .activitySystemActionForegroundColor(LATheme.ink)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    feedSideBadge(state: context.state, size: 38, onDark: true)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    feedTimerText(state: context.state, size: 24, onDark: true)
                        .frame(minWidth: 80, alignment: .trailing)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.isPaused ? "Paused" : "\(context.state.currentSide.capitalized) breast")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(LATheme.onDarkMuted)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    feedControlsRow(state: context.state, compact: true)
                }
            } compactLeading: {
                feedSideBadge(state: context.state, size: 18, onDark: true)
            } compactTrailing: {
                feedTimerText(state: context.state, size: 13, onDark: true)
                    .frame(maxWidth: 50)
            } minimal: {
                feedTimerText(state: context.state, size: 11, onDark: true)
                    .frame(maxWidth: 38)
            }
        }
    }
}

// MARK: - Feed lock screen layout

@available(iOS 16.2, *)
private struct FeedLockScreenView: View {
    let state: NourishFeedActivityAttributes.ContentState

    var body: some View {
        VStack(spacing: 12) {
            // Top row: side badge | status + timer | spacer for visual balance
            HStack(alignment: .center, spacing: 14) {
                feedSideBadge(state: state, size: 56)

                VStack(alignment: .leading, spacing: 2) {
                    Text(state.isPaused ? "Paused" : "Feeding")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(LATheme.muted)
                        .textCase(.uppercase)
                        .kerning(0.8)
                    feedTimerText(state: state, size: 38)
                        .fontWeight(.bold)
                    HStack(spacing: 6) {
                        Text("Total · \(totalLabel(state: state))")
                        Text("·")
                        Text("Started \(state.sessionStartDate.formatted(date: .omitted, time: .shortened))")
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(LATheme.muted)
                    .lineLimit(1)
                }

                Spacer(minLength: 0)
            }

            feedControlsRow(state: state, compact: false)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

// MARK: - Visible control chips

@available(iOS 16.2, *)
@ViewBuilder
private func feedControlsRow(
    state: NourishFeedActivityAttributes.ContentState,
    compact: Bool
) -> some View {
    let chipSize: CGFloat = compact ? 44 : 52
    let iconSize: CGFloat = compact ? 17 : 20

    // Order: Pause (safest, reversible) → Switch (mid) → End (destructive).
    HStack(spacing: compact ? 12 : 16) {
        // Pause / Resume — outlined first so the safest action is leftmost
        Button(intent: PauseFeedLiveIntent()) {
            LAControlChip(
                systemName: state.isPaused ? "play.fill" : "pause.fill",
                iconSize: iconSize,
                size: chipSize,
                style: .outlined
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(state.isPaused ? "Resume" : "Pause")

        // Switch — filled accent (terra cotta if leaving left, slate if leaving right)
        Button(intent: SwitchSideLiveIntent()) {
            LAControlChip(
                systemName: "arrow.left.arrow.right",
                iconSize: iconSize,
                size: chipSize,
                style: .filled(state.currentSide == "left" ? LATheme.leftAccent : LATheme.rightAccent)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Switch side")

        // End — solid dark, slightly smaller so it reads as the destructive action
        Button(intent: EndFeedLiveIntent()) {
            LAControlChip(
                systemName: "stop.fill",
                iconSize: iconSize - 2,
                size: chipSize - 4,
                style: .dark
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("End feed")
    }
    .frame(maxWidth: .infinity)
}

@available(iOS 16.2, *)
private struct LAControlChip: View {
    enum Style {
        case filled(Color)
        case outlined
        case dark
    }

    let systemName: String
    let iconSize: CGFloat
    let size: CGFloat
    let style: Style

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: iconSize, weight: .bold))
            .foregroundStyle(foreground)
            .frame(width: size, height: size)
            .background(background)
            .clipShape(Circle())
            .overlay(border)
            .contentShape(Circle())
    }

    private var foreground: Color {
        switch style {
        case .filled:    return .white
        case .outlined:  return LATheme.ink
        case .dark:      return .white
        }
    }

    @ViewBuilder private var background: some View {
        switch style {
        case .filled(let c): Circle().fill(c)
        case .outlined:      Circle().fill(LATheme.cream)
        // `.dark` chip stays dark in both appearances so the destructive
        // End action is always visually distinct from the others.
        case .dark:          Circle().fill(Color(red: 44/255, green: 24/255, blue: 16/255))
        }
    }

    @ViewBuilder private var border: some View {
        switch style {
        case .filled:
            Circle().stroke(.white.opacity(0.0), lineWidth: 0)
        case .outlined:
            Circle().stroke(LATheme.ink.opacity(0.85), lineWidth: 2)
        case .dark:
            Circle().stroke(.white.opacity(0.0), lineWidth: 0)
        }
    }
}

// MARK: Helpers

@ViewBuilder
private func feedSideBadge(
    state: NourishFeedActivityAttributes.ContentState,
    size: CGFloat,
    onDark: Bool = false
) -> some View {
    let isLeft = state.currentSide == "left"
    let accent = isLeft ? LATheme.leftAccent : LATheme.rightAccent
    // On the dark Dynamic Island, swap the pale tinted background for a
    // saturated accent fill so the L/R glyph is white on color — readable
    // against the system's black island.
    let bg: Color = onDark ? accent : (isLeft ? LATheme.leftBg : LATheme.rightBg)
    let glyph: Color = onDark ? .white : accent

    Text(isLeft ? "L" : "R")
        .font(.system(size: size * 0.55, weight: .heavy, design: .rounded))
        .foregroundStyle(glyph)
        .frame(width: size, height: size)
        .background(Circle().fill(bg))
        .overlay(Circle().stroke((onDark ? Color.white : accent).opacity(0.35), lineWidth: 1.5))
}

@ViewBuilder
private func feedTimerText(
    state: NourishFeedActivityAttributes.ContentState,
    size: CGFloat,
    onDark: Bool = false
) -> some View {
    let fg: Color = onDark ? LATheme.onDarkPrimary : LATheme.ink
    if state.isPaused {
        Text(formatTimer(state.pausedSideElapsedSeconds))
            .font(.system(size: size, weight: .semibold, design: .monospaced))
            .foregroundStyle(fg)
            .lineLimit(1)
    } else {
        Text(state.currentSideStartDate, style: .timer)
            .font(.system(size: size, weight: .semibold, design: .monospaced))
            .foregroundStyle(fg)
            .lineLimit(1)
            .multilineTextAlignment(.leading)
    }
}

private func formatTimer(_ seconds: Int) -> String {
    let h = seconds / 3600
    let m = (seconds % 3600) / 60
    let s = seconds % 60
    if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
    return String(format: "%d:%02d", m, s)
}

private func totalLabel(state: NourishFeedActivityAttributes.ContentState) -> String {
    // Accumulators already include any committed segment, so we only add
    // the in-flight uncommitted segment (zero when paused).
    let currentSideAcc = (state.currentSide == "left")
        ? state.leftAccumulatedSeconds
        : state.rightAccumulatedSeconds
    let uncommittedSegment: Int
    if state.isPaused {
        uncommittedSegment = 0
    } else {
        let sideTotal = max(0, Int(Date.now.timeIntervalSince(state.currentSideStartDate)))
        uncommittedSegment = max(0, sideTotal - currentSideAcc)
    }
    let total = state.leftAccumulatedSeconds + state.rightAccumulatedSeconds + uncommittedSegment
    let m = total / 60
    return "\(m) min"
}

// MARK: - Sleep Live Activity

@available(iOS 16.2, *)
struct NourishSleepLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: NourishSleepActivityAttributes.self) { context in
            SleepLockScreenView(state: context.state, babyName: context.attributes.babyName)
                .activityBackgroundTint(LATheme.cream)
                .activitySystemActionForegroundColor(LATheme.ink)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        Image(systemName: "moon.fill")
                            .foregroundStyle(LATheme.lavender)
                        Text(context.attributes.babyName)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(LATheme.ink)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.sleepStartDate, style: .timer)
                        .font(.system(size: 22, weight: .bold, design: .monospaced))
                        .foregroundStyle(LATheme.lavender)
                        .multilineTextAlignment(.trailing)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    sleepWakeButton(compact: true)
                }
            } compactLeading: {
                Image(systemName: "moon.fill")
                    .foregroundStyle(LATheme.lavender)
            } compactTrailing: {
                Text(context.state.sleepStartDate, style: .timer)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .frame(maxWidth: 50)
            } minimal: {
                Image(systemName: "moon.fill")
                    .foregroundStyle(LATheme.lavender)
            }
        }
    }
}

@available(iOS 16.2, *)
private struct SleepLockScreenView: View {
    let state: NourishSleepActivityAttributes.ContentState
    let babyName: String

    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .center, spacing: 14) {
                ZStack {
                    Circle().fill(LATheme.lavenderBg)
                    Image(systemName: "moon.fill")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(LATheme.lavender)
                }
                .frame(width: 56, height: 56)
                .overlay(Circle().stroke(LATheme.lavender.opacity(0.3), lineWidth: 1.5))

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(babyName) is sleeping")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(LATheme.muted)
                        .textCase(.uppercase)
                        .kerning(0.8)
                    Text(state.sleepStartDate, style: .timer)
                        .font(.system(size: 38, weight: .bold, design: .monospaced))
                        .foregroundStyle(LATheme.lavender)
                        .lineLimit(1)
                    Text("Fell asleep at \(state.sleepStartDate.formatted(date: .omitted, time: .shortened))")
                        .font(.system(size: 11))
                        .foregroundStyle(LATheme.muted)
                }

                Spacer(minLength: 0)
            }

            sleepWakeButton(compact: false)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

@available(iOS 16.2, *)
@ViewBuilder
private func sleepWakeButton(compact: Bool) -> some View {
    Button(intent: EndSleepLiveIntent()) {
        HStack(spacing: 8) {
            Image(systemName: "sun.max.fill")
                .font(.system(size: compact ? 15 : 17, weight: .bold))
            Text("Baby woke up")
                .font(.system(size: compact ? 14 : 16, weight: .bold))
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .frame(height: compact ? 44 : 48)
        .background(LATheme.lavender)
        .clipShape(Capsule())
    }
    .buttonStyle(.plain)
    .accessibilityLabel("Baby woke up")
}
