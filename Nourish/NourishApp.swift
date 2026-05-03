import SwiftUI
import SwiftData

@main
struct NourishApp: App {
    @AppStorage("hasRequestedNotifPermission") private var hasRequestedPermission = false
    @AppStorage("reminderEnabled") private var reminderEnabled = false
    @AppStorage("reminderHours")   private var reminderHours: Double = 3

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    NourishFont.registerAll()
                    if !hasRequestedPermission {
                        NotificationManager.shared.requestPermission()
                        hasRequestedPermission = true
                    }
                    if reminderEnabled {
                        NotificationManager.shared.updateReminder(enabled: true, hours: reminderHours)
                    }
                }
        }
        .modelContainer(for: FeedingSession.self)
    }
}
