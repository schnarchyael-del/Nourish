import SwiftUI
import SwiftData
import UIKit
import AuthenticationServices

struct SettingsView: View {
    @Environment(\.nourishColors) private var c
    @ObservedObject private var auth = AuthManager.shared
    @ObservedObject private var firestore = FirestoreService.shared

    @AppStorage("userName")             private var userName             = "Sarah"
    @AppStorage("babyName")             private var babyName             = "Lily"
    @AppStorage("babyDOBTimestamp")     private var babyDOBTimestamp: Double = Date.now.timeIntervalSince1970
    @AppStorage("accentVariant")        private var accentVariant        = "terra"
    @AppStorage("rightAccentVariant")   private var rightAccentVariant   = "blue"
    @AppStorage("alarmEnabled")         private var alarmEnabled         = true
    @AppStorage("alarmMinutes")         private var alarmMinutes         = 45
    @AppStorage("reminderEnabled")      private var reminderEnabled      = false
    @AppStorage("reminderHours")        private var reminderHours: Double = 3
    @AppStorage("partnerActivityNotif") private var partnerActivityNotif = true
    @AppStorage("familyCode")           private var familyCode           = ""
    @AppStorage("partnerConnected")     private var partnerConnected     = false

    @State private var activeSheet: ActiveSheet? = nil

    enum ActiveSheet: String, Identifiable {
        case profile, baby, appearance, partner, alarm, reminder, data
        var id: String { rawValue }
    }

    private var babyDOB: Date { Date(timeIntervalSince1970: babyDOBTimestamp) }

    private var babyAge: String {
        let weeks = Calendar.current.dateComponents([.weekOfYear], from: babyDOB, to: .now).weekOfYear ?? 0
        if weeks < 16 { return "\(weeks) week\(weeks == 1 ? "" : "s")" }
        let months = Calendar.current.dateComponents([.month], from: babyDOB, to: .now).month ?? 0
        return "\(months) month\(months == 1 ? "" : "s")"
    }

    private var appearanceSubtitle: String {
        "\(accentVariant.capitalized) · \(rightAccentVariant.capitalized)"
    }

    private var partnerSubtitle: String {
        partnerConnected ? "Connected with partner" : "Not set up"
    }

    // MARK: Body

    var body: some View {
        mainView
            .sheet(item: $activeSheet) { sheet in
                sheetContent(for: sheet)
                    .environment(\.nourishColors, c)
                    .presentationDetents([.fraction(0.875)])
                    .presentationDragIndicator(.hidden)
                    .presentationCornerRadius(28)
            }
            .alert(
                "Replace local data?",
                isPresented: $firestore.hasPendingAccountSwitch
            ) {
                Button("Cancel", role: .cancel) { firestore.cancelAccountSwitch() }
                Button("Continue", role: .destructive) {
                    Task { await firestore.confirmAccountSwitch() }
                }
            } message: {
                Text("Signing into a different account will replace your local feeding data with the data on this account. This can't be undone.")
            }
            .onAppear {
                if familyCode.isEmpty { familyCode = Self.generateFamilyCode() }
            }
            .onChange(of: reminderEnabled) { _, v in
                NotificationManager.shared.updateReminder(enabled: v, hours: reminderHours)
            }
            .onChange(of: reminderHours) { _, v in
                guard reminderEnabled else { return }
                NotificationManager.shared.updateReminder(enabled: true, hours: v)
            }
    }

    @ViewBuilder
    private func sheetContent(for sheet: ActiveSheet) -> some View {
        switch sheet {
        case .profile:    ProfileEditView()
        case .baby:       BabyEditView()
        case .appearance: AppearanceSubView()
        case .partner:    PartnerSubView()
        case .alarm:      AlarmSubView()
        case .reminder:   ReminderSubView()
        case .data:       DataSubView()
        }
    }

    // MARK: Main settings list

