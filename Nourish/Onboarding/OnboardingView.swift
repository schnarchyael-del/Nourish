import SwiftUI
import AuthenticationServices

fileprivate enum OnboardingField: Hashable {
    case babyName, userName, partnerName
}

struct OnboardingView: View {
    @Environment(\.nourishColors) private var c
    @ObservedObject private var auth = AuthManager.shared
    let onComplete: () -> Void

    @State private var step = 0
    @State private var babyName    = "Lily"
    @State private var babyDOB     = Calendar.current.date(byAdding: .weekOfYear, value: -7, to: .now) ?? .now
    @State private var babyGender  = "Girl"
    @State private var userName    = ""
    @State private var partnerName = ""
    @State private var showDOBPicker = false
    @State private var showEmailSignIn = false
    @FocusState private var focus: OnboardingField?

    var body: some View {
        Group {
            switch step {
            case 0: welcomeStep
            case 1: babyStep
            case 2: partnerStep
            default: welcomeStep
            }
        }
        .animation(.easeInOut(duration: 0.22), value: step)
        .background(c.bg.ignoresSafeArea())
        .sheet(isPresented: $showEmailSignIn) {
            EmailSignInView()
                .environment(\.nourishColors, c)
                .presentationDetents([.fraction(0.875)])
                .presentationDragIndicator(.hidden)
                .presentationCornerRadius(28)
        }
        .onChange(of: auth.isSignedIn) { _, signedIn in
            if signedIn && step == 0 {
                showEmailSignIn = false
                withAnimation { step = 1 }
            }
        }
    }

    // MARK: Step 0 – Welcome + auth gateway

