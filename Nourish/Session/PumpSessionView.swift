import SwiftUI
import SwiftData

struct PumpSessionView: View {
    @Environment(\.nourishColors) private var c
    @Environment(\.modelContext) private var modelContext

    let store: PumpStore
    let onDismiss: () -> Void

    @AppStorage("darkActiveScreen") private var darkActiveScreen = true

    @State private var selectedSide: PumpSide = .both
    @State private var timerStarted = false
    @State private var volumeMl: Int = 0
    @State private var notes: String = ""
    @State private var showDiscardConfirm = false
    @State private var showVolumeInput = false

    private var darkMode: Bool { darkActiveScreen }

    // MARK: Dark-mode colors

    private var bgGradient: some ShapeStyle {
        if darkMode {
            return AnyShapeStyle(
                RadialGradient(
                    colors: [
                        Color(hex: "0A2E28"),
                        Color(hex: "071A17"),
                        Color(hex: "040D0B"),
                    ],
                    center: UnitPoint(x: 0.5, y: 0.28),
                    startRadius: 0, endRadius: 500
                )
            )
        } else {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [c.pumpBg.opacity(0.6), c.bg],
                    startPoint: .top, endPoint: .bottom
                )
            )
        }
    }

    private var timerColor: Color {
        darkMode ? Color(hex: "6FBAAD") : c.pumpAccent
    }
    private var ghostBg: Color  { darkMode ? .white.opacity(0.07) : c.surface }
    private var ghostBorder: Color { darkMode ? .white.opacity(0.14) : c.border }
    private var labelColor: Color { darkMode ? .white.opacity(0.38) : c.muted }
    private var textColor: Color  { darkMode ? .white.opacity(0.78) : c.ink }

    // MARK: Body

    var body: some View {
        ZStack {
            Rectangle()
                .fill(bgGradient)
                .ignoresSafeArea()

            if timerStarted {
                runningView
            } else {
                sidePickerView
            }
        }
        .preferredColorScheme(darkMode ? .dark : nil)
        .alert("Discard this pump session?", isPresented: $showDiscardConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Discard", role: .destructive) {
                store.cancel()
                onDismiss()
            }
        } message: {
            Text("All data from this session will be lost.")
        }
    }

    // MARK: Side picker (step 1)

    private var sidePickerView: some View {
        VStack(spacing: 0) {
            // Top bar
            HStack {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.nSans(13, weight: .semibold))
                        .foregroundStyle(darkMode ? .white.opacity(0.78) : c.muted)
                        .frame(width: 32, height: 32)
                        .background(ghostBg)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(ghostBorder, lineWidth: 1))
                }
                .buttonStyle(.plain)

                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 58 + 10)
            .padding(.bottom, 32)

            VStack(spacing: 6) {
                Text("Pump session")
                    .font(.nSerif(32))
                    .foregroundStyle(darkMode ? .white.opacity(0.9) : c.ink)

                Text("Which side?")
                    .font(.nSans(15))
                    .foregroundStyle(labelColor)
            }
            .padding(.bottom, 36)

            // Side options
            VStack(spacing: 12) {
                ForEach(PumpSide.allCases, id: \.rawValue) { side in
                    let isSelected = selectedSide == side
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation(.easeInOut(duration: 0.15)) { selectedSide = side }
                    } label: {
                        HStack(spacing: 14) {
                            ZStack {
                                Circle()
                                    .fill(isSelected ? c.pumpAccent : (darkMode ? .white.opacity(0.06) : c.surface))
                                    .frame(width: 38, height: 38)
                                    .overlay(Circle().stroke(isSelected ? c.pumpAccent : ghostBorder, lineWidth: 1.5))
                                Text(side.icon)
                                    .font(.nSans(15, weight: .bold))
                                    .foregroundStyle(isSelected ? .white : (darkMode ? .white.opacity(0.55) : c.muted))
                            }

                            Text(side.displayName)
                                .font(.nSans(17, weight: .semibold))
                                .foregroundStyle(isSelected ? (darkMode ? Color(hex: "6FBAAD") : c.pumpAccent) : textColor)

                            Spacer()

                            if isSelected {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(c.pumpAccent)
                                    .font(.nSans(20))
                            }
                        }
                        .padding(.horizontal, 20)
                        .frame(height: 60)
                        .background(isSelected ? c.pumpAccent.opacity(darkMode ? 0.12 : 0.08) : ghostBg)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18)
                                .stroke(isSelected ? c.pumpAccent.opacity(0.4) : ghostBorder, lineWidth: 1.5)
                        )
                    }
                    .buttonStyle(ScaleButtonStyle())
                }
            }
            .padding(.horizontal, 24)

            Spacer()

            Button {
                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                store.start(side: selectedSide)
                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                    timerStarted = true
                }
                AnalyticsService.pumpSessionStarted(side: selectedSide.rawValue)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "drop.fill")
                        .font(.nSans(17))
                    Text("Start pumping")
                        .font(.nSans(18, weight: .bold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 64)
                .background(c.pumpAccent)
                .clipShape(Capsule())
                .shadow(color: c.pumpAccent.opacity(0.35), radius: 12, y: 5)
            }
            .buttonStyle(ScaleButtonStyle(scale: 0.97))
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
    }

    // MARK: Running timer (step 2)

    private var runningView: some View {
        VStack(spacing: 0) {
            // Top bar
            HStack(spacing: 12) {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    showDiscardConfirm = true
                } label: {
                    Image(systemName: "xmark")
                        .font(.nSans(13, weight: .semibold))
                        .foregroundStyle(darkMode ? .white.opacity(0.78) : c.muted)
                        .frame(width: 32, height: 32)
                        .background(ghostBg)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(ghostBorder, lineWidth: 1))
                }
                .buttonStyle(.plain)

                // Side pill
                NourishPill(
                    label: "● \(store.pumpSide.displayName.uppercased())",
                    fill: darkMode ? c.pumpAccent.opacity(0.12) : c.pumpBg,
                    border: darkMode ? c.pumpAccent.opacity(0.25) : c.pumpBorder,
                    color: darkMode ? Color(hex: "6FBAAD") : c.pumpAccent
                )

                Spacer()

                Text(Date.now.formatted(date: .omitted, time: .shortened))
                    .font(.nSans(14))
                    .foregroundStyle(labelColor)
            }
            .padding(.horizontal, 24)
            .padding(.top, 58 + 10)
            .padding(.bottom, 28)

            // Timer hero
            VStack(spacing: 10) {
                Text(store.isPaused ? "paused" : "pump time")
                    .font(.nSans(11, weight: .semibold))
                    .foregroundStyle(labelColor)
                    .kerning(0.18 * 11)
                    .textCase(.uppercase)

                Text(store.formattedTime)
                    .font(.nSerif(92))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .foregroundStyle(timerColor)
                    .opacity(store.isPaused ? 0.42 : 1.0)
                    .shadow(
                        color: (!darkMode || store.isPaused) ? .clear : c.pumpAccent.opacity(0.38),
                        radius: 25
                    )
                    .animation(.easeInOut(duration: 0.4), value: store.isPaused)
                    .contentTransition(.numericText())

                Text("Pump session · \(store.pumpSide.displayName)")
                    .font(.nSans(14))
                    .foregroundStyle(labelColor)
            }
            .padding(.bottom, 20)

            // Volume input card
            volumeCard
                .padding(.horizontal, 24)
                .padding(.bottom, 14)

            // Notes
            notesField
                .padding(.horizontal, 24)

            Spacer()

            // Action buttons
            VStack(spacing: 10) {
                // Pause/Resume
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    store.isPaused ? store.resume() : store.pause()
                } label: {
                    HStack(spacing: 10) {
                        Text(store.isPaused ? "▶" : "⏸")
                            .font(.nSans(17))
                        Text(store.isPaused ? "Resume timer" : "Pause timer")
                            .font(.nSans(16, weight: .semibold))
                    }
                    .foregroundStyle(textColor)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(ghostBg)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(ghostBorder, lineWidth: 1))
                }
                .buttonStyle(ScaleButtonStyle())

                // Save
                Button {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    saveSession()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "drop.fill")
                            .font(.nSans(17))
                        Text("Save session")
                            .font(.nSans(18, weight: .bold))
                    }
                    .foregroundStyle(darkMode ? Color(hex: "6FBAAD") : .white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 64)
                    .background(darkMode ? c.pumpAccent.opacity(0.15) : c.pumpAccent)
                    .clipShape(Capsule())
                    .overlay(
                        darkMode
                            ? AnyView(Capsule().stroke(c.pumpAccent.opacity(0.38), lineWidth: 1))
                            : AnyView(EmptyView())
                    )
                    .shadow(color: darkMode ? .clear : c.pumpAccent.opacity(0.32), radius: 10, y: 4)
                }
                .buttonStyle(ScaleButtonStyle(scale: 0.97))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 14)
        }
    }

    // MARK: Volume card

    private var volumeCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("VOLUME")
                    .font(.nSans(11, weight: .bold))
                    .foregroundStyle(labelColor)
                    .kerning(0.1 * 11)

                Spacer()

                if volumeMl == 0 {
                    Text("optional")
                        .font(.nSans(11))
                        .foregroundStyle(labelColor.opacity(0.7))
                }
            }

            HStack(spacing: 0) {
                // Decrement buttons
                Button {
                    withAnimation { volumeMl = max(0, volumeMl - 10) }
                } label: {
                    Text("−10")
                        .font(.nSans(13, weight: .semibold))
                        .foregroundStyle(volumeMl >= 10 ? textColor : labelColor.opacity(0.4))
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(ScaleButtonStyle())
                .disabled(volumeMl < 10)

                Divider().frame(height: 28).overlay(ghostBorder)

                Button {
                    withAnimation { volumeMl = max(0, volumeMl - 1) }
                } label: {
                    Text("−")
                        .font(.nSans(20))
                        .foregroundStyle(volumeMl > 0 ? textColor : labelColor.opacity(0.4))
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(ScaleButtonStyle())
                .disabled(volumeMl == 0)

                Divider().frame(height: 28).overlay(ghostBorder)

                // Display
                VStack(spacing: 1) {
                    if volumeMl == 0 {
                        Text("—")
                            .font(.nSerif(28))
                            .foregroundStyle(labelColor.opacity(0.5))
                    } else {
                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            Text("\(volumeMl)")
                                .font(.nSerif(28))
                                .foregroundStyle(timerColor)
                                .contentTransition(.numericText())
                            Text("ml")
                                .font(.nSans(12))
                                .foregroundStyle(timerColor.opacity(0.7))
                        }
                    }
                }
                .frame(maxWidth: .infinity)

                Divider().frame(height: 28).overlay(ghostBorder)

                Button {
                    withAnimation { volumeMl = min(500, volumeMl + 1) }
                } label: {
                    Text("+")
                        .font(.nSans(20))
                        .foregroundStyle(textColor)
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(ScaleButtonStyle())

                Divider().frame(height: 28).overlay(ghostBorder)

                Button {
                    withAnimation { volumeMl = min(500, volumeMl + 10) }
                } label: {
                    Text("+10")
                        .font(.nSans(13, weight: .semibold))
                        .foregroundStyle(textColor)
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(ScaleButtonStyle())
            }
            .background(ghostBg)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(ghostBorder, lineWidth: 1))
        }
    }

    // MARK: Notes field

    private var notesField: some View {
        HStack(spacing: 10) {
            Image(systemName: "note.text")
                .font(.nSans(14))
                .foregroundStyle(labelColor)

            TextField("Add a note...", text: $notes)
                .font(.nSans(14))
                .foregroundStyle(textColor)
                .tint(c.pumpAccent)
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(ghostBg)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(ghostBorder, lineWidth: 1))
    }

    // MARK: Save

    private func saveSession() {
        let result = store.end()

        let session = FeedingSession(
            startTime: result.startTime,
            feedType: .pump,
            endTime: result.endTime,
            pumpSide: result.side,
            pumpVolumeMl: volumeMl > 0 ? volumeMl : nil,
            notes: notes.isEmpty ? nil : notes
        )
        modelContext.insert(session)
        try? modelContext.save()
        Task { await FirestoreService.shared.pushSession(session) }
        NotificationManager.shared.refreshReminder(modelContainer: NourishApp.modelContainer)
        SharedFeedSnapshot.refresh(modelContainer: NourishApp.modelContainer)
        AnalyticsService.pumpSessionCompleted(
            side: result.side.rawValue,
            durationSeconds: result.elapsedSeconds,
            volumeMl: volumeMl > 0 ? volumeMl : nil
        )
        onDismiss()
    }
}
