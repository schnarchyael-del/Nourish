import SwiftUI
import AuthenticationServices

/// Second-step confirmation sheet for account deletion.
/// First step (a simple alert) lives in `SettingsView`; this sheet handles
/// the type-DELETE field, the actual deletion, and the reauthentication
/// retry flow when Firebase requires a recent login.
struct DeleteAccountView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.nourishColors) private var c
    @ObservedObject private var auth = AuthManager.shared

    var onDeleted: () -> Void = {}

    @State private var typed: String = ""
    @State private var isWorking: Bool = false
    @State private var errorMessage: String?
    @State private var reauthProvider: AuthManager.AccountProvider?
    @State private var password: String = ""
    @State private var didSucceed: Bool = false

    private let requiredPhrase = "DELETE"

    private var canDelete: Bool {
        typed.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == requiredPhrase
            && !isWorking
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    warningCard

                    if reauthProvider == nil {
                        confirmField
                    } else {
                        reauthSection
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.nSans(13))
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 18)
                .padding(.bottom, 24)
            }

            footerButtons
        }
        .background(c.bg)
        .interactiveDismissDisabled(isWorking)
        .overlay {
            if didSucceed {
                successOverlay
            }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color.primary.opacity(0.15))
                .frame(width: 36, height: 4)
                .padding(.top, 14)
                .padding(.bottom, 16)

            HStack {
                Text("Delete account")
                    .font(.nSerif(22))
                    .foregroundStyle(c.ink)
                Spacer()
                Button(action: { if !isWorking { dismiss() } }) {
                    Image(systemName: "xmark")
                        .font(.nSans(13, weight: .semibold))
                        .foregroundStyle(c.muted)
                        .frame(width: 30, height: 30)
                        .background(c.surface)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(c.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .opacity(isWorking ? 0.4 : 1)
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 12)

            Divider().overlay(c.border)
        }
    }

    // MARK: Warning copy

    private var warningCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("⚠️").font(.nSans(20))
                Text("This cannot be undone")
                    .font(.nSans(15, weight: .semibold))
                    .foregroundStyle(c.ink)
            }
            Text("Deleting your account will permanently remove your feeding sessions, pump sessions, baby profile, and partner sharing. Your data will be erased from our servers and from this device.")
                .font(.nSans(14))
                .foregroundStyle(c.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(c.surface)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(c.border, lineWidth: 1))
    }

    // MARK: Type-DELETE confirmation

    private var confirmField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Type DELETE to confirm")
                .font(.nSans(13, weight: .semibold))
                .foregroundStyle(c.muted)
            TextField("DELETE", text: $typed)
                .font(.nSans(17, weight: .semibold))
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(c.surface)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(c.border, lineWidth: 1))
                .disabled(isWorking)
        }
    }

    // MARK: Reauth retry

    private var reauthSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sign in again to confirm")
                .font(.nSans(13, weight: .semibold))
                .foregroundStyle(c.muted)
            Text("For your safety, Apple/Firebase require you to sign in again before permanent account deletion.")
                .font(.nSans(13))
                .foregroundStyle(c.muted)
                .fixedSize(horizontal: false, vertical: true)

            switch reauthProvider {
            case .apple:
                ZStack {
                    SignInWithAppleButton(.continue,
                        onRequest: { auth.configure($0) },
                        onCompletion: { result in
                            Task { await runAppleReauth(result) }
                        }
                    )
                    .signInWithAppleButtonStyle(.white)
                    .frame(height: 46)
                    .cornerRadius(23)
                    .disabled(isWorking)
                    .opacity(isWorking ? 0.5 : 1)
                    if isWorking { ProgressView().tint(c.ink) }
                }
            case .password:
                VStack(spacing: 10) {
                    SecureField("Password", text: $password)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(c.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(c.border, lineWidth: 1))
                        .disabled(isWorking)
                    destructiveButton(label: "Confirm & Delete") {
                        Task { await runPasswordReauth() }
                    }
                    .disabled(password.isEmpty || isWorking)
                    .opacity(password.isEmpty || isWorking ? 0.5 : 1)
                }
            case .other, .none:
                Text("Please sign out, sign in again, and tap Delete Account again to finish.")
                    .font(.nSans(13))
                    .foregroundStyle(c.muted)
            }
        }
    }

    // MARK: Footer

    @ViewBuilder
    private var footerButtons: some View {
        if reauthProvider == nil {
            VStack(spacing: 10) {
                destructiveButton(label: isWorking ? "Deleting…" : "Delete Account") {
                    Task { await runInitialDelete() }
                }
                .disabled(!canDelete)
                .opacity(canDelete ? 1 : 0.5)

                Button("Cancel") { dismiss() }
                    .font(.nSans(15, weight: .semibold))
                    .foregroundStyle(c.muted)
                    .disabled(isWorking)
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 22)
            .padding(.top, 8)
            .background(c.bg)
            .overlay(Divider().overlay(c.border), alignment: .top)
        }
    }

    private func destructiveButton(label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isWorking { ProgressView().tint(.white) }
                Text(label)
                    .font(.nSans(15, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(Color.red)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: Success overlay

    private var successOverlay: some View {
        ZStack {
            c.bg.opacity(0.97)
            VStack(spacing: 14) {
                Text("✅").font(.nSans(40))
                Text("Account deleted")
                    .font(.nSerif(22))
                    .foregroundStyle(c.ink)
            }
        }
        .transition(.opacity)
        .ignoresSafeArea()
    }

    // MARK: Actions

    private func runInitialDelete() async {
        errorMessage = nil
        isWorking = true
        defer { isWorking = false }
        do {
            try await auth.deleteAccount()
            await finishSuccess()
        } catch let AuthManager.AccountDeletionError.reauthenticationRequired(provider) {
            reauthProvider = provider
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func runAppleReauth(_ result: Result<ASAuthorization, Error>) async {
        errorMessage = nil
        isWorking = true
        defer { isWorking = false }
        do {
            try await auth.reauthenticateWithAppleAndDelete(result)
            await finishSuccess()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func runPasswordReauth() async {
        errorMessage = nil
        isWorking = true
        defer { isWorking = false }
        do {
            try await auth.reauthenticateWithEmailAndDelete(password: password)
            await finishSuccess()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func finishSuccess() async {
        withAnimation(.easeInOut(duration: 0.2)) { didSucceed = true }
        try? await Task.sleep(nanoseconds: 1_400_000_000)
        onDeleted()
        dismiss()
    }
}
