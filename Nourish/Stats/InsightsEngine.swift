import Foundation

// MARK: - Insight model

struct Insight: Identifiable, Hashable {
    let id: String
    let emoji: String
    let title: String
    let description: String
    let category: Category
    let trend: TrendDirection?

    enum Category: Int { case milestone = 0, trend = 1, pattern = 2 }
    enum TrendDirection { case up, down }
}

enum InsightsTimeFilter {
    case day, week, month, history

    /// Window of "current period" in days, used for pattern scoping.
    /// nil = all-time.
    var windowDays: Int? {
        switch self {
        case .day:     return 1
        case .week:    return 7
        case .month:   return 30
        case .history: return nil
        }
    }

    /// Trend comparisons need a "prior period" — for History/Week we use a
    /// 7-day rolling window, for Month a 30-day one.
    var trendWindowDays: Int? {
        switch self {
        case .day:                return nil   // no trends
        case .week, .history:     return 7
        case .month:              return 30
        }
    }
}

// MARK: - Engine

struct InsightsEngine {
    let sessions: [FeedingSession]   // assumed sorted descending by startTime
    let filter: InsightsTimeFilter
    let now: Date

    // Split ONCE at init. These were computed properties re-filtering the
    // whole session array on every access — with a few thousand sessions
    // the repeated passes (behind slow SwiftData accessors) add up to
    // visible main-thread stalls on the stats screen.
    private let breastSessions: [FeedingSession]
    private let pumpSessions: [FeedingSession]
    private let sleepSessions: [FeedingSession]

    init(sessions: [FeedingSession], filter: InsightsTimeFilter, now: Date = .now) {
        self.sessions = sessions
        self.filter = filter
        self.now = now
        var breast: [FeedingSession] = [], pump: [FeedingSession] = [], sleep: [FeedingSession] = []
        for s in sessions {
            switch s.feedType {
            case .left, .right: breast.append(s)
            case .pump:         pump.append(s)
            case .sleep:        sleep.append(s)
            case .bottle:       break
            }
        }
        self.breastSessions = breast
        self.pumpSessions = pump
        self.sleepSessions = sleep
    }

    /// Two-phase visibility per insight:
    ///   * stick   — insight stays visible while still relevant
    ///   * cycle   — total time before the insight can resurface
    /// (cycle == nil means permanently retired after the stick window expires.)
    private struct TimingPolicy {
        let stickDays: Int
        let cycleDays: Int?
    }

    private func policy(for category: Insight.Category) -> TimingPolicy {
        switch category {
        case .milestone: return TimingPolicy(stickDays: 7, cycleDays: nil)   // visible 7d, then retired
        case .trend:     return TimingPolicy(stickDays: 2, cycleDays: 7)     // 2d on, 5d off
        case .pattern:   return TimingPolicy(stickDays: 3, cycleDays: 14)    // 3d on, 11d off
        }
    }

    func compute(maxCount: Int = 3) -> [Insight] {
        var pool: [Insight] = []

        // Milestones first — always evaluated against the full session set.
        pool.append(contentsOf: milestones().filter { shouldShow($0) })

        // Trends — only when the filter has something to compare against.
        if let windowDays = filter.trendWindowDays {
            pool.append(contentsOf: trends().filter { shouldShow($0) })
            pool.append(contentsOf: pumpTrends(windowDays: windowDays).filter { shouldShow($0) })
            pool.append(contentsOf: sleepTrends(windowDays: windowDays).filter { shouldShow($0) })
        }

        // Patterns.
        pool.append(contentsOf: patterns().filter { shouldShow($0) })
        pool.append(contentsOf: pumpPatterns().filter { shouldShow($0) })
        pool.append(contentsOf: sleepPatterns().filter { shouldShow($0) })

        return Array(pool.sorted { $0.category.rawValue < $1.category.rawValue }.prefix(maxCount))
    }

    func markShown(_ insights: [Insight]) {
        let defaults = UserDefaults.standard
        for insight in insights {
            if insight.category == .milestone {
                // Milestones are view-count retired: increment each appearance.
                let key = InsightKey.viewCount(insight.id)
                defaults.set(defaults.integer(forKey: key) + 1, forKey: key)
                continue
            }

            let key = InsightKey.firstShown(insight.id)
            let p = policy(for: insight.category)
            if let firstShown = defaults.object(forKey: key) as? Double {
                if let cycleDays = p.cycleDays {
                    let elapsed = now.timeIntervalSince1970 - firstShown
                    if elapsed >= Double(cycleDays) * 86_400 {
                        defaults.set(now.timeIntervalSince1970, forKey: key)
                    }
                }
            } else {
                defaults.set(now.timeIntervalSince1970, forKey: key)
            }
        }
    }

