import SwiftUI
import SwiftData

struct StatsView: View {
    var onLogFirstSession: (() -> Void)? = nil

    @Environment(\.nourishColors) private var c
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var tooltips: TooltipManager
    @Query(sort: \FeedingSession.startTime, order: SortOrder.reverse) private var sessions: [FeedingSession]

    @State private var selectedTab = 1   // 0=Day, 1=Week, 2=Month, 3=History
    @State private var chartAnimated = false
    @State private var sessionPendingDelete: FeedingSession?
    @State private var editingSession: FeedingSession?
    @State private var selectedSession: FeedingSession?
    @State private var didEvaluateTooltips = false

    /// The date that anchors the Day/Week/Month period the user is viewing.
    /// Defaults to "now" so the screen opens on today's stats.
    @State private var anchorDate: Date = .now
    @State private var showDatePicker = false
    /// The year currently displayed in the Month picker grid.
    @State private var monthPickerYear: Int = Calendar.current.component(.year, from: .now)
    /// First-of-month date that drives the Week picker's calendar grid.
    @State private var weekPickerMonth: Date = {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month], from: .now)
        return cal.date(from: comps) ?? .now
    }()
    /// Optional "From" date for the History tab range filter. nil = no lower bound.
    @State private var historyFromDate: Date? = nil
    /// Optional "To" date for the History tab range filter. nil = no upper bound.
    @State private var historyToDate: Date? = nil
    /// First-of-month date driving the History filter calendar.
    @State private var historyFilterMonth: Date = {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month], from: .now)
        return cal.date(from: comps) ?? .now
    }()

    // MARK: Period range

    /// Half-open interval [start, end) for the currently viewed period.
    /// Day: a calendar day. Week: the calendar week containing `anchorDate`.
    /// Month: the calendar month containing `anchorDate`.
    private var anchorRange: (start: Date, end: Date) {
        let cal = Calendar.current
        switch selectedTab {
        case 0:
            let start = cal.startOfDay(for: anchorDate)
            let end   = cal.date(byAdding: .day, value: 1, to: start) ?? start
            return (start, end)
        case 2:
            let start = cal.dateInterval(of: .month, for: anchorDate)?.start
                        ?? cal.startOfDay(for: anchorDate)
            let end   = cal.date(byAdding: .month, value: 1, to: start) ?? start
            return (start, end)
        default:
            let start = cal.dateInterval(of: .weekOfYear, for: anchorDate)?.start
                        ?? cal.startOfDay(for: anchorDate)
            let end   = cal.date(byAdding: .weekOfYear, value: 1, to: start) ?? start
            return (start, end)
        }
    }

    // MARK: Computed stats

    private var filteredSessions: [FeedingSession] {
        let r = anchorRange
        return sessions.filter { $0.startTime >= r.start && $0.startTime < r.end }
    }

    private var breastSessions: [FeedingSession]  { filteredSessions.filter { $0.feedType == .left || $0.feedType == .right } }
    private var bottleSessions: [FeedingSession]  { filteredSessions.filter { $0.feedType == .bottle } }
    private var pumpSessions: [FeedingSession]    { filteredSessions.filter { $0.feedType == .pump } }
    private var leftSessions: [FeedingSession]    { filteredSessions.filter { $0.feedType == .left } }
    private var rightSessions: [FeedingSession]   { filteredSessions.filter { $0.feedType == .right } }

    /// All feeds (breast + bottle, excluding pump + sleep). Each non-feed
    /// type is tracked separately and shouldn't inflate "sessions" or
    /// "avg per session".
    private var feedSessions: [FeedingSession]    { filteredSessions.filter { $0.feedType != .pump && $0.feedType != .sleep } }

    private var sleepSessions: [FeedingSession]   { filteredSessions.filter { $0.feedType == .sleep } }

    private var totalSessions: Int { feedSessions.count }

    private var avgDurationMins: Int {
        guard !feedSessions.isEmpty else { return 0 }
        let total = feedSessions.reduce(0) { $0 + $1.totalActiveMinutes }
        return total / feedSessions.count
    }

    private var totalPumpVolumeMl: Int {
        pumpSessions.compactMap(\.pumpVolumeMl).reduce(0, +)
    }

    private var avgPumpVolumeMl: Int {
        let withVolume = pumpSessions.filter { $0.pumpVolumeMl != nil }
        guard !withVolume.isEmpty else { return 0 }
        return withVolume.compactMap(\.pumpVolumeMl).reduce(0, +) / withVolume.count
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

    // Bar chart data — adapts to selected tab and anchorDate.
    // Feed-only (breast + bottle); pump and sleep have their own dedicated
    // surfaces and would muddle this "feeds per period" view.
    private var chartBarData: [(label: String, count: Int)] {
        let cal = Calendar.current
        let r = anchorRange
        let isFeed: (FeedingSession) -> Bool = { $0.feedType != .pump && $0.feedType != .sleep }

        switch selectedTab {
        case 0: // Day — 6 × 4-hour buckets across the anchored day
            return (0..<6).map { i in
                let bucketStart = cal.date(byAdding: .hour, value: i * 4, to: r.start)!
                let bucketEnd   = cal.date(byAdding: .hour, value: i * 4 + 4, to: r.start)!
                let count = sessions.filter { $0.startTime >= bucketStart && $0.startTime < bucketEnd && isFeed($0) }.count
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
        case 2: // Month — 4 even buckets covering the anchored month
            let total = r.end.timeIntervalSince(r.start)
            let bucket = total / 4
            return (0..<4).map { i in
                let bucketStart = r.start.addingTimeInterval(bucket * Double(i))
                let bucketEnd   = r.start.addingTimeInterval(bucket * Double(i + 1))
                let count = sessions.filter { $0.startTime >= bucketStart && $0.startTime < bucketEnd && isFeed($0) }.count
                return ("Wk \(i + 1)", count)
            }
        default: // Week — 7 days starting at the anchored week's start
            return (0..<7).map { offset in
                let dayStart = cal.date(byAdding: .day, value: offset, to: r.start)!
                let dayEnd   = cal.date(byAdding: .day, value: 1, to: dayStart)!
                let count    = sessions.filter { $0.startTime >= dayStart && $0.startTime < dayEnd && isFeed($0) }.count
                let weekday  = cal.shortWeekdaySymbols[cal.component(.weekday, from: dayStart) - 1]
                return (String(weekday.prefix(1)), count)
            }
        }
    }

    // MARK: Sleep aggregates

    private var napCount: Int { sleepSessions.count }
    private var totalSleepMinutes: Int { sleepSessions.reduce(0) { $0 + $1.totalActiveMinutes } }
    private var avgNapMinutes: Int {
        guard !sleepSessions.isEmpty else { return 0 }
        return totalSleepMinutes / sleepSessions.count
    }
    private var longestNapMinutes: Int {
        sleepSessions.map { $0.totalActiveMinutes }.max() ?? 0
    }

    // MARK: Per-period normalisation
    //
    // Week/Month cells show daily averages instead of raw totals, since
    // "28 sessions" across a month tells you nothing — "5.8/day" does.
    // Day view stays absolute. We divide by the full period length even
    // when some days have zero activity, so the average honestly reflects
    // the period rather than over-stating it.

    /// Days to divide by for per-day averages. For the *current* period
    /// (this week, this month) we count days that have actually elapsed —
    /// dividing 7 sleeps logged on a Monday by the full 7-day week would
    /// give "1.0/day" when the honest answer is "7.0/day". For past
    /// periods we divide by the full length.
    private var daysInPeriod: Int {
        if selectedTab == 0 { return 1 }
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let r = anchorRange
        if today >= r.start && today < r.end {
            let elapsed = cal.dateComponents([.day], from: r.start, to: today).day ?? 0
            return max(1, elapsed + 1)   // +1 to include today itself
        }
        let totalDays = cal.dateComponents([.day], from: r.start, to: r.end).day ?? 7
        return max(1, totalDays)
    }

    private var sessionsPerDay: Double {
        Double(totalSessions) / Double(daysInPeriod)
    }
    private var napsPerDay: Double {
        Double(napCount) / Double(daysInPeriod)
    }
    private var sleepMinutesPerDay: Int {
        totalSleepMinutes / daysInPeriod
    }
    private var pumpsPerDay: Double {
        Double(pumpSessions.count) / Double(daysInPeriod)
    }

    /// "5.8" if < 10, "12" otherwise. Mirrors `InsightsEngine.formatPerDay`.
    private func formatPerDay(_ value: Double) -> String {
        value >= 10 ? "\(Int(value.rounded()))" : String(format: "%.1f", value)
    }

    /// Lower-case label for the currently-selected period, used in
    /// phrases like "1 nap this week".
    private var periodLabel: String {
        switch selectedTab {
        case 1: return "week"
        case 2: return "month"
        default: return "period"
        }
    }

    /// Decision for how to present a low-frequency count in Week/Month.
    /// `≥ 1/day` → daily average reads naturally; `< 1/day` → fall back to
    /// the absolute total for the period ("0.2 naps/day" is correct but
    /// useless; "1 nap this week" is honest and readable).
    private func showsDailyAverage(forPerDay value: Double) -> Bool {
        value >= 1.0
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
            // Bottom padding is 6pt less than the design gap — the picker
            // buttons carry a 6pt invisible tap margin on each side.
            tabPicker
                .padding(.bottom, selectedTab == 3 ? 0 : 8)
            if selectedTab == 3 {
                historyList
            } else {
                ScrollView {
                    if sessions.isEmpty {
                        statsEmptyState
                    } else if filteredSessions.isEmpty {
                        emptyPeriodState
                            .frame(minHeight: 320)
                    } else {
                        VStack(spacing: 0) {
                            summaryCards
                            barChartCard
                            breastVsBottleCard
                            avgTimeCard
                            if !sleepSessions.isEmpty { sleepCard }
                            insightsSection
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 16)
                    }
                }
            }
        }
        .background(c.bg)
        .sheet(isPresented: $showDatePicker) {
            datePickerSheet
        }
        .onChange(of: selectedTab) { _, newTab in
            // When switching tabs, keep anchorDate but reset to "now" if it
            // was in the future for the new period's granularity (shouldn't
            // happen, but safety belt).
            chartAnimated = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                withAnimation { chartAnimated = true }
            }
            if newTab == 3 {
                AnalyticsService.historyViewed()
            }
            evaluateTooltips()
        }
        .onChange(of: anchorDate) { _, _ in
            chartAnimated = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                withAnimation { chartAnimated = true }
            }
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
        .sheet(item: $selectedSession) { session in
            SessionDetailSheet(
                session: session,
                onEdit: {
                    selectedSession = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { editingSession = session }
                },
                onDelete: {
                    selectedSession = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { sessionPendingDelete = session }
                }
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
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("Stats")
                .font(.nSerif(28))
                .foregroundStyle(c.ink)
            Spacer()
            headerDatePickerTrigger
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, 2)
    }

    /// Calendar icon (+ date label when viewing a past period) on the right
    /// of the Stats header. Tapping opens the per-tab picker sheet. Hidden
    /// on the History tab — nothing to filter there.
    private var headerDatePickerTrigger: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            showDatePicker = true
        } label: {
            HStack(spacing: 6) {
                if !isAnchoredAtCurrentPeriod {
                    Text(anchorLabel)
                        .font(.nSans(13))
                        .foregroundStyle(c.muted)
                        .lineLimit(1)
                        .transition(.opacity)
                }
                Image(systemName: "calendar")
                    .font(.nSans(15))
                    .foregroundStyle(c.muted)
            }
            .contentShape(Rectangle())
            .padding(.vertical, 4)
            .padding(.leading, 6)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Pick a \(periodNoun)")
        .accessibilityValue(anchorLabel)
    }

    /// True when the date-trigger should hide its label (icon only).
    /// Day/Week/Month: anchor on the current period. History: no filter set.
    private var isAnchoredAtCurrentPeriod: Bool {
        let cal = Calendar.current
        switch selectedTab {
        case 0: return cal.isDateInToday(anchorDate)
        case 2: return cal.isDate(anchorDate, equalTo: .now, toGranularity: .month)
        case 3: return historyFromDate == nil && historyToDate == nil
        default: return cal.isDate(anchorDate, equalTo: .now, toGranularity: .weekOfYear)
        }
    }

    // MARK: Tab picker

    private let tabLabels = ["Day", "Week", "Month", "History"]

    private var tabPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(0..<tabLabels.count, id: \.self) { index in
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) { selectedTab = index }
                    } label: {
                        Text(tabLabels[index])
                            .font(.nSans(14, weight: .semibold))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .foregroundStyle(selectedTab == index ? c.bg : c.muted)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 7)
                            .background(selectedTab == index ? c.ink : Color.clear)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(selectedTab == index ? c.ink : c.border, lineWidth: 1.5))
                            // Unselected tabs have a clear background, which
                            // is not hit-testable — without an explicit
                            // content shape only the text glyphs catch taps.
                            .contentShape(Capsule())
                            // Invisible margin so near-misses above/below the
                            // 31pt capsule still land (44pt effective target).
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 24)
        }
        .scrollClipDisabled()
    }

    private var periodNoun: String {
        switch selectedTab {
        case 0: return "day"
        case 2: return "month"
        default: return "week"
        }
    }

    private var anchorLabel: String {
        let cal = Calendar.current
        switch selectedTab {
        case 0:
            if cal.isDateInToday(anchorDate)     { return "Today" }
            if cal.isDateInYesterday(anchorDate) { return "Yesterday" }
            return anchorDate.formatted(.dateTime.day().month(.abbreviated))
        case 2:
            return anchorDate.formatted(.dateTime.month(.wide).year())
        case 3:
            return historyFilterLabel
        default:
            let r = anchorRange
            let lastDay = cal.date(byAdding: .day, value: -1, to: r.end) ?? r.start
            let style: Date.FormatStyle = .dateTime.day().month(.abbreviated)
            if cal.isDate(r.start, equalTo: lastDay, toGranularity: .month) {
                let dayOnly: Date.FormatStyle = .dateTime.day()
                return "\(r.start.formatted(dayOnly))–\(lastDay.formatted(style))"
            }
            return "\(r.start.formatted(style)) – \(lastDay.formatted(style))"
        }
    }

    /// Short label describing the active History range, e.g. "1–14 May",
    /// "From 1 May", "Until 14 May", or "" (no filter / show all).
    private var historyFilterLabel: String {
        let style: Date.FormatStyle = .dateTime.day().month(.abbreviated)
        let dayOnly: Date.FormatStyle = .dateTime.day()
        switch (historyFromDate, historyToDate) {
        case let (.some(from), .some(to)):
            let cal = Calendar.current
            if cal.isDate(from, equalTo: to, toGranularity: .month) {
                return "\(from.formatted(dayOnly))–\(to.formatted(style))"
            }
            return "\(from.formatted(style)) – \(to.formatted(style))"
        case let (.some(from), nil):
            return "From \(from.formatted(style))"
        case let (nil, .some(to)):
            return "Until \(to.formatted(style))"
        case (nil, nil):
            return ""
        }
    }

    /// True when there is a "future" period beyond the current anchor.
    /// Day: anchored before today. Week: before current week. Month: before current month.
    private var canGoForward: Bool {
        let cal = Calendar.current
        switch selectedTab {
        case 0:
            return !cal.isDateInToday(anchorDate)
                && anchorDate < Date.now
        case 2:
            return !cal.isDate(anchorDate, equalTo: .now, toGranularity: .month)
                && anchorDate < Date.now
        default:
            return !cal.isDate(anchorDate, equalTo: .now, toGranularity: .weekOfYear)
                && anchorDate < Date.now
        }
    }

    private func stepAnchor(by direction: Int) {
        let cal = Calendar.current
        let component: Calendar.Component
        switch selectedTab {
        case 0: component = .day
        case 2: component = .month
        default: component = .weekOfYear
        }
        guard let next = cal.date(byAdding: component, value: direction, to: anchorDate) else { return }
        // Going forward: don't allow past today/this-week/this-month.
        if direction > 0 {
            switch selectedTab {
            case 0:
                guard next <= Date.now else { return }
            case 2:
                let now = Date.now
                if cal.compare(next, to: now, toGranularity: .month) == .orderedDescending { return }
            default:
                let now = Date.now
                if cal.compare(next, to: now, toGranularity: .weekOfYear) == .orderedDescending { return }
            }
        }
        withAnimation(.easeInOut(duration: 0.18)) {
            anchorDate = next
        }
    }

    // MARK: Date picker sheet (per-tab)

    /// Routes to the right picker UI for the current tab.
    /// Day → graphical calendar. Week → vertical list. Month → year + grid.
    @ViewBuilder
    private var datePickerSheet: some View {
        Group {
            switch selectedTab {
            case 0: dayPickerSheet
            case 2: monthPickerSheet
            case 3: historyFilterSheet
            default: weekPickerSheet
            }
        }
        .background(c.bg)
        .presentationDetents([.fraction(0.78)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
        .onAppear {
            let cal = Calendar.current
            monthPickerYear = cal.component(.year, from: anchorDate)
            let comps = cal.dateComponents([.year, .month], from: anchorDate)
            weekPickerMonth = cal.date(from: comps) ?? .now
            // History filter: open on month containing From, else current month.
            let historyAnchor = historyFromDate ?? historyToDate ?? .now
            let hComps = cal.dateComponents([.year, .month], from: historyAnchor)
            historyFilterMonth = cal.date(from: hComps) ?? .now
        }
    }

    /// Top bar shared by all picker sheets: Cancel | Title | quick action.
    /// The default quick action snaps the anchor to "now"; pass a custom
    /// `onQuickAction` to override (e.g. the History tab clears its filter).
    private func pickerHeader(
        title: String,
        quickLabel: String,
        onQuickAction: (() -> Void)? = nil
    ) -> some View {
        HStack {
            Button("Cancel") { showDatePicker = false }
                .font(.nSans(15))
                .foregroundStyle(c.muted)
            Spacer()
            Text(title)
                .font(.nSerif(18))
                .foregroundStyle(c.ink)
            Spacer()
            Button(quickLabel) {
                if let onQuickAction {
                    withAnimation(.easeInOut(duration: 0.18)) { onQuickAction() }
                } else {
                    withAnimation(.easeInOut(duration: 0.18)) { anchorDate = .now }
                    monthPickerYear = Calendar.current.component(.year, from: .now)
                    showDatePicker = false
                }
            }
            .font(.nSans(15, weight: .semibold))
            .foregroundStyle(c.leftAccent)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(c.surface)
    }

    private var doneButton: some View {
        Button { showDatePicker = false } label: {
            Text("Done")
                .font(.nSans(17, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(c.leftAccent)
                .clipShape(Capsule())
        }
        .buttonStyle(ScaleButtonStyle())
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
    }

    // MARK: Day picker — graphical calendar (unchanged from before)

    private var dayPickerSheet: some View {
        VStack(spacing: 0) {
            pickerHeader(title: "Pick a day", quickLabel: "Today")

            DatePicker(
                "",
                selection: Binding(
                    get: { anchorDate },
                    set: { newDate in anchorDate = newDate }
                ),
                in: ...Date.now,
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .tint(c.leftAccent)
            .padding(.horizontal, 14)
            .padding(.top, 8)

            Spacer()
            doneButton
        }
    }

    // MARK: Week picker — calendar grid with whole-week row highlight

    private var weekPickerSheet: some View {
        VStack(spacing: 0) {
            pickerHeader(title: "Pick a week", quickLabel: "This week")
            weekPickerMonthNav
            weekdayHeaderRow
            weekPickerGrid
                .padding(.horizontal, 18)
                .padding(.top, 4)
            Spacer(minLength: 0)
            doneButton
        }
    }

    private var weekPickerMonthNav: some View {
        HStack(spacing: 16) {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                if let prev = Calendar.current.date(byAdding: .month, value: -1, to: weekPickerMonth) {
                    weekPickerMonth = prev
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.nSans(13, weight: .bold))
                    .foregroundStyle(c.leftAccent)
                    .frame(width: 36, height: 36)
                    .background(c.leftBg)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            Text(weekPickerMonth.formatted(.dateTime.month(.wide).year()))
                .font(.nSerif(20))
                .foregroundStyle(c.ink)
                .frame(minWidth: 140)
                .contentTransition(.opacity)

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                if let next = Calendar.current.date(byAdding: .month, value: 1, to: weekPickerMonth),
                   next <= Date.now {
                    weekPickerMonth = next
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.nSans(13, weight: .bold))
                    .foregroundStyle(c.leftAccent)
                    .frame(width: 36, height: 36)
                    .background(c.leftBg)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(!canAdvanceWeekPickerMonth)
            .opacity(canAdvanceWeekPickerMonth ? 1 : 0.35)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    /// Single-letter weekday header row aligned with the calendar grid below.
    private var weekdayHeaderRow: some View {
        HStack(spacing: 0) {
            ForEach(weekdayInitials, id: \.self) { initial in
                Text(initial)
                    .font(.nSans(11, weight: .semibold))
                    .foregroundStyle(c.muted)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 6)
    }

    /// 6 rows × 7 columns. Each row is a single calendar week — tapping any
    /// day in the row selects the whole week, painted terra cotta.
    private var weekPickerGrid: some View {
        let weeks = weekRowsFor(month: weekPickerMonth)
        let cal = Calendar.current
        let anchorWeekStart = cal.dateInterval(of: .weekOfYear, for: anchorDate)?.start

        return VStack(spacing: 4) {
            ForEach(weeks.indices, id: \.self) { rowIdx in
                let row = weeks[rowIdx]
                let weekStart = cal.dateInterval(of: .weekOfYear, for: row[0])?.start
                let isSelected = (anchorWeekStart != nil && weekStart == anchorWeekStart)
                let hasSelectableDay = row.contains { $0 <= Date.now }

                ZStack {
                    if isSelected {
                        Capsule(style: .continuous)
                            .fill(c.leftAccent)
                            .frame(height: 38)
                    }
                    HStack(spacing: 0) {
                        ForEach(row.indices, id: \.self) { col in
                            let date = row[col]
                            weekPickerDayCell(
                                date: date,
                                rowSelected: isSelected,
                                inDisplayedMonth: cal.isDate(date, equalTo: weekPickerMonth, toGranularity: .month)
                            )
                        }
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    guard hasSelectableDay else { return }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    // Anchor on the row's first day clipped to "today" so we
                    // never land in the future.
                    let target = min(row[0], Date.now)
                    withAnimation(.easeInOut(duration: 0.18)) {
                        anchorDate = target
                    }
                    showDatePicker = false
                }
                .opacity(hasSelectableDay ? 1 : 0.4)
            }
        }
    }

    private func weekPickerDayCell(date: Date, rowSelected: Bool, inDisplayedMonth: Bool) -> some View {
        let cal = Calendar.current
        let day = cal.component(.day, from: date)
        let isToday = cal.isDateInToday(date)
        let isFuture = date > Date.now

        let textColor: Color = {
            if rowSelected         { return .white }
            if isFuture            { return c.muted.opacity(0.35) }
            if !inDisplayedMonth   { return c.muted.opacity(0.55) }
            return c.ink
        }()

        return Text("\(day)")
            .font(.nSans(14, weight: isToday ? .bold : .medium))
            .foregroundStyle(textColor)
            .frame(maxWidth: .infinity)
            .frame(height: 38)
            .overlay(
                Circle()
                    .stroke(isToday && !rowSelected ? c.leftAccent : .clear, lineWidth: 1.2)
                    .frame(width: 30, height: 30)
            )
    }

    /// Weekday initials reordered to match `Calendar.current.firstWeekday`.
    private var weekdayInitials: [String] {
        let cal = Calendar.current
        let symbols = cal.veryShortStandaloneWeekdaySymbols
        let offset = cal.firstWeekday - 1
        guard offset >= 0, offset < symbols.count else { return symbols }
        return Array(symbols[offset...]) + Array(symbols[..<offset])
    }

    /// 6 weeks × 7 days that cover the displayed month, with leading/trailing
    /// days from the surrounding months padding the first/last rows.
    private func weekRowsFor(month: Date) -> [[Date]] {
        let cal = Calendar.current
        let firstOfMonth = cal.dateInterval(of: .month, for: month)?.start
                           ?? cal.startOfDay(for: month)
        let firstWeekday = cal.component(.weekday, from: firstOfMonth)
        let leading = (firstWeekday - cal.firstWeekday + 7) % 7
        guard let gridStart = cal.date(byAdding: .day, value: -leading, to: firstOfMonth) else {
            return []
        }
        return (0..<6).map { row in
            (0..<7).map { col in
                cal.date(byAdding: .day, value: row * 7 + col, to: gridStart) ?? gridStart
            }
        }
    }

    private var canAdvanceWeekPickerMonth: Bool {
        let cal = Calendar.current
        guard let next = cal.date(byAdding: .month, value: 1, to: weekPickerMonth) else { return false }
        return cal.compare(next, to: .now, toGranularity: .month) != .orderedDescending
    }

    // MARK: History filter — calendar grid with start/end range selection

    private var historyFilterSheet: some View {
        VStack(spacing: 0) {
            pickerHeader(
                title: "Filter history",
                quickLabel: "All time",
                onQuickAction: {
                    historyFromDate = nil
                    historyToDate = nil
                    showDatePicker = false
                }
            )
            historyFilterMonthNav
            weekdayHeaderRow
            historyFilterGrid
                .padding(.horizontal, 18)
                .padding(.top, 4)
            historyRangeReadout
            Spacer(minLength: 0)
            doneButton
        }
    }

    private var historyFilterMonthNav: some View {
        HStack(spacing: 16) {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                if let prev = Calendar.current.date(byAdding: .month, value: -1, to: historyFilterMonth) {
                    historyFilterMonth = prev
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.nSans(13, weight: .bold))
                    .foregroundStyle(c.leftAccent)
                    .frame(width: 36, height: 36)
                    .background(c.leftBg)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            Text(historyFilterMonth.formatted(.dateTime.month(.wide).year()))
                .font(.nSerif(20))
                .foregroundStyle(c.ink)
                .frame(minWidth: 140)

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                if let next = Calendar.current.date(byAdding: .month, value: 1, to: historyFilterMonth),
                   next <= Date.now {
                    historyFilterMonth = next
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.nSans(13, weight: .bold))
                    .foregroundStyle(c.leftAccent)
                    .frame(width: 36, height: 36)
                    .background(c.leftBg)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(!canAdvanceHistoryFilterMonth)
            .opacity(canAdvanceHistoryFilterMonth ? 1 : 0.35)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private var canAdvanceHistoryFilterMonth: Bool {
        let cal = Calendar.current
        guard let next = cal.date(byAdding: .month, value: 1, to: historyFilterMonth) else { return false }
        return cal.compare(next, to: .now, toGranularity: .month) != .orderedDescending
    }

    private var historyFilterGrid: some View {
        let weeks = weekRowsFor(month: historyFilterMonth)
        return VStack(spacing: 4) {
            ForEach(weeks.indices, id: \.self) { rowIdx in
                let row = weeks[rowIdx]
                HStack(spacing: 0) {
                    ForEach(row.indices, id: \.self) { col in
                        historyFilterDayCell(date: row[col])
                    }
                }
            }
        }
    }

    private func historyFilterDayCell(date: Date) -> some View {
        let cal = Calendar.current
        let day = cal.startOfDay(for: date)
        let from = historyFromDate.map { cal.startOfDay(for: $0) }
        let to   = historyToDate.map { cal.startOfDay(for: $0) }

        let isStart   = from != nil && day == from
        let isEnd     = to != nil && day == to
        let isBetween = (from != nil && to != nil) && day > from! && day < to!
        let inRange   = isStart || isEnd || isBetween
        let bothEnds  = from != nil && to != nil
        // While only From is set, no strip — just the start circle.
        let isSingleDayRange = bothEnds && from == to

        let isToday = cal.isDateInToday(date)
        let isFuture = date > Date.now
        let inDisplayedMonth = cal.isDate(date, equalTo: historyFilterMonth, toGranularity: .month)

        let textColor: Color = {
            if inRange             { return .white }
            if isFuture            { return c.muted.opacity(0.30) }
            if !inDisplayedMonth   { return c.muted.opacity(0.55) }
            return c.ink
        }()

        return ZStack {
            // Strip background under the range (between endpoints).
            if inRange && !isSingleDayRange && (bothEnds || (isStart && to != nil) || (isEnd && from != nil)) {
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(showsLeftStrip(isStart: isStart, isEnd: isEnd, isBetween: isBetween) ? c.leftAccent.opacity(0.20) : Color.clear)
                    Rectangle()
                        .fill(showsRightStrip(isStart: isStart, isEnd: isEnd, isBetween: isBetween) ? c.leftAccent.opacity(0.20) : Color.clear)
                }
                .frame(height: 34)
            }

            // Endpoint dot.
            if isStart || isEnd {
                Circle()
                    .fill(c.leftAccent)
                    .frame(width: 34, height: 34)
            }

            // Today ring (only when not an endpoint).
            if isToday && !isStart && !isEnd {
                Circle()
                    .stroke(c.leftAccent, lineWidth: 1.2)
                    .frame(width: 30, height: 30)
            }

            Text("\(cal.component(.day, from: date))")
                .font(.nSans(14, weight: (isStart || isEnd || isToday) ? .bold : .medium))
                .foregroundStyle(textColor)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 38)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !isFuture else { return }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            handleHistoryRangeTap(day)
        }
    }

    /// Left half of a cell shows the strip when this cell is between the
    /// two endpoints, or when it's the end-of-range endpoint (strip connects
    /// from the left).
    private func showsLeftStrip(isStart: Bool, isEnd: Bool, isBetween: Bool) -> Bool {
        if isBetween { return true }
        if isEnd     { return true }
        return false
    }

    /// Right half mirrors: it shows when this is the start endpoint (strip
    /// extends rightward), or an in-between day.
    private func showsRightStrip(isStart: Bool, isEnd: Bool, isBetween: Bool) -> Bool {
        if isBetween { return true }
        if isStart   { return true }
        return false
    }

    /// Tap handler for a calendar day in the history filter.
    /// First tap → sets From, clears To. Second tap → sets To (or extends
    /// From earlier if user tapped before From). Third tap → reset cycle.
    private func handleHistoryRangeTap(_ day: Date) {
        switch (historyFromDate, historyToDate) {
        case (nil, _):
            historyFromDate = day
            historyToDate = nil
        case let (.some(from), nil):
            if day < from {
                historyFromDate = day
            } else {
                historyToDate = day
            }
        case (.some, .some):
            historyFromDate = day
            historyToDate = nil
        }
    }

    private var historyRangeReadout: some View {
        let label: String = {
            switch (historyFromDate, historyToDate) {
            case (nil, _):
                return "Tap a date to start"
            case let (.some(from), nil):
                return "From \(from.formatted(.dateTime.day().month(.abbreviated))) — tap the end date"
            case let (.some(from), .some(to)):
                let style: Date.FormatStyle = .dateTime.day().month(.abbreviated)
                if Calendar.current.isDate(from, equalTo: to, toGranularity: .month) {
                    let dayOnly: Date.FormatStyle = .dateTime.day()
                    return "\(from.formatted(dayOnly)) – \(to.formatted(style))"
                }
                return "\(from.formatted(style)) – \(to.formatted(style))"
            }
        }()
        return Text(label)
            .font(.nSans(13, weight: .medium))
            .foregroundStyle(c.muted)
            .frame(maxWidth: .infinity)
            .padding(.top, 14)
            .padding(.horizontal, 24)
            .multilineTextAlignment(.center)
            .lineLimit(2)
    }

    // MARK: Month picker — year navigator + 3×4 month grid

    private var currentCalendarYear: Int {
        Calendar.current.component(.year, from: .now)
    }

    private var currentCalendarMonth: Int {
        Calendar.current.component(.month, from: .now)
    }

    private var anchorYear: Int {
        Calendar.current.component(.year, from: anchorDate)
    }

    private var anchorMonth: Int {
        Calendar.current.component(.month, from: anchorDate)
    }

    private func monthIsInFuture(_ month: Int, year: Int) -> Bool {
        if year > currentCalendarYear { return true }
        if year == currentCalendarYear && month > currentCalendarMonth { return true }
        return false
    }

    private func selectMonth(_ month: Int, year: Int) {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = 1
        if let date = Calendar.current.date(from: comps) {
            withAnimation(.easeInOut(duration: 0.18)) {
                anchorDate = date
            }
            showDatePicker = false
        }
    }

    private var monthPickerSheet: some View {
        VStack(spacing: 0) {
            pickerHeader(title: "Pick a month", quickLabel: "This month")

            // Year navigator
            HStack(spacing: 16) {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    monthPickerYear -= 1
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.nSans(14, weight: .bold))
                        .foregroundStyle(c.leftAccent)
                        .frame(width: 38, height: 38)
                        .background(c.leftBg)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                Text(String(monthPickerYear))
                    .font(.nSerif(26))
                    .foregroundStyle(c.ink)
                    .frame(minWidth: 120)
                    .contentTransition(.numericText())

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    monthPickerYear += 1
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.nSans(14, weight: .bold))
                        .foregroundStyle(c.leftAccent)
                        .frame(width: 38, height: 38)
                        .background(c.leftBg)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(monthPickerYear >= currentCalendarYear)
                .opacity(monthPickerYear >= currentCalendarYear ? 0.35 : 1)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 18)
            .padding(.bottom, 16)

            // 3 columns × 4 rows of months
            let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(1...12, id: \.self) { month in
                    let inFuture = monthIsInFuture(month, year: monthPickerYear)
                    let isSelected = month == anchorMonth && monthPickerYear == anchorYear

                    Button {
                        guard !inFuture else { return }
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        selectMonth(month, year: monthPickerYear)
                    } label: {
                        Text(monthShortName(month))
                            .font(.nSans(15, weight: .semibold))
                            .foregroundStyle(monthLabelColor(selected: isSelected, future: inFuture))
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(monthBackground(selected: isSelected, future: inFuture))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(isSelected ? c.leftAccent : c.border,
                                            lineWidth: isSelected ? 1.5 : 1)
                            )
                    }
                    .buttonStyle(ScaleButtonStyle())
                    .disabled(inFuture)
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 12)

            Spacer()
            doneButton
        }
    }

    private func monthShortName(_ month: Int) -> String {
        Calendar.current.shortMonthSymbols[month - 1]
    }

    private func monthLabelColor(selected: Bool, future: Bool) -> Color {
        if selected { return .white }
        if future   { return c.muted.opacity(0.35) }
        return c.ink
    }

    private func monthBackground(selected: Bool, future: Bool) -> Color {
        if selected { return c.leftAccent }
        if future   { return c.surface.opacity(0.5) }
        return c.surface
    }

    // MARK: Empty period state

    private var emptyPeriodState: some View {
        VStack(spacing: 8) {
            Text("🌙")
                .font(.nSans(38))
                .padding(.top, 48)
            Text(noSessionsMessage)
                .font(.nSans(15, weight: .semibold))
                .foregroundStyle(c.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 48)
    }

    private var noSessionsMessage: String {
        switch selectedTab {
        case 0: return "No sessions on this day"
        case 2: return "No sessions this month"
        default: return "No sessions this week"
        }
    }

    // MARK: Summary cards

    private var summaryCards: some View {
        HStack(spacing: 10) {
            if selectedTab == 0 {
                summaryCell(big: "\(totalSessions)", small: "sessions")
            } else {
                summaryCell(big: "\(formatPerDay(sessionsPerDay))/day", small: "feeds/day")
            }
            summaryCell(big: "\(avgDurationMins) min", small: "avg/session")
            summaryCell(big: String(format: "%.1fh", avgGapHours), small: "avg gap")
        }
        .padding(.bottom, 14)
    }

    private func summaryCell(big: String, small: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(big)
                .font(.nSerif(22))
                .foregroundStyle(c.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(small)
                .font(.nSans(12))
                .foregroundStyle(c.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
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
    private var hasPumpFeeds: Bool   { !pumpSessions.isEmpty }

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

    // MARK: Sleep card

    private var sleepCard: some View {
        // Uses the same standard `card { }` shell as Feed Breakdown / Avg
        // Session Time so the section blends visually; the only purple is
        // on the SLEEP label and the big numbers themselves.
        let isDayView = selectedTab == 0
        return card {
            HStack(spacing: 8) {
                Text("🌙").font(.nSans(15))
                Text("SLEEP")
                    .font(.nSans(11, weight: .bold))
                    .foregroundStyle(SleepView.sleepAccent)
                    .kerning(0.1 * 11)
                Spacer()
            }
            .padding(.bottom, 14)

            HStack(spacing: 10) {
                if isDayView {
                    sleepStatCell(big: "\(napCount)",
                                  small: napCount == 1 ? "nap" : "naps")
                    sleepStatCell(big: SleepView.formatHM(totalSleepMinutes),
                                  small: "total")
                } else if showsDailyAverage(forPerDay: napsPerDay) {
                    sleepStatCell(big: "\(formatPerDay(napsPerDay))/day",
                                  small: "naps/day")
                    sleepStatCell(big: "\(SleepView.formatHM(sleepMinutesPerDay))/day",
                                  small: "sleep/day")
                } else {
                    // Less than one nap a day on average — daily fractions
                    // are noise, just show the actual count + total.
                    sleepStatCell(big: "\(napCount) \(napCount == 1 ? "nap" : "naps")",
                                  small: "this \(periodLabel)")
                    sleepStatCell(big: SleepView.formatHM(totalSleepMinutes),
                                  small: "total this \(periodLabel)")
                }
            }
            .padding(.bottom, 10)
            HStack(spacing: 10) {
                sleepStatCell(big: SleepView.formatHM(avgNapMinutes),     small: "avg nap")
                sleepStatCell(big: SleepView.formatHM(longestNapMinutes), small: "longest")
            }
        }
    }

    private func sleepStatCell(big: String, small: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(big)
                .font(.nSerif(22))
                .foregroundStyle(SleepView.sleepAccent)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(small)
                .font(.nSans(12))
                .foregroundStyle(c.muted)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .background(c.bg)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(c.border, lineWidth: 1))
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
        if hasPumpFeeds && !pumpSessions.isEmpty {
            pumpBreakdown
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
                    let hasLeft   = leftFractionOfTotal > 0
                    let hasRight  = rightFractionOfTotal > 0
                    let hasBottle = bottleFractionOfTotal > 0
                    if hasLeft {
                        // Fixed width unless it's the only segment
                        if hasRight || hasBottle {
                            Capsule().fill(c.leftAccent)
                                .frame(width: geo.size.width * leftFractionOfTotal)
                        } else {
                            Capsule().fill(c.leftAccent).frame(maxWidth: .infinity)
                        }
                    }
                    if hasRight {
                        if hasBottle {
                            Capsule().fill(c.rightAccent)
                                .frame(width: geo.size.width * rightFractionOfTotal)
                        } else {
                            Capsule().fill(c.rightAccent).frame(maxWidth: .infinity)
                        }
                    }
                    if hasBottle {
                        Capsule().fill(c.bottleAccent).frame(maxWidth: .infinity)
                    }
                    if !hasLeft && !hasRight && !hasBottle {
                        Capsule().fill(c.muted.opacity(0.2)).frame(maxWidth: .infinity)
                    }
                }
            }
            .frame(height: 16)

            HStack(spacing: 10) {
                if leftFractionOfTotal > 0 {
                    legendDot(color: c.leftAccent, label: "Left \(percent(leftFractionOfTotal))%")
                }
                if rightFractionOfTotal > 0 {
                    legendDot(color: c.rightAccent, label: "Right \(percent(rightFractionOfTotal))%")
                }
                if bottleFractionOfTotal > 0 {
                    HStack(spacing: 4) {
                        Text("🍼").font(.nSans(11))
                        Text("Bottle \(percent(bottleFractionOfTotal))%")
                            .font(.nSans(12, weight: .semibold))
                            .foregroundStyle(c.bottleAccent)
                    }
                }
                Spacer(minLength: 0)
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
                // Legacy bottles without an explicit content type get
                // bucketed as breast milk (the more common case). New
                // logged sessions require a selection, so going forward
                // this fallback only affects historical data.
                let count = bottleSessions.filter { ($0.bottleContentType ?? .breastmilk) == type }.count
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

    @ViewBuilder
    private var pumpBreakdown: some View {
        Divider().overlay(c.border).padding(.bottom, 10)

        Text("Pump")
            .font(.nSans(11, weight: .bold))
            .foregroundStyle(c.muted)
            .kerning(0.08 * 11)
            .textCase(.uppercase)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 7)

        HStack(spacing: 8) {
            pumpCountCell
            if avgPumpVolumeMl > 0 {
                pumpStatCell(value: "\(avgPumpVolumeMl) ml", label: "avg volume")
            }
            if totalPumpVolumeMl > 0 {
                pumpStatCell(value: "\(totalPumpVolumeMl) ml", label: "total pumped")
            }
        }
    }

    /// Pump count cell — Day shows the raw count, Week/Month switches
    /// between daily average and "N this week/month" based on frequency.
    @ViewBuilder
    private var pumpCountCell: some View {
        let count = pumpSessions.count
        if selectedTab == 0 {
            pumpStatCell(value: "\(count)", label: count == 1 ? "pump" : "pumps")
        } else if showsDailyAverage(forPerDay: pumpsPerDay) {
            pumpStatCell(value: "\(formatPerDay(pumpsPerDay))/day", label: "pumps/day")
        } else {
            pumpStatCell(value: "\(count) \(count == 1 ? "pump" : "pumps")",
                         label: "this \(periodLabel)")
        }
    }

    private func pumpStatCell(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                Image("pump_icon").renderingMode(.template).resizable().scaledToFit().frame(height: 11).foregroundStyle(c.pumpAccent)
                Text(value)
                    .font(.nSans(14, weight: .bold))
                    .foregroundStyle(c.pumpAccent)
                    .lineLimit(1)
            }
            Text(label)
                .font(.nSans(11))
                .foregroundStyle(c.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(c.pumpBg)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(c.pumpBorder, lineWidth: 1))
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

    /// Sessions filtered by the History tab's From/To range, then grouped
    /// by calendar day (startOfDay), newest day first. Days with no sessions
    /// are simply absent — no empty headers.
    private var historyDays: [(date: Date, sessions: [FeedingSession])] {
        let cal = Calendar.current

        let lowerBound = historyFromDate.map { cal.startOfDay(for: $0) }
        let upperBound = historyToDate.flatMap { to -> Date? in
            let startOfTo = cal.startOfDay(for: to)
            return cal.date(byAdding: .day, value: 1, to: startOfTo)
        }

        let filtered = sessions.filter { session in
            if let lower = lowerBound, session.startTime < lower { return false }
            if let upper = upperBound, session.startTime >= upper { return false }
            return true
        }

        let grouped = Dictionary(grouping: filtered) { cal.startOfDay(for: $0.startTime) }
        return grouped
            .map { (date: $0.key, sessions: $0.value.sorted { $0.startTime > $1.startTime }) }
            .sorted { $0.date > $1.date }
    }

    private func historyHeaderLabel(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date)     { return "Today" }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }

    @ViewBuilder
    private var historyList: some View {
        if sessions.isEmpty {
            ScrollView { historyEmptyState }
        } else if historyDays.isEmpty {
            ScrollView { historyFilterEmptyState }
        } else {
            historyListContent
        }
    }

    private var historyListContent: some View {
        List {
            ForEach(historyDays, id: \.date) { day in
                Section {
                    ForEach(Array(day.sessions.enumerated()), id: \.element.id) { offset, session in
                        VStack(spacing: 0) {
                            historyRow(session)
                            Divider().overlay(c.border).padding(.horizontal, 20)
                        }
                        .contentShape(Rectangle())
                        .simultaneousGesture(TapGesture().onEnded { selectedSession = session })
                        .listRowBackground(c.bg)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets())
                        .tooltipTargetIf(
                            day.date == historyDays.first?.date && offset == 0,
                            .historySwipe
                        )
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
                } header: {
                    historySectionHeader(date: day.date, sessions: day.sessions)
                }
            }
        }
        .listStyle(.plain)
        .listSectionSpacing(0)
        .contentMargins(.top, 0, for: .scrollContent)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListHeaderHeight, 0)
    }

    private func historySectionHeader(date: Date, sessions: [FeedingSession]) -> some View {
        let feedCount = sessions.filter { $0.feedType != .pump && $0.feedType != .sleep }.count
        let pumpCount = sessions.filter { $0.feedType == .pump  }.count
        let napCount  = sessions.filter { $0.feedType == .sleep }.count
        let parts: [String] = {
            var p: [String] = []
            if feedCount > 0 { p.append("\(feedCount) \(feedCount == 1 ? "feed" : "feeds")") }
            if pumpCount > 0 { p.append("\(pumpCount) \(pumpCount == 1 ? "pump" : "pumps")") }
            if napCount > 0  { p.append("\(napCount) \(napCount == 1 ? "nap" : "naps")") }
            return p
        }()
        return HStack {
            Text(historyHeaderLabel(date))
                .font(.nSans(14, weight: .semibold))
                .foregroundStyle(c.muted)
            Spacer()
            Text(parts.joined(separator: " · "))
                .font(.nSans(12, weight: .semibold))
                .foregroundStyle(c.muted.opacity(0.85))
        }
        .padding(.horizontal, 20)
        .padding(.top, 6)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(c.bg)
        .listRowInsets(EdgeInsets())
    }

    private func historyRow(_ s: FeedingSession) -> some View {
        HStack(spacing: 12) {
            // Side indicator
            Group {
                switch s.feedType {
                case .bottle:
                    Text("🍼")
                        .font(.nSans(18))
                        .frame(width: 36, height: 36)
                        .background(c.bottleBg)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(c.bottleBorder, lineWidth: 1.5))
                case .pump:
                    Image("pump_icon")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(c.pumpAccent)
                        .padding(7)
                        .frame(width: 36, height: 36)
                        .background(c.pumpBg)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(c.pumpBorder, lineWidth: 1.5))
                case .sleep:
                    Text("🌙")
                        .font(.nSans(17))
                        .frame(width: 36, height: 36)
                        .background(SleepView.sleepBg)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(SleepView.sleepBorder, lineWidth: 1.5))
                default:
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

            // Left block
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(s.startTime.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                        .font(.nSans(14, weight: .semibold))
                        .foregroundStyle(c.ink)
                    // Note indicator
                    if let notes = s.notes, !notes.isEmpty {
                        Image(systemName: "note.text")
                            .font(.nSans(10))
                            .foregroundStyle(c.muted.opacity(0.7))
                    }
                }
                switch s.feedType {
                case .bottle:
                    Text(s.startTime.formatted(date: .omitted, time: .shortened))
                        .font(.nSans(12))
                        .foregroundStyle(c.muted)
                case .pump:
                    Text(historyPumpSubtitle(s))
                        .font(.nSans(12))
                        .foregroundStyle(c.muted)
                case .sleep:
                    Text(historySleepSubtitle(s))
                        .font(.nSans(12))
                        .foregroundStyle(c.muted)
                default:
                    Text(historyTimeAndTotal(s))
                        .font(.nSans(12))
                        .foregroundStyle(c.muted)
                }
            }

            Spacer()

            // Right block
            switch s.feedType {
            case .bottle:
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
            case .pump:
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(s.totalActiveMinutes) min")
                        .font(.nSans(13, weight: .semibold))
                        .foregroundStyle(c.pumpAccent)
                    if let vol = s.pumpVolumeMl {
                        Text("\(vol) ml")
                            .font(.nSans(11))
                            .foregroundStyle(c.muted)
                    }
                }
            case .sleep:
                Text(SleepView.formatHM(s.totalActiveMinutes))
                    .font(.nSans(14, weight: .bold))
                    .foregroundStyle(SleepView.sleepAccent)
            default:
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

    private func historyTimeAndTotal(_ s: FeedingSession) -> String {
        let time = s.startTime.formatted(date: .omitted, time: .shortened)
        let total = s.leftMinutesResolved + s.rightMinutesResolved
        return "\(time) · Total: \(formatMins(total))"
    }

    private func historyPumpSubtitle(_ s: FeedingSession) -> String {
        let time = s.startTime.formatted(date: .omitted, time: .shortened)
        let side = s.pumpSide?.displayName ?? "Pump"
        return "\(time) · \(side)"
    }

    private func historySleepSubtitle(_ s: FeedingSession) -> String {
        let start = s.startTime.formatted(date: .omitted, time: .shortened)
        guard let end = s.endTime else { return start }
        let endStr = end.formatted(date: .omitted, time: .shortened)
        return "\(start) - \(endStr)"
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

    /// Shown on the History tab when sessions exist but the active From/To
    /// filter excludes every one of them.
    private var historyFilterEmptyState: some View {
        VStack(spacing: 12) {
            Text("🔍")
                .font(.nSans(38))
                .padding(.top, 64)
            Text("No sessions in this range")
                .font(.nSerif(20))
                .foregroundStyle(c.ink)
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(.easeInOut(duration: 0.18)) {
                    historyFromDate = nil
                    historyToDate = nil
                }
            } label: {
                Text("Clear filter")
                    .font(.nSans(14, weight: .semibold))
                    .foregroundStyle(c.leftAccent)
                    .padding(.horizontal, 18)
                    .frame(height: 38)
                    .background(c.leftBg)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(c.leftAccent.opacity(0.25), lineWidth: 1))
            }
            .buttonStyle(ScaleButtonStyle())
            .padding(.top, 4)
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
