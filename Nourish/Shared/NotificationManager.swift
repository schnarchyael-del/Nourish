import Foundation
import UserNotifications

final class NotificationManager {
    static let shared = NotificationManager()
    private let reminderID = "com.yael.nourish.feedReminder"
    private init() {}

    func requestPermission() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    func updateReminder(enabled: Bool, hours: Double) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [reminderID])
        guard enabled, hours > 0 else { return }

        let baby = UserDefaults.standard.string(forKey: "babyName") ?? "your baby"
        let hoursLabel: String
        if hours.truncatingRemainder(dividingBy: 1) == 0 {
            hoursLabel = hours == 1 ? "1 hour" : "\(Int(hours)) hours"
        } else {
            hoursLabel = "\(hours) hours"
        }

        let content = UNMutableNotificationContent()
        content.title = "Time to feed \(baby)! 🍼"
        content.body = "It's been \(hoursLabel) since the last session. \(baby) is waiting 💛"
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: hours * 3600, repeats: true)
        let request = UNNotificationRequest(
            identifier: reminderID, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    func sendPartnerSessionNotification(side: String, durationMins: Int) {
        let partnerName = UserDefaults.standard.string(forKey: "partnerName")
        let displayName = (partnerName?.isEmpty == false) ? partnerName! : "Your partner"

        let content = UNMutableNotificationContent()
        content.title = "\(displayName) logged a session 👶"
        content.body = "\(side) · \(durationMins) min · just now"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "com.yael.nourish.partner." + UUID().uuidString,
            content: content,
            trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
