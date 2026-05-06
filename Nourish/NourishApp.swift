import SwiftUI
import SwiftData

@main
struct NourishApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @AppStorage("hasRequestedNotifPermission") private var hasRequestedPermission = false

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
                }
        }
        .modelContainer(NourishApp.modelContainer)
    }
}