    /// Returns true if an insight should be displayed in this compute pass.
    private func shouldShow(_ insight: Insight) -> Bool {
        if insight.category == .milestone {
            let legacySeen = Set(UserDefaults.standard.stringArray(forKey: InsightKey.legacyMilestonesSeen) ?? [])
            if legacySeen.contains(insight.id) { return false }
            // Show for up to 3 stat-screen appearances, then permanently retire.
            let count = UserDefaults.standard.integer(forKey: InsightKey.viewCount(insight.id))
            return count < 3
        }

        let p = policy(for: insight.category)
        guard let firstShown = UserDefaults.standard.object(forKey: InsightKey.firstShown(insight.id)) as? Double else {
            return true                         // first time ever — surface fresh
        }
        let elapsed = now.timeIntervalSince1970 - firstShown
        if elapsed < Double(p.stickDays) * 86_400 { return true }   // still in stick window
        guard let cycleDays = p.cycleDays else { return false }     // permanent retirement
        return elapsed >= Double(cycleDays) * 86_400                // re-surface after full cycle
    }

    // MARK: - Staleness storage

    private enum InsightKey {
        static func firstShown(_ id: String) -> String { "insight_lastShown_\(id)" }
        static func viewCount(_ id: String) -> String  { "insight_viewCount_\(id)" }
        static let legacyMilestonesSeen = "insights_milestones_seen"
    }

    // MARK: - Session sets

    private var sessionsInPatternWindow: [FeedingSession] {
        guard let days = filter.windowDays else { return sessions }
        let start = Calendar.current.date(byAdding: .day, value: -days, to: now) ?? now
        return sessions.filter { $0.startTime >= start }
    }

    private var pumpSessionsInWindow: [FeedingSession] {
        guard let days = filter.windowDays else { return pumpSessions }
        let start = Calendar.current.date(byAdding: .day, value: -days, to: now) ?? now
        return pumpSessions.filter { $0.startTime >= start }
    }

    private var sleepSessionsInWindow: [FeedingSession] {
        guard let days = filter.windowDays else { return sleepSessions }
        let start = Calendar.current.date(byAdding: .day, value: -days, to: now) ?? now
        return sleepSessions.filter { $0.startTime >= start }
    }

    // MARK: - Pattern insights

    private func patterns() -> [Insight] {
        var out: [Insight] = []
        let pool = sessionsInPatternWindow.filter { $0.feedType == .left || $0.feedType == .right }
        guard pool.count >= 8 else { return [] }

        if let i = morningVsEveningInsight(pool) { out.append(i) }
        if let i = sidePreferenceInsight(pool)   { out.append(i) }

        let gap = longestGapWindowInsight(pool)
        let busy = busiestWindowInsight(pool)

        // If the "longest stretch" and "busiest window" point at the same
        // 4-hour bucket the two cards literally contradict each other.
        // Suppress the longest-stretch one in that case; busiest is the more
        // reliable signal (just counts sessions, no gap-midpoint heuristics).
        if let g = gap, let b = busy, g.bucket == b.bucket {
            out.append(b.insight)
        } else {
            if let g = gap  { out.append(g.insight) }
            if let b = busy { out.append(b.insight) }
        }
        return out
    }

    private func morningVsEveningInsight(_ pool: [FeedingSession]) -> Insight? {
        let cal = Calendar.current
        let morning = pool.filter { cal.component(.hour, from: $0.startTime) < 12 }
        let evening = pool.filter { cal.component(.hour, from: $0.startTime) >= 12 }
        guard morning.count >= 3, evening.count >= 3 else { return nil }
        let mAvg = avgActiveMinutes(morning)
        let eAvg = avgActiveMinutes(evening)
        guard mAvg > 0, eAvg > 0 else { return nil }
        let bigger = max(mAvg, eAvg)
        let diff = abs(mAvg - eAvg)
        guard Double(diff) / Double(bigger) > 0.15 else { return nil }
        return Insight(
            id: "pattern_morning_vs_evening",
            emoji: "🌅",
            title: "Time of day pattern",
            description: "Morning feeds average \(mAvg) min, evening feeds average \(eAvg) min.",
            category: .pattern, trend: nil
        )
    }

