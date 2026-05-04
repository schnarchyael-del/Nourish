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
        } catch {
            errorMessage = error.localizedDescription
        }
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
