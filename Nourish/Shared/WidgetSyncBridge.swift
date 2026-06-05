import Foundation

/// Cross-process change notifier between the widget extension and the main
/// app, built on Darwin notifications (the only documented way to notify
/// across process boundaries on iOS).
///
/// Why this exists: `UserDefaults.didChangeNotification` does NOT fire for
/// writes made by another process — even for App Group suites. So when the
/// widget intent updates shared UserDefaults, the app has no built-in way
/// to know. A Darwin notification fixes that without polling.
///
/// Usage:
///   - Widget side: call `WidgetSyncBridge.postChanged()` after every
///     shared-UserDefaults mutation.
///   - App side: call `WidgetSyncBridge.startListening()` once at launch.
///     Then any view can observe `NotificationCenter.default.publisher(
///     for: WidgetSyncBridge.changed)` and react.
enum WidgetSyncBridge {
    /// Darwin notification name. Lives outside any specific suite/process.
    private static let darwinName = "me.nourish.widget.snapshot.changed" as CFString

    /// The Swift-side notification re-posted by `startListening` so views
    /// can use the standard `NotificationCenter` / `onReceive` plumbing.
    static let changed = Notification.Name("WidgetSyncBridge.changed")

    /// Broadcast that the shared snapshot just changed. Cheap (kernel-level
    /// notification) — safe to call from every widget intent.
    static func postChanged() {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(darwinName),
            nil, nil, true
        )
    }

    /// Start re-posting Darwin notifications onto `NotificationCenter.default`
    /// so SwiftUI views can subscribe normally. Idempotent — safe to call
    /// multiple times.
    static func startListening() {
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            nil,
            { _, _, _, _, _ in
                // C callback — can't capture, can't touch Swift types other
                // than via DispatchQueue.main. Post on main so onReceive
                // handlers run on the right actor.
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: WidgetSyncBridge.changed,
                        object: nil
                    )
                }
            },
            darwinName,
            nil,
            .deliverImmediately
        )
    }
}