    private func sidePreferenceInsight(_ pool: [FeedingSession]) -> Insight? {
        let leftCount  = pool.filter { $0.feedType == .left }.count
        let rightCount = pool.filter { $0.feedType == .right }.count
        let total = leftCount + rightCount
        guard total >= 5 else { return nil }
        let leftPct  = Double(leftCount)  / Double(total)
        let rightPct = Double(rightCount) / Double(total)
        let (side, pct) = leftPct >= rightPct ? ("left", leftPct) : ("right", rightPct)
        guard pct > 0.60 else { return nil }
        return Insight(
            id: "pattern_side_preference_\(side)",
            emoji: "🤱",
            title: "Side preference",
            description: "You start on the \(side) \(Int((pct * 100).rounded()))% of the time.",
            category: .pattern, trend: nil
        )
    }

    private func longestGapWindowInsight(_ pool: [FeedingSession]) -> (insight: Insight, bucket: Int)? {
        let sorted = pool.sorted { $0.startTime < $1.startTime }
        guard sorted.count >= 6 else { return nil }
        var allGaps: [TimeInterval] = []
        var bucketGaps: [Int: [TimeInterval]] = [:]
        for i in 1..<sorted.count {
            let gap = sorted[i].startTime.timeIntervalSince(sorted[i - 1].endTime ?? sorted[i - 1].startTime)
            guard gap > 0 else { continue }
            allGaps.append(gap)
            let mid = sorted[i - 1].startTime.addingTimeInterval(gap / 2)
            let bucket = Calendar.current.component(.hour, from: mid) / 4   // 0...5
            bucketGaps[bucket, default: []].append(gap)
        }
        let overallAvg = avg(allGaps)
        guard overallAvg > 0 else { return nil }

        // Need at least 3 gap samples in a bucket to call it a "stretch".
        guard let best = bucketGaps
            .filter({ $0.value.count >= 3 })
            .max(by: { avg($0.value) < avg($1.value) })
        else { return nil }

        let bestAvg = avg(best.value)
        let bestAvgHours = bestAvg / 3600

        // Both gates: ≥ 2 h *and* clearly longer than the overall average gap.
        guard bestAvgHours >= 2.0 else { return nil }
        guard bestAvg >= overallAvg * 1.5 else { return nil }

        let insight = Insight(
            id: "pattern_longest_gap_\(best.key)",
            emoji: "🌙",
            title: "Longest stretch",
            description: "Longest stretch is usually between \(bucketLabel(best.key)) (avg \(formatHours(bestAvgHours))).",
            category: .pattern, trend: nil
        )
        return (insight, best.key)
    }

    private func busiestWindowInsight(_ pool: [FeedingSession]) -> (insight: Insight, bucket: Int)? {
        var counts: [Int: Int] = [:]
        for s in pool {
            let bucket = Calendar.current.component(.hour, from: s.startTime) / 4
            counts[bucket, default: 0] += 1
        }
        let total = counts.values.reduce(0, +)
        guard total >= 8 else { return nil }
        let avgPerBucket = Double(total) / 6.0
        guard let best = counts.max(by: { $0.value < $1.value }),
              Double(best.value) > 1.5 * avgPerBucket
        else { return nil }
        let insight = Insight(
            id: "pattern_busiest_\(best.key)",
            emoji: "⏰",
            title: "Busiest window",
            description: "Most feeds happen between \(bucketLabel(best.key)).",
            category: .pattern, trend: nil
        )
        return (insight, best.key)
    }

    // MARK: - Trend insights

    private func trends() -> [Insight] {
        guard let windowDays = filter.trendWindowDays else { return [] }
        let curStart  = Calendar.current.date(byAdding: .day, value: -windowDays,     to: now)!
        let priorStart = Calendar.current.date(byAdding: .day, value: -2 * windowDays, to: now)!

        let current = sessions.filter { $0.startTime >= curStart }
        let prior   = sessions.filter { $0.startTime >= priorStart && $0.startTime < curStart }
        guard current.count >= 3, prior.count >= 3 else { return [] }

        var out: [Insight] = []
        if let i = durationTrend(current: current, prior: prior)  { out.append(i) }
        if let i = frequencyTrend(current: current, prior: prior, windowDays: windowDays) { out.append(i) }
        if let i = gapTrend(current: current, prior: prior) { out.append(i) }
        return out
    }

