import SwiftUI
import SwiftData

@main
struct NourishApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @AppStorage("hasRequestedNotifPermission") private var hasRequestedPermission = false
    @AppStorage("reminderEnabled") private var reminderEnabled = false
    @AppStorage("reminderHours")   private var reminderHours: Double = 3

    static let modelContainer: ModelContainer = {
        do {
            return try ModelContainer(for: FeedingSession.self)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    NourishFont.registerAll()
                    FirestoreService.shared.attach(modelContainer: NourishApp.modelContainer)
                    if !hasRequestedPermission {
                        NotificationManager.shared.requestPermission()
                        hasRequestedPermission = true
                    }
                    if reminderEnabled {
                        NotificationManager.shared.updateReminder(enabled: true, hours: reminderHours)
                    }
                }
        }
        .modelContainer(NourishApp.modelContainer)
    }
}