    private var mainView: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Settings")
                    .font(.nSerif(28))
                    .foregroundStyle(c.ink)
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 10)

            ScrollView {
                VStack(spacing: 0) {
                    accountSection

                    settingsGroup("Profile") {
                        row(icon: "👤", label: userName, sub: "Tap to edit profile",
                            action: { activeSheet = .profile })
                    }

                    settingsGroup("Baby") {
                        row(icon: "🍼", label: babyName, sub: "Baby's name",
                            action: { activeSheet = .baby })
                        Divider().overlay(c.border).padding(.horizontal, 18)
                        row(icon: "📅",
                            label: babyDOB.formatted(date: .abbreviated, time: .omitted),
                            sub: "Date of birth", action: { activeSheet = .baby })
                        Divider().overlay(c.border).padding(.horizontal, 18)
                        row(icon: "🌱", label: babyAge, sub: "Current age")
                    }

                    settingsGroup("Appearance") {
                        Button { activeSheet = .appearance } label: {
                            settingsNavRow(icon: "🎨", label: "Appearance", sub: appearanceSubtitle)
                        }
                        .buttonStyle(.plain)
                    }

                    settingsGroup("Partner sharing") {
                        Button { activeSheet = .partner } label: {
                            settingsNavRow(icon: "👨‍👩‍👧", label: "Partner sharing", sub: partnerSubtitle)
                        }
                        .buttonStyle(.plain)
                    }

                    settingsGroup("Notifications") {
                        notificationsSection
                    }

                    settingsGroup("Data") {
                        Button { activeSheet = .data } label: {
                            settingsNavRow(icon: "📤", label: "Export sessions",
                                          sub: "Download your feeding history as CSV")
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
        .background(c.bg)
    }

    // MARK: Account section

    private var accountSection: some View {
        settingsGroup("Account") {
            if auth.isSignedIn {
                signedInRow
            } else {
                signInPrompt
            }
        }
    }

    private var signedInRow: some View {
        HStack(spacing: 14) {
            Text("👤").font(.nSans(19))
            VStack(alignment: .leading, spacing: 2) {
                Text(auth.displayLabel)
                    .font(.nSans(15, weight: .semibold))
                    .foregroundStyle(c.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 6) {
                    if firestore.isSyncing {
                        ProgressView().scaleEffect(0.7)
                        Text("Syncing…")
                            .font(.nSans(12))
                            .foregroundStyle(c.muted)
                    } else {
                        Text("Synced to cloud")
                            .font(.nSans(12))
                            .foregroundStyle(c.muted)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                auth.signOut()
            } label: {
                Text("Sign Out")
                    .font(.nSans(13))
                    .foregroundStyle(c.muted)
                    .padding(.horizontal, 12)
                    .frame(height: 32)
                    .overlay(Capsule().stroke(c.border, lineWidth: 1))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private var signInPrompt: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sign in to back up your sessions and sync them across devices.")
                .font(.nSans(13))
                .foregroundStyle(c.muted)
                .lineSpacing(4)

            ZStack {
                SignInWithAppleButton(.signIn,
                    onRequest: { auth.configure($0) },
                    onCompletion: { auth.handleAppleSignIn($0) }
                )
                .signInWithAppleButtonStyle(.black)
                .frame(height: 50)
                .clipShape(Capsule())
                .disabled(auth.isWorking)
                .opacity(auth.isWorking ? 0.5 : 1)

                if auth.isWorking {
                    ProgressView().tint(.white)
                }
            }

            if let error = auth.errorMessage {
                Text(error)
                    .font(.nSans(12))
                    .foregroundStyle(.red.opacity(0.85))
                    .lineSpacing(3)
            }
        }
        .padding(18)
    }

    // MARK: Notifications section

    private var alarmSubtitle: String {
        alarmEnabled ? "After \(alarmMinutes) min · On" : "Off"
    }

    private var reminderSubtitle: String {
        guard reminderEnabled else { return "Off" }
        let label = reminderHours.truncatingRemainder(dividingBy: 1) == 0
            ? "\(Int(reminderHours))h" : "\(reminderHours)h"
        return "Every \(label) · On"
    }

    private var notificationsSection: some View {
        VStack(spacing: 0) {
            Button { activeSheet = .alarm } label: {
                settingsNavRow(icon: "⏱", label: "Session alarm", sub: alarmSubtitle)
            }
            .buttonStyle(.plain)

            Divider().overlay(c.border).padding(.horizontal, 18)

            Button { activeSheet = .reminder } label: {
                settingsNavRow(icon: "🔔", label: "Feed reminder", sub: reminderSubtitle)
            }
            .buttonStyle(.plain)

            Divider().overlay(c.border).padding(.horizontal, 18)

            toggleRow(icon: "👫", label: "Partner activity",
                      sub: "When they log a session",
                      isOn: $partnerActivityNotif)
        }
    }

    // MARK: Reusable components

    private func settingsNavRow(icon: String, label: String, sub: String) -> some View {
        HStack(spacing: 14) {
            Text(icon).font(.nSans(19))
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.nSans(15, weight: .semibold)).foregroundStyle(c.ink)
                Text(sub).font(.nSans(12)).foregroundStyle(c.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .font(.nSans(13, weight: .semibold))
                .foregroundStyle(c.muted.opacity(0.45))
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
    }

    private func settingsGroup<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title.uppercased())
                .font(.nSans(11, weight: .bold))
                .foregroundStyle(c.muted)
                .kerning(0.1 * 11)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4).padding(.bottom, 8)
            VStack(spacing: 0) { content() }
                .background(c.surface)
                .clipShape(RoundedRectangle(cornerRadius: 22))
                .overlay(RoundedRectangle(cornerRadius: 22).stroke(c.border, lineWidth: 1))
        }
        .padding(.bottom, 14)
    }

    private func row(icon: String, label: String, sub: String? = nil,
                     trailing: (() -> AnyView)? = nil, action: (() -> Void)? = nil) -> some View {
        Button { action?() } label: {
            HStack(spacing: 14) {
                Text(icon).font(.nSans(19))
                VStack(alignment: .leading, spacing: 2) {
                    Text(label).font(.nSans(15, weight: .semibold)).foregroundStyle(c.ink)
                    if let sub { Text(sub).font(.nSans(12)).foregroundStyle(c.muted) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let trailing = trailing { trailing() }
                else if action != nil {
                    Image(systemName: "chevron.right")
                        .font(.nSans(13)).foregroundStyle(c.muted.opacity(0.45))
                }
            }
            .padding(.horizontal, 18).padding(.vertical, 14)
        }
        .buttonStyle(.plain)
        .disabled(action == nil)
    }

    private func toggleRow(icon: String, label: String, sub: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 14) {
            Text(icon).font(.nSans(19))
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.nSans(15, weight: .semibold)).foregroundStyle(c.ink)
                Text(sub).font(.nSans(12)).foregroundStyle(c.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Toggle("", isOn: isOn).toggleStyle(NourishToggleStyle(colors: c)).labelsHidden()
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
    }

    private static func generateFamilyCode() -> String {
        let chars = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        return String((0..<6).map { _ in chars.randomElement()! })
    }
}

// MARK: - Sheet header (shared by all sub-views)

private struct NourishSheetHeader: View {
    @Environment(\.nourishColors) private var c
    let title: String
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color.primary.opacity(0.15))
                .frame(width: 36, height: 4)
                .padding(.top, 14)
                .padding(.bottom, 16)

            HStack {
                Text(title)
                    .font(.nSerif(22))
                    .foregroundStyle(c.ink)
                Spacer()
                Button(action: onDismiss) {
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
}

// MARK: - Appearance sub-screen

private struct AppearanceSubView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.nourishColors) private var c
    @AppStorage("accentVariant")      private var accentVariant      = "terra"
    @AppStorage("rightAccentVariant") private var rightAccentVariant = "blue"
    @AppStorage("darkActiveScreen")   private var darkActiveScreen   = true
    @AppStorage("showEncouragements") private var showEncouragements = true

    var body: some View {
        VStack(spacing: 0) {
            NourishSheetHeader(title: "Appearance", onDismiss: { dismiss() })
            ScrollView {
                VStack(spacing: 0) {
                    VStack(spacing: 0) {
                        HStack {
                            Text("🎨").font(.nSans(19))
                            Text("Left accent")
                                .font(.nSans(15, weight: .semibold))
                                .foregroundStyle(c.ink)
                            Spacer()
                            HStack(spacing: 8) {
                                ForEach(AccentVariant.allCases, id: \.rawValue) { v in
                                    Button { accentVariant = v.rawValue } label: {
                                        Circle().fill(v.swatchColor).frame(width: 26, height: 26)
                                            .overlay(Circle().stroke(c.ink, lineWidth: accentVariant == v.rawValue ? 2 : 0).padding(2))
                                    }.buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(.horizontal, 18).padding(.vertical, 14)

                        Divider().overlay(c.border).padding(.horizontal, 18)

                        HStack {
                            Text("🎨").font(.nSans(19))
                            Text("Right accent")
                                .font(.nSans(15, weight: .semibold))
                                .foregroundStyle(c.ink)
                            Spacer()
                            HStack(spacing: 8) {
                                ForEach(RightAccentVariant.allCases, id: \.rawValue) { v in
                                    Button { rightAccentVariant = v.rawValue } label: {
                                        Circle().fill(v.swatchColor).frame(width: 26, height: 26)
                                            .overlay(Circle().stroke(c.ink, lineWidth: rightAccentVariant == v.rawValue ? 2 : 0).padding(2))
                                    }.buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(.horizontal, 18).padding(.vertical, 14)

                        Divider().overlay(c.border).padding(.horizontal, 18)

                        HStack(spacing: 14) {
                            Text("🌙").font(.nSans(19))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Dark active screen").font(.nSans(15, weight: .semibold)).foregroundStyle(c.ink)
                                Text("Dark background while feeding").font(.nSans(12)).foregroundStyle(c.muted)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Toggle("", isOn: $darkActiveScreen)
                                .toggleStyle(NourishToggleStyle(colors: c)).labelsHidden()
                        }
                        .padding(.horizontal, 18).padding(.vertical, 14)

                        Divider().overlay(c.border).padding(.horizontal, 18)

                        HStack(spacing: 14) {
                            Text("✨").font(.nSans(19))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Encouragements").font(.nSans(15, weight: .semibold)).foregroundStyle(c.ink)
                                Text("Affirmations during sessions").font(.nSans(12)).foregroundStyle(c.muted)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Toggle("", isOn: $showEncouragements)
                                .toggleStyle(NourishToggleStyle(colors: c)).labelsHidden()
                        }
                        .padding(.horizontal, 18).padding(.vertical, 14)
                    }
                    .background(c.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 22))
                    .overlay(RoundedRectangle(cornerRadius: 22).stroke(c.border, lineWidth: 1))
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
        }
        .background(c.bg.ignoresSafeArea())
    }
}

// MARK: - Partner sharing sub-screen

private struct PartnerSubView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.nourishColors) private var c
    @AppStorage("familyCode")       private var familyCode       = ""
    @AppStorage("partnerConnected") private var partnerConnected = false

    @State private var joinCodeInput = ""
    @State private var isJoining     = false
    @State private var joinError: String? = nil
    @State private var codeCopied    = false

    var body: some View {
        VStack(spacing: 0) {
            NourishSheetHeader(title: "Partner Sharing", onDismiss: { dismiss() })
            ScrollView {
                VStack(spacing: 0) {
                    partnerContent
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
        }
        .background(c.bg.ignoresSafeArea())
        .onAppear {
            if familyCode.isEmpty { familyCode = Self.generateFamilyCode() }
        }
    }

    private var partnerContent: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Your family code".uppercased())
                    .font(.nSans(11, weight: .bold))
                    .foregroundStyle(c.muted)
                    .kerning(0.09 * 11)

                HStack(spacing: 12) {
                    HStack(spacing: 6) {
                        ForEach(Array(familyCode.enumerated()), id: \.offset) { _, char in
                            Text(String(char))
                                .font(.nSans(22, weight: .bold))
                                .foregroundStyle(c.leftText)
                                .frame(width: 30, height: 36)
                                .background(c.leftBg)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    Spacer()
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        UIPasteboard.general.string = familyCode
                        withAnimation { codeCopied = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            withAnimation { codeCopied = false }
                        }
                    } label: {
                        Label(codeCopied ? "Copied!" : "Copy",
                              systemImage: codeCopied ? "checkmark" : "doc.on.doc")
                            .font(.nSans(13, weight: .semibold))
                            .foregroundStyle(codeCopied ? c.green : c.leftAccent)
                            .padding(.horizontal, 14)
                            .frame(height: 36)
                            .background(codeCopied ? c.greenBg : c.leftBg)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(
                                codeCopied ? c.green.opacity(0.3) : c.leftAccent.opacity(0.3), lineWidth: 1))
                    }
                    .buttonStyle(ScaleButtonStyle())
                    .animation(.easeInOut(duration: 0.2), value: codeCopied)
                }
            }
            .padding(.horizontal, 18).padding(.vertical, 14)

            Divider().overlay(c.border).padding(.horizontal, 18)

            ShareLink(
                item: "Join me on Nourish! Use code \(familyCode) to sync our feeds 🤱",
                preview: SharePreview("Nourish — family code \(familyCode)")
            ) {
                HStack(spacing: 14) {
                    Text("📤").font(.nSans(19))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Share your code").font(.nSans(15, weight: .semibold)).foregroundStyle(c.ink)
                        Text("Invite your partner to join").font(.nSans(12)).foregroundStyle(c.muted)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.nSans(13)).foregroundStyle(c.muted.opacity(0.45))
                }
                .padding(.horizontal, 18).padding(.vertical, 14)
            }
            .buttonStyle(.plain)

            Divider().overlay(c.border).padding(.horizontal, 18)

            if partnerConnected {
                HStack(spacing: 14) {
                    Text("✓").font(.nSans(19, weight: .bold)).foregroundStyle(c.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Connected with partner").font(.nSans(15, weight: .semibold)).foregroundStyle(c.ink)
                        Text("Their sessions will be marked 'by partner'").font(.nSans(12)).foregroundStyle(c.muted)
                    }
                    Spacer()
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        PartnerSyncManager.shared.disconnect()
                        partnerConnected = false
                    } label: {
                        Text("Disconnect")
                            .font(.nSans(13))
                            .foregroundStyle(c.muted)
                            .padding(.horizontal, 12).frame(height: 32)
                            .overlay(Capsule().stroke(c.border, lineWidth: 1))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 18).padding(.vertical, 14)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Join with a code".uppercased())
                        .font(.nSans(11, weight: .bold)).foregroundStyle(c.muted).kerning(0.09 * 11)
                    HStack(spacing: 10) {
                        TextField("Partner's code", text: $joinCodeInput)
                            .textFieldStyle(.plain)
                            .font(.nSans(17, weight: .semibold))
                            .foregroundStyle(c.ink)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.characters)
                            .padding(.horizontal, 14).frame(height: 44)
                            .background(c.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(c.border, lineWidth: 1))
                            .onChange(of: joinCodeInput) { _, v in
                                joinCodeInput = String(v.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(6))
                            }
                        Button {
                            guard joinCodeInput.count == 6 else { return }
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            isJoining = true; joinError = nil
                            Task {
                                await PartnerSyncManager.shared.joinWithCode(joinCodeInput)
                                if PartnerSyncManager.shared.isConnected {
                                    partnerConnected = true; joinCodeInput = ""
                                } else {
                                    joinError = PartnerSyncManager.shared.errorMessage ?? "Code not found."
                                }
                                isJoining = false
                            }
                        } label: {
                            Group {
                                if isJoining { ProgressView().tint(.white).frame(width: 70) }
                                else { Text("Join").font(.nSans(15, weight: .bold)).frame(width: 70) }
                            }
                            .foregroundStyle(.white).frame(height: 44)
                            .background(joinCodeInput.count == 6 ? c.leftAccent : c.muted.opacity(0.3))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(ScaleButtonStyle())
                        .disabled(joinCodeInput.count < 6 || isJoining)
                    }
                    if let err = joinError {
                        Text(err).font(.nSans(12)).foregroundStyle(.red.opacity(0.8))
                    }
                }
                .padding(.horizontal, 18).padding(.vertical, 14).background(c.bg)
            }
        }
        .background(c.surface)
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(c.border, lineWidth: 1))
    }

    private static func generateFamilyCode() -> String {
        let chars = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        return String((0..<6).map { _ in chars.randomElement()! })
    }
}

// MARK: - Alarm sub-screen

private struct AlarmSubView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.nourishColors) private var c
    @AppStorage("alarmEnabled") private var alarmEnabled = true
    @AppStorage("alarmMinutes") private var alarmMinutes = 45

    var body: some View {
        VStack(spacing: 0) {
            NourishSheetHeader(title: "Session Alarm", onDismiss: { dismiss() })
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(spacing: 0) {
                        HStack(spacing: 14) {
                            Text("⏱").font(.nSans(19))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Enable alarm").font(.nSans(15, weight: .semibold)).foregroundStyle(c.ink)
                                Text("Fires a vibration + sound mid-session")
                                    .font(.nSans(12)).foregroundStyle(c.muted)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Toggle("", isOn: $alarmEnabled).toggleStyle(NourishToggleStyle(colors: c)).labelsHidden()
                        }
                        .padding(.horizontal, 18).padding(.vertical, 14)
                    }
                    .background(c.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 22))
                    .overlay(RoundedRectangle(cornerRadius: 22).stroke(c.border, lineWidth: 1))
                    .padding(.bottom, 20)

                    if alarmEnabled {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Alert after".uppercased())
                                .font(.nSans(11, weight: .bold)).foregroundStyle(c.muted).kerning(0.09 * 11)

                            FlowLayout(spacing: 8) {
                                ForEach([15, 30, 45, 60, 90], id: \.self) { mins in
                                    Button { alarmMinutes = mins } label: {
                                        Text("\(mins) min")
                                            .font(.nSans(13, weight: .semibold))
                                            .foregroundStyle(alarmMinutes == mins ? .white : c.muted)
                                            .padding(.horizontal, 14).padding(.vertical, 6)
                                            .background(alarmMinutes == mins ? c.leftAccent : Color.clear)
                                            .clipShape(Capsule())
                                            .overlay(Capsule().stroke(
                                                alarmMinutes == mins ? c.leftAccent : c.border, lineWidth: 1.5))
                                    }
                                    .buttonStyle(.plain)
                                    .animation(.easeInOut(duration: 0.15), value: alarmMinutes)
                                }
                            }

                            HStack(spacing: 8) {
                                Text("Custom:").font(.nSans(13)).foregroundStyle(c.muted)
                                ForEach([("−", -5), ("+", 5)], id: \.0) { op, delta in
                                    Button { alarmMinutes = max(5, min(180, alarmMinutes + delta)) } label: {
                                        Text(op).font(.nSans(17)).foregroundStyle(c.ink)
                                            .frame(width: 32, height: 32)
                                            .background(c.surface)
                                            .clipShape(RoundedRectangle(cornerRadius: 10))
                                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(c.border, lineWidth: 1))
                                    }
                                    .buttonStyle(ScaleButtonStyle())
                                }
                                Text("\(alarmMinutes) min")
                                    .font(.nSans(14, weight: .bold)).foregroundStyle(c.leftAccent)
                                    .frame(maxWidth: .infinity).frame(height: 32)
                                    .background(c.surface)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(c.leftAccent, lineWidth: 1))
                                    .contentTransition(.numericText())
                            }
                        }
                        .padding(18)
                        .background(c.leftBg)
                        .clipShape(RoundedRectangle(cornerRadius: 22))
                        .overlay(RoundedRectangle(cornerRadius: 22).stroke(c.leftAccent.opacity(0.15), lineWidth: 1))
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 32)
                .animation(.spring(response: 0.38, dampingFraction: 0.75), value: alarmEnabled)
            }
        }
        .background(c.bg.ignoresSafeArea())
    }
}