    private func durationTrend(current: [FeedingSession], prior: [FeedingSession]) -> Insight? {
        let cBreast = current.filter { $0.feedType == .left || $0.feedType == .right }
        let pBreast = prior.filter   { $0.feedType == .left || $0.feedType == .right }
        guard cBreast.count >= 3, pBreast.count >= 3 else { return nil }
        let cAvg = avgActiveMinutes(cBreast)
        let pAvg = avgActiveMinutes(pBreast)
        guard cAvg > 0, pAvg > 0 else { return nil }
        let pct = (Double(cAvg - pAvg) / Double(pAvg)) * 100
        guard abs(pct) >= 20 else { return nil }
        let direction: Insight.TrendDirection = pct > 0 ? .up : .down
        let word = pct > 0 ? "longer" : "shorter"
        return Insight(
            id: "trend_duration_\(direction == .up ? "up" : "down")",
            emoji: "⏱",
            title: "Session duration trend",
            description: "Sessions are \(Int(abs(pct).rounded()))% \(word) than last period (\(cAvg) min vs \(pAvg) min).",
            category: .trend, trend: direction
        )
    }

    private func frequencyTrend(current: [FeedingSession], prior: [FeedingSession], windowDays: Int) -> Insight? {
        let cPerDay = Double(current.count) / Double(windowDays)
        let pPerDay = Double(prior.count)   / Double(windowDays)
        guard cPerDay > 0, pPerDay > 0 else { return nil }
        let pct = ((cPerDay - pPerDay) / pPerDay) * 100
        guard abs(pct) >= 20 else { return nil }
        let direction: Insight.TrendDirection = pct > 0 ? .up : .down
        let word = pct > 0 ? "up" : "down"
        return Insight(
            id: "trend_frequency_\(direction == .up ? "up" : "down")",
            emoji: "📈",
            title: "Feeding frequency",
            description: "\(formatPerDay(cPerDay)) feeds/day this period, \(word) from \(formatPerDay(pPerDay)) last period.",
            category: .trend, trend: direction
        )
    }

    private func gapTrend(current: [FeedingSession], prior: [FeedingSession]) -> Insight? {
        let cGap = avgGapHours(current)
        let pGap = avgGapHours(prior)
        guard cGap > 0, pGap > 0 else { return nil }
        let pct = ((cGap - pGap) / pGap) * 100
        guard abs(pct) >= 20 else { return nil }
        let direction: Insight.TrendDirection = pct > 0 ? .up : .down
        let phrase = pct > 0 ? "getting longer" : "getting shorter"
        return Insight(
            id: "trend_gap_\(direction == .up ? "up" : "down")",
            emoji: "🛏",
            title: "Time between feeds",
            description: "Gaps are \(phrase) — \(formatHours(cGap)) avg this period vs \(formatHours(pGap)) last period.",
            category: .trend, trend: direction
        )
    }

    // MARK: - Milestones

    private func milestones() -> [Insight] {
        var out: [Insight] = []
        out.append(contentsOf: sessionCountMilestone())
        out.append(contentsOf: streakMilestone())
        out.append(contentsOf: totalTimeMilestone())
        out.append(contentsOf: pumpSessionCountMilestone())
        out.append(contentsOf: pumpVolumeMilestone())
        out.append(contentsOf: sleepSessionCountMilestone())
        return out
    }

    private func sessionCountMilestone() -> [Insight] {
        let total = sessions.count
        let thresholds = [10, 25, 50, 100, 250, 500]
        let hit = thresholds.last(where: { total >= $0 })
        guard let n = hit else { return [] }
        return [Insight(
            id: "milestone_sessions_\(n)",
            emoji: "🎉",
            title: "Logged \(n) sessions!",
            description: "You've logged \(n)+ sessions. That's a lot of love. 💛",
            category: .milestone, trend: nil
        )]
    }

    private func streakMilestone() -> [Insight] {
        let cal = Calendar.current
        let dates = Set(sessions.map { cal.startOfDay(for: $0.startTime) })
        var streak = 0
        var day = cal.startOfDay(for: now)
        while dates.contains(day) {
            streak += 1
            day = cal.date(byAdding: .day, value: -1, to: day) ?? day
        }
        let thresholds = [3, 7, 14, 30, 60, 100]
        let hit = thresholds.last(where: { streak >= $0 })
        guard let n = hit else { return [] }
        return [Insight(
            id: "milestone_streak_\(n)",
            emoji: "🔥",
            title: "\(n)-day tracking streak!",
            description: "You've logged at least one feed every day for \(n) days running.",
            category: .milestone, trend: nil
        )]
    }

    private func totalTimeMilestone() -> [Insight] {
        let mins = sessions.reduce(0) { $0 + $1.totalActiveMinutes }
        let thresholds = [10, 24, 50, 100, 200].map { $0 * 60 }
        let hit = thresholds.last(where: { mins >= $0 })
        guard let m = hit else { return [] }
        let hours = m / 60
        let suffix: String
        switch hours {
        case 24:  suffix = " — that's a full day!"
        case 100: suffix = " — wow, three full days of feeds."
        case 50:  suffix = " — over two days of dedication."
        default:  suffix = ""
        }
        return [Insight(
            id: "milestone_time_\(hours)h",
            emoji: "💛",
            title: "\(hours) hours of feeding",
            description: "You've spent over \(hours) hours feeding\(suffix)",
            category: .milestone, trend: nil
        )]
    }

