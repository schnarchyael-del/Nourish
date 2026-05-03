import SwiftUI
import SwiftData
import AudioToolbox
import AVFoundation

struct ActiveSessionView: View {
    @Environment(\.nourishColors) private var c
    @Environment(\.modelContext) private var modelContext
    @AppStorage("babyGender")    private var babyGender    = "Girl"
    @AppStorage("alarmEnabled")  private var alarmEnabled  = true
    @AppStorage("alarmMinutes")  private var alarmMinutes  = 45

    let store: SessionStore
    let darkMode: Bool
    let showEncouragements: Bool

    @State private var msgIndex      = 0
    @State private var showAlarmModal = false
    @State private var alarmFired    = false

    // Captured at alarm-fire time so save closure has stable values
    @State private var capturedStartTime:  Date     = .now
    @State private var capturedFeedType:   FeedType = .left
    @State private var capturedSide:       FeedSide = .left
    @State private var capturedElapsed:    Int      = 0

    private var encouragements: [String] {
        let pronoun:    String
        let possessive: String
        let object:     String
        switch babyGender {
        case "Boy":   pronoun = "He";   possessive = "his";   object = "him"
        case "Other": pronoun = "They"; possessive = "their"; object = "them"
        default:      pronoun = "She";  possessive = "her";   object = "her"
        }
        return [
            "You're doing amazing ✨",
            "Every drop counts 💛",
            "You're \(possessive) whole world right now 🌙",
            "This moment is precious 🤍",
            "Rest easy — you've got this",
            "\(pronoun) knows it's you holding \(object) 🫶",
        ]
    }

    private var side: FeedSide { store.currentSide ?? .left }

    // MARK: Dark-mode aware colors