// MARK: - Reminder sub-screen

private struct ReminderSubView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.nourishColors) private var c
    @AppStorage("reminderEnabled") private var reminderEnabled = false
    @AppStorage("reminderHours")   private var reminderHours: Double = 3

    var body: some View {
        VStack(spacing: 0) {
            NourishSheetHeader(title: "Feed Reminder", onDismiss: { dismiss() })
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(spacing: 0) {
                        HStack(spacing: 14) {
                            Text("🔔").font(.nSans(19))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Enable reminder").font(.nSans(15, weight: .semibold)).foregroundStyle(c.ink)
                                Text("System notification when it's time to feed")
                                    .font(.nSans(12)).foregroundStyle(c.muted)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Toggle("", isOn: $reminderEnabled).toggleStyle(NourishToggleStyle(colors: c)).labelsHidden()
                        }
                        .padding(.horizontal, 18).padding(.vertical, 14)
                    }
                    .background(c.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 22))
                    .overlay(RoundedRectangle(cornerRadius: 22).stroke(c.border, lineWidth: 1))
                    .padding(.bottom, 20)

                    if reminderEnabled {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Remind every".uppercased())
                                .font(.nSans(11, weight: .bold)).foregroundStyle(c.muted).kerning(0.09 * 11)

                            FlowLayout(spacing: 8) {
                                ForEach([1.0, 1.5, 2.0, 2.5, 3.0, 4.0], id: \.self) { h in
                                    Button { reminderHours = h } label: {
                                        let label = h.truncatingRemainder(dividingBy: 1) == 0
                                            ? "\(Int(h))h" : "\(h)h"
                                        Text(label)
                                            .font(.nSans(14, weight: .semibold))
                                            .foregroundStyle(reminderHours == h ? .white : c.muted)
                                            .padding(.horizontal, 16).padding(.vertical, 6)
                                            .background(reminderHours == h ? c.leftAccent : Color.clear)
                                            .clipShape(Capsule())
                                            .overlay(Capsule().stroke(
                                                reminderHours == h ? c.leftAccent : c.border, lineWidth: 1.5))
                                    }
                                    .buttonStyle(.plain)
                                    .animation(.easeInOut(duration: 0.15), value: reminderHours)
                                }
                            }

                            Text("You'll receive a notification if no session has been logged for this long.")
                                .font(.nSans(13))
                                .foregroundStyle(c.muted)
                                .lineSpacing(4)
                        }
                        .padding(18)
                        .background(c.leftBg)
                        .clipShape(RoundedRectangle(cornerRadius: 22))
                        .overlay(RoundedRectangle(cornerRadius: 22).stroke(c.leftAccent.opacity(0.15), lineWidth: 1))
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 32)
                .animation(.spring(response: 0.38, dampingFraction: 0.75), value: reminderEnabled)
            }
        }
        .background(c.bg.ignoresSafeArea())
        .onChange(of: reminderEnabled) { _, v in
            NotificationManager.shared.updateReminder(enabled: v, hours: reminderHours)
        }
        .onChange(of: reminderHours) { _, v in
            guard reminderEnabled else { return }
            NotificationManager.shared.updateReminder(enabled: true, hours: v)
        }
    }
}

