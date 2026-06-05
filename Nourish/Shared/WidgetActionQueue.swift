import Foundation

/// Pending widget action — written from the widget extension when the user
/// taps an interactive button, drained by the main app on foreground.
///
/// The widget process has no direct SwiftData/Firestore access, so it
/// only updates the shared snapshot (so the widget itself can refresh
/// immediately) and appends a record here describing what the app should
/// persist on the next launch.
struct WidgetAction: Codable {
    enum Kind: String, Codable {
        case endSleep
        case endFeed
        case pauseToggleFeed   // pause-state was flipped at `timestamp`
        case switchSide        // side was switched at `timestamp`
    }
    let kind: Kind
    /// Wall-clock seconds. Always set; meaning varies by kind:
    ///   - endSleep:        the wake-up moment
    ///   - endFeed:         the end-of-session moment
    ///   - pauseToggleFeed: the moment pause/resume was tapped
    ///   - switchSide:      the moment the side was switched
    let timestamp: Double
    /// Sleep-specific: when the sleep started (so the app can create the
    /// session even after the active flag has been cleared).
    var sleepStartTs: Double?
    /// Feed-specific: minutes accumulated on each side at the moment of
    /// the widget tap. Lets the app save accurate split durations even
    /// when the action happened outside the running SessionStore.
    var leftMinutes: Int?
    var rightMinutes: Int?
    /// Switch-side specific: the new side ("left" / "right").
    var newSide: String?
    /// Feed-specific: the session start time (for end actions when the
    /// in-memory store is gone).
    var feedStartTs: Double?
    /// Feed-specific: the current side at the moment of the action.
    var currentSide: String?
}

enum WidgetActionQueue {
    private static let suiteName = "group.com.yael.nourish"
    private static let key       = "widget.pendingActions"

    /// Append an action to the queue, atomically.
    static func append(_ action: WidgetAction) {
        guard let d = UserDefaults(suiteName: suiteName) else { return }
        var pool = loadRaw(d)
        if let data = try? JSONEncoder().encode(action),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            pool.append(dict)
        }
        d.set(pool, forKey: key)
    }

    /// Read all pending actions and clear the queue. Order preserved (oldest first).
    static func drain() -> [WidgetAction] {
        guard let d = UserDefaults(suiteName: suiteName) else { return [] }
        let pool = loadRaw(d)
        d.removeObject(forKey: key)

        var actions: [WidgetAction] = []
        for dict in pool {
            guard let data = try? JSONSerialization.data(withJSONObject: dict),
                  let a = try? JSONDecoder().decode(WidgetAction.self, from: data)
            else { continue }
            actions.append(a)
        }
        return actions
    }

    private static func loadRaw(_ d: UserDefaults) -> [[String: Any]] {
        (d.array(forKey: key) as? [[String: Any]]) ?? []
    }
}
