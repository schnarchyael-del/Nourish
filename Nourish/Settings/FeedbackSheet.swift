import SwiftUI
import MessageUI
import UIKit
import FirebaseAuth

struct FeedbackSheet: View {
    @Environment(\.nourishColors) private var c
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var auth = AuthManager.shared

    @State private var feedbackText = ""
    @State private var replyEmail = ""
    @State private var showMailComposer = false
    @State private var showFallbackAlert = false

    private var isSendable: Bool {
        !feedbackText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var deviceInfoFooter: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build   = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        let ios     = UIDevice.current.systemVersion
        let device  = UIDevice.current.model
        let userId  = auth.userId ?? "not signed in"
        let trimmedEmail = replyEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        let replyLine = trimmedEmail.isEmpty ? "" : "\nReply-to: \(trimmedEmail)"
        return """


        ---
        App: \(version) (\(build))
        iOS: \(ios)
        Device: \(device)
        User: \(userId)\(replyLine)
        """
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Send Feedback")
                        .font(.nSerif(22))
                        .foregroundStyle(c.ink)
                    Text("We'd love to hear from you — bugs, ideas, anything!")
                        .font(.nSans(13))
                        .foregroundStyle(c.muted)
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(c.muted)
                        .frame(width: 30, height: 30)
                        .background(c.muted.opacity(0.12))
                        .clipShape(Circle())
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 22)
            .padding(.bottom, 18)

            // Text input
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 18)
                    .fill(c.surface)
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(c.border, lineWidth: 1))

                if feedbackText.isEmpty {
                    Text("What's on your mind?")
                        .font(.nSans(15))
                        .foregroundStyle(c.muted.opacity(0.55))
                        .padding(.horizontal, 16)
                        .padding(.top, 14)
                        .allowsHitTesting(false)
                }

                TextEditor(text: $feedbackText)
                    .font(.nSans(15))
                    .foregroundStyle(c.ink)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
            }
            .frame(minHeight: 170)
            .padding(.horizontal, 20)
            .padding(.bottom, 12)

            // Optional reply email
            HStack(spacing: 10) {
                Image(systemName: "envelope")
                    .font(.system(size: 14))
                    .foregroundStyle(c.muted.opacity(0.6))
                TextField("Your email for follow-up (optional)", text: $replyEmail)
                    .font(.nSans(14))
                    .foregroundStyle(c.ink)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }
            .padding(.horizontal, 14)
            .frame(height: 46)
            .background(c.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(c.border, lineWidth: 1))
            .padding(.horizontal, 20)
            .padding(.bottom, 16)

            // Send button
            Button { sendFeedback() } label: {
                Text("Send")
                    .font(.nSans(16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(isSendable ? c.leftAccent : c.leftAccent.opacity(0.35))
                    .clipShape(Capsule())
            }
            .disabled(!isSendable)
            .buttonStyle(ScaleButtonStyle())
            .padding(.horizontal, 20)
            .padding(.bottom, 12)

            Spacer(minLength: 0)
        }
        .background(c.bg.ignoresSafeArea())
        .sheet(isPresented: $showMailComposer) {
            MailComposerView(
                toRecipient: "schnarch.yael@gmail.com",
                subject: "Nourish Feedback",
                body: feedbackText + deviceInfoFooter
            ) { result in
                showMailComposer = false
                if result == .sent {
                    AnalyticsService.feedbackSent()
                    dismiss()
                }
            }
            .ignoresSafeArea()
        }
        .alert("Mail isn't set up on this device", isPresented: $showFallbackAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Your feedback has been copied — paste it in an email to schnarch.yael@gmail.com")
        }
        .onAppear {
            AnalyticsService.feedbackOpened()
            if replyEmail.isEmpty, let email = auth.currentUser?.email {
                replyEmail = email
            }
        }
    }

    private func sendFeedback() {
        let trimmed = feedbackText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if MFMailComposeViewController.canSendMail() {
            showMailComposer = true
        } else {
            UIPasteboard.general.string = trimmed + deviceInfoFooter
            showFallbackAlert = true
            AnalyticsService.feedbackSent()
        }
    }
}

// MARK: - MFMailComposeViewController wrapper

struct MailComposerView: UIViewControllerRepresentable {
    let toRecipient: String
    let subject: String
    let body: String
    let onDismiss: (MFMailComposeResult) -> Void

    class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let onDismiss: (MFMailComposeResult) -> Void
        init(onDismiss: @escaping (MFMailComposeResult) -> Void) { self.onDismiss = onDismiss }

        func mailComposeController(_ controller: MFMailComposeViewController,
                                   didFinishWith result: MFMailComposeResult,
                                   error: Error?) {
            controller.dismiss(animated: true)
            onDismiss(result)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(onDismiss: onDismiss) }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let vc = MFMailComposeViewController()
        vc.setToRecipients([toRecipient])
        vc.setSubject(subject)
        vc.setMessageBody(body, isHTML: false)
        vc.mailComposeDelegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}
}
