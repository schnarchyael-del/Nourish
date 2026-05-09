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

    init(sessions: [FeedingSession], filter: InsightsTimeFilter, now: Date = .now) {
        self.sessions = sessions
        self.filter = filter
        self.now = now
    }

    /// Suppression windows.
    private let trendSuppressionDays = 7
    private let patternSuppressionDays = 14

    func compute(maxCount: Int = 3) -> [Insight] {
        var pool: [Insight] = []

        // Milestones first — always evaluated against the full session set.
        pool.append(contentsOf: milestones().filter { !milestoneSeen($0.id) })

        // Trends — only when the filter has something to compare against.
        if filter.trendWindowDays != nil {
            pool.append(contentsOf: trends().filter {
                !recentlyShown($0.id, withinDays: trendSuppressionDays)
            })
        }

        // Patterns.
        pool.append(contentsOf: patterns().filter {
            !recentlyShown($0.id, withinDays: patternSuppressionDays)
        })

        return Array(pool.sorted { $0.category.rawValue < $1.category.rawValue }.prefix(maxCount))
    }

    func markShown(_ insights: [Insight]) {
        let defaults = UserDefaults.standard
        var seen = Set(defaults.stringArray(forKey: InsightKey.milestonesSeen) ?? [])
        for insight in insights {
            switch insight.category {
            case .milestone:
                seen.insert(insight.id)
            case .trend, .pattern:
                defaults.set(now.timeIntervalSince1970,
                             forKey: InsightKey.lastShown(insight.id))
            }
        }
        defaults.set(Array(seen), forKey: InsightKey.milestonesSeen)
    }

    // MARK: - Staleness storage

    private enum InsightKey {
        static let milestonesSeen = "insights_milestones_seen"
        static func lastShown(_ id: String) -> String { "insight_lastShown_\(id)" }
    }

    private func milestoneSeen(_ id: String) -> Bool {
        let seen = Set(UserDefaults.standard.stringArray(forKey: InsightKey.milestonesSeen) ?? [])
        return seen.contains(id)
    }

    private func recentlyShown(_ id: String, withinDays days: Int) -> Bool {
        let key = InsightKey.lastShown(id)
        guard let last = UserDefaults.standard.object(forKey: key) as? Double else { return false }
        let secs = Double(days) * 86_400
        return now.timeIntervalSince1970 - last < secs
    }

    // MARK: - Session sets

    private var breastSessions: [FeedingSession] {
        sessions.filter { $0.feedType != .bottle }
    }

    private var sessionsInPatternWindow: [FeedingSession] {
        guard let days = filter.windowDays else { return sessions }
        let start = Calendar.current.date(byAdding: .day, value: -days, to: now) ?? now
        return sessions.filter { $0.startTime >= start }
    }

    // MARK: - Pattern insights

    private func patterns() -> [Insight] {
        var out: [Insight] = []
        let pool = sessionsInPatternWindow.filter { $0.feedType != .bottle }
        guard pool.count >= 5 else { return [] }

        if let i = morningVsEveningInsight(pool) { out.append(i) }
        if let i = sidePreferenceInsight(pool)   { out.append(i) }
        if let i = longestGapWindowInsight(pool) { out.append(i) }
        if let i = busiestWindowInsight(pool)    { out.append(i) }
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

    private func longestGapWindowInsight(_ pool: [FeedingSession]) -> Insight? {
        let sorted = pool.sorted { $0.startTime < $1.startTime }
        guard sorted.count >= 4 else { return nil }
        var bucketGaps: [Int: [TimeInterval]] = [:]
        for i in 1..<sorted.count {
            let gap = sorted[i].startTime.timeIntervalSince(sorted[i - 1].endTime ?? sorted[i - 1].startTime)
            guard gap > 0 else { continue }
            let mid = sorted[i - 1].startTime.addingTimeInterval(gap / 2)
            let bucket = Calendar.current.component(.hour, from: mid) / 4   // 0...5
            bucketGaps[bucket, default: []].append(gap)
        }
        guard let best = bucketGaps
            .filter({ $0.value.count >= 2 })
            .max(by: { avg($0.value) < avg($1.value) })
        else { return nil }
        let bestAvgHours = avg(best.value) / 3600
        guard bestAvgHours > 1.0 else { return nil }
        return Insight(
            id: "pattern_longest_gap_\(best.key)",
            emoji: "🌙",
            title: "Longest stretch",
            description: "Longest stretch is usually between \(bucketLabel(best.key)) (avg \(formatHours(bestAvgHours)))",
            category: .pattern, trend: nil
        )
    }

    private func busiestWindowInsight(_ pool: [FeedingSession]) -> Insight? {
        var counts: [Int: Int] = [:]
        for s in pool {
            let bucket = Calendar.current.component(.hour, from: s.startTime) / 4
            counts[bucket, default: 0] += 1
        }
        let total = counts.values.reduce(0, +)
        guard total >= 6 else { return nil }
        let avgPerBucket = Double(total) / 6.0
        guard let best = counts.max(by: { $0.value < $1.value }),
              Double(best.value) > 1.5 * avgPerBucket
        else { return nil }
        return Insight(
            id: "pattern_busiest_\(best.key)",
            emoji: "⏰",
            title: "Busiest window",
            description: "Most feeds happen between \(bucketLabel(best.key)).",
            category: .pattern, trend: nil
        )
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
        let cBreast = current.filter { $0.feedType != .bottle }
        let pBreast = prior.filter   { $0.feedType != .bottle }
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

    // MARK: - Helpers

    private func avgActiveMinutes(_ pool: [FeedingSession]) -> Int {
        guard !pool.isEmpty else { return 0 }
        let total = pool.reduce(0) { $0 + $1.totalActiveMinutes }
        return Int((Double(total) / Double(pool.count)).rounded())
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