    private var welcomeStep: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)

            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [c.leftBg, c.rightBg],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 150, height: 150)
                        .overlay(Circle().stroke(c.border, lineWidth: 1.5))
                        .shadow(color: c.leftShadow, radius: 20, y: 8)
                    Text("🤱")
                        .font(.nSans(56))
                }
                .padding(.bottom, 22)

                Text("Nourish")
                    .font(.nSerif(40))
                    .foregroundStyle(c.ink)
                    .padding(.bottom, 8)

                Text("Track every feeding with one tap.\nBuilt for tired, loving parents.")
                    .font(.nSans(15))
                    .foregroundStyle(c.muted)
                    .multilineTextAlignment(.center)
                    .lineSpacing(5)
                    .frame(maxWidth: 280)
            }

            Spacer(minLength: 24)

            VStack(spacing: 10) {
                ZStack {
                    SignInWithAppleButton(.signIn,
                        onRequest: { auth.configure($0) },
                        onCompletion: { auth.handleAppleSignIn($0) }
                    )
                    .signInWithAppleButtonStyle(.white)
                    .frame(height: 46)
                    .cornerRadius(23)
                    .disabled(auth.isWorking)
                    .opacity(auth.isWorking ? 0.5 : 1)

                    if auth.isWorking {
                        ProgressView().tint(c.ink)
                    }
                }

                Button {
                    auth.errorMessage = nil
                    showEmailSignIn = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "envelope.fill").font(.nSans(14))
                        Text("Sign in with Email")
                            .font(.nSans(15, weight: .semibold))
                    }
                    .foregroundStyle(c.leftText)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(c.leftBg)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(c.leftAccent.opacity(0.25), lineWidth: 1))
                }
                .buttonStyle(ScaleButtonStyle())

                if let error = auth.errorMessage {
                    Text(error)
                        .font(.nSans(12))
                        .foregroundStyle(.red.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .padding(.horizontal, 8)
                }

                Button("Continue without an account") {
                    withAnimation { step = 1 }
                }
                .font(.nSans(13, weight: .semibold))
                .foregroundStyle(c.muted)
                .padding(.top, 6)
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 32)
        }
    }

    // MARK: Step 1 – Baby info

    private var babyStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                backButton { step = 0 }
                    .padding(.bottom, 20)

                progressDots
                    .padding(.bottom, 28)

                Text("Meet your little one 🍼")
                    .font(.nSerif(28))
                    .foregroundStyle(c.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 6)

                Text("We'll personalise reminders to your baby's schedule.")
                    .font(.nSans(14))
                    .foregroundStyle(c.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineSpacing(4)
                    .padding(.bottom, 26)

                fieldLabel("Baby's name")
                OnboardingTextField(text: $babyName, colors: c, focused: true)
                    .focused($focus, equals: .babyName)
                    .submitLabel(.next)
                    .onSubmit { focus = .userName }
                    .padding(.bottom, 16)

                fieldLabel("Date of birth")
                dobPickerField
                    .padding(.bottom, 16)

                fieldLabel("Gender")
                genderPicker
                    .padding(.bottom, 16)

                fieldLabel("Your name")
                OnboardingTextField(text: $userName, placeholder: "Your name", colors: c)
                    .focused($focus, equals: .userName)
                    .submitLabel(.done)
                    .onSubmit { focus = nil }
                    .padding(.bottom, 24)

                ctaButton("Continue →", disabled: babyName.trimmingCharacters(in: .whitespaces).isEmpty) {
                    focus = nil
                    step = 2
                }
            }
            .padding(.horizontal, 26)
            .padding(.top, 58 + 14)
            .padding(.bottom, 28)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var genderPicker: some View {
        HStack(spacing: 10) {
            ForEach(["Boy", "Girl", "Other"], id: \.self) { option in
                let selected = babyGender == option
                let emoji = option == "Boy" ? "👦" : option == "Girl" ? "👧" : "🌈"
                Button {
                    focus = nil
                    babyGender = option
                } label: {
                    HStack(spacing: 6) {
                        Text(emoji).font(.nSans(16))
                        Text(option)
                            .font(.nSans(15, weight: .bold))
                            .foregroundStyle(selected ? c.leftText : c.muted)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(selected ? c.leftBg : Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(selected ? c.leftAccent.opacity(0.4) : c.border, lineWidth: selected ? 1.5 : 1)
                    )
                }
                .buttonStyle(ScaleButtonStyle())
                .animation(.easeInOut(duration: 0.15), value: babyGender)
            }
        }
    }

    // Tappable row that expands into a full .graphical DatePicker
    private var dobPickerField: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                focus = nil
                withAnimation(.easeInOut(duration: 0.25)) { showDOBPicker.toggle() }
            } label: {
                HStack {
                    Text(babyDOB.formatted(date: .long, time: .omitted))
                        .font(.nSans(18, weight: .semibold))
                        .foregroundStyle(c.ink)
                    Spacer()
                    Image(systemName: showDOBPicker ? "chevron.up" : "calendar")
                        .font(.nSans(15))
                        .foregroundStyle(c.muted)
                }
                .padding(.horizontal, 18)
                .frame(height: 56)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(showDOBPicker ? c.leftAccent : c.border,
                                lineWidth: showDOBPicker ? 1.5 : 1)
                )
            }
            .buttonStyle(.plain)

            if showDOBPicker {
                DatePicker("", selection: $babyDOB, in: ...Date.now, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .tint(c.leftAccent)
                    .colorScheme(.light)
                    .padding(8)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(c.border, lineWidth: 1))
                    .padding(.top, 4)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    // MARK: Step 2 – Partner

    private var partnerStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            backButton { step = 1 }
                .padding(.horizontal, 26)
                .padding(.top, 58 + 14)
                .padding(.bottom, 20)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    progressDots
                        .padding(.bottom, 28)

                    Text("Feed together 👫")
                        .font(.nSerif(28))
                        .foregroundStyle(c.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, 6)

                    Text("Invite your partner so you both can log and view sessions.")
                        .font(.nSans(14))
                        .foregroundStyle(c.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lineSpacing(4)
                        .padding(.bottom, 24)

                    VStack(alignment: .leading, spacing: 0) {
                        Text("Share with your partner")
                            .font(.nSans(20, weight: .bold))
                            .foregroundStyle(c.ink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.bottom, 12)

                        fieldLabel("Their name")
                        OnboardingTextField(text: $partnerName, placeholder: "Partner's name", colors: c)
                            .focused($focus, equals: .partnerName)
                            .submitLabel(.done)
                            .onSubmit { focus = nil }
                            .padding(.bottom, 14)

                        Text("They can view and log sessions. You'll both see each other's activity.")
                            .font(.nSans(13))
                            .foregroundStyle(c.muted)
                            .lineSpacing(4)
                            .padding(.bottom, 14)

                        HStack(spacing: 8) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.nSans(15, weight: .semibold))
                            Text("Share invite link")
                                .font(.nSans(15, weight: .semibold))
                            Text("· coming soon")
                                .font(.nSans(13))
                        }
                        .foregroundStyle(c.muted)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.white.opacity(0.5))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(c.border, lineWidth: 1.5))
                    }
                    .padding(20)
                    .background(c.greenBg)
                    .clipShape(RoundedRectangle(cornerRadius: 22))
                    .overlay(RoundedRectangle(cornerRadius: 22).stroke(c.green.opacity(0.2), lineWidth: 1))
                    .padding(.bottom, 24)

                    ctaButton("Start tracking →", action: finishOnboarding)

                    Button("Skip for now", action: finishOnboarding)
                        .font(.nSans(14))
                        .foregroundStyle(c.muted)
                        .underline()
                        .buttonStyle(.plain)
                        .background(.clear)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 14)
                }
                .padding(.horizontal, 26)
                .padding(.bottom, 28)
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    // MARK: Helpers

    private func finishOnboarding() {
        focus = nil
        UserDefaults.standard.set(babyName, forKey: "babyName")
        UserDefaults.standard.set(babyDOB.timeIntervalSince1970, forKey: "babyDOBTimestamp")
        UserDefaults.standard.set(babyGender, forKey: "babyGender")
        UserDefaults.standard.set(userName.isEmpty ? "You" : userName, forKey: "userName")
        UserDefaults.standard.set(partnerName, forKey: "partnerName")
        AnalyticsService.babyProfileCreated()
        onComplete()
    }

    private var progressDots: some View {
        HStack(spacing: 8) {
            ForEach(0..<3) { i in
                Capsule()
                    .fill(i == step ? c.leftAccent : c.border)
                    .frame(width: i == step ? 24 : 8, height: 8)
                    .animation(.easeInOut(duration: 0.25), value: step)
            }
        }
    }

    private func fieldLabel(_ label: String) -> some View {
        Text(label.uppercased())
            .font(.nSans(12, weight: .bold))
            .foregroundStyle(c.muted)
            .kerning(0.08 * 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 6)
    }

    private func backButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .font(.nSans(14, weight: .semibold))
                .foregroundStyle(c.ink)
                .frame(width: 38, height: 38)
                .background(Color.white)
                .clipShape(Circle())
                .overlay(Circle().stroke(c.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func ctaButton(_ label: String, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.nSans(18, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 62)
                .background(disabled ? c.leftAccent.opacity(0.35) : c.leftAccent)
                .clipShape(Capsule())
                .shadow(color: disabled ? .clear : c.leftShadow, radius: 12, y: 4)
        }
        .buttonStyle(ScaleButtonStyle())
        .disabled(disabled)
    }
}

// MARK: - Shared text field

private struct OnboardingTextField: View {
    @Binding var text: String
    var placeholder: String = ""
    let colors: NourishColors
    var focused: Bool = false

    @State private var cursorVisible = true

    var body: some View {
        HStack {
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.nSans(18, weight: .semibold))
                .foregroundStyle(colors.ink)
            if focused {
                Text("|")
                    .font(.nSans(18, weight: .semibold))
                    .foregroundStyle(colors.leftAccent)
                    .opacity(cursorVisible ? 1 : 0)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                            cursorVisible = false
                        }
                    }
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 56)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(focused ? colors.leftAccent : colors.border,
                        lineWidth: focused ? 1.5 : 1)
        )
    }
}