    // MARK: - Pump milestones

    private func pumpSessionCountMilestone() -> [Insight] {
        let count = pumpSessions.count
        guard let n = [10, 25, 50, 100].last(where: { count >= $0 }) else { return [] }
        return [Insight(
            id: "milestone_pump_sessions_\(n)",
            emoji: "💪",
            title: "\(n) pump sessions!",
            description: "You've completed \(n) pump sessions. Every drop counts.",
            category: .milestone, trend: nil
        )]
    }

    private func pumpVolumeMilestone() -> [Insight] {
        let totalMl = pumpSessions.compactMap(\.pumpVolumeMl).reduce(0, +)
        guard let ml = [500, 1_000, 2_000, 5_000, 10_000].last(where: { totalMl >= $0 }) else { return [] }
        let label: String
        let suffix: String
        switch ml {
        case 500:    label = "500ml";     suffix = " — half a liter!"
        case 1_000:  label = "1 liter";   suffix = " 🥛"
        case 2_000:  label = "2 liters";  suffix = " — that's dedication!"
        case 5_000:  label = "5 liters";  suffix = " — incredible!"
        default:     label = "10 liters"; suffix = " — amazing!"
        }
        return [Insight(
            id: "milestone_pump_volume_\(ml)",
            emoji: "🥛",
            title: "Pumped over \(label)!",
            description: "Your total pumped volume has crossed \(label)\(suffix)",
            category: .milestone, trend: nil
        )]
    }

    // MARK: - Pump trends

    private func pumpTrends(windowDays: Int) -> [Insight] {
        var out: [Insight] = []
        if let i = pumpVolumeTrend(windowDays: windowDays) { out.append(i) }
        return out
    }

    private func pumpVolumeTrend(windowDays: Int) -> Insight? {
        let curStart   = Calendar.current.date(byAdding: .day, value: -windowDays,     to: now)!
        let priorStart = Calendar.current.date(byAdding: .day, value: -2 * windowDays, to: now)!
        let current = pumpSessions.filter { $0.startTime >= curStart && $0.pumpVolumeMl != nil }
        let prior   = pumpSessions.filter { $0.startTime >= priorStart && $0.startTime < curStart && $0.pumpVolumeMl != nil }
        guard current.count >= 3, prior.count >= 3 else { return nil }
        let cAvg = avgVolumeMl(current)
        let pAvg = avgVolumeMl(prior)
        guard cAvg > 0, pAvg > 0 else { return nil }
        let pct = (Double(cAvg - pAvg) / Double(pAvg)) * 100
        guard abs(pct) >= 15 else { return nil }
        let direction: Insight.TrendDirection = pct > 0 ? .up : .down
        let word = pct > 0 ? "up" : "down"
        let period = windowDays == 7 ? "week" : "period"
        return Insight(
            id: "trend_pump_volume_\(direction == .up ? "up" : "down")",
            emoji: "🍼",
            title: "Pump output trend",
            description: "Output is \(word) \(Int(abs(pct).rounded()))% this \(period) (avg \(cAvg)ml vs \(pAvg)ml).",
            category: .trend, trend: direction
        )
    }

    // MARK: - Pump patterns

    private func pumpPatterns() -> [Insight] {
        let pool = pumpSessionsInWindow
        guard pool.count >= 3 else { return [] }
        var out: [Insight] = []
        if let i = pumpTimePreferenceInsight(pool)   { out.append(i) }
        if let i = pumpSidePreferenceInsight(pool)   { out.append(i) }
        if let i = pumpBestOutputInsight(pool)       { out.append(i) }
        if let i = pumpFeedRatioInsight()            { out.append(i) }
        return out
    }

    private func pumpTimePreferenceInsight(_ pool: [FeedingSession]) -> Insight? {
        let cal = Calendar.current
        let morning = pool.filter { cal.component(.hour, from: $0.startTime) < 12 }.count
        let other   = pool.count - morning
        let total   = pool.count
        let mPct = Double(morning) / Double(total)
        let oPct = Double(other)   / Double(total)
        let (label, pct) = mPct >= oPct ? ("morning", mPct) : ("afternoon/evening", oPct)
        guard pct > 0.60 else { return nil }
        return Insight(
            id: "pattern_pump_time_of_day",
            emoji: "🕐",
            title: "Pump time preference",
            description: "You usually pump in the \(label) (\(Int((pct * 100).rounded()))% of sessions).",
            category: .pattern, trend: nil
        )
    }