// MARK: - Data export sub-screen

private struct DataSubView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.nourishColors) private var c
    @Query(sort: \FeedingSession.startTime, order: .reverse) private var sessions: [FeedingSession]

    var body: some View {
        VStack(spacing: 0) {
            NourishSheetHeader(title: "Data & Export", onDismiss: { dismiss() })
            ScrollView {
                VStack(spacing: 0) {
                    HStack(spacing: 10) {
                        statCell(value: "\(sessions.count)", label: "sessions")
                        statCell(value: "\(bottleCount)", label: "bottle feeds")
                        statCell(value: "\(breastCount)", label: "breast feeds")
                    }
                    .padding(.bottom, 20)

                    VStack(alignment: .leading, spacing: 16) {
                        Text("Export as CSV")
                            .font(.nSerif(20))
                            .foregroundStyle(c.ink)

                        Text("Your full session history in spreadsheet-compatible format. Opens the iOS share sheet so you can save to Files, email, or open in Numbers.")
                            .font(.nSans(14))
                            .foregroundStyle(c.muted)
                            .lineSpacing(4)

                        Button {
                            exportSessions()
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "arrow.up.doc.fill")
                                    .font(.nSans(16))
                                Text("Export \(sessions.count) session\(sessions.count == 1 ? "" : "s")")
                                    .font(.nSans(16, weight: .bold))
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(sessions.isEmpty ? c.muted.opacity(0.3) : c.leftAccent)
                            .clipShape(Capsule())
                            .shadow(color: sessions.isEmpty ? .clear : c.leftShadow, radius: 10, y: 4)
                        }
                        .buttonStyle(ScaleButtonStyle())
                        .disabled(sessions.isEmpty)
                    }
                    .padding(20)
                    .background(c.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 22))
                    .overlay(RoundedRectangle(cornerRadius: 22).stroke(c.border, lineWidth: 1))
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
        }
        .background(c.bg.ignoresSafeArea())
    }

    private var bottleCount: Int { sessions.filter { $0.feedType == .bottle }.count }
    private var breastCount: Int { sessions.filter { $0.feedType != .bottle }.count }

    private func statCell(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.nSerif(22)).foregroundStyle(c.ink)
            Text(label).font(.nSans(12)).foregroundStyle(c.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .background(c.surface)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(c.border, lineWidth: 1))
    }

    private func exportSessions() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        let df = DateFormatter(); df.dateFormat = "d MMM yyyy"
        let tf = DateFormatter(); tf.dateFormat = "HH:mm"

        var csv = "Date,Start Time,Duration (mins),Left Duration (mins),Right Duration (mins),Side,Bottle Type,Amount ML\n"
        for s in sessions {
            let side = s.feedType == .bottle ? "" : s.feedType.displayName
            let row = [
                df.string(from: s.startTime),
                tf.string(from: s.startTime),
                "\(s.durationMinutes)",
                "\(s.leftMinutesResolved)",
                "\(s.rightMinutesResolved)",
                side,
                s.bottleContentType?.displayName ?? "",
                s.bottleAmountMl.map { "\($0)" } ?? ""
            ].joined(separator: ",")
            csv += row + "\n"
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Nourish_Sessions.csv")
        guard (try? csv.write(to: url, atomically: true, encoding: .utf8)) != nil else { return }

        let vc = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
        let root = windowScene.windows.first(where: { $0.isKeyWindow })?.rootViewController
        else { return }

        var topVC = root
        while let presented = topVC.presentedViewController { topVC = presented }
        topVC.present(vc, animated: true)
    }
}

