import SwiftUI
import SwiftData
import UIKit
import Combine

/// Sleep tab. Two states:
/// - Awake: card + big "Baby fell asleep" CTA + today's nap list
/// - Sleeping: live timer + "Baby woke up" CTA
///
/// Active sleep is persisted in @AppStorage("activeSleepStartedAt") so a
/// force-quit, crash, or reboot mid-sleep doesn't lose the in-progress
/// session. The timer is computed from `now - storedStart`, so the screen
/// is correct whenever the user re-opens the app.
struct SleepView: View {
    @Environment(\.nourishColors) private var c
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var tooltips: TooltipManager

    @AppStorage("babyName") private var babyName = "Lily"
    @AppStorage("activeSleepStartedAt") private var activeSleepStartedAt: Double = 0

    @Query(sort: \FeedingSession.startTime, order: .reverse)
    private var allSessions: [FeedingSession]

    @State private var notes: String = ""
    @State private var showEndFeedAlert = false

    static let sleepAccent = Color(hex: "534AB7")
    /// Soft lavender in light mode; a tinted-dark variant in dark mode so it
    /// composes correctly against the warm dark background (a fixed light
    /// lavender shows up as grey/washed when laid over the dark surface).
    /// Mirrors how the widget's bottleBg / pumpBg switch tints between modes.
    static let sleepBg = Color(UIColor { trait in
        if trait.userInterfaceStyle == .dark {
            return UIColor(red: 83/255, green: 74/255, blue: 183/255, alpha: 0.22)
        }
        return UIColor(red: 238/255, green: 237/255, blue: 254/255, alpha: 1.0)
    })
    static let sleepBorder = Color(hex: "534AB7").opacity(0.18)

    private var isSleeping: Bool { activeSleepStartedAt > 0 }
    private var sleepStartDate: Date { Date(timeIntervalSince1970: activeSleepStartedAt) }