    private func pumpSidePreferenceInsight(_ pool: [FeedingSession]) -> Insight? {
        let withSide = pool.filter { $0.pumpSide != nil }
        guard withSide.count >= 3 else { return nil }
        let total = withSide.count
        let both  = withSide.filter { $0.pumpSide == .both  }.count
        let left  = withSide.filter { $0.pumpSide == .left  }.count
        let right = withSide.filter { $0.pumpSide == .right }.count
        let (label, count): (String, Int)
        if both >= left && both >= right { (label, count) = ("both sides", both) }
        else if left >= right            { (label, count) = ("left only",  left) }
        else                            { (label, count) = ("right only", right) }
        let pct = Double(count) / Double(total)
        guard pct > 0.60 else { return nil }
        return Insight(
            id: "pattern_pump_side",
            emoji: "🤱",
            title: "Pump side preference",
            description: "You pump \(label) \(Int((pct * 100).rounded()))% of the time.",
            category: .pattern, trend: nil
        )
    }

    private func pumpBestOutputInsight(_ pool: [FeedingSession]) -> Insight? {
        let cal = Calendar.current
        let withVol = pool.filter { $0.pumpVolumeMl != nil }
        guard withVol.count >= 4 else { return nil }
        let morning = withVol.filter { cal.component(.hour, from: $0.startTime) < 12 }
        let other   = withVol.filter { cal.component(.hour, from: $0.startTime) >= 12 }
        guard morning.count >= 2, other.count >= 2 else { return nil }
        let mAvg = avgVolumeMl(morning)
        let oAvg = avgVolumeMl(other)
        guard mAvg > 0, oAvg > 0 else { return nil }
        let diff = abs(mAvg - oAvg)
        guard Double(diff) / Double(max(mAvg, oAvg)) > 0.20 else { return nil }
        let (bestLabel, bestAvg, otherAvg) = mAvg > oAvg
            ? ("morning", mAvg, oAvg)
            : ("afternoon/evening", oAvg, mAvg)
        return Insight(
            id: "pattern_pump_best_output",
            emoji: "📊",
            title: "Best output window",
            description: "Your highest output is usually in the \(bestLabel) (avg \(bestAvg)ml vs \(otherAvg)ml).",
            category: .pattern, trend: nil
        )
    }

    private func pumpFeedRatioInsight() -> Insight? {
        guard let days = filter.windowDays else { return nil }
        let start  = Calendar.current.date(byAdding: .day, value: -days, to: now) ?? now
        let window = sessions.filter { $0.startTime >= start }
        let breast  = window.filter { $0.feedType == .left || $0.feedType == .right }.count
        let pump    = window.filter { $0.feedType == .pump   }.count
        let bottle  = window.filter { $0.feedType == .bottle }.count
        guard breast > 0, pump >= 3, bottle > 0 else { return nil }
        let bf = breast == 1 ? "breastfeed" : "breastfeeds"
        let ps = pump   == 1 ? "pump session" : "pump sessions"
        let bt = bottle == 1 ? "bottle" : "bottles"
        return Insight(
            id: "pattern_pump_feed_ratio",
            emoji: "📋",
            title: "Your feeding mix",
            description: "This period: \(breast) \(bf), \(pump) \(ps), \(bottle) \(bt).",
            category: .pattern, trend: nil
        )
    }

    // MARK: - Sleep milestones

    private func sleepSessionCountMilestone() -> [Insight] {
        let count = sleepSessions.count
        guard let n = [10, 25, 50, 100].last(where: { count >= $0 }) else { return [] }
        return [Insight(
            id: "milestone_sleep_sessions_\(n)",
            emoji: "🌙",
            title: "\(n) naps tracked!",
            description: "You've logged \(n) sleep sessions. Sweet dreams 💜",
            category: .milestone, trend: nil
        )]
    }

    // MARK: - Sleep trends

    private func sleepTrends(windowDays: Int) -> [Insight] {
        var out: [Insight] = []
        if let i = sleepTotalTrend(windowDays: windowDays)    { out.append(i) }
        if let i = sleepDurationTrend(windowDays: windowDays) { out.append(i) }
        return out
    }

