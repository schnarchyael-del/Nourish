import Foundation
import SwiftData
import UserNotifications

final class NotificationManager {
    static let shared = NotificationManager()
    private let reminderID    = "com.yael.nourish.feedReminder"
    private let sessionAlarmID = "com.yael.nourish.sessionAlarm"
    private init() {}

    // MARK: Authorization

    func requestPermission() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    // MARK: Feed reminder

    /// Cancels any pending reminder, finds the most recent saved session, and
    /// re-schedules a one-shot reminder for `lastEndTime + hours`. Reads
    /// `reminderEnabled` + `reminderHours` from UserDefaults; cancels if disabled
    /// or if the trigger time has already passed.
    func refreshReminder(modelContainer: ModelContainer) {
        cancelReminder()

        let enabled = (UserDefaults.standard.object(forKey: "reminderEnabled") as? Bool) ?? false
        let hours   = UserDefaults.standard.double(forKey: "reminderHours")
        guard enabled, hours > 0 else {
            print("[NotificationManager] Reminder disabled — nothing scheduled.")
            return
        }

        let context = ModelContext(modelContainer)
        var descriptor = FetchDescriptor<FeedingSession>(
            sortBy: [SortDescriptor(\.startTime, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        let anchor = (try? context.fetch(descriptor).first).map { $0.endTime ?? $0.startTime }
                  ?? Date.now

        scheduleReminder(after: anchor, hours: hours)
    }

    /// Schedule a one-shot reminder relative to a specific session end time.
    func scheduleReminder(after lastSessionEnd: Date, hours: Double) {
        cancelReminder()
        guard hours > 0 else { return }

        let interval     = hours * 3600
        let fireDate     = lastSessionEnd.addingTimeInterval(interval)
        let timeUntil    = fireDate.timeIntervalSinceNow
        guard timeUntil > 0 else {
            print("[NotificationManager] Reminder skipped — last session was \(Int(-timeUntil))s ago, already past the \(hours)h mark.")
            return
        }

        let baby = UserDefaults.standard.string(forKey: "babyName") ?? "your baby"
        let hoursLabel = formatHoursLabel(hours)

        let content = UNMutableNotificationContent()
        content.title = "Time to feed \(baby)! 🍼"
        content.body  = "It's been \(hoursLabel) since the last session. \(baby) is waiting 💛"
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: timeUntil, repeats: false)
        let request = UNNotificationRequest(identifier: reminderID, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)

        print("[NotificationManager] Scheduled reminder for \(fireDate) (in \(Int(timeUntil))s, anchored to \(lastSessionEnd))")
    }

    func cancelReminder() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [reminderID])
    }

    private func formatHoursLabel(_ hours: Double) -> String {
        if hours.truncatingRemainder(dividingBy: 1) == 0 {
            return hours == 1 ? "1 hour" : "\(Int(hours)) hours"
        }
        return "\(hours) hours"
    }

    // MARK: Session alarm (active session "switch sides" / time-limit)

    /// Schedule a local notification to fire `seconds` from now. Cancels any
    /// existing pending alarm first. Used so the alarm reaches the user when
    /// the app is backgrounded or the phone is locked.
    func scheduleSessionAlarm(seconds: TimeInterval) {
        cancelSessionAlarm()
        guard seconds > 0 else { return }

        // Idempotent — no-op if already granted, prompts only if .notDetermined.
        requestPermission()

        let mins = Int(seconds.rounded() / 60)
        let content = UNMutableNotificationContent()
        content.title = "Nourish"
        content.body  = "Session reached \(mins) min — time to switch sides? 🤱"
        content.sound = .default
        content.categoryIdentifier = "SESSION_ALARM"

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        let request = UNNotificationRequest(identifier: sessionAlarmID, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)

        let fireDate = Date.now.addingTimeInterval(seconds)
        print("[NotificationManager] Scheduled session alarm for \(fireDate) (in \(Int(seconds))s)")
    }

    func cancelSessionAlarm() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [sessionAlarmID])
    }

    // MARK: Partner notification (existing)

    func sendPartnerSessionNotification(side: String, durationMins: Int) {
        let partnerName = UserDefaults.standard.string(forKey: "partnerName")
        let displayName = (partnerName?.isEmpty == false) ? partnerName! : "Your partner"

        let content = UNMutableNotificationContent()
        content.title = "\(displayName) logged a session 👶"
        content.body  = "\(side) · \(durationMins) min · just now"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "com.yael.nourish.partner." + UUID().uuidString,
            content: content,
            trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
