import Foundation
import FirebaseAnalytics

/// Single funnel for all app analytics. Forwards to Firebase Analytics.
/// Note: events only ship if `IS_ANALYTICS_ENABLED` is true in
/// GoogleService-Info.plist or `Analytics.setAnalyticsCollectionEnabled(true)`
/// has been called at runtime.
enum AnalyticsService {

    // MARK: Generic

    static func log(_ name: String, _ parameters: [String: Any]? = nil) {
        Analytics.logEvent(name, parameters: parameters)
    }

    // MARK: Sessions

    static func sessionStarted(startingSide: String, feedType: String) {
        log("session_started", [
            "starting_side": startingSide,
            "feed_type": feedType,
        ])
    }

    static func sessionCompleted(totalSeconds: Int,
                                 leftSeconds: Int,
                                 rightSeconds: Int,
                                 feedType: String) {
        log("session_completed", [
            "total_duration_seconds": totalSeconds,
            "left_duration_seconds": leftSeconds,
            "right_duration_seconds": rightSeconds,
            "feed_type": feedType,
        ])
    }

    static func sessionDiscarded() {
        log("session_discarded")
    }

    static func sessionEdited() {
        log("session_edited")
    }

    static func sessionDeleted() {
        log("session_deleted")
    }

    static func pumpSessionStarted(side: String) {
        log("pump_session_started", ["side": side])
    }

    static func pumpSessionCompleted(side: String, durationSeconds: Int, volumeMl: Int?) {
        var params: [String: Any] = [
            "side": side,
            "duration_seconds": durationSeconds,
        ]
        if let v = volumeMl { params["volume_ml"] = v }
        log("pump_session_completed", params)
    }

    // MARK: Feature usage

    static func exportCSV() {
        log("export_csv")
    }

    static func statsViewed() {
        log("stats_viewed")
    }

    static func historyViewed() {
        log("history_viewed")
    }

    // MARK: Account

    static func signInApple() {
        log("sign_in_apple")
    }

    static func signInEmail() {
        log("sign_in_email")
    }

    static func signOut() {
        log("sign_out")
    }

    static func accountCreatedEmail() {
        log("account_created_email")
    }

    // MARK: Onboarding

    static func babyProfileCreated() {
        log("baby_profile_created")
    }

    static func babyProfileEdited() {
        log("baby_profile_edited")
    }
}
