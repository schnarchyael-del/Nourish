import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore
import SwiftData

/// Owns the user's "family" (the shared baby + sessions pool that one or two
/// signed-in users belong to). One family per user; the family's invite code
/// IS the document id (6 chars from an unambiguous alphabet, ~1B combos).
///
/// Firestore layout:
///   users/{uid}.familyId           // pointer to the family this user belongs to
///   families/{code}                // root doc — invite code, members, metadata
///   families/{code}/sessions/{id}  // feeding sessions (mirrors local SwiftData)
///   families/{code}/profile/main   // baby profile (single doc)
@MainActor
final class FamilyService: ObservableObject {
    static let shared = FamilyService()

    @Published private(set) var familyId: String? = nil
    @Published private(set) var memberUids: [String] = []
    @Published private(set) var isLoading: Bool = false
    @Published var lastError: String? = nil

    private var modelContainer: ModelContainer?
    private var familyListener: ListenerRegistration?
    private var sessionsListener: ListenerRegistration?
    private var profileListener: ListenerRegistration?

    private init() {}

    func attach(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    // MARK: Lifecycle hooks (called by FirestoreService on auth changes)

    /// Called when a user signs in. Loads their familyId from Firestore.
    /// - If a familyId is already set → attach listeners.
    /// - If not, and the user has previously completed onboarding (existing
    ///   pre-update user with local data) → auto-create a family and migrate
    ///   their data into it.
    /// - Otherwise → leave familyId unset; onboarding will create or join.
    func handleSignIn(uid: String) async {
        do {
            let snap = try await Firestore.firestore()
                .collection("users").document(uid).getDocument()
            if let fid = snap.data()?["familyId"] as? String, !fid.isEmpty {
                attachToFamily(fid)
            } else if UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") {
                _ = try await createFamily(uid: uid)
            }
        } catch {
            lastError = "Couldn't load family: \(error.localizedDescription)"
        }
    }

    func handleSignOut() {
        detach()
    }

    // MARK: Create / join / leave

    /// Create a brand-new family for this user. Migrates any local sessions
    /// and the local baby profile into the family's Firestore subcollections.
    @discardableResult
    func createFamily(uid: String) async throws -> String {
        isLoading = true
        defer { isLoading = false }

        let code = try await reserveUniqueCode()
        let db = Firestore.firestore()

        // 1. Point the user at the new family FIRST so rules permit the
        //    family-doc write below (rules check users/{uid}.familyId == code).
        try await db.collection("users").document(uid).setData([
            "familyId": code,
        ], merge: true)

        // 2. Create the family root doc.
        try await db.collection("families").document(code).setData([
            "inviteCode": code,
            "createdBy":  uid,
            "createdAt":  FieldValue.serverTimestamp(),
            "memberUids": [uid],
        ])

        attachToFamily(code)

        // 3. Push existing local data so this family is the source of truth.
        await pushAllLocalDataToCurrentFamily()
        return code
    }

    /// Join an existing family by its invite code. Pushes the joining user's
    /// local sessions into the family too, so the partner sees everything.
    func joinFamily(code rawCode: String, uid: String) async throws {
        isLoading = true
        defer { isLoading = false }

        let code = rawCode.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard code.count == 6, code.allSatisfy({ $0.isLetter || $0.isNumber }) else {
            throw FamilyError.invalidCode
        }

        let db = Firestore.firestore()
        let familyRef = db.collection("families").document(code)

        // Verify the family exists. Allowed for any signed-in user — only the
        // root doc is readable pre-join; subcollections stay members-only.
        let familySnap = try await familyRef.getDocument()
        guard familySnap.exists else {
            throw FamilyError.codeNotFound
        }

        // Point the user at the family so rules permit the arrayUnion below.
        try await db.collection("users").document(uid).setData([
            "familyId": code,
        ], merge: true)

        // Append self to memberUids (purely informational; auth comes from
        // the user-doc pointer, not this array).
        try await familyRef.updateData([
            "memberUids": FieldValue.arrayUnion([uid]),
        ])

        attachToFamily(code)

        // Mirror the joining user's local data into the joined family so the
        // existing partner sees those sessions too.
        await pushAllLocalDataToCurrentFamily()
    }

