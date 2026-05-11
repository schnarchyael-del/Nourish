import SwiftUI
import SwiftData

struct StatsView: View {
    var onLogFirstSession: (() -> Void)? = nil

    @Environment(\.nourishColors) private var c
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var tooltips: TooltipManager
    @Query(sort: \FeedingSession.startTime, order: SortOrder.reverse) private var sessions: [FeedingSession]

    @State private var selectedTab = 1   // 0=Day, 1=Week, 2=Month
    @State private var chartAnimated = false
    @State private var sessionPendingDelete: FeedingSession?
    @State private var editingSession: FeedingSession?
    @State private var didEvaluateTooltips = false

    // MARK: Computed stats

    private var filteredSessions: [FeedingSession] {
        let now = Date.now
        let calendar = Calendar.current
        switch selectedTab {
        case 0:
            let start = calendar.startOfDay(for: now)
            return sessions.filter { $0.startTime >= start }
        case 2:
            let start = calendar.date(byAdding: .month, value: -1, to: now)!
            return sessions.filter { $0.startTime >= start }
        default:
            let start = calendar.date(byAdding: .weekOfYear, value: -1, to: now)!
            return sessions.filter { $0.startTime >= start }
        }
    }

    private var breastSessions: [FeedingSession]  { filteredSessions.filter { $0.feedType != .bottle } }
    private var bottleSessions: [FeedingSession]  { filteredSessions.filter { $0.feedType == .bottle } }
    private var leftSessions: [FeedingSession]    { filteredSessions.filter { $0.feedType == .left } }
    private var rightSessions: [FeedingSession]   { filteredSessions.filter { $0.feedType == .right } }

    private var totalSessions: Int { filteredSessions.count }

    private var avgDurationMins: Int {
        guard !breastSessions.isEmpty else { return 0 }
        let total = breastSessions.reduce(0) { $0 + $1.totalActiveMinutes }
        return total / breastSessions.count
    }

    private var avgGapHours: Double {
        guard breastSessions.count > 1 else { return 0 }
        let sorted = breastSessions.sorted { $0.startTime < $1.startTime }
        var totalGap: TimeInterval = 0
        for i in 1..<sorted.count {
            totalGap += sorted[i].startTime.timeIntervalSince(sorted[i-1].endTime ?? sorted[i-1].startTime)
        }
        return (totalGap / Double(sorted.count - 1)) / 3600
    }

    // Bar chart data — adapts to selected tab
    private var chartBarData: [(label: String, count: Int)] {
        let calendar = Calendar.current
        let now = Date.now

        switch selectedTab {
        case 0: // Day — 6 × 4-hour buckets across today
            let dayStart = calendar.startOfDay(for: now)
            return (0..<6).map { i in
                let bucketStart = calendar.date(byAdding: .hour, value: i * 4, to: dayStart)!
                let bucketEnd   = calendar.date(byAdding: .hour, value: i * 4 + 4, to: dayStart)!
                let count = sessions.filter { $0.startTime >= bucketStart && $0.startTime < bucketEnd }.count
                let label: String
                switch i * 4 {
                case 0:  label = "12A"
                case 4:  label = "4A"
                case 8:  label = "8A"
                case 12: label = "12P"
                case 16: label = "4P"
                default: label = "8P"
                }
                return (label, count)
            }
        case 2: // Month — 4 weekly buckets, oldest → newest
            return (0..<4).map { i in
                let weeksAgo    = 3 - i
                let bucketEnd   = calendar.date(byAdding: .weekOfYear, value: -weeksAgo, to: now)!
                let bucketStart = calendar.date(byAdding: .weekOfYear, value: -1, to: bucketEnd)!
                let count = sessions.filter { $0.startTime >= bucketStart && $0.startTime < bucketEnd }.count
                return ("Wk \(i + 1)", count)
            }
        default: // Week — last 7 days
            return (0..<7).reversed().map { offset in
                let date     = calendar.date(byAdding: .day, value: -offset, to: now)!
                let dayStart = calendar.startOfDay(for: date)
                let dayEnd   = calendar.date(byAdding: .day, value: 1, to: dayStart)!
                let count    = sessions.filter { $0.startTime >= dayStart && $0.startTime < dayEnd }.count
                let weekday  = calendar.shortWeekdaySymbols[calendar.component(.weekday, from: date) - 1]
                return (String(weekday.prefix(1)), count)
            }
        }
    }

    private var maxBarValue: Int { max(1, chartBarData.map { $0.count }.max() ?? 1) }