    private var sleepSessions: [FeedingSession] {
        allSessions.filter { $0.feedType == .sleep }
    }
    private var todaySleepSessions: [FeedingSession] {
        let dayStart = Calendar.current.startOfDay(for: .now)
        return sleepSessions.filter { $0.startTime >= dayStart }
    }
    private var todayTotalMinutes: Int {
        todaySleepSessions.reduce(0) { $0 + $1.totalActiveMinutes }
    }
    private var lastCompletedSleep: FeedingSession? {
        sleepSessions.first(where: { $0.endTime != nil })
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                Group {
                    if isSleeping {
                        sleepingContent
                    } else {
                        awakeContent
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
        }
        .background(c.bg)
        .alert("\(babyName) is feeding", isPresented: $showEndFeedAlert) {
            Button("Cancel", role: .cancel) {}
            Button("End feed & sleep") {
                endActiveFeedAndStartSleep()
            }
        } message: {
            Text("Would you like to end the feed and start sleep?")
        }
        .onAppear {
            if !tooltips.hasSeen(.sleepTab) {
                tooltips.show(.sleepTab)
            }
        }
        // Realtime sync — same belt-and-suspenders pattern as ActiveSessionView.
        // Darwin notification is the fast lane; 1Hz polling is the safety net
        // in case the widget-process notification gets dropped.
        .onReceive(NotificationCenter.default.publisher(for: WidgetSyncBridge.changed)) { _ in
            absorbWidgetSleepEnd()
        }
        .onReceive(Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()) { _ in
            absorbWidgetSleepEnd()
        }
    }

    /// If the shared snapshot says no sleep is in progress but our local
    /// `activeSleepStartedAt` flag is still set, the widget just ended the
    /// nap. Clear the local flag here — the drainer running on next
    /// foreground will persist the FeedingSession.
    private func absorbWidgetSleepEnd() {
        guard activeSleepStartedAt > 0 else { return }
        let sharedSleeping = UserDefaults(suiteName: "group.com.yael.nourish")?
            .bool(forKey: "widget.isBabySleeping") ?? false
        if !sharedSleeping {
            activeSleepStartedAt = 0
        }
    }

    // MARK: Header

    private var header: some View {
        HStack {
            Text("Sleep")
                .font(.nSerif(28))
                .foregroundStyle(c.ink)
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.top, 26)
        .padding(.bottom, 10)
    }

    // MARK: Awake state

    private var awakeContent: some View {
        VStack(spacing: 16) {
            awakeCard
            startSleepButton
            if !todaySleepSessions.isEmpty {
                todaySection
            }
        }
    }

    private var awakeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Text("☀️").font(.nSans(28))
                Text("\(babyName) is awake")
                    .font(.nSerif(22))
                    .foregroundStyle(c.ink)
                Spacer()
            }
            if let last = lastCompletedSleep {
                Text("Last sleep: \(last.startTime.formatted(date: .omitted, time: .shortened)) · \(formatHM(last.totalActiveMinutes))")
                    .font(.nSans(13))
                    .foregroundStyle(c.muted)
            } else {
                Text("No naps tracked yet. Tap below when baby falls asleep.")
                    .font(.nSans(13))
                    .foregroundStyle(c.muted)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(c.surface)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(c.border, lineWidth: 1))
    }

    private var startSleepButton: some View {
        Button {
            if Self.hasActiveFeed {
                showEndFeedAlert = true
            } else {
                doStartSleep()
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "moon.fill").font(.nSans(17))
                Text("Baby fell asleep").font(.nSans(17, weight: .bold))
            }
            .foregroundStyle(Self.sleepAccent)
            .frame(maxWidth: .infinity)
            .frame(height: 60)
            .background(Self.sleepBg)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Self.sleepBorder, lineWidth: 1.5))
        }
        .buttonStyle(ScaleButtonStyle(scale: 0.97))
    }

    private var todaySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Today")
                    .font(.nSans(11, weight: .bold))
                    .foregroundStyle(c.muted)
                    .kerning(0.09 * 11)
                    .textCase(.uppercase)
                Spacer()
                Text("\(formatHM(todayTotalMinutes)) total")
                    .font(.nSans(11, weight: .bold))
                    .foregroundStyle(Self.sleepAccent)
                    .kerning(0.09 * 11)
                    .textCase(.uppercase)
            }
            .padding(.horizontal, 6)
            .padding(.top, 8)

            VStack(spacing: 8) {
                ForEach(todaySleepSessions) { session in
                    sleepRow(session)
                }
            }
        }
    }

    private func sleepRow(_ s: FeedingSession) -> some View {
        HStack(spacing: 14) {
            Circle().fill(Self.sleepAccent).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(timeRange(s))
                    .font(.nSans(15, weight: .semibold))
                    .foregroundStyle(c.ink)
                if let note = s.notes, !note.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "note.text").font(.nSans(11))
                        Text(note).font(.nSans(12)).lineLimit(1)
                    }
                    .foregroundStyle(c.muted)
                }
            }
            Spacer()
            Text(formatHM(s.totalActiveMinutes))
                .font(.nSans(14, weight: .semibold))
                .foregroundStyle(Self.sleepAccent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(c.surface)
        .overlay(
            Rectangle().fill(Self.sleepAccent).frame(width: 3),
            alignment: .leading
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(c.border, lineWidth: 1))
        .contextMenu {
            Button(role: .destructive) {
                deleteSession(s)
            } label: {
                Label("Delete nap", systemImage: "trash")
            }
        }
    }

    // MARK: Sleeping state

    private var sleepingContent: some View {
        VStack(spacing: 16) {
            sleepingCard
            wakeUpButton
            noteField
            if !todaySleepSessions.isEmpty {
                todaySection
            }
        }
    }

    private var sleepingCard: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(spacing: 14) {
                HStack(spacing: 12) {
                    Text("🌙").font(.nSans(28))
                    Text("\(babyName) is sleeping")
                        .font(.nSerif(22))
                        .foregroundStyle(c.ink)
                }
                .padding(.top, 28)

                Text(elapsedString(now: context.date))
                    .font(.nSerif(72))
                    .foregroundStyle(Self.sleepAccent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .contentTransition(.numericText())

                Text("Fell asleep at \(sleepStartDate.formatted(date: .omitted, time: .shortened))")
                    .font(.nSans(13))
                    .foregroundStyle(c.muted)
                    .padding(.bottom, 28)
            }
            .frame(maxWidth: .infinity)
            // Match the standard card bg used everywhere else in the app
            // (warm off-white / warm dark brown) — purple stays as text + a
            // subtle border tint, never as a card fill.
            .background(c.surface)
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(Self.sleepBorder, lineWidth: 1))
        }
    }

    private var wakeUpButton: some View {
        Button {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            endSleep()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "sun.max.fill").font(.nSans(17))
                Text("Baby woke up").font(.nSans(17, weight: .bold))
            }
            .foregroundStyle(Self.sleepAccent)
            .frame(maxWidth: .infinity)
            .frame(height: 60)
            .background(Self.sleepBg)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Self.sleepBorder, lineWidth: 1.5))
        }
        .buttonStyle(ScaleButtonStyle(scale: 0.97))
    }

    private var noteField: some View {
        HStack(spacing: 10) {
            Image(systemName: "note.text").font(.nSans(14)).foregroundStyle(c.muted)
            TextField(
                "",
                text: $notes,
                prompt: Text("Add a note").foregroundColor(c.muted)
            )
            .font(.nSans(14))
            .foregroundStyle(c.ink)
            .tint(Self.sleepAccent)
            .submitLabel(.done)
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
        .background(c.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(c.border, lineWidth: 1))
    }

    // MARK: Actions

    private func endSleep() {
        let start = sleepStartDate
        let end = Date.now
        let duration = max(0, Int(end.timeIntervalSince(start)))

        let session = FeedingSession(
            startTime: start,
            feedType: .sleep,
            endTime: end,
            notes: notes.isEmpty ? nil : notes
        )
        modelContext.insert(session)
        try? modelContext.save()
        Task { await FirestoreService.shared.pushSession(session) }
        AnalyticsService.sleepEnded(durationSeconds: duration)

        activeSleepStartedAt = 0
        SharedFeedSnapshot.clearActiveSleep()
        notes = ""
    }

    private func deleteSession(_ s: FeedingSession) {
        let id = s.id
        modelContext.delete(s)
        try? modelContext.save()
        Task { await FirestoreService.shared.deleteSession(id: id) }
    }

    // MARK: Formatting helpers

    private func elapsedString(now: Date) -> String {
        let secs = max(0, Int(now.timeIntervalSince(sleepStartDate)))
        let h = secs / 3600
        let m = (secs % 3600) / 60
        let s = secs % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }

    // MARK: Sleep start (with feed-conflict guard)

    /// Reachable in normal UI is rare (ContentView routes active feeds to
    /// the ActiveSessionView regardless of selectedTab), but stale shared
    /// state could carry over after a crash. If the widget snapshot says
    /// a feed is in progress, give the user a chance to acknowledge it
    /// before we tear it down.
    static var hasActiveFeed: Bool {
        UserDefaults(suiteName: "group.com.yael.nourish")?
            .bool(forKey: "widget.isSessionActive") ?? false
    }

    fileprivate func doStartSleep() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        Self.startActiveSleep()
    }

    /// Starts an active sleep from outside this view (e.g. the pump screen).
    /// Same persistence + widget sync as the in-view "Baby fell asleep"
    /// button — writing UserDefaults.standard directly updates the
    /// @AppStorage-backed UI too.
    static func startActiveSleep() {
        let now = Date.now
        UserDefaults.standard.set(now.timeIntervalSince1970, forKey: "activeSleepStartedAt")
        SharedFeedSnapshot.setActiveSleep(startedAt: now)
        AnalyticsService.sleepStarted()
    }

    fileprivate func endActiveFeedAndStartSleep() {
        // We don't hold a reference to SessionStore / PumpStore here; the
        // shared snapshot is the most authoritative cross-process state.
        // Clearing it stops the widget from reporting an active feed; the
        // in-app stores can only be active if the user is viewing the
        // active-session screen (which is unreachable from SleepView).
        SharedFeedSnapshot.clearActiveSession()
        doStartSleep()
    }

    // MARK: External coordination
    //
    // Other screens (HomeView's feed buttons, etc.) need to ask "is the
    // baby currently sleeping?" and, on user confirmation, end the active
    // sleep so a new activity can start. These helpers keep that flow in
    // one place — same persistence + cloud sync as the in-view "Baby woke up"
    // button.

    /// Reads the persisted sleep flag without instantiating the view.
    /// Cheap; safe to call from any tap handler.
    static var hasActiveSleep: Bool {
        UserDefaults.standard.double(forKey: "activeSleepStartedAt") > 0
    }

    /// Saves the in-progress sleep as a `.sleep` FeedingSession (start →
    /// now), clears the active-sleep flag in both the app's AppStorage
    /// and the widget's shared UserDefaults, and pushes to Firestore.
    /// No-op if no sleep is active.
    static func endActiveSleep(modelContext: ModelContext) {
        let ts = UserDefaults.standard.double(forKey: "activeSleepStartedAt")
        guard ts > 0 else { return }
        let start = Date(timeIntervalSince1970: ts)
        let end = Date.now
        let duration = max(0, Int(end.timeIntervalSince(start)))

        let session = FeedingSession(
            startTime: start,
            feedType: .sleep,
            endTime: end
        )
        modelContext.insert(session)
        try? modelContext.save()
        Task { await FirestoreService.shared.pushSession(session) }
        AnalyticsService.sleepEnded(durationSeconds: duration)

        UserDefaults.standard.set(0.0, forKey: "activeSleepStartedAt")
        SharedFeedSnapshot.clearActiveSleep()
    }

    /// "1h 45m" / "45m" / "2h"
    static func formatHM(_ minutes: Int) -> String {
        let h = minutes / 60
        let m = minutes % 60
        if h > 0 && m > 0 { return "\(h)h \(m)m" }
        if h > 0          { return "\(h)h" }
        return "\(m)m"
    }

    private func formatHM(_ minutes: Int) -> String {
        Self.formatHM(minutes)
    }

    private func timeRange(_ s: FeedingSession) -> String {
        let start = s.startTime.formatted(date: .omitted, time: .shortened)
        if let end = s.endTime {
            return "\(start) - \(end.formatted(date: .omitted, time: .shortened))"
        }
        return start
    }
}