    /// Disconnect from the current family. Does not delete the family doc;
    /// other members keep using it. The user's local SwiftData is preserved.
    func leaveFamily(uid: String) async throws {
        let db = Firestore.firestore()
        if let fid = familyId {
            // Best-effort cleanup of memberUids; safe to fail.
            _ = try? await db.collection("families").document(fid).updateData([
                "memberUids": FieldValue.arrayRemove([uid]),
            ])
        }
        try await db.collection("users").document(uid).setData([
            "familyId": FieldValue.delete(),
        ], merge: true)
        detach()
    }

    // MARK: Pushing local data (called by FirestoreService on save)

    func pushSession(_ session: FeedingSession) async {
        guard let fid = familyId else { return }
        do {
            try await Firestore.firestore()
                .collection("families").document(fid)
                .collection("sessions").document(session.id.uuidString)
                .setData(session.toFirestoreData(), merge: true)
        } catch {
            print("FamilyService.pushSession failed: \(error)")
        }
    }

    func deleteSession(id: UUID) async {
        guard let fid = familyId else { return }
        do {
            try await Firestore.firestore()
                .collection("families").document(fid)
                .collection("sessions").document(id.uuidString)
                .delete()
        } catch {
            print("FamilyService.deleteSession failed: \(error)")
        }
    }

    func pushProfile() async {
        guard let fid = familyId else { return }
        let d = UserDefaults.standard
        let payload: [String: Any] = [
            "babyName":         d.string(forKey: "babyName") ?? "",
            "babyDOBTimestamp": d.double(forKey: "babyDOBTimestamp"),
            "babyGender":       d.string(forKey: "babyGender") ?? "",
        ]
        do {
            try await Firestore.firestore()
                .collection("families").document(fid)
                .collection("profile").document("main")
                .setData(payload, merge: true)
        } catch {
            print("FamilyService.pushProfile failed: \(error)")
        }
    }

    // MARK: Listeners — keep local mirrors in sync with the family

    private func attachToFamily(_ fid: String) {
        familyId = fid
        startListeners(for: fid)
    }

    private func detach() {
        stopListeners()
        familyId = nil
        memberUids = []
    }

    private func startListeners(for fid: String) {
        stopListeners()
        let db = Firestore.firestore()

        familyListener = db.collection("families").document(fid)
            .addSnapshotListener { [weak self] snap, _ in
                Task { @MainActor in
                    self?.memberUids = (snap?.data()?["memberUids"] as? [String]) ?? []
                }
            }

        sessionsListener = db.collection("families").document(fid)
            .collection("sessions")
            .addSnapshotListener { [weak self] snap, _ in
                Task { @MainActor in
                    guard let self, let snap else { return }
                    self.applyRemoteSessionChanges(snap.documentChanges)
                }
            }

        profileListener = db.collection("families").document(fid)
            .collection("profile").document("main")
            .addSnapshotListener { [weak self] snap, _ in
                Task { @MainActor in
                    self?.applyRemoteProfile(snap?.data())
                }
            }
    }

    private func stopListeners() {
        familyListener?.remove(); familyListener = nil
        sessionsListener?.remove(); sessionsListener = nil
        profileListener?.remove(); profileListener = nil
    }