    private var avgLeftMins: Int {
        let mins = breastSessions.map(\.leftMinutesResolved).filter { $0 > 0 }
        guard !mins.isEmpty else { return 0 }
        let avg = Double(mins.reduce(0, +)) / Double(mins.count)
        return Int(avg.rounded())
    }

    private var avgRightMins: Int {
        let mins = breastSessions.map(\.rightMinutesResolved).filter { $0 > 0 }
        guard !mins.isEmpty else { return 0 }
        let avg = Double(mins.reduce(0, +)) / Double(mins.count)
        return Int(avg.rounded())
    }

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {
            header
            tabPicker
            if selectedTab == 3 {
                historyList
            } else {
                ScrollView {
                    if sessions.isEmpty {
                        statsEmptyState
                    } else {
                        VStack(spacing: 0) {
                            summaryCards
                            barChartCard
                            breastVsBottleCard
                            avgTimeCard
                            insightsSection
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 16)
                    }
                }
            }
        }
        .background(c.bg)
        .onChange(of: selectedTab) { _, newTab in
            chartAnimated = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                withAnimation { chartAnimated = true }
            }
            if newTab == 3 {
                AnalyticsService.historyViewed()
            }
            evaluateTooltips()
        }
        .onAppear {
            AnalyticsService.statsViewed()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                withAnimation { chartAnimated = true }
            }
            guard !didEvaluateTooltips else { return }
            didEvaluateTooltips = true
            evaluateTooltips()
        }
        .alert(
            "Delete this session?",
            isPresented: Binding(
                get: { sessionPendingDelete != nil },
                set: { if !$0 { sessionPendingDelete = nil } }
            )
        ) {
            Button("Cancel", role: .cancel) { sessionPendingDelete = nil }
            Button("Delete", role: .destructive) {
                if let s = sessionPendingDelete { performDelete(s) }
                sessionPendingDelete = nil
            }
        } message: {
            Text("This can't be undone.")
        }
        .sheet(item: $editingSession) { session in
            LogSessionView(
                editing: session,
                onBack: { editingSession = nil },
                onSave: { editingSession = nil }
            )
            .environment(\.nourishColors, c)
        }
    }

    private func evaluateTooltips() {
        guard tooltips.active == nil else { return }
        if selectedTab == 3 {
            if !sessions.isEmpty, !tooltips.hasSeen(.historySwipe) {
                tooltips.show(.historySwipe)
            }
        } else {
            if sessions.count >= 3, !tooltips.hasSeen(.statsHint) {
                tooltips.show(.statsHint)
            }
        }
    }

    private func performDelete(_ session: FeedingSession) {
        let id = session.id
        modelContext.delete(session)
        try? modelContext.save()
        Task { await FirestoreService.shared.deleteSession(id: id) }
        NotificationManager.shared.refreshReminder(modelContainer: NourishApp.modelContainer)
        SharedFeedSnapshot.refresh(modelContainer: NourishApp.modelContainer)
        AnalyticsService.sessionDeleted()
    }

    // MARK: Header

    private var header: some View {
        HStack {
            Text("Stats")
                .font(.nSerif(28))
                .foregroundStyle(c.ink)
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    // MARK: Tab picker

    private let tabLabels = ["Day", "Week", "Month", "History"]

    private var tabPicker: some View {
        HStack(spacing: 8) {
            ForEach(0..<tabLabels.count, id: \.self) { index in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { selectedTab = index }
                } label: {
                    Text(tabLabels[index])
                        .font(.nSans(14, weight: .semibold))
                        .foregroundStyle(selectedTab == index ? c.bg : c.muted)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 7)
                        .background(selectedTab == index ? c.ink : Color.clear)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(selectedTab == index ? c.ink : c.border, lineWidth: 1.5))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.bottom, 14)
    }

    // MARK: Summary cards

    private var summaryCards: some View {
        HStack(spacing: 10) {
            summaryCell(big: "\(totalSessions)", small: "sessions")
            summaryCell(big: "\(avgDurationMins) min", small: "avg per session")
            summaryCell(big: String(format: "%.1fh", avgGapHours), small: "avg gap")
        }
        .padding(.bottom, 14)
    }

    private func summaryCell(big: String, small: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(big)
                .font(.nSerif(22))
                .foregroundStyle(c.ink)
            Text(small)
                .font(.nSans(12))
                .foregroundStyle(c.muted)
                .lineLimit(2)
                .lineSpacing(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .background(c.surface)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(c.border, lineWidth: 1))
    }

    // MARK: Bar chart

    private var chartTitle: String {
        switch selectedTab {
        case 0: return "Sessions by time of day"
        case 2: return "Sessions per week"
        default: return "Sessions per day"
        }
    }

    private var barChartCard: some View {
        card {
            cardTitle(chartTitle)

            HStack(alignment: .bottom, spacing: 7) {
                ForEach(chartBarData.indices, id: \.self) { i in
                    let item = chartBarData[i]
                    let fraction = maxBarValue > 0 ? Double(item.count) / Double(maxBarValue) : 0

                    VStack(spacing: 5) {
                        GeometryReader { geo in
                            VStack(spacing: 0) {
                                Spacer()
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(
                                        LinearGradient(
                                            colors: i == chartBarData.count - 1
                                                ? [c.leftAccent.opacity(0.8), c.leftAccent]
                                                : [c.leftAccent.opacity(0.4), c.leftAccent.opacity(0.6)],
                                            startPoint: .top, endPoint: .bottom
                                        )
                                    )
                                    .frame(height: chartAnimated ? geo.size.height * fraction : 0)
                                    .animation(
                                        .spring(duration: 0.7, bounce: 0.4)
                                            .delay(Double(i) * 0.06),
                                        value: chartAnimated
                                    )
                            }
                            .frame(width: geo.size.width, height: geo.size.height)
                            .background(c.leftAccent.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                        }
                        .frame(height: 96)

                        Text(item.label)
                            .font(.nSans(11))
                            .foregroundStyle(c.muted)
                    }
                }
            }
            .frame(height: 110)
        }
    }

    // MARK: Feed breakdown

    private var hasBottleFeeds: Bool { !bottleSessions.isEmpty }

    /// Approx feeding minutes per bottle session, used so bottle feeds carry
    /// some weight in the Feed Breakdown bar even though we don't track an
    /// actual bottle feeding duration. Tunable.
    private static let bottleEquivalentMinutes = 10

    private var leftMinutesTotal: Int {
        breastSessions.reduce(0) { $0 + $1.leftMinutesResolved }
    }

    private var rightMinutesTotal: Int {
        breastSessions.reduce(0) { $0 + $1.rightMinutesResolved }
    }

    private var bottleEquivalentMinutesTotal: Int {
        bottleSessions.count * Self.bottleEquivalentMinutes
    }

    private var totalFeedMinutes: Int {
        leftMinutesTotal + rightMinutesTotal + bottleEquivalentMinutesTotal
    }

    private var bottleFractionOfTotal: Double {
        guard totalFeedMinutes > 0 else { return 0 }
        return Double(bottleEquivalentMinutesTotal) / Double(totalFeedMinutes)
    }

    private var breastVsBottleCard: some View {
        card {
            cardTitle("Feed breakdown")

            if filteredSessions.isEmpty {
                Text("No sessions yet")
                    .font(.nSans(14))
                    .foregroundStyle(c.muted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            } else {
                feedBreakdownContent
            }
        }
    }

    @ViewBuilder
    private var feedBreakdownContent: some View {
        feedBreakdownBar
            .padding(.bottom, 12)
        if hasBottleFeeds {
            bottleTypeBreakdown
        }
    }

    // MARK: Adaptive single-row bar

    private var leftFractionOfTotal: Double {
        guard totalFeedMinutes > 0 else { return 0 }
        return Double(leftMinutesTotal) / Double(totalFeedMinutes)
    }

    private var rightFractionOfTotal: Double {
        guard totalFeedMinutes > 0 else { return 0 }
        return Double(rightMinutesTotal) / Double(totalFeedMinutes)
    }

    private var feedBreakdownBar: some View {
        VStack(spacing: 8) {
            GeometryReader { geo in
                HStack(spacing: 3) {
                    if leftFractionOfTotal > 0 {
                        Capsule()
                            .fill(c.leftAccent)
                            .frame(width: geo.size.width * leftFractionOfTotal)
                    }
                    if rightFractionOfTotal > 0 {
                        Capsule()
                            .fill(c.rightAccent)
                            .frame(width: geo.size.width * rightFractionOfTotal)
                    }
                    if bottleFractionOfTotal > 0 {
                        Capsule()
                            .fill(c.bottleAccent)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .frame(height: 16)

            HStack {
                if leftFractionOfTotal > 0 {
                    legendDot(color: c.leftAccent, label: "Left \(percent(leftFractionOfTotal))%")
                }
                if rightFractionOfTotal > 0 {
                    Spacer()
                    legendDot(color: c.rightAccent, label: "Right \(percent(rightFractionOfTotal))%")
                }
                if bottleFractionOfTotal > 0 {
                    Spacer()
                    HStack(spacing: 4) {
                        Text("🍼").font(.nSans(12))
                        Text("Bottle \(percent(bottleFractionOfTotal))%")
                            .font(.nSans(12, weight: .semibold))
                            .foregroundStyle(c.bottleAccent)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var bottleTypeBreakdown: some View {
        Divider().overlay(c.border).padding(.bottom, 10)

        Text("Bottle type")
            .font(.nSans(11, weight: .bold))
            .foregroundStyle(c.muted)
            .kerning(0.08 * 11)
            .textCase(.uppercase)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 7)

        HStack(spacing: 8) {
            ForEach(BottleContentType.allCases, id: \.rawValue) { type in
                let count = bottleSessions.filter { $0.bottleContentType == type }.count
                HStack(spacing: 7) {
                    Text(type.icon).font(.nSans(16))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(type.displayName)
                            .font(.nSans(13, weight: .bold))
                            .foregroundStyle(c.bottleAccent)
                        Text("\(count) session\(count == 1 ? "" : "s")")
                            .font(.nSans(11))
                            .foregroundStyle(c.muted)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(c.bottleBg)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(c.bottleBorder, lineWidth: 1))
            }
        }
    }

    private func percent(_ fraction: Double) -> Int {
        Int((fraction * 100).rounded())
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label)
                .font(.nSans(12, weight: .semibold))
                .foregroundStyle(color == c.leftAccent ? c.leftText : c.rightText)
        }
    }

    // MARK: Avg time per breast

    private var avgTimeCard: some View {
        card {
            cardTitle("Avg session time")
            HStack(spacing: 0) {
                avgTimeCell(value: avgLeftMins > 0 ? "\(avgLeftMins) min" : "--", label: "Left", color: c.leftText)
                Divider().overlay(c.border)
                avgTimeCell(value: avgRightMins > 0 ? "\(avgRightMins) min" : "--", label: "Right", color: c.rightText)
            }
        }
    }

    private func avgTimeCell(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.nSerif(26))
                .foregroundStyle(color)
            Text(label)
                .font(.nSans(11))
                .foregroundStyle(c.muted)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
    }

    // MARK: Insights

    private var insightsTimeFilter: InsightsTimeFilter {
        switch selectedTab {
        case 0: return .day
        case 2: return .month
        case 3: return .history
        default: return .week
        }
    }

    private var insights: [Insight] {
        InsightsEngine(sessions: sessions, filter: insightsTimeFilter).compute(maxCount: 3)
    }

    @ViewBuilder
    private var insightsSection: some View {
        if !insights.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Insights")
                        .font(.nSerif(20))
                        .foregroundStyle(c.ink)
                    Spacer()
                }
                .padding(.bottom, 10)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(insights) { insight in
                            insightCard(insight)
                        }
                    }
                    .padding(.trailing, 4)
                }
                .scrollClipDisabled()
                .onAppear {
                    InsightsEngine(sessions: sessions, filter: insightsTimeFilter).markShown(insights)
                }
            }
            .padding(.top, 8)
        }
    }

    private func insightCard(_ insight: Insight) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                Text(insight.emoji)
                    .font(.nSans(20))
                    .frame(width: 32, height: 32)
                    .background(c.bg)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(c.border, lineWidth: 1))
                if let trend = insight.trend {
                    Image(systemName: trend == .up ? "arrow.up.right" : "arrow.down.right")
                        .font(.nSans(11, weight: .bold))
                        .foregroundStyle(trend == .up ? c.green : c.leftAccent)
                }
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(insight.title)
                    .font(.nSans(13, weight: .bold))
                    .foregroundStyle(c.ink)
                Text(insight.description)
                    .font(.nSans(13))
                    .foregroundStyle(c.muted)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(width: 260, alignment: .leading)
        .padding(14)
        .background(c.surface)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(c.border, lineWidth: 1))
    }

    // MARK: History list

    @ViewBuilder
    private var historyList: some View {
        if sessions.isEmpty {
            ScrollView { historyEmptyState }
        } else {
            List {
                ForEach(Array(sessions.enumerated()), id: \.element.id) { index, session in
                    VStack(spacing: 0) {
                        historyRow(session)
                        Divider().overlay(c.border).padding(.horizontal, 20)
                    }
                    .listRowBackground(c.bg)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets())
                    .tooltipTargetIf(index == 0, .historySwipe)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            sessionPendingDelete = session
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        Button {
                            editingSession = session
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        .tint(.blue)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    private func historyRow(_ s: FeedingSession) -> some View {
        HStack(spacing: 12) {
            // Side indicator
            Group {
                if s.feedType == .bottle {
                    Text("🍼").font(.nSans(20))
                } else {
                    Text(s.feedType.shortLabel)
                        .font(.nSans(14, weight: .bold))
                        .foregroundStyle(s.feedType == .left ? c.leftText : c.rightText)
                        .frame(width: 36, height: 36)
                        .background(s.feedType == .left ? c.leftBg : c.rightBg)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(
                            s.feedType == .left
                                ? c.leftAccent.opacity(0.25)
                                : c.rightAccent.opacity(0.25),
                            lineWidth: 1.5))
                }
            }

            // Left block — date on top, time + total below (or just time for bottle)
            VStack(alignment: .leading, spacing: 2) {
                Text(s.startTime.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                    .font(.nSans(14, weight: .semibold))
                    .foregroundStyle(c.ink)
                if s.feedType == .bottle {
                    Text(s.startTime.formatted(date: .omitted, time: .shortened))
                        .font(.nSans(12))
                        .foregroundStyle(c.muted)
                } else {
                    Text(historyTimeAndTotal(s))
                        .font(.nSans(12))
                        .foregroundStyle(c.muted)
                }
            }

            Spacer()

            // Right block — bottle: ml + type. Breast: per-side durations.
            if s.feedType == .bottle {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(s.bottleAmountMl.map { "\($0) ml" } ?? "—")
                        .font(.nSans(14, weight: .bold))
                        .foregroundStyle(c.bottleAccent)
                    if let contentType = s.bottleContentType {
                        Text(contentType.displayName)
                            .font(.nSans(11))
                            .foregroundStyle(c.muted)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    if s.leftMinutesResolved > 0 {
                        Text("L: \(formatMins(s.leftMinutesResolved))")
                            .font(.nSans(13, weight: .semibold))
                            .foregroundStyle(c.leftText)
                    }
                    if s.rightMinutesResolved > 0 {
                        Text("R: \(formatMins(s.rightMinutesResolved))")
                            .font(.nSans(13, weight: .semibold))
                            .foregroundStyle(c.rightText)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    /// "16:22 · Total: 17:00" — start time + total active duration.
    private func historyTimeAndTotal(_ s: FeedingSession) -> String {
        let time = s.startTime.formatted(date: .omitted, time: .shortened)
        let total = s.leftMinutesResolved + s.rightMinutesResolved
        return "\(time) · Total: \(formatMins(total))"
    }

    private func formatMins(_ minutes: Int) -> String {
        String(format: "%d:%02d", minutes, 0)
    }

    // MARK: Empty states

    private var statsEmptyState: some View {
        VStack(spacing: 14) {
            Text("🌱")
                .font(.nSans(52))
                .padding(.top, 64)

            Text("Your stats will grow here")
                .font(.nSerif(24))
                .foregroundStyle(c.ink)
                .multilineTextAlignment(.center)

            Text("Log your first session to start seeing patterns")
                .font(.nSans(14))
                .foregroundStyle(c.muted)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.horizontal, 40)

            if sessions.isEmpty, let action = onLogFirstSession {
                Button {
                    action()
                } label: {
                    HStack(spacing: 6) {
                        Text("Log first session")
                            .font(.nSans(15, weight: .semibold))
                        Image(systemName: "arrow.right")
                            .font(.nSans(13, weight: .semibold))
                    }
                    .foregroundStyle(c.bg)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 13)
                    .background(c.ink)
                    .clipShape(Capsule())
                    .shadow(color: c.ink.opacity(0.18), radius: 8, y: 4)
                }
                .buttonStyle(ScaleButtonStyle())
                .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 48)
    }

    private var historyEmptyState: some View {
        VStack(spacing: 12) {
            Text("🌿")
                .font(.nSans(44))
                .padding(.top, 64)

            Text("No sessions yet")
                .font(.nSerif(22))
                .foregroundStyle(c.ink)

            Text("Your feeding history will appear here\nas you log sessions.")
                .font(.nSans(14))
                .foregroundStyle(c.muted)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 48)
    }

    // MARK: Card container

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .padding(16)
        .background(c.surface)
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(c.border, lineWidth: 1))
        .padding(.bottom, 14)
    }

    private func cardTitle(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.nSans(11, weight: .bold))
            .foregroundStyle(c.muted)
            .kerning(0.1 * 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 12)
    }
}