// MARK: - Edit Profile Sheet

private struct ProfileEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.nourishColors) private var c
    @AppStorage("userName") private var userName = "Sarah"

    var body: some View {
        VStack(spacing: 0) {
            NourishSheetHeader(title: "Edit Profile", onDismiss: { dismiss() })
            ScrollView {
                VStack(spacing: 0) {
                    Text(String(userName.prefix(1)))
                        .font(.nSans(28, weight: .bold)).foregroundStyle(c.leftText)
                        .frame(width: 80, height: 80).background(c.leftBg).clipShape(Circle())
                        .overlay(Circle().stroke(c.leftAccent, lineWidth: 2))
                        .frame(maxWidth: .infinity).padding(.bottom, 28)
                    editField("Your name", text: $userName)
                    saveButton { dismiss() }
                }
                .padding(.horizontal, 22).padding(.top, 24).padding(.bottom, 28)
            }
        }
        .background(c.bg.ignoresSafeArea())
    }

    private func editField(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(.nSans(12, weight: .bold)).foregroundStyle(c.muted).kerning(0.08 * 12)
                .frame(maxWidth: .infinity, alignment: .leading)
            TextField(label, text: text).textFieldStyle(.plain)
                .font(.nSans(17, weight: .semibold)).foregroundStyle(c.ink)
                .padding(.horizontal, 18).frame(height: 54)
                .background(Color.white).clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(c.border, lineWidth: 1))
        }.padding(.bottom, 16)
    }

    private func saveButton(action: @escaping () -> Void) -> some View {
        Button("Save changes", action: action)
            .font(.nSans(17, weight: .bold)).foregroundStyle(.white)
            .frame(maxWidth: .infinity).frame(height: 58)
            .background(c.leftAccent).clipShape(Capsule())
            .shadow(color: c.leftShadow, radius: 10, y: 4)
            .buttonStyle(ScaleButtonStyle())
    }
}

