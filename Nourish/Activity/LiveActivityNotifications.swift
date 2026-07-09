import Foundation
import os.log

// Standalone declarations for the notification name and shared logger so
// any file in the Nourish app target (SessionStore, SleepView,
// NourishLiveActivityIntents, LiveActivityManager) can reference them
// without depending on each other's compile order or availability gates.

extension Notification.Name {
    /// Posted by every LiveActivityIntent after it mutates shared App
    /// Group state. SessionStore listens on the main thread and
    /// reconciles its in-memory @Observable properties from the snapshot.
    static let liveActivityStateChanged = Notification.Name("liveActivityStateChanged")
}

/// Filter Console.app by subsystem `com.yael.nourish` category
/// `LiveActivity` to see every intent firing in real time.
let liveActivityLog = Logger(subsystem: "com.yael.nourish", category: "LiveActivity")
