import SwiftUI
import AuthenticationServices

fileprivate enum OnboardingField: Hashable {
    case babyName, userName, partnerName, partnerCode
}

struct OnboardingView: View {
    @Environment(\.nourishColors) private var c
    @ObservedObject private var auth = AuthManager.shared
    @ObservedObject private var family = FamilyService.shared
    let onComplete: () -> Void

    @State private var step = 0
    @State private var babyName    = "Lily"
    @State private var babyDOB     = Calendar.current.date(byAdding: .weekOfYear, value: -7, to: .now) ?? .now
    @State private var babyGender  = "Girl"
    @State private var userName    = ""
    @State private var partnerName = ""

    // Partner step
    @State private var partnerCodeInput = ""
    @State private var partnerJoinError: String? = nil
    @State private var partnerIsJoining = false
    @State private var didJoinPartner = false   // set when join succeeds — skips baby step

    @State private var showDOBPicker = false
    @State private var showEmailSignIn = false
    @State private var didFinish = false
    @FocusState private var focus: OnboardingField?

    // MARK: Step ids — order is: welcome → partner → baby → done

    private enum Step: Int { case welcome = 0, partner = 1, baby = 2 }
    private var currentStep: Step { Step(rawValue: step) ?? .welcome }

    var body: some View {
        Group {
            switch currentStep {
            case .welcome: welcomeStep
            case .partner: partnerStep
            case .baby:    babyStep
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
                Task { await postSignInRouting() }
            }
        }
        .onChange(of: family.familyId) { _, fid in
            // Safety net for slow networks: if a family loads after the user
            // has already advanced past welcome, jump straight to home so
            // they don't re-enter data the cloud already has.
            if fid != nil && step != 0 && !didFinish {
                finishOnboarding(skipProfileWrite: true)
            }
        }
        .onAppear {
            // Cover the "already signed in on launch" case — Firebase persists
            // sessions across launches, so the welcome step's auth gate would
            // sit there forever (no state transition for .onChange to fire).
            if auth.isSignedIn && step == 0 {
                Task { await postSignInRouting() }
            }
        }
    }

