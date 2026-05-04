import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore
import SwiftData

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

    /// Wire SwiftData and start observing auth state. Call once after FirebaseApp.configure().
    func attach(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        guard authHandle == nil else { return }
        authHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                guard let self else { return }
                if let user {
                    self.handleSignIn(uid: user.uid)
                }
                // On sign-out we just stop. Local data is preserved by design.
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
            Task { await mergeSyncForUser(uid: uid) }
        }
    }

    /// User accepted the "replace local data" prompt — wipe local, then pull cloud.
    func confirmAccountSwitch() async {
        guard let pending = pendingAccountSwitch else { return }
        UserDefaults.standard.set(pending.newUid, forKey: lastUserKey)
        hasPendingAccountSwitch = false
        pendingAccountSwitch = nil
        await wipeLocalSessions()
        await pullSessions(uid: pending.newUid)
        await pullProfile(uid: pending.newUid)
    }

    /// User declined — sign back out so we don't sit in a "signed in but unsynced" state.
    func cancelAccountSwitch() {
        hasPendingAccountSwitch = false
        pendingAccountSwitch = nil
        try? Auth.auth().signOut()
    }

    // MARK: Public push helpers (call after local saves)

    /// Push a single session to Firestore. No-op when not signed in or during a pending switch.
    func pushSession(_ session: FeedingSession) async {
        guard let uid = Auth.auth().currentUser?.uid,
              !hasPendingAccountSwitch else { return }
        do {
            try await sessionsCollection(uid: uid)
                .document(session.id.uuidString)
                .setData(session.toFirestoreData(), merge: true)
        } catch {
            print("FirestoreService.pushSession failed: \(error)")
        }
    }

    /// Push the @AppStorage baby profile to Firestore.
    func pushProfile() async {
        guard let uid = Auth.auth().currentUser?.uid,
              !hasPendingAccountSwitch else { return }
        let payload = currentProfilePayload()
        do {
            try await profileDocument(uid: uid).setData(payload, merge: true)
        } catch {
            print("FirestoreService.pushProfile failed: \(error)")
        }
    }

    // MARK: Sync flows

    private func mergeSyncForUser(uid: String) async {
        isSyncing = true
        defer { isSyncing = false }

        let cloudSessions = await fetchCloudSessions(uid: uid)
        let cloudByID = Dictionary(uniqueKeysWithValues: cloudSessions.map { ($0.id, $0) })

        guard let container = modelContainer else { return }
        let context = ModelContext(container)
        guard let localSessions = try? context.fetch(FetchDescriptor<FeedingSession>()) else { return }

        // Cloud-wins: overwrite local fields when IDs collide; insert cloud-only sessions locally.
        for cloud in cloudSessions {
            if let local = localSessions.first(where: { $0.id == cloud.id }) {
                local.startTime         = cloud.startTime
                local.endTime           = cloud.endTime
                local.feedType          = cloud.feedType
                local.bottleContentType = cloud.bottleContentType
                local.bottleAmountMl    = cloud.bottleAmountMl
                local.leftDurationMins  = cloud.leftDurationMins
                local.rightDurationMins = cloud.rightDurationMins
                local.loggedByDeviceID  = cloud.loggedByDeviceID
            } else {
                context.insert(cloud)
            }
        }
        try? context.save()

        // Push local-only sessions up.
        for local in localSessions where cloudByID[local.id] == nil {
            await pushSessionDirect(local, uid: uid)
        }

        await reconcileProfile(uid: uid)
    }

    private func pullSessions(uid: String) async {
        isSyncing = true
        defer { isSyncing = false }
        let cloudSessions = await fetchCloudSessions(uid: uid)
        guard let container = modelContainer else { return }
        let context = ModelContext(container)
        for cloud in cloudSessions {
            context.insert(cloud)
        }
        try? context.save()
    }

    private func pullProfile(uid: String) async {
        do {
            let snap = try await profileDocument(uid: uid).getDocument()
            applyProfile(from: snap.data())
        } catch {
            print("FirestoreService.pullProfile failed: \(error)")
        }
    }

    /// On a same-account merge, prefer cloud profile if present; otherwise upload local.
    private func reconcileProfile(uid: String) async {
        do {
            let snap = try await profileDocument(uid: uid).getDocument()
            if snap.exists, let data = snap.data(), !data.isEmpty {
                applyProfile(from: data)
            } else {
                await pushProfile()
            }
        } catch {
            print("FirestoreService.reconcileProfile failed: \(error)")
        }
    }

    // MARK: Local-only ops

    private func wipeLocalSessions() async {
        guard let container = modelContainer else { return }
        let context = ModelContext(container)
        if let sessions = try? context.fetch(FetchDescriptor<FeedingSession>()) {
            for session in sessions { context.delete(session) }
            try? context.save()
        }
    }

    // MARK: Firestore plumbing

    private func sessionsCollection(uid: String) -> CollectionReference {
        Firestore.firestore()
            .collection("users").document(uid)
            .collection("sessions")
    }

    private func profileDocument(uid: String) -> DocumentReference {
        Firestore.firestore()
            .collection("users").document(uid)
            .collection("profile").document("main")
    }

    private func fetchCloudSessions(uid: String) async -> [FeedingSession] {
        do {
            let snap = try await sessionsCollection(uid: uid).getDocuments()
            return snap.documents.compactMap { FeedingSession.fromFirestoreData($0.data()) }
        } catch {
            print("FirestoreService.fetchCloudSessions failed: \(error)")
            return []
        }
    }

    private func pushSessionDirect(_ session: FeedingSession, uid: String) async {
        do {
            try await sessionsCollection(uid: uid)
                .document(session.id.uuidString)
                .setData(session.toFirestoreData(), merge: true)
        } catch {
            print("FirestoreService.pushSessionDirect failed: \(error)")
        }
    }

    private func currentProfilePayload() -> [String: Any] {
        let d = UserDefaults.standard
        return [
            "babyName":         d.string(forKey: "babyName") ?? "",
            "babyDOBTimestamp": d.double(forKey: "babyDOBTimestamp"),
            "babyGender":       d.string(forKey: "babyGender") ?? "",
        ]
    }

    private func applyProfile(from data: [String: Any]?) {
        guard let data else { return }
        let d = UserDefaults.standard
        if let name = data["babyName"] as? String, !name.isEmpty {
            d.set(name, forKey: "babyName")
        }
        if let ts = data["babyDOBTimestamp"] as? Double, ts > 0 {
            d.set(ts, forKey: "babyDOBTimestamp")
        }
        if let gender = data["babyGender"] as? String, !gender.isEmpty {
            d.set(gender, forKey: "babyGender")
        }
    }
}