// MARK: - Baby Profile Sheet

private struct BabyEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.nourishColors) private var c
    @AppStorage("babyName")         private var babyName         = "Lily"
    @AppStorage("babyDOBTimestamp") private var babyDOBTimestamp: Double = Date.now.timeIntervalSince1970
    @State private var showDOBPicker = false
    @FocusState private var nameFocused: Bool

    private var babyDOB: Date { Date(timeIntervalSince1970: babyDOBTimestamp) }
    private var babyAge: String {
        let w = Calendar.current.dateComponents([.weekOfYear], from: babyDOB, to: .now).weekOfYear ?? 0
        if w < 16 { return "\(w) week\(w == 1 ? "" : "s")" }
        let m = Calendar.current.dateComponents([.month], from: babyDOB, to: .now).month ?? 0
        return "\(m) month\(m == 1 ? "" : "s")"
    }

    var body: some View {
        VStack(spacing: 0) {
            NourishSheetHeader(title: "Baby Profile", onDismiss: { dismiss() })
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    editField("Baby's name", text: $babyName)
                        .focused($nameFocused)
                        .submitLabel(.done)
                        .onSubmit { nameFocused = false }
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Date of birth".uppercased())
                            .font(.nSans(12, weight: .bold)).foregroundStyle(c.muted)
                            .kerning(0.08 * 12).padding(.bottom, 6)
                        Button {
                            nameFocused = false
                            withAnimation(.easeInOut(duration: 0.25)) { showDOBPicker.toggle() }
                        } label: {
                            HStack {
                                Text(babyDOB.formatted(date: .abbreviated, time: .omitted))
                                    .font(.nSans(17, weight: .semibold)).foregroundStyle(c.ink)
                                Spacer()
                                Image(systemName: showDOBPicker ? "chevron.up" : "calendar")
                                    .font(.nSans(15)).foregroundStyle(c.muted)
                            }
                            .padding(.horizontal, 18).frame(height: 54).background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .overlay(RoundedRectangle(cornerRadius: 16).stroke(
                                showDOBPicker ? c.leftAccent : c.border,
                                lineWidth: showDOBPicker ? 1.5 : 1))
                        }.buttonStyle(.plain)
                        if showDOBPicker {
                            DatePicker("", selection: Binding(
                                get: { babyDOB },
                                set: { babyDOBTimestamp = $0.timeIntervalSince1970 }
                            ), in: ...Date.now, displayedComponents: .date)
                                .datePickerStyle(.graphical).tint(c.leftAccent).colorScheme(.light)
                                .padding(8).background(Color.white)
                                .clipShape(RoundedRectangle(cornerRadius: 18))
                                .overlay(RoundedRectangle(cornerRadius: 18).stroke(c.border, lineWidth: 1))
                                .padding(.top, 4)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                    .padding(.bottom, 20)
                    Text("🌱 **\(babyName) is \(babyAge) old.** Reminders are calibrated to their feeding schedule.")
                        .font(.nSans(14)).foregroundStyle(c.muted).lineSpacing(4)
                        .padding(14).background(c.leftBg)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .overlay(RoundedRectangle(cornerRadius: 18).stroke(c.leftAccent.opacity(0.15), lineWidth: 1))
                        .padding(.bottom, 20)
                    saveButton {
                        nameFocused = false
                        dismiss()
                    }
                }
                .padding(.horizontal, 22).padding(.top, 24).padding(.bottom, 28)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(c.bg.ignoresSafeArea())
    }

    private func editField(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(.nSans(12, weight: .bold)).foregroundStyle(c.muted).kerning(0.08 * 12)
                .frame(maxWidth: .infinity, alignment: .leading)
            TextField(label, text: text).textFieldStyle(.plain)
                .font(.nSans(17, weight: .semibold)).foregroundStyle(c.ink)
                .padding(.horizontal, 18).frame(height: 54)
                .background(Color.white).clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(c.border, lineWidth: 1))
        }.padding(.bottom, 16)
    }

    private func saveButton(action: @escaping () -> Void) -> some View {
        Button("Save changes", action: action)
            .font(.nSans(17, weight: .bold)).foregroundStyle(.white)
            .frame(maxWidth: .infinity).frame(height: 58)
            .background(c.leftAccent).clipShape(Capsule())
            .shadow(color: c.leftShadow, radius: 10, y: 4)
            .buttonStyle(ScaleButtonStyle())
    }
}

