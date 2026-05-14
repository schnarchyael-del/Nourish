import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore
import SwiftData

/// Thin coordinator around Firebase Auth + `FamilyService`. Push/pull of
/// feeding-session and baby-profile data is delegated to `FamilyService`,
/// which scopes everything to the current shared family. This class still
/// owns the auth-state listener, the "account switch" prompt, and the
/// `hasPendingAccountSwitch` UI gate.
@MainActor
final class FirestoreService: ObservableObject {
    static let shared = FirestoreService()

    @Published private(set) var isSyncing: Bool = false
    @Published var hasPendingAccountSwitch: Bool = false

    struct PendingSwitch {
        let newUid: String
        let previousUid: String
    }
    private(set) var pendingAccountSwitch: PendingSwitch?

    private var modelContainer: ModelContainer?
    private var authHandle: AuthStateDidChangeListenerHandle?
    private let lastUserKey = "lastSyncedFirebaseUid"

    private init() {}

    /// Wire SwiftData + start observing auth. Call once after FirebaseApp.configure().
    func attach(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        FamilyService.shared.attach(modelContainer: modelContainer)

        guard authHandle == nil else { return }
        authHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                guard let self else { return }
                if let user {
                    self.handleSignIn(uid: user.uid)
                } else {
                    FamilyService.shared.handleSignOut()
                }
            }
        }
    }

    private func handleSignIn(uid: String) {
        let last = UserDefaults.standard.string(forKey: lastUserKey)
        if let last, last != uid {
            pendingAccountSwitch = PendingSwitch(newUid: uid, previousUid: last)
            hasPendingAccountSwitch = true
        } else {
            UserDefaults.standard.set(uid, forKey: lastUserKey)
            Task {
                isSyncing = true
                await FamilyService.shared.handleSignIn(uid: uid)
                isSyncing = false
            }
        }
    }

    /// User accepted the "replace local data" prompt — wipe local SwiftData
    /// and re-attach to the new account's family (listeners will repopulate).
    func confirmAccountSwitch() async {
        guard let pending = pendingAccountSwitch else { return }
        UserDefaults.standard.set(pending.newUid, forKey: lastUserKey)
        hasPendingAccountSwitch = false
        pendingAccountSwitch = nil

        isSyncing = true
        await wipeLocalSessions()
        FamilyService.shared.handleSignOut()
        await FamilyService.shared.handleSignIn(uid: pending.newUid)
        isSyncing = false
    }

    /// User declined — sign back out so we don't sit in a "signed in but unsynced" state.
    func cancelAccountSwitch() {
        hasPendingAccountSwitch = false
        pendingAccountSwitch = nil
        try? Auth.auth().signOut()
    }

    // MARK: Public push helpers (call after local saves)

    /// Push a single session to the current family. No-op when not signed
    /// into a family or during a pending account switch.
    func pushSession(_ session: FeedingSession) async {
        guard !hasPendingAccountSwitch else { return }
        await FamilyService.shared.pushSession(session)
    }

    /// Delete a session from the current family. No-op when not signed in.
    func deleteSession(id: UUID) async {
        guard !hasPendingAccountSwitch else { return }
        await FamilyService.shared.deleteSession(id: id)
    }

    /// Push the @AppStorage baby profile to the current family.
    func pushProfile() async {
        guard !hasPendingAccountSwitch else { return }
        await FamilyService.shared.pushProfile()
    }

    // MARK: Local cleanup

    private func wipeLocalSessions() async {
        guard let container = modelContainer else { return }
        let context = ModelContext(container)
        if let sessions = try? context.fetch(FetchDescriptor<FeedingSession>()) {
            for session in sessions { context.delete(session) }
            try? context.save()
        }
        SharedFeedSnapshot.clear()
    }
}