    private var bgGradient: some ShapeStyle {
        if darkMode {
            return AnyShapeStyle(
                RadialGradient(
                    colors: [
                        Color(hex: "3D1504"),
                        Color(hex: "1C0906"),
                        Color(hex: "0E0402"),
                    ],
                    center: UnitPoint(x: 0.5, y: 0.28),
                    startRadius: 0, endRadius: 500
                )
            )
        } else {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        side == .left ? Color(hex: "FAF0EC") : Color(hex: "EEF4F8"),
                        c.bg,
                    ],
                    startPoint: .top, endPoint: .bottom
                )
            )
        }
    }

    private var timerColor: Color {
        darkMode ? Color(hex: "F5C49A") : c.accentColor(for: side)
    }

    private var timerGlow: Bool { darkMode && !store.isPaused }

    private var labelColor: Color {
        darkMode ? .white.opacity(0.38) : c.muted
    }

    private var textColor: Color {
        darkMode ? .white.opacity(0.78) : c.ink
    }

    private var ghostBg: Color {
        darkMode ? .white.opacity(0.07) : c.surface
    }

    private var ghostBorder: Color {
        darkMode ? .white.opacity(0.14) : c.border
    }

    private var switchBg: Color {
        if darkMode { return .white.opacity(0.05) }
        return c.bgColor(for: side.opposite)
    }

    private var switchBorder: Color {
        if darkMode { return .white.opacity(0.2) }
        return c.accentColor(for: side.opposite).opacity(0.25)
    }

    private var startTimeLabel: String {
        let start = Date.now.addingTimeInterval(-TimeInterval(store.elapsedSeconds))
        return start.formatted(date: .omitted, time: .shortened)
    }

    // MARK: Body

    var body: some View {
        ZStack {
            Rectangle()
                .fill(bgGradient)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                timerHero
                if showEncouragements { encouragementCard }
                Spacer()
                actionButtons
            }
            .padding(.horizontal, 24)
            .padding(.top, 58 + 10)
            .padding(.bottom, 14)
        }
        .preferredColorScheme(darkMode ? .dark : nil)
        .onAppear { msgIndex = Int.random(in: 0..<encouragements.count) }
        .onChange(of: store.elapsedSeconds) { _, newValue in
            guard alarmEnabled, !alarmFired, !showAlarmModal else { return }
            if newValue >= alarmMinutes * 60 {
                alarmFired = true
                capturedStartTime  = Date.now.addingTimeInterval(-TimeInterval(newValue))
                capturedFeedType   = (store.startSide ?? .left).feedType
                capturedSide       = store.startSide ?? .left
                capturedElapsed    = newValue
                fireAlarmHapticAndSound()
                withAnimation(.easeInOut(duration: 0.3)) { showAlarmModal = true }
            }
        }
        .overlay {
            if showAlarmModal {
                AlarmModal(
                    side: capturedSide,
                    startTime: capturedStartTime,
                    elapsedSeconds: capturedElapsed,
                    onSave: { endTime in
                        let startTime  = capturedStartTime
                        let feedType   = capturedFeedType
                        store.cancel()
                        let session = FeedingSession(
                            startTime: startTime,
                            feedType: feedType,
                            endTime: endTime
                        )
                        modelContext.insert(session)
                        try? modelContext.save()
                        showAlarmModal = false
                    },
                    onDiscard: {
                        store.cancel()
                        showAlarmModal = false
                    }
                )
                .environment(\.nourishColors, c)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: showAlarmModal)
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack {
            NourishPill(
                label: "● \(side == .left ? "LEFT" : "RIGHT")",
                fill: darkMode ? .white.opacity(0.1) : c.bgColor(for: side),
                border: darkMode ? .white.opacity(0.18) : c.accentColor(for: side).opacity(0.22),
                color: darkMode ? .white.opacity(0.85) : c.textColor(for: side)
            )
            Spacer()
            Text(Date.now.formatted(date: .omitted, time: .shortened))
                .font(.nSans(14))
                .foregroundStyle(labelColor)
        }
        .padding(.bottom, 28)
    }

    // MARK: Timer

    private var timerHero: some View {
        VStack(spacing: 12) {
            Text(store.isPaused ? "paused" : "session time")
                .font(.nSans(11, weight: .semibold))
                .foregroundStyle(labelColor)
                .kerning(0.18 * 11)
                .textCase(.uppercase)

            Text(store.formattedTime)
                .font(.nSerif(92))
                .foregroundStyle(timerColor)
                .opacity(store.isPaused ? 0.42 : 1.0)
                .shadow(
                    color: timerGlow ? Color(hex: "F5A05A").opacity(0.45) : .clear,
                    radius: timerGlow ? 25 : 0
                )
                .animation(.easeInOut(duration: 0.4), value: store.isPaused)
                .animation(.easeInOut(duration: 0.4), value: timerGlow)
                .contentTransition(.numericText())

            Text("\(side.name) breast · started \(startTimeLabel)")
                .font(.nSans(14))
                .foregroundStyle(labelColor)
        }
        .padding(.bottom, 16)
    }

    // MARK: Encouragement

    @ViewBuilder
    private var encouragementCard: some View {
        if showEncouragements {
            Text("\u{201C}\(encouragements[msgIndex])\u{201D}")
                .font(.nSerif(17, italic: true))
                .foregroundStyle(darkMode ? .white.opacity(0.58) : c.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
                .padding(.vertical, 13)
                .background(ghostBg)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(ghostBorder, lineWidth: 1))
                .padding(.bottom, 20)
        }
    }

    // MARK: Action buttons

    private var actionButtons: some View {
        VStack(spacing: 10) {
            // Pause / Resume
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

            // Switch side
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                store.switchSide()
            } label: {
                HStack(spacing: 10) {
                    Text("⇄")
                        .font(.nSans(18))
                        .foregroundStyle(darkMode
                            ? .white.opacity(0.55)
                            : c.accentColor(for: side.opposite))
                    Text("Switch to \(side.opposite.name) breast")
                        .font(.nSans(16, weight: .semibold))
                        .foregroundStyle(darkMode ? .white.opacity(0.78) : c.ink)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(switchBg)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(switchBorder, lineWidth: 1))
            }
            .buttonStyle(ScaleButtonStyle())

            // End session
            Button {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                endSession()
            } label: {
                HStack(spacing: 10) {
                    Text("■")
                        .font(.nSans(17))
                    Text("End session")
                        .font(.nSans(18, weight: .bold))
                }
                .foregroundStyle(darkMode ? Color(hex: "F5C49A") : .white)
                .frame(maxWidth: .infinity)
                .frame(height: 64)
                .background(
                    darkMode
                        ? Color(hex: "F5C49A").opacity(0.13)
                        : c.accentColor(for: side)
                )
                .clipShape(Capsule())
                .overlay(
                    darkMode
                        ? AnyView(Capsule().stroke(Color(hex: "F5C49A").opacity(0.32), lineWidth: 1))
                        : AnyView(EmptyView())
                )
                .shadow(
                    color: darkMode ? .clear : c.shadowColor(for: side),
                    radius: 10, y: 4
                )
            }
            .buttonStyle(ScaleButtonStyle(scale: 0.97))
        }
    }

    // MARK: Alarm sound + haptic

    private func fireAlarmHapticAndSound() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        AudioServicesPlaySystemSound(1013)
    }

    // MARK: End session

    private func endSession() {
        let result = store.end()
        let session = FeedingSession(
            startTime: result.startTime,
            feedType: result.feedType,
            endTime: result.endTime
        )
        modelContext.insert(session)
        try? modelContext.save()
    }
}

