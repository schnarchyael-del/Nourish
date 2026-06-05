import Foundation
import Combine
import AuthenticationServices
import CryptoKit
import FirebaseAuth

@MainActor
final class AuthManager: NSObject, ObservableObject {
    static let shared = AuthManager()

    @Published private(set) var isSignedIn: Bool = false
    @Published private(set) var isWorking: Bool = false
    @Published var errorMessage: String?

    private(set) var currentUser: User?
    private var authStateHandle: AuthStateDidChangeListenerHandle?
    private var currentNonce: String?

    override init() {
        super.init()
        currentUser = Auth.auth().currentUser
        isSignedIn = currentUser != nil
        authStateHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                guard let self else { return }
                self.currentUser = user
                self.isSignedIn = user != nil
            }
        }
    }

    deinit {
        if let handle = authStateHandle {
            Auth.auth().removeStateDidChangeListener(handle)
        }
    }

    var userId: String? { currentUser?.uid }

    var displayLabel: String {
        if let name = currentUser?.displayName, !name.isEmpty { return name }
        if let email = currentUser?.email, !email.isEmpty { return email }
        return "Signed in"
    }

    // MARK: Sign in with Apple

    /// Hand off to `SignInWithAppleButton.onRequest` so we set scopes + nonce.
    func configure(_ request: ASAuthorizationAppleIDRequest) {
        errorMessage = nil
        let nonce = Self.randomNonce()
        currentNonce = nonce
        request.requestedScopes = [.fullName, .email]
        request.nonce = Self.sha256(nonce)
    }

    /// Hand off to `SignInWithAppleButton.onCompletion`.
    func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .failure(let error):
            // User-initiated cancel isn't an error worth showing.
            if let asError = error as? ASAuthorizationError, asError.code == .canceled {
                isWorking = false
                return
            }
            errorMessage = error.localizedDescription
            isWorking = false

        case .success(let authorization):
            guard
                let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                let nonce = currentNonce,
                let tokenData = credential.identityToken,
                let token = String(data: tokenData, encoding: .utf8)
            else {
                errorMessage = "Couldn't read the Apple credential."
                isWorking = false
                return
            }

            isWorking = true
            let firebaseCredential = OAuthProvider.appleCredential(
                withIDToken: token,
                rawNonce: nonce,
                fullName: credential.fullName
            )

            Task {
                do {
                    _ = try await Auth.auth().signIn(with: firebaseCredential)
                    AnalyticsService.signInApple()
                } catch {
                    errorMessage = error.localizedDescription
                }
                isWorking = false
            }
        }
    }

    func signOut() {
        do {
            try Auth.auth().signOut()
            AnalyticsService.signOut()
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        // Sign-out should leave the device in a clean "not signed in" state.
        // Without this, the home screen keeps showing the previous account's
        // sessions and baby profile until app restart.
        // Cloud data stays safe — listeners on next sign-in repopulate it.
        Self.clearAccountScopedAppStorageOnSignOut()
        Task {
            await Task.yield()  // let auth-state listeners detach Firestore listeners first
            await FirestoreService.shared.wipeAllLocalData()
        }
    }

    /// Profile + onboarding keys to clear when *signing out* (not deleting).
    /// Theme + notification preferences are device-level and preserved.
    private static func clearAccountScopedAppStorageOnSignOut() {
        let d = UserDefaults.standard
        let keys = [
            "userName", "babyName", "babyDOBTimestamp", "babyGender",
            "partnerName",
            "hasCompletedOnboarding",
            "lastSyncedFirebaseUid",
        ]
        for k in keys { d.removeObject(forKey: k) }
    }

    // MARK: Email + password

    func signIn(email: String, password: String) async -> Bool {
        errorMessage = nil
        isWorking = true
        defer { isWorking = false }
        do {
            _ = try await Auth.auth().signIn(withEmail: email, password: password)
            AnalyticsService.signInEmail()
            return true
        } catch {
            errorMessage = Self.friendlyAuthError(error)
            return false
        }
    }

    func createAccount(email: String, password: String) async -> Bool {
        errorMessage = nil
        isWorking = true
        defer { isWorking = false }
        do {
            _ = try await Auth.auth().createUser(withEmail: email, password: password)
            AnalyticsService.accountCreatedEmail()
            return true
        } catch {
            errorMessage = Self.friendlyAuthError(error)
            return false
        }
    }

    func sendPasswordReset(email: String) async -> Bool {
        errorMessage = nil
        do {
            try await Auth.auth().sendPasswordReset(withEmail: email)
            return true
        } catch {
            errorMessage = Self.friendlyAuthError(error)
            return false
        }
    }

    /// Translate Firebase Auth errors to short, action-oriented messages.
    /// Anything we don't recognize falls through to Firebase's text.
    static func friendlyAuthError(_ error: Error) -> String {
        let nsError = error as NSError
        guard nsError.domain == AuthErrorDomain else {
            return error.localizedDescription
        }
        switch nsError.code {
        case AuthErrorCode.invalidEmail.rawValue:
            return "That email doesn't look right."
        case AuthErrorCode.wrongPassword.rawValue,
             AuthErrorCode.invalidCredential.rawValue:
            return "Wrong email or password. Try again or tap Forgot Password."
        case AuthErrorCode.userNotFound.rawValue:
            return "No account with this email. Tap \"Create Account\" above to sign up."
        case AuthErrorCode.emailAlreadyInUse.rawValue:
            return "An account already exists for this email. Tap \"Sign In\" above to continue."
        case AuthErrorCode.weakPassword.rawValue:
            return "Password is too short — use at least 6 characters."
        case AuthErrorCode.networkError.rawValue:
            return "No internet connection. Check your network and try again."
        case AuthErrorCode.tooManyRequests.rawValue:
            return "Too many attempts. Wait a moment, then try again."
        case AuthErrorCode.userDisabled.rawValue:
            return "This account has been disabled. Contact support."
        default:
            return error.localizedDescription
        }
    }

    // MARK: Delete account

    enum AccountProvider: String {
        case apple = "apple.com"
        case password = "password"
        case other = ""
    }

    enum AccountDeletionError: LocalizedError {
        case notSignedIn
        case reauthenticationRequired(AccountProvider)
        case other(String)

        var errorDescription: String? {
            switch self {
            case .notSignedIn:                  return "You're not signed in."
            case .reauthenticationRequired:     return "For security, please sign in again before deleting your account."
            case .other(let message):           return message
            }
        }
    }

    /// Provider used by the current Firebase user (Apple, password, etc.).
    var currentProvider: AccountProvider {
        guard let id = currentUser?.providerData.first?.providerID else { return .other }
        return AccountProvider(rawValue: id) ?? .other
    }

    /// Wipes all cloud + local data for the current user and deletes their
    /// Firebase Auth account. On `requiresRecentLogin`, throws
    /// `.reauthenticationRequired` — caller should reauthenticate and retry;
    /// the wipe is idempotent.
    func deleteAccount() async throws {
        guard let user = Auth.auth().currentUser else {
            throw AccountDeletionError.notSignedIn
        }
        let uid = user.uid

        AnalyticsService.accountDeletionStarted()
        isWorking = true
        defer { isWorking = false }

        // Wipe cloud data first (while still authenticated).
        try await FirestoreService.shared.wipeFirestoreAccount(uid: uid)

        // Now delete the auth user. This is the step that may demand a
        // recent login.
        do {
            try await user.delete()
        } catch let error as NSError {
            if error.code == AuthErrorCode.requiresRecentLogin.rawValue {
                AnalyticsService.accountDeletionFailed(reason: "requires_recent_login")
                throw AccountDeletionError.reauthenticationRequired(currentProvider)
            }
            AnalyticsService.accountDeletionFailed(reason: error.localizedDescription)
            throw AccountDeletionError.other(error.localizedDescription)
        }

        // Local wipe + reset only after the auth account is gone.
        await FirestoreService.shared.wipeAllLocalData()
        Self.clearAppStorageForAccountDeletion()

        AnalyticsService.accountDeleted()
    }

    /// Reauthenticate with Apple, then run the account deletion to completion.
    /// Used after `deleteAccount()` throws `.reauthenticationRequired(.apple)`.
    func reauthenticateWithAppleAndDelete(_ result: Result<ASAuthorization, Error>) async throws {
        switch result {
        case .failure(let error):
            if let asError = error as? ASAuthorizationError, asError.code == .canceled {
                throw AccountDeletionError.other("Sign-in cancelled.")
            }
            throw AccountDeletionError.other(error.localizedDescription)

        case .success(let authorization):
            guard
                let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                let nonce = currentNonce,
                let tokenData = credential.identityToken,
                let token = String(data: tokenData, encoding: .utf8),
                let user = Auth.auth().currentUser
            else {
                throw AccountDeletionError.other("Couldn't read the Apple credential.")
            }
            let firebaseCredential = OAuthProvider.appleCredential(
                withIDToken: token, rawNonce: nonce, fullName: credential.fullName
            )
            do {
                _ = try await user.reauthenticate(with: firebaseCredential)
            } catch {
                throw AccountDeletionError.other(error.localizedDescription)
            }
            try await deleteAccount()
        }
    }

    /// Reauthenticate with email + password, then run the account deletion.
    /// Used after `deleteAccount()` throws `.reauthenticationRequired(.password)`.
    func reauthenticateWithEmailAndDelete(password: String) async throws {
        guard let user = Auth.auth().currentUser, let email = user.email else {
            throw AccountDeletionError.notSignedIn
        }
        let credential = EmailAuthProvider.credential(withEmail: email, password: password)
        do {
            _ = try await user.reauthenticate(with: credential)
        } catch {
            throw AccountDeletionError.other(error.localizedDescription)
        }
        try await deleteAccount()
    }

    /// Clears every @AppStorage key the app uses so the next launch is
    /// indistinguishable from a fresh install — sends the user back to
    /// onboarding and removes baby/profile data.
    private static func clearAppStorageForAccountDeletion() {
        let d = UserDefaults.standard
        let keys = [
            "userName", "babyName", "babyDOBTimestamp", "babyGender",
            "partnerName", "accentVariant", "rightAccentVariant", "appTheme",
            "alarmEnabled", "alarmMinutes",
            "reminderEnabled", "reminderHours",
            "partnerActivityNotif",
            "darkActiveScreen", "showEncouragements",
            "hasCompletedOnboarding", "hasRequestedNotifPermission",
            "lastSyncedFirebaseUid",
        ]
        for key in keys { d.removeObject(forKey: key) }
    }

    // MARK: Nonce

    private static func randomNonce(length: Int = 32) -> String {
        precondition(length > 0)
        let charset: [Character] = Array(
            "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._"
        )
        var result = ""
        var remaining = length
        while remaining > 0 {
            var random = [UInt8](repeating: 0, count: 16)
            let status = SecRandomCopyBytes(kSecRandomDefault, random.count, &random)
            guard status == errSecSuccess else {
                fatalError("SecRandomCopyBytes failed (status \(status))")
            }
            for byte in random where remaining > 0 {
                if byte < charset.count {
                    result.append(charset[Int(byte)])
                    remaining -= 1
                }
            }
        }
        return result
    }

    private static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
