import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.nourishColors) private var c
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var tooltips: TooltipManager

    let store: SessionStore
    let onLog: () -> Void
    let onPump: () -> Void

    @Query(sort: \FeedingSession.startTime, order: SortOrder.reverse) private var sessions: [FeedingSession]

    @AppStorage("userName") private var userName = "Sarah"
    @AppStorage("babyName") private var babyName = "Lily"
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var showBottleSheet   = false
    @State private var avatarTapCount    = 0
    @State private var avatarResetTask: DispatchWorkItem? = nil
    @State private var didInitialEvaluate = false

    // "Baby is sleeping — end nap and start a feed?" alert state.
    // Any tap on a feed action (L/R/Bottle/Pump) is routed through
    // `attemptFeedAction(_:)`; if a nap is in progress we stash the action
    // and prompt instead of starting immediately.
    private enum PendingFeedAction { case side(FeedSide), bottle, pump }
    @State private var pendingFeedAction: PendingFeedAction?
    @State private var showEndSleepAlert = false
    /// Cached count of consecutive recent days with at least one feed. Only
    /// surfaced when >= 5 so we never show a "0 day streak" or empty state.
    @State private var streakDays: Int = 0

    private var lastFeed: FeedingSession? {
        sessions.first(where: { $0.feedType != .pump && $0.feedType != .sleep })
    }

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
                secondaryButtons
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
        .alert("\(babyName) is sleeping", isPresented: $showEndSleepAlert) {
            Button("Cancel", role: .cancel) { pendingFeedAction = nil }
            Button("End nap & feed") {
                SleepView.endActiveSleep(modelContext: modelContext)
                if let action = pendingFeedAction { executeFeedAction(action) }
                pendingFeedAction = nil
            }
        } message: {
            Text("Would you like to end the nap and start feeding?")
        }
        .onAppear {
            // .onAppear can fire multiple times during initial layout and
            // tab transitions in SwiftUI; gate to once per HomeView instance.
            guard !didInitialEvaluate else { return }
            didInitialEvaluate = true
            tooltips.bumpHomeAppearanceIfFirstThisLaunch(haveSessions: !sessions.isEmpty)
            evaluateTooltips()
        }
        .task(id: sessions.first?.id) {
            // @Query results land asynchronously (initial fetch + Firestore
            // sync). Whenever the leading session id changes — including
            // the initial nil → real-id transition — count this launch and
            // re-evaluate so the widget tip can fire if it's earned.
            tooltips.bumpHomeAppearanceIfFirstThisLaunch(haveSessions: !sessions.isEmpty)
            evaluateTooltips()
        }
        .onChange(of: tooltips.active) { _, new in
            // When a tooltip dismisses, re-evaluate so the next one in the
            // home sequence (e.g. settings after startFeed) can chain in.
            if new == nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    evaluateTooltips()
                }
            }
        }
        .task { recomputeStreak() }
        .onChange(of: sessions.count)       { _, _ in recomputeStreak() }
        .onChange(of: sessions.first?.id)   { _, _ in recomputeStreak() }
        .onChange(of: scenePhase) { _, phase in
            // Re-evaluate on foreground so the noon cutoff catches up after
            // the app has been backgrounded across the boundary.
            if phase == .active { recomputeStreak() }
        }
    }

    /// Counts consecutive days, ending at today, that have at least one
    /// completed breast or bottle feed. Pump sessions are excluded.
    ///
    /// Noon grace: before local noon, if the user hasn't fed yet today we
    /// anchor the count to yesterday instead of today — so the badge doesn't
    /// blink off every morning before the first AM feed. After noon, today
    /// is required (the user's had half a day to log something).
    ///
    /// Cheap (O(sessions)) but cached in @State so it only re-runs when
    /// sessions actually change or the app foregrounds.
    private func recomputeStreak() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let hour = cal.component(.hour, from: .now)

        var feedDays: Set<Date> = []
        for session in sessions where session.feedType != .pump && session.feedType != .sleep {
            feedDays.insert(cal.startOfDay(for: session.startTime))
        }

        var cursor = today
        if hour < 12 && !feedDays.contains(today) {
            guard let yesterday = cal.date(byAdding: .day, value: -1, to: today) else {
                streakDays = 0
                return
            }
            cursor = yesterday
        }

        var streak = 0
        while feedDays.contains(cursor) {
            streak += 1
            guard let prev = cal.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }
        streakDays = streak
    }

    // MARK: Feed-action routing (sleep conflict guard)

    /// Entry point for every feed-start tap on Home. If a nap is in
    /// progress, prompts to end it first; otherwise runs the action
    /// immediately (existing behavior).
    private func attemptFeedAction(_ action: PendingFeedAction) {
        if SleepView.hasActiveSleep {
            pendingFeedAction = action
            showEndSleepAlert = true
        } else {
            executeFeedAction(action)
        }
    }

    private func executeFeedAction(_ action: PendingFeedAction) {
        switch action {
        case .side(let side):
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            store.start(side: side)
            AnalyticsService.sessionStarted(startingSide: side.rawValue, feedType: "breast")
        case .bottle:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            showBottleSheet = true
        case .pump:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onPump()
        }
    }

    private func evaluateTooltips() {
        guard tooltips.active == nil else { return }

        if !tooltips.hasSeen(.startFeed) {
            tooltips.show(.startFeed)
            return
        }
        if !tooltips.hasSeen(.settings) {
            tooltips.show(.settings)
            return
        }
        if !tooltips.hasSeen(.pumpButton), tooltips.hasSeen(.settings) {
            tooltips.show(.pumpButton)
            return
        }
        if !sessions.isEmpty,
           !tooltips.hasSeen(.widgetTip),
           tooltips.homeAppearancesAfterFirstSession >= 2 {
            tooltips.show(.widgetTip)
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
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if streakDays >= 5 {
                    Text("🔥 \(streakDays) day streak")
                        .font(.nSans(13))
                        .foregroundStyle(c.muted)
                        .padding(.top, 2)
                        .transition(.opacity)
                }
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
        // TimelineView re-evaluates the body every minute AND when the app
        // returns to the foreground, so the "X min ago" line stays in sync
        // with reality without us managing scene-phase state by hand.
        TimelineView(.periodic(from: .now, by: 60)) { context in
            VStack(alignment: .leading, spacing: 7) {
                if let s = lastFeed {
                    filledSessionCard(s, now: context.date)
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
    }

    private func filledSessionCard(_ s: FeedingSession, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Last feed · \(s.formattedTime)")
                .font(.nSans(11, weight: .semibold))
                .foregroundStyle(c.muted)
                .kerning(0.1 * 11)
                .textCase(.uppercase)

            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    if s.feedType == .bottle {
                        Text("Bottle · \(timeAgo(from: s.startTime, now: now))")
                            .font(.nSans(17, weight: .bold))
                            .foregroundStyle(c.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    } else {
                        Text("Started \(s.feedType.displayName) · \(timeAgo(from: s.startTime, now: now))")
                            .font(.nSans(17, weight: .bold))
                            .foregroundStyle(c.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }

                    if s.feedType != .bottle {
                        Text("\(s.totalActiveMinutes) min total")
                            .font(.nSans(13))
                            .foregroundStyle(c.muted)
                            .lineLimit(1)
                    } else if let ml = s.bottleAmountMl {
                        Text("\(ml) ml · \(s.bottleContentType?.displayName ?? "")")
                            .font(.nSans(13))
                            .foregroundStyle(c.muted)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                Spacer(minLength: 8)

                if s.feedType == .bottle {
                    Text("🍼").font(.nSans(22))
                } else {
                    NourishPill(
                        label: s.feedType.shortLabel,
                        fill: s.feedType == .left ? c.leftBg : c.rightBg,
                        border: s.feedType == .left
                            ? c.leftAccent.opacity(0.2)
                            : c.rightAccent.opacity(0.2),
                        color: s.feedType == .left ? c.leftText : c.rightText
                    )
                }
            }
        }
    }

    private func timeAgo(from date: Date, now: Date) -> String {
        let interval = max(0, now.timeIntervalSince(date))
        let hours = Int(interval) / 3600
        let mins  = (Int(interval) % 3600) / 60
        if hours > 0 && mins > 0 { return "\(hours)h \(mins)m ago" }
        if hours > 0              { return "\(hours)h ago" }
        return "\(mins)m ago"
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
                .tooltipTarget(.startFeed)
            sideButton(.right)
        }
        .padding(.horizontal, 20)
        .frame(maxHeight: .infinity)
        .padding(.bottom, 16)
    }

    private func sideButton(_ side: FeedSide) -> some View {
        Button {
            attemptFeedAction(.side(side))
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
                    colors: gradientColors(for: side),
                    startPoint: .top, endPoint: .bottom
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 28))
            .overlay(
                RoundedRectangle(cornerRadius: 28)
                    .stroke(
                        c.accentColor(for: side).opacity(c.darkMode ? 0.35 : 0.15),
                        lineWidth: 1.5
                    )
            )
            .shadow(color: c.shadowColor(for: side), radius: 15, y: 6)
        }
        .buttonStyle(ScaleButtonStyle(scale: 0.963))
    }

    private func gradientColors(for side: FeedSide) -> [Color] {
        if c.darkMode {
            // Subtle warm-tint gradient from a brighter accent wash to the
            // dimmer side bg. No hardcoded near-white that would harshly fade
            // against the dark background.
            return [
                c.accentColor(for: side).opacity(0.32),
                c.bgColor(for: side)
            ]
        } else {
            return [
                side == .left ? Color(hex: "FFFAF8") : Color(hex: "F8FAFE"),
                c.bgColor(for: side)
            ]
        }
    }

    // MARK: Secondary buttons (Bottle + Pump side by side)

    private var secondaryButtons: some View {
        HStack(spacing: 10) {
            Button {
                attemptFeedAction(.bottle)
            } label: {
                HStack(spacing: 6) {
                    Text("🍼").font(.nSans(17))
                    Text("Bottle")
                        .font(.nSans(14, weight: .semibold))
                        .foregroundStyle(c.bottleAccent)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(c.bottleBg)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(c.bottleBorder, lineWidth: 1.5))
            }
            .buttonStyle(ScaleButtonStyle())

            Button {
                attemptFeedAction(.pump)
            } label: {
                HStack(spacing: 6) {
                    Image("pump_icon")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(height: 15)
                        .foregroundStyle(c.pumpAccent)
                    Text("Pump")
                        .font(.nSans(14, weight: .semibold))
                        .foregroundStyle(c.pumpAccent)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(c.pumpBg)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(c.pumpBorder, lineWidth: 1.5))
            }
            .buttonStyle(ScaleButtonStyle())
            .tooltipTarget(.pumpButton)
        }
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