    /// Total daily sleep this period vs prior period.
    private func sleepTotalTrend(windowDays: Int) -> Insight? {
        let curStart   = Calendar.current.date(byAdding: .day, value: -windowDays,     to: now)!
        let priorStart = Calendar.current.date(byAdding: .day, value: -2 * windowDays, to: now)!
        let current = sleepSessions.filter { $0.startTime >= curStart }
        let prior   = sleepSessions.filter { $0.startTime >= priorStart && $0.startTime < curStart }
        guard current.count >= 3, prior.count >= 3 else { return nil }
        let cAvg = sleepHoursPerDay(current, days: windowDays)
        let pAvg = sleepHoursPerDay(prior,   days: windowDays)
        guard cAvg > 0, pAvg > 0 else { return nil }
        let pct = ((cAvg - pAvg) / pAvg) * 100
        guard abs(pct) >= 15 else { return nil }
        let direction: Insight.TrendDirection = pct > 0 ? .up : .down
        let word = pct > 0 ? "up" : "down"
        return Insight(
            id: "trend_sleep_total_\(direction == .up ? "up" : "down")",
            emoji: "💤",
            title: "Total sleep trend",
            description: "Total daily sleep is \(word) \(Int(abs(pct).rounded()))% this period (\(formatHours(cAvg)) vs \(formatHours(pAvg)) last period).",
            category: .trend, trend: direction
        )
    }

    /// Average nap duration this period vs prior period.
    private func sleepDurationTrend(windowDays: Int) -> Insight? {
        let curStart   = Calendar.current.date(byAdding: .day, value: -windowDays,     to: now)!
        let priorStart = Calendar.current.date(byAdding: .day, value: -2 * windowDays, to: now)!
        let current = sleepSessions.filter { $0.startTime >= curStart }
        let prior   = sleepSessions.filter { $0.startTime >= priorStart && $0.startTime < curStart }
        guard current.count >= 3, prior.count >= 3 else { return nil }
        let cAvg = avgActiveMinutes(current)
        let pAvg = avgActiveMinutes(prior)
        guard cAvg > 0, pAvg > 0 else { return nil }
        let pct = (Double(cAvg - pAvg) / Double(pAvg)) * 100
        guard abs(pct) >= 15 else { return nil }
        let direction: Insight.TrendDirection = pct > 0 ? .up : .down
        let phrase = pct > 0 ? "getting longer" : "getting shorter"
        return Insight(
            id: "trend_sleep_duration_\(direction == .up ? "up" : "down")",
            emoji: "🌙",
            title: "Nap duration trend",
            description: "Average nap is \(phrase) — \(formatMinutesHM(cAvg)) vs \(formatMinutesHM(pAvg)) last period.",
            category: .trend, trend: direction
        )
    }

    // MARK: - Sleep patterns

    private func sleepPatterns() -> [Insight] {
        let pool = sleepSessionsInWindow
        guard pool.count >= 3 else { return [] }
        var out: [Insight] = []
        if let i = sleepLongestNapWindowInsight(pool) { out.append(i) }
        if let i = napFrequencyInsight(pool)          { out.append(i) }
        if let i = sleepAfterFeedInsight(pool)        { out.append(i) }
        return out
    }

    /// When are the longest naps? Bucket by 4-hour windows, find the bucket
    /// with the highest average duration if it has at least 2 samples and is
    /// >= 30 min average.
    private func sleepLongestNapWindowInsight(_ pool: [FeedingSession]) -> Insight? {
        var bucketMinutes: [Int: [Int]] = [:]
        for s in pool {
            let bucket = Calendar.current.component(.hour, from: s.startTime) / 4
            bucketMinutes[bucket, default: []].append(s.totalActiveMinutes)
        }
        guard let best = bucketMinutes
            .filter({ $0.value.count >= 2 })
            .max(by: { (avg($0.value)) < (avg($1.value)) })
        else { return nil }
        let bestAvg = Int(avg(best.value).rounded())
        guard bestAvg >= 30 else { return nil }
        return Insight(
            id: "pattern_sleep_longest_window_\(best.key)",
            emoji: "🌙",
            title: "Longest nap window",
            description: "Longest naps are usually between \(bucketLabel(best.key)) (avg \(formatMinutesHM(bestAvg))).",
            category: .pattern, trend: nil
        )
    }

    /// Naps per day across the pattern window.
    private func napFrequencyInsight(_ pool: [FeedingSession]) -> Insight? {
        guard let days = filter.windowDays, days > 0 else { return nil }
        let perDay = Double(pool.count) / Double(days)
        guard perDay >= 1 else { return nil }
        let label = perDay >= 10 ? "\(Int(perDay.rounded()))" : String(format: "%.1f", perDay)
        let period = filter == .week ? "week" : "period"
        return Insight(
            id: "pattern_sleep_frequency",
            emoji: "💤",
            title: "Nap frequency",
            description: "Averaging \(label) nap\(perDay == 1 ? "" : "s") per day this \(period).",
            category: .pattern, trend: nil
        )
    }