    /// After a sign-in (fresh or restored), wait briefly for FamilyService to
    /// discover an existing family in Firestore. If one exists, skip the rest
    /// of onboarding entirely — the partner profile + sessions will populate
    /// automatically through listeners. Otherwise, continue to the partner step.
    @MainActor
    private func postSignInRouting() async {
        for _ in 0..<20 {
            if family.familyId != nil { break }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        if didFinish { return }
        if family.familyId != nil {
            finishOnboarding(skipProfileWrite: true)
        } else if step == 0 {
            withAnimation { step = Step.partner.rawValue }
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
                    withAnimation { step = Step.baby.rawValue }
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

    // MARK: Step 1 – Partner code (NEW order — comes before baby profile)

    private var partnerStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                backButton { step = Step.welcome.rawValue }
                    .padding(.bottom, 20)

                progressDots
                    .padding(.bottom, 28)

                Text("Feed together 👫")
                    .font(.nSerif(28))
                    .foregroundStyle(c.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 6)

                Text("If your partner is already using Nourish, enter their code to sync the same baby and feeding history. Otherwise, set up on your own and invite them later.")
                    .font(.nSans(14))
                    .foregroundStyle(c.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineSpacing(4)
                    .padding(.bottom, 24)

                joinCodeCard
                    .padding(.bottom, 16)

                Text("or".uppercased())
                    .font(.nSans(11, weight: .bold))
                    .foregroundStyle(c.muted)
                    .kerning(0.09 * 11)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 6)

                ctaButton(
                    "Set up a new baby →",
                    disabled: partnerIsJoining
                ) {
                    focus = nil
                    withAnimation { step = Step.baby.rawValue }
                }
                .padding(.bottom, 10)
            }
            .padding(.horizontal, 26)
            .padding(.top, 58 + 14)
            .padding(.bottom, 28)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var joinCodeCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Text("🔗").font(.nSans(20))
                Text("I have a partner code")
                    .font(.nSans(17, weight: .bold))
                    .foregroundStyle(c.ink)
            }

            Text("Ask your partner to open Nourish → Settings → Partner sharing.")
                .font(.nSans(13))
                .foregroundStyle(c.muted)
                .lineSpacing(3)

            HStack(spacing: 10) {
                TextField("ABC123", text: $partnerCodeInput)
                    .textFieldStyle(.plain)
                    .font(.nSans(18, weight: .semibold))
                    .foregroundStyle(c.ink)
                    .focused($focus, equals: .partnerCode)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.characters)
                    .padding(.horizontal, 16)
                    .frame(height: 48)
                    .background(c.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(focus == .partnerCode ? c.leftAccent : c.border,
                                    lineWidth: focus == .partnerCode ? 1.5 : 1)
                    )
                    .onChange(of: partnerCodeInput) { _, v in
                        partnerCodeInput = String(v.uppercased()
                            .filter { $0.isLetter || $0.isNumber }
                            .prefix(6))
                    }
                Button {
                    Task { await joinWithPartnerCode() }
                } label: {
                    Group {
                        if partnerIsJoining {
                            ProgressView().tint(.white).frame(width: 80)
                        } else {
                            Text("Join")
                                .font(.nSans(15, weight: .bold))
                                .frame(width: 80)
                        }
                    }
                    .foregroundStyle(.white)
                    .frame(height: 48)
                    .background(canJoin ? c.leftAccent : c.muted.opacity(0.3))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(ScaleButtonStyle())
                .disabled(!canJoin)
            }

            if let err = partnerJoinError {
                Text(err)
                    .font(.nSans(12))
                    .foregroundStyle(.red.opacity(0.85))
            }

            if !auth.isSignedIn {
                Text("Sign in on the welcome screen first to join a partner.")
                    .font(.nSans(12))
                    .foregroundStyle(c.muted)
                    .padding(.top, 2)
            }
        }
        .padding(18)
        .background(c.greenBg)
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(c.green.opacity(0.25), lineWidth: 1))
    }

    private var canJoin: Bool {
        auth.isSignedIn
        && partnerCodeInput.count == 6
        && !partnerIsJoining
    }

    @MainActor
    private func joinWithPartnerCode() async {
        guard let uid = auth.userId else {
            partnerJoinError = "Sign in first so we can link your account."
            return
        }
        partnerJoinError = nil
        partnerIsJoining = true
        defer { partnerIsJoining = false }
        do {
            try await family.joinFamily(code: partnerCodeInput, uid: uid)
            didJoinPartner = true
            // The family's baby profile will arrive via the listener; finish
            // onboarding immediately so the user goes straight to Home.
            finishOnboarding(skipProfileWrite: true)
        } catch {
            partnerJoinError = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
        }
    }

    // MARK: Step 2 – Baby info (only reached if user didn't join a partner)

    private var babyStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                backButton { step = Step.partner.rawValue }
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

                ctaButton(
                    "Start tracking →",
                    disabled: babyName.trimmingCharacters(in: .whitespaces).isEmpty
                ) {
                    focus = nil
                    finishOnboarding(skipProfileWrite: false)
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
                    .background(selected ? c.leftBg : c.input)
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
                .background(c.input)
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
                    .background(c.input)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(c.border, lineWidth: 1))
                    .padding(.top, 4)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    // MARK: Finish

    /// Writes baby-profile defaults, completes onboarding, and (if the user is
    /// signed in but didn't join a family) creates a fresh family for them.
    /// When `skipProfileWrite` is true, the partner's profile is the source of
    /// truth — we leave UserDefaults alone so the listener fills it in.
    private func finishOnboarding(skipProfileWrite: Bool) {
        guard !didFinish else { return }
        didFinish = true
        focus = nil

        if !skipProfileWrite {
            UserDefaults.standard.set(babyName, forKey: "babyName")
            UserDefaults.standard.set(babyDOB.timeIntervalSince1970, forKey: "babyDOBTimestamp")
            UserDefaults.standard.set(babyGender, forKey: "babyGender")
        }
        UserDefaults.standard.set(userName.isEmpty ? "You" : userName, forKey: "userName")
        UserDefaults.standard.set(partnerName, forKey: "partnerName")

        AnalyticsService.babyProfileCreated()

        // If signed in but we didn't join a partner, make sure a family exists.
        if !skipProfileWrite, let uid = auth.userId, family.familyId == nil {
            Task { _ = try? await family.createFamily(uid: uid) }
        } else if !skipProfileWrite, family.familyId != nil {
            // Family was already created during sign-in auto-migration; push
            // the freshly entered profile to it.
            Task { await family.pushProfile() }
        }

        onComplete()
    }

    // MARK: Helpers

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
                .background(c.input)
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
        .background(colors.input)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(focused ? colors.leftAccent : colors.border,
                        lineWidth: focused ? 1.5 : 1)
        )
    }
}