// MARK: - Alarm modal

struct AlarmModal: View {
    @Environment(\.nourishColors) private var c
    let side: FeedSide
    let startTime: Date
    let elapsedSeconds: Int
    let onSave: (Date) -> Void
    let onDiscard: () -> Void

    @State private var endTime: Date = .now

    private var elapsedDisplay: String {
        let h = elapsedSeconds / 3600
        let m = (elapsedSeconds % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m) min"
    }

    private var durationMins: Int {
        max(0, Int(endTime.timeIntervalSince(startTime))) / 60
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.48)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                Capsule()
                    .fill(c.border)
                    .frame(width: 40, height: 5)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 22)

                VStack(spacing: 0) {
                    Text("😴")
                        .font(.nSans(50))
                        .padding(.bottom, 12)

                    Text("Did you fall asleep?")
                        .font(.nSerif(28))
                        .foregroundStyle(c.ink)
                        .multilineTextAlignment(.center)
                        .padding(.bottom, 7)

                    Text("Timer's been going for \(elapsedDisplay)...\nwe won't judge 😅")
                        .font(.nSans(15))
                        .foregroundStyle(c.muted)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, 18)

                // End time picker
                VStack(alignment: .leading, spacing: 10) {
                    Text("When did you finish?")
                        .font(.nSans(11, weight: .bold))
                        .foregroundStyle(c.muted)
                        .kerning(0.09 * 11)
                        .textCase(.uppercase)

                    HStack(spacing: 10) {
                        DatePicker("", selection: $endTime, displayedComponents: .hourAndMinute)
                            .datePickerStyle(.compact)
                            .labelsHidden()
                            .tint(c.accentColor(for: side))
                            .colorScheme(.light)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .frame(height: 50)
                            .background(c.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .overlay(RoundedRectangle(cornerRadius: 16).stroke(c.border, lineWidth: 1))

                        Text("≈ \(durationMins) min")
                            .font(.nSans(14, weight: .semibold))
                            .foregroundStyle(c.muted)
                            .lineLimit(1)
                            .padding(.horizontal, 14)
                            .frame(height: 50)
                            .background(c.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(c.border, lineWidth: 1))
                            .contentTransition(.numericText())
                    }
                }
                .padding(15)
                .background(c.bgColor(for: side))
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(c.accentColor(for: side).opacity(0.18), lineWidth: 1)
                )
                .padding(.bottom, 14)

                VStack(spacing: 10) {
                    Button {
                        onSave(endTime)
                    } label: {
                        Text("✓  Save with this time")
                            .font(.nSans(17, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 60)
                            .background(c.accentColor(for: side))
                            .clipShape(Capsule())
                            .shadow(color: c.shadowColor(for: side), radius: 10, y: 4)
                    }
                    .buttonStyle(ScaleButtonStyle())

                    Button {
                        onDiscard()
                    } label: {
                        Text("Discard session")
                            .font(.nSans(16))
                            .foregroundStyle(c.muted)
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .overlay(Capsule().stroke(c.border, lineWidth: 1))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 22)
            .padding(.bottom, 10)
            .background(c.bg)
            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
            .shadow(color: .black.opacity(0.14), radius: 25, y: -10)
            .frame(maxWidth: .infinity)
            .frame(maxHeight: .infinity, alignment: .bottom)
            .ignoresSafeArea(edges: .bottom)
        }
    }
}