    /// Applies a Firestore snapshot delta to SwiftData.
    ///
    /// Performance matters here: on every listener (re)attach — i.e. every
    /// app launch — Firestore delivers the ENTIRE collection as `.added`
    /// changes, and this runs on the main actor. So:
    ///  * fetch all local sessions ONCE and index by id, instead of one
    ///    predicate fetch per document;
    ///  * skip the write when the remote data matches what we already have,
    ///    so an unchanged history dirties nothing — otherwise every launch
    ///    rewrites every row and the resulting @Query invalidation freezes
    ///    the UI for seconds on real data sets.
    private func applyRemoteSessionChanges(_ changes: [DocumentChange]) {
        guard let container = modelContainer else { return }
        let context = ModelContext(container)

        guard let locals = try? context.fetch(FetchDescriptor<FeedingSession>()) else { return }
        var byId = Dictionary(locals.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var dirty = false

        for change in changes {
            switch change.type {
            case .added, .modified:
                guard let cloud = FeedingSession.fromFirestoreData(change.document.data()) else {
                    continue
                }
                if let local = byId[cloud.id] {
                    if local.startTime         != cloud.startTime         { local.startTime         = cloud.startTime;         dirty = true }
                    if local.endTime           != cloud.endTime           { local.endTime           = cloud.endTime;           dirty = true }
                    if local.feedType          != cloud.feedType          { local.feedType          = cloud.feedType;          dirty = true }
                    if local.bottleContentType != cloud.bottleContentType { local.bottleContentType = cloud.bottleContentType; dirty = true }
                    if local.bottleAmountMl    != cloud.bottleAmountMl    { local.bottleAmountMl    = cloud.bottleAmountMl;    dirty = true }
                    if local.leftDurationMins  != cloud.leftDurationMins  { local.leftDurationMins  = cloud.leftDurationMins;  dirty = true }
                    if local.rightDurationMins != cloud.rightDurationMins { local.rightDurationMins = cloud.rightDurationMins; dirty = true }
                    if local.loggedByDeviceID  != cloud.loggedByDeviceID  { local.loggedByDeviceID  = cloud.loggedByDeviceID;  dirty = true }
                    if local.pumpSide          != cloud.pumpSide          { local.pumpSide          = cloud.pumpSide;          dirty = true }
                    if local.pumpVolumeMl      != cloud.pumpVolumeMl      { local.pumpVolumeMl      = cloud.pumpVolumeMl;      dirty = true }
                    if local.notes             != cloud.notes             { local.notes             = cloud.notes;             dirty = true }
                } else {
                    context.insert(cloud)
                    byId[cloud.id] = cloud
                    dirty = true
                }

            case .removed:
                guard
                    let idStr = change.document.data()["id"] as? String,
                    let id = UUID(uuidString: idStr)
                else { continue }
                if let local = byId[id] {
                    context.delete(local)
                    byId[id] = nil
                    dirty = true
                }
            }
        }

        guard dirty else { return }
        try? context.save()
        SharedFeedSnapshot.refresh(modelContainer: container)
    }

    private func applyRemoteProfile(_ data: [String: Any]?) {
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

    // MARK: Migration helpers

    private func pushAllLocalDataToCurrentFamily() async {
        guard let fid = familyId, let container = modelContainer else { return }
        let context = ModelContext(container)
        if let sessions = try? context.fetch(FetchDescriptor<FeedingSession>()) {
            for session in sessions {
                try? await Firestore.firestore()
                    .collection("families").document(fid)
                    .collection("sessions").document(session.id.uuidString)
                    .setData(session.toFirestoreData(), merge: true)
            }
        }
        await pushProfile()
    }

    // MARK: Code generation

    /// Generate a 6-char code from an unambiguous alphabet and confirm no
    /// existing family is using it. Tries up to 5 times before giving up.
    private func reserveUniqueCode() async throws -> String {
        for _ in 0..<5 {
            let code = Self.makeRandomCode()
            let snap = try await Firestore.firestore()
                .collection("families").document(code).getDocument()
            if !snap.exists { return code }
        }
        throw FamilyError.codeGenerationFailed
    }

    private static func makeRandomCode() -> String {
        let chars = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        return String((0..<6).map { _ in chars.randomElement()! })
    }

    enum FamilyError: LocalizedError {
        case invalidCode
        case codeNotFound
        case codeGenerationFailed

        var errorDescription: String? {
            switch self {
            case .invalidCode:
                return "That code doesn't look right — 6 letters or numbers."
            case .codeNotFound:
                return "Code not found. Double-check it with your partner."
            case .codeGenerationFailed:
                return "Couldn't reserve a code. Try again in a moment."
            }
        }
    }
}
