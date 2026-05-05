import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.nourishColors) private var c
    @Environment(\.modelContext) private var modelContext

    let store: SessionStore
    let onLog: () -> Void

    @Query(sort: \FeedingSession.startTime, order: SortOrder.reverse) private var sessions: [FeedingSession]

    @AppStorage("userName") private var userName = "Sarah"
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var showBottleSheet   = false
    @State private var avatarTapCount    = 0
    @State private var avatarResetTask: DispatchWorkItem? = nil

    private var lastSession: FeedingSession? { sessions.first }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        switch hour {
        case 5..<12:  return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<21: return "Good evening"
        default:       return "Good night"
        }
    }

    var body: some View {
        ZStack {
            VStack(spacing: 16) {
                header
                lastSessionCard
                breastButtons
                bottleButton
                logPastButton
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(c.bg)
        }
        .sheet(isPresented: $showBottleSheet) {
            BottleFeedSheet(isPresented: $showBottleSheet)
                .environment(\.nourishColors, c)
                .presentationDetents([.height(360)])
                .presentationDragIndicator(.hidden)
                .presentationCornerRadius(28)
                .presentationBackground(c.bg)
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(Date.now.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                    .font(.nSans(12, weight: .medium))
                    .foregroundStyle(c.muted)
                    .kerning(0.09 * 12)
                    .textCase(.uppercase)

                Text("\(greeting), \(userName)")
                    .font(.nSerif(26))
                    .foregroundStyle(c.ink)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer()

            Text(String(userName.prefix(1)))
                .font(.nSans(15, weight: .bold))
                .foregroundStyle(c.leftText)
                .frame(width: 40, height: 40)
                .background(c.leftBg)
                .clipShape(Circle())
                .overlay(Circle().stroke(c.leftAccent.opacity(0.22), lineWidth: 1))
                .shadow(color: c.leftShadow, radius: 5, y: 2)
                .onTapGesture {
                    avatarResetTask?.cancel()
                    avatarTapCount += 1
                    if avatarTapCount >= 3 {
                        avatarTapCount = 0
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        hasCompletedOnboarding = false
                    } else {
                        let task = DispatchWorkItem { avatarTapCount = 0 }
                        avatarResetTask = task
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: task)
                    }
                }
        }
        .padding(.horizontal, 24)
        .padding(.top, 26)
        .padding(.bottom, 4)
    }

    // MARK: Last session card

    private var lastSessionCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            if let s = lastSession {
                filledSessionCard(s)
            } else {
                emptySessionCard
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(c.surface)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(c.border, lineWidth: 1))
        .shadow(color: .black.opacity(0.04), radius: 7, y: 2)
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }

    private func filledSessionCard(_ s: FeedingSession) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Last session · \(s.formattedTime)")
                .font(.nSans(11, weight: .semibold))
                .foregroundStyle(c.muted)
                .kerning(0.1 * 11)
                .textCase(.uppercase)

            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    if s.feedType == .bottle {
                        Text("Bottle · \(s.timeAgoString)")
                            .font(.nSans(17, weight: .bold))
                            .foregroundStyle(c.ink)
                    } else {
                        Text("Started \(s.feedType.displayName) · \(s.timeAgoString)")
                            .font(.nSans(17, weight: .bold))
                            .foregroundStyle(c.ink)
                    }

                    if s.feedType != .bottle {
                        Text("\(s.durationMinutes) min total")
                            .font(.nSans(13))
                            .foregroundStyle(c.muted)
                    } else if let ml = s.bottleAmountMl {
                        Text("\(ml) ml · \(s.bottleContentType?.displayName ?? "")")
                            .font(.nSans(13))
                            .foregroundStyle(c.muted)
                    }
                }
                Spacer()

                if s.feedType != .bottle {
                    NourishPill(
                        label: s.feedType.shortLabel,
                        fill: s.feedType == .left ? c.leftBg : c.rightBg,
                        border: s.feedType == .left
                            ? c.leftAccent.opacity(0.2)
                            : c.rightAccent.opacity(0.2),
                        color: s.feedType == .left ? c.leftText : c.rightText
                    )
                } else {
                    Text("🍼").font(.nSans(22))
                }
            }
        }
    }

    private var emptySessionCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("No sessions yet")
                .font(.nSans(11, weight: .semibold))
                .foregroundStyle(c.muted)
                .kerning(0.1 * 11)
                .textCase(.uppercase)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text("Tap L or R to start your first session")
                .font(.nSans(14))
                .foregroundStyle(c.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Breast buttons

    private var breastButtons: some View {
        HStack(spacing: 14) {
            sideButton(.left)
            sideButton(.right)
        }
        .padding(.horizontal, 20)
        .frame(maxHeight: .infinity)
        .padding(.bottom, 16)
    }

    private func sideButton(_ side: FeedSide) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            store.start(side: side)
            AnalyticsService.sessionStarted(startingSide: side.rawValue, feedType: "breast")
        } label: {
            VStack(spacing: 8) {
                Text(side.label)
                    .font(.nSerif(78))
                    .foregroundStyle(c.accentColor(for: side))

                Text(side.name)
                    .font(.nSans(17, weight: .bold))
                    .foregroundStyle(c.textColor(for: side))

                Text("tap to start")
                    .font(.nSans(13))
                    .foregroundStyle(c.muted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                LinearGradient(
                    colors: [
                        side == .left ? Color(hex: "FFFAF8") : Color(hex: "F8FAFE"),
                        c.bgColor(for: side)
                    ],
                    startPoint: .top, endPoint: .bottom
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 28))
            .overlay(
                RoundedRectangle(cornerRadius: 28)
                    .stroke(
                        side == .left
                            ? Color(hex: "C05840").opacity(0.15)
                            : Color(hex: "5A87A4").opacity(0.15),
                        lineWidth: 1.5
                    )
            )
            .shadow(color: c.shadowColor(for: side), radius: 15, y: 6)
        }
        .buttonStyle(ScaleButtonStyle(scale: 0.963))
    }

    // MARK: Bottle & Log buttons

    private var bottleButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            showBottleSheet = true
        } label: {
            HStack(spacing: 8) {
                Text("🍼")
                    .font(.nSans(19))
                Text("Bottle feed")
                    .font(.nSans(15, weight: .semibold))
                    .foregroundStyle(c.bottleAccent)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(c.bottleBg)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(c.bottleBorder, lineWidth: 1.5))
        }
        .buttonStyle(ScaleButtonStyle())
        .padding(.horizontal, 20)
        .padding(.bottom, 14)
    }

    private var logPastButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onLog()
        } label: {
            HStack(spacing: 8) {
                Text("+")
                    .font(.nSans(21))
                    .foregroundStyle(c.muted)
                Text("Log a past session")
                    .font(.nSans(15))
                    .foregroundStyle(c.muted)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(
                        c.muted.opacity(0.35),
                        style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
                    )
            )
        }
        .buttonStyle(ScaleButtonStyle())
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
    }
}
