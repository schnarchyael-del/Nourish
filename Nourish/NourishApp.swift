import SwiftUI
import SwiftData

@main
struct NourishApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @AppStorage("hasRequestedNotifPermission") private var hasRequestedPermission = false
    @Environment(\.scenePhase) private var scenePhase

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
                    NotificationManager.shared.refreshReminder(modelContainer: NourishApp.modelContainer)
                    SharedFeedSnapshot.refresh(modelContainer: NourishApp.modelContainer)
                    // Reconnect any in-flight Live Activity (if the app was
                    // backgrounded / restarted while a feed or sleep was
                    // still on the lock screen).
                    if #available(iOS 16.2, *) {
                        LiveActivityManager.shared.restoreOnLaunch()
                    }
                }
        }
        .modelContainer(NourishApp.modelContainer)
    }
}