    /// How long after a feed does the baby usually fall asleep? Looks at every
    /// nap that started within 2 hours of any prior feed and reports the
    /// typical range.
    private func sleepAfterFeedInsight(_ pool: [FeedingSession]) -> Insight? {
        let feeds = sessions.filter { $0.feedType != .pump && $0.feedType != .sleep }
        guard !feeds.isEmpty else { return nil }

        var gapsMin: [Int] = []
        for nap in pool {
            // Most recent feed that ENDED before this nap started.
            let priorFeed = feeds
                .filter { ($0.endTime ?? $0.startTime) <= nap.startTime }
                .max(by: { ($0.endTime ?? $0.startTime) < ($1.endTime ?? $1.startTime) })
            guard let pf = priorFeed else { continue }
            let feedEnd = pf.endTime ?? pf.startTime
            let gapSec = nap.startTime.timeIntervalSince(feedEnd)
            guard gapSec > 0, gapSec < 2 * 3600 else { continue }
            gapsMin.append(Int(gapSec / 60))
        }
        guard gapsMin.count >= 3 else { return nil }

        let sorted = gapsMin.sorted()
        let low  = sorted[sorted.count / 4]
        let high = sorted[(sorted.count * 3) / 4]
        let range = high == low ? "\(low) min" : "\(low)-\(high) min"
        return Insight(
            id: "pattern_sleep_after_feed",
            emoji: "🍼",
            title: "Sleep after feed",
            description: "Usually falls asleep \(range) after a feed.",
            category: .pattern, trend: nil
        )
    }

    private func sleepHoursPerDay(_ pool: [FeedingSession], days: Int) -> Double {
        let totalMin = pool.reduce(0) { $0 + $1.totalActiveMinutes }
        return Double(totalMin) / Double(days) / 60.0
    }

    private func avg(_ values: [Int]) -> Double {
        guard !values.isEmpty else { return 0 }
        return Double(values.reduce(0, +)) / Double(values.count)
    }

    private func formatMinutesHM(_ minutes: Int) -> String {
        let h = minutes / 60
        let m = minutes % 60
        if h > 0 && m > 0 { return "\(h)h \(m)m" }
        if h > 0          { return "\(h)h" }
        return "\(m)m"
    }

    // MARK: - Helpers

    private func avgActiveMinutes(_ pool: [FeedingSession]) -> Int {
        guard !pool.isEmpty else { return 0 }
        let total = pool.reduce(0) { $0 + $1.totalActiveMinutes }
        return Int((Double(total) / Double(pool.count)).rounded())
    }

    private func avgVolumeMl(_ pool: [FeedingSession]) -> Int {
        let vols = pool.compactMap(\.pumpVolumeMl)
        guard !vols.isEmpty else { return 0 }
        return vols.reduce(0, +) / vols.count
    }

    private func avgGapHours(_ pool: [FeedingSession]) -> Double {
        let sorted = pool.sorted { $0.startTime < $1.startTime }
        guard sorted.count > 1 else { return 0 }
        var total: TimeInterval = 0
        for i in 1..<sorted.count {
            total += sorted[i].startTime.timeIntervalSince(sorted[i - 1].endTime ?? sorted[i - 1].startTime)
        }
        return total / Double(sorted.count - 1) / 3600
    }

    private func avg(_ values: [TimeInterval]) -> TimeInterval {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    private func bucketLabel(_ bucket: Int) -> String {
        let start = bucket * 4
        let end   = start + 4
        let s = formatHourLabel(start)
        let e = formatHourLabel(end == 24 ? 0 : end)
        return "\(s)–\(e)"
    }

    private func formatHourLabel(_ hour: Int) -> String {
        switch hour {
        case 0:           return "12am"
        case 12:          return "12pm"
        case 1...11:      return "\(hour)am"
        default:          return "\(hour - 12)pm"
        }
    }

    private func formatHours(_ hours: Double) -> String {
        if hours < 1 { return "\(Int((hours * 60).rounded()))m" }
        let whole = Int(hours)
        let mins = Int(((hours - Double(whole)) * 60).rounded())
        if mins == 0 { return "\(whole)h" }
        return "\(whole)h \(mins)m"
    }

    private func formatPerDay(_ value: Double) -> String {
        if value >= 10 { return "\(Int(value.rounded()))" }
        return String(format: "%.1f", value)
    }
}
