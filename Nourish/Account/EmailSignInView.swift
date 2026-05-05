import SwiftUI

struct EmailSignInView: View {
    @Environment(\.nourishColors) private var c
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var auth = AuthManager.shared

    private enum Mode { case signIn, createAccount }
    @State private var mode: Mode = .signIn
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var resetSent = false
    @FocusState private var focus: Field?

    private enum Field { case email, password, confirm }

    private var isCreate: Bool { mode == .createAccount }

    private var canSubmit: Bool {
        guard !email.isEmpty, password.count >= 6 else { return false }
        if isCreate { return password == confirmPassword }
        return true
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(isCreate ? "Create your account" : "Welcome back")
                        .font(.nSerif(28))
                        .foregroundStyle(c.ink)
                        .padding(.top, 8)

                    Text(isCreate
                         ? "Set up an account to back up your sessions to the cloud."
                         : "Sign in to keep your sessions in sync across devices.")
                        .font(.nSans(14))
                        .foregroundStyle(c.muted)
                        .lineSpacing(4)
                        .padding(.bottom, 6)

                    fieldLabel("Email")
                    field(text: $email,
                          placeholder: "you@example.com",
                          field: .email,
                          isSecure: false,
                          contentType: .emailAddress,
                          keyboard: .emailAddress)

                    fieldLabel("Password")
                    field(text: $password,
                          placeholder: "At least 6 characters",
                          field: .password,
                          isSecure: true,
                          contentType: isCreate ? .newPassword : .password,
                          keyboard: .default)

                    if isCreate {
                        fieldLabel("Confirm password")
                        field(text: $confirmPassword,
                              placeholder: "Type it again",
                              field: .confirm,
                              isSecure: true,
                              contentType: .newPassword,
                              keyboard: .default)
                    }

                    if let error = auth.errorMessage {
                        Text(error)
                            .font(.nSans(13))
                            .foregroundStyle(.red.opacity(0.85))
                            .lineSpacing(3)
                    }

                    if resetSent {
                        Text("Password reset email sent. Check your inbox.")
                            .font(.nSans(13))
                            .foregroundStyle(c.green)
                    }

                    submitButton
                        .padding(.top, 4)

                    if !isCreate {
                        forgotButton
                    }

                    HStack(spacing: 4) {
                        Text(isCreate ? "Already have an account?" : "New to Nourish?")
                            .font(.nSans(14))
                            .foregroundStyle(c.muted)
                        Button(isCreate ? "Sign in" : "Create account") {
                            withAnimation {
                                mode = isCreate ? .signIn : .createAccount
                                auth.errorMessage = nil
                                resetSent = false
                                confirmPassword = ""
                            }
                        }
                        .font(.nSans(14, weight: .bold))
                        .foregroundStyle(c.leftAccent)
                        .buttonStyle(.plain)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 14)
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 28)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(c.bg.ignoresSafeArea())
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
                Text(isCreate ? "Create Account" : "Sign In")
                    .font(.nSerif(22))
                    .foregroundStyle(c.ink)
                Spacer()
                Button {
                    focus = nil
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.nSans(13, weight: .semibold))
                        .foregroundStyle(c.muted)
                        .frame(width: 30, height: 30)
                        .background(c.surface)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(c.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 12)

            Divider().overlay(c.border)
        }
    }

    // MARK: Field

    @ViewBuilder
    private func field(text: Binding<String>,
                       placeholder: String,
                       field: Field,
                       isSecure: Bool,
                       contentType: UITextContentType,
                       keyboard: UIKeyboardType) -> some View {
        Group {
            if isSecure {
                SecureField(placeholder, text: text)
            } else {
                TextField(placeholder, text: text)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
        }
        .focused($focus, equals: field)
        .textContentType(contentType)
        .keyboardType(keyboard)
        .font(.nSans(17, weight: .semibold))
        .foregroundStyle(c.ink)
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(c.border, lineWidth: 1))
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.nSans(11, weight: .bold))
            .foregroundStyle(c.muted)
            .kerning(0.09 * 11)
            .padding(.bottom, -8)
    }

    // MARK: Submit

    private var submitButton: some View {
        Button {
            focus = nil
            Task { await submit() }
        } label: {
            ZStack {
                Text(isCreate ? "Create Account" : "Sign In")
                    .font(.nSans(17, weight: .bold))
                    .foregroundStyle(.white)
                    .opacity(auth.isWorking ? 0 : 1)
                if auth.isWorking {
                    ProgressView().tint(.white)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(canSubmit ? c.leftAccent : c.muted.opacity(0.3))
            .clipShape(Capsule())
            .shadow(color: canSubmit ? c.leftShadow : .clear, radius: 10, y: 4)
        }
        .buttonStyle(ScaleButtonStyle())
        .disabled(!canSubmit || auth.isWorking)
    }

    private var forgotButton: some View {
        Button("Forgot password?") {
            focus = nil
            guard !email.isEmpty else {
                auth.errorMessage = "Enter your email above first."
                return
            }
            Task {
                if await auth.sendPasswordReset(email: email) {
                    resetSent = true
                }
            }
        }
        .font(.nSans(14, weight: .semibold))
        .foregroundStyle(c.muted)
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
        .buttonStyle(.plain)
    }

    private func submit() async {
        let success: Bool
        if isCreate {
            success = await auth.createAccount(email: email, password: password)
        } else {
            success = await auth.signIn(email: email, password: password)
        }
        if success {
            dismiss()
        }
    }
}