// MARK: - Custom toggle style

struct NourishToggleStyle: ToggleStyle {
    let colors: NourishColors
    func makeBody(configuration: Configuration) -> some View {
        ZStack(alignment: configuration.isOn ? .trailing : .leading) {
            Capsule()
                .fill(configuration.isOn ? colors.leftAccent : Color(hex: "7A6E67").opacity(0.2))
                .frame(width: 48, height: 28)
                .overlay(Capsule().stroke(configuration.isOn ? colors.leftAccent.opacity(0.3) : .clear, lineWidth: 1))
            Circle().fill(.white).frame(width: 22, height: 22)
                .shadow(color: .black.opacity(0.2), radius: 2, y: 1).padding(3)
        }
        .animation(.easeInOut(duration: 0.22), value: configuration.isOn)
        .onTapGesture { configuration.isOn.toggle() }
    }
}

// MARK: - Flow layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        var x: CGFloat = 0; var y: CGFloat = 0; var rowH: CGFloat = 0
        for view in subviews {
            let s = view.sizeThatFits(.unspecified)
            if x + s.width > width && x > 0 { y += rowH + spacing; x = 0; rowH = 0 }
            x += s.width + spacing; rowH = max(rowH, s.height)
        }
        return CGSize(width: width, height: y + rowH)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX; var y = bounds.minY; var rowH: CGFloat = 0
        for view in subviews {
            let s = view.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX && x > bounds.minX { y += rowH + spacing; x = bounds.minX; rowH = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing; rowH = max(rowH, s.height)
        }
    }
}
