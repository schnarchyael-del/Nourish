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
        await wipeAllLocalData()
    }

    /// Public entry point for account deletion: empties SwiftData (all feeding
    /// AND pump sessions, since both are `FeedingSession`) and clears the
    /// widget's shared UserDefaults.
    func wipeAllLocalData() async {
        guard let container = modelContainer else { return }
        let context = ModelContext(container)
        if let sessions = try? context.fetch(FetchDescriptor<FeedingSession>()) {
            for session in sessions { context.delete(session) }
            try? context.save()
        }
        SharedFeedSnapshot.clear()
    }

    // MARK: Account deletion

    /// Tear down all cloud data owned by this user, then drop local sync state.
    /// - Deletes every session + the baby profile in the user's family.
    /// - If they're the only family member, deletes the family root doc too.
    /// - If a partner is still in the family, just removes this user from
    ///   `memberUids` so the partner's data survives.
    /// - Deletes the `users/{uid}` document.
    ///
    /// Must be called while the user is still authenticated (Firestore rules
    /// require it). Safe to re-run if a later step fails — every delete is
    /// idempotent.
    func wipeFirestoreAccount(uid: String) async throws {
        let db = Firestore.firestore()
        let userRef = db.collection("users").document(uid)

        let userSnap = try? await userRef.getDocument()
        let familyId = userSnap?.data()?["familyId"] as? String

        if let fid = familyId, !fid.isEmpty {
            let familyRef = db.collection("families").document(fid)
            let familySnap = try? await familyRef.getDocument()
            let memberUids = (familySnap?.data()?["memberUids"] as? [String]) ?? []
            let othersRemain = memberUids.contains { $0 != uid }

            if othersRemain {
                // Partner still using this family — just remove ourselves.
                try? await familyRef.updateData([
                    "memberUids": FieldValue.arrayRemove([uid]),
                ])
            } else {
                // Sole member — nuke everything in the family.
                let sessionsSnap = try? await familyRef.collection("sessions").getDocuments()
                for doc in sessionsSnap?.documents ?? [] {
                    try? await doc.reference.delete()
                }
                try? await familyRef.collection("profile").document("main").delete()
                try? await familyRef.delete()
            }
        }

        try? await userRef.delete()

        // Drop local sync marker so the next signed-in user doesn't trigger
        // the "replace local data?" prompt against a uid that no longer exists.
        UserDefaults.standard.removeObject(forKey: lastUserKey)

        // Detach Firestore listeners.
        FamilyService.shared.handleSignOut()
    }
}
