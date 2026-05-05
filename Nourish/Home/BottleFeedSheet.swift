import SwiftUI
import SwiftData

struct BottleFeedSheet: View {
    @Environment(\.nourishColors) private var c
    @Environment(\.modelContext) private var modelContext
    @Binding var isPresented: Bool

    @State private var step: Int = 1
    @State private var bottleType: BottleContentType = .breastmilk
    @State private var amountMl: Int = 120

    var body: some View {
        VStack(spacing: 0) {
            dragHandle

            if step == 1 {
                typeStep
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
            } else {
                amountStep
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 32)
        .background(c.bg)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 20, y: -8)
        .animation(.easeInOut(duration: 0.2), value: step)
    }

    private var dragHandle: some View {
        Capsule()
            .fill(Color.primary.opacity(0.18))
            .frame(width: 36, height: 4)
            .padding(.vertical, 20)
    }

    // MARK: Step 1 – Choose type

    private var typeStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Bottle feed 🍼")
                .font(.nSerif(24))
                .foregroundStyle(c.ink)
                .padding(.bottom, 6)

            Text("What's in the bottle?")
                .font(.nSans(14))
                .foregroundStyle(c.muted)
                .padding(.bottom, 20)

            HStack(spacing: 12) {
                ForEach(BottleContentType.allCases, id: \.rawValue) { type in
                    Button {
                        bottleType = type
                        withAnimation { step = 2 }
                    } label: {
                        VStack(spacing: 6) {
                            Text(type.icon)
                                .font(.nSans(28))
                            Text(type.displayName)
                                .font(.nSans(14, weight: .bold))
                                .foregroundStyle(c.bottleAccent)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 80)
                        .background(c.bottleBg)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(c.bottleBorder, lineWidth: 2)
                        )
                    }
                    .buttonStyle(ScaleButtonStyle())
                }
            }
            .padding(.bottom, 16)

            cancelButton
        }
    }

    // MARK: Step 2 – Amount

    private var amountStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Button {
                    withAnimation { step = 1 }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.nSans(14, weight: .semibold))
                        .foregroundStyle(c.ink)
                        .frame(width: 34, height: 34)
                        .background(c.surface)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(c.border, lineWidth: 1))
                }
                .buttonStyle(.plain)

                HStack(spacing: 4) {
                    Text(bottleType.icon)
                        .font(.nSans(20))
                    Text(bottleType.displayName)
                        .font(.nSerif(22))
                        .foregroundStyle(c.ink)
                }
            }
            .padding(.bottom, 18)

            Text("How much did the baby drink?")
                .font(.nSans(13))
                .foregroundStyle(c.muted)
                .italic()
                .padding(.bottom, 16)

            // Stepper buttons
            HStack(spacing: 10) {
                ForEach([(-10, "−10"), (-1, "−1"), (1, "+1"), (10, "+10")], id: \.1) { delta, label in
                    Button {
                        amountMl = max(10, min(500, amountMl + delta))
                    } label: {
                        Text(label)
                            .font(.nSans(15, weight: .semibold))
                            .foregroundStyle(c.ink)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(c.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(c.border, lineWidth: 1))
                    }
                    .buttonStyle(ScaleButtonStyle())
                }
            }
            .padding(.bottom, 10)

            // Amount display
            HStack(spacing: 6) {
                Text("\(amountMl)")
                    .font(.nSerif(36))
                    .foregroundStyle(c.bottleAccent)
                    .contentTransition(.numericText())
                Text("ml")
                    .font(.nSans(18, weight: .semibold))
                    .foregroundStyle(c.bottleAccent)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(c.bottleBg)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(c.bottleBorder, lineWidth: 1.5))
            .padding(.bottom, 16)

            HStack(spacing: 10) {
                Button("Skip amount") {
                    save(ml: nil)
                }
                .font(.nSans(15))
                .foregroundStyle(c.muted)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .overlay(Capsule().stroke(c.border, lineWidth: 1))
                .clipShape(Capsule())
                .buttonStyle(.plain)

                Button {
                    save(ml: amountMl)
                } label: {
                    Text("Save feed")
                        .font(.nSans(16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(c.bottleAccent)
                        .clipShape(Capsule())
                        .shadow(color: c.bottleAccent.opacity(0.28), radius: 8, y: 4)
                }
                .buttonStyle(ScaleButtonStyle())
                .layoutPriority(2)
            }
        }
    }

    private var cancelButton: some View {
        Button("Cancel") { isPresented = false }
            .font(.nSans(14))
            .foregroundStyle(c.muted)
            .underline()
            .frame(maxWidth: .infinity)
    }

    private func save(ml: Int?) {
        let session = FeedingSession(
            startTime: .now,
            feedType: .bottle,
            endTime: .now,
            bottleContentType: bottleType,
            bottleAmountMl: ml
        )
        modelContext.insert(session)
        try? modelContext.save()
        Task { await FirestoreService.shared.pushSession(session) }
        AnalyticsService.sessionStarted(startingSide: "bottle", feedType: "bottle")
        AnalyticsService.sessionCompleted(totalSeconds: 0, leftSeconds: 0, rightSeconds: 0, feedType: "bottle")
        isPresented = false
    }
}
