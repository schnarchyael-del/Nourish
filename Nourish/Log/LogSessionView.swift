import SwiftUI
import SwiftData

struct LogSessionView: View {
    @Environment(\.nourishColors) private var c
    @Environment(\.modelContext) private var modelContext

    let onBack: () -> Void
    let onSave: () -> Void
    let editing: FeedingSession?

    @State private var feedType: FeedType
    @State private var bottleContentType: BottleContentType
    @State private var startTime: Date
    @State private var leftDurationMins: Int
    @State private var rightDurationMins: Int
    @State private var bottleAmountMl: Int
    @State private var showDurationError = false

    init(editing: FeedingSession? = nil,
         onBack: @escaping () -> Void,
         onSave: @escaping () -> Void) {
        self.editing = editing
        self.onBack = onBack
        self.onSave = onSave

        if let s = editing {
            _feedType          = State(initialValue: s.feedType)
            _bottleContentType = State(initialValue: s.bottleContentType ?? .breastmilk)
            _startTime         = State(initialValue: s.startTime)
            _leftDurationMins  = State(initialValue: s.leftDurationMins ?? 0)
            _rightDurationMins = State(initialValue: s.rightDurationMins ?? 0)
            _bottleAmountMl    = State(initialValue: s.bottleAmountMl ?? 120)
        } else {
            _feedType          = State(initialValue: .left)
            _bottleContentType = State(initialValue: .breastmilk)
            _startTime         = State(initialValue: Calendar.current.date(byAdding: .minute, value: -24, to: .now) ?? .now)
            _leftDurationMins  = State(initialValue: 5)
            _rightDurationMins = State(initialValue: 5)
            _bottleAmountMl    = State(initialValue: 120)
        }
    }

    private var isBreast: Bool { feedType != .bottle }

    // Resolved feedType based on which sides have duration
    private var resolvedFeedType: FeedType {
        guard isBreast else { return .bottle }
        if leftDurationMins > 0 && rightDurationMins == 0 { return .left }
        if rightDurationMins > 0 && leftDurationMins == 0 { return .right }
        return feedType  // both > 0 or both == 0: use selection
    }

    private var typeSectionLabel: String {
        feedType == .bottle ? "Feed type" : "Starting side"
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    typeSection
                    if feedType == .bottle { bottleTypeSection }
                    startTimeSection
                    if isBreast {
                        breastDurationSection
                    } else {
                        bottleAmountSection
                    }
                    if showDurationError {
                        Text("Add at least 1 min to save this session 🌸")
                            .font(.nSans(13).italic())
                            .foregroundStyle(c.muted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 2)
                            .padding(.bottom, 14)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    saveButton
                    Spacer(minLength: 20)
                }
                .padding(.horizontal, 20)
                .padding(.top, 14)
            }
        }
        .background(c.bg.ignoresSafeArea())
        .animation(.easeInOut(duration: 0.2), value: showDurationError)
    }

    // MARK: Header

    private var header: some View {
        HStack {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.nSans(16, weight: .semibold))
                    .foregroundStyle(c.ink)
                    .frame(width: 38, height: 38)
                    .background(c.input)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(c.ink.opacity(0.09), lineWidth: 1))
            }
            .buttonStyle(.plain)

            Text(editing == nil ? "Log a past session" : "Edit session")
                .font(.nSerif(24))
                .foregroundStyle(c.ink)

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    // MARK: Type picker

    private var typeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel(typeSectionLabel)

            HStack(spacing: 10) {
                ForEach([FeedType.left, .right, .bottle], id: \.rawValue) { type in
                    typeButton(type)
                }
            }
        }
        .padding(.bottom, 18)
    }

    private func typeButton(_ type: FeedType) -> some View {
        let isSelected = feedType == type
        let accent: Color = type == .bottle ? c.bottleAccent : (type == .left ? c.leftAccent : c.rightAccent)
        let bg: Color = type == .bottle ? c.bottleBg : (type == .left ? c.leftBg : c.rightBg)
        let border: Color = isSelected
            ? (type == .bottle ? c.bottleAccent.opacity(0.4) : accent.opacity(0.32))
            : c.border

        return Button {
            feedType = type
            showDurationError = false
        } label: {
            HStack(spacing: 6) {
                if type == .bottle { Text("🍼").font(.nSans(17)) }
                Text(type.displayName)
                    .font(.nSans(17, weight: .bold))
                    .foregroundStyle(isSelected
                        ? (type == .bottle ? c.bottleAccent : (type == .left ? c.leftText : c.rightText))
                        : c.muted)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(isSelected ? bg : c.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(border, lineWidth: 1.5))
            .shadow(color: isSelected ? accent.opacity(0.10) : .clear, radius: 6, y: 2)
        }
        .buttonStyle(ScaleButtonStyle())
        .animation(.easeInOut(duration: 0.15), value: feedType)
    }

    // MARK: Bottle content type

    private var bottleTypeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("What's in the bottle?")

            HStack(spacing: 10) {
                ForEach(BottleContentType.allCases, id: \.rawValue) { type in
                    Button {
                        bottleContentType = type
                    } label: {
                        HStack(spacing: 6) {
                            Text(type.icon).font(.nSans(16))
                            Text(type.displayName)
                                .font(.nSans(15, weight: .bold))
                                .foregroundStyle(bottleContentType == type ? c.bottleAccent : c.muted)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(bottleContentType == type ? c.bottleBg : c.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(bottleContentType == type ? c.bottleBorder : c.border, lineWidth: 1.5)
                        )
                    }
                    .buttonStyle(ScaleButtonStyle())
                }
            }
        }
        .padding(.bottom, 18)
        .animation(.easeInOut(duration: 0.15), value: bottleContentType)
    }

    // MARK: Start time

    private var startTimeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Start time")

            DatePicker("", selection: $startTime, in: ...Date.now, displayedComponents: [.date, .hourAndMinute])
                .datePickerStyle(.compact)
                .labelsHidden()
                .tint(c.leftAccent)
                .colorScheme(.light)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .frame(height: 52)
                .background(c.input)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(c.border, lineWidth: 1))
        }
        .padding(.bottom, 18)
    }

    // MARK: Breast duration (left + right rows)

    private var breastDurationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Duration")

            VStack(spacing: 0) {
                durationRow(
                    sideLabel: "Left",
                    accent: c.leftAccent,
                    accentBg: c.leftBg,
                    minutes: $leftDurationMins
                )
                Divider().overlay(c.border)
                durationRow(
                    sideLabel: "Right",
                    accent: c.rightAccent,
                    accentBg: c.rightBg,
                    minutes: $rightDurationMins
                )
            }
            .background(c.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(c.border, lineWidth: 1))
        }
        .padding(.bottom, 18)
    }

    private func durationRow(
        sideLabel: String,
        accent: Color,
        accentBg: Color,
        minutes: Binding<Int>
    ) -> some View {
        HStack(spacing: 12) {
            Text(String(sideLabel.prefix(1)))
                .font(.nSans(12, weight: .semibold))
                .foregroundStyle(c.muted)
                .frame(width: 28, height: 28)
                .clipShape(Circle())
                .overlay(Circle().stroke(c.border, lineWidth: 1.5))

            Text("\(sideLabel) breast")
                .font(.nSans(14, weight: .semibold))
                .foregroundStyle(c.ink)

            Spacer()

            HStack(spacing: 6) {
                Button {
                    withAnimation {
                        minutes.wrappedValue = max(0, minutes.wrappedValue - 1)
                        showDurationError = false
                    }
                } label: {
                    Text("−")
                        .font(.nSans(16))
                        .foregroundStyle(c.muted)
                        .frame(width: 30, height: 30)
                        .background(c.bg)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(c.border, lineWidth: 1))
                }
                .buttonStyle(ScaleButtonStyle())

                Text("\(minutes.wrappedValue) min")
                    .font(.nSans(14, weight: .bold))
                    .foregroundStyle(minutes.wrappedValue > 0 ? accent : c.muted)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .frame(height: 30)
                    .frame(minWidth: 52)
                    .background(minutes.wrappedValue > 0 ? accentBg : c.bg)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .contentTransition(.numericText())

                Button {
                    withAnimation {
                        minutes.wrappedValue = min(120, minutes.wrappedValue + 1)
                        showDurationError = false
                    }
                } label: {
                    Text("+")
                        .font(.nSans(16))
                        .foregroundStyle(c.muted)
                        .frame(width: 30, height: 30)
                        .background(c.bg)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(c.border, lineWidth: 1))
                }
                .buttonStyle(ScaleButtonStyle())
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: Bottle amount

    private var bottleAmountSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Amount (optional)")

            HStack(spacing: 0) {
                Button {
                    withAnimation { bottleAmountMl = max(10, bottleAmountMl - 10) }
                } label: {
                    Text("−10")
                        .font(.nSans(14, weight: .semibold))
                        .foregroundStyle(c.muted)
                        .frame(maxWidth: .infinity, minHeight: 56)
                }
                .buttonStyle(ScaleButtonStyle())

                Divider().frame(height: 32).overlay(c.border)

                Button {
                    withAnimation { bottleAmountMl = max(10, bottleAmountMl - 1) }
                } label: {
                    Text("−")
                        .font(.nSans(22))
                        .foregroundStyle(c.muted)
                        .frame(maxWidth: .infinity, minHeight: 56)
                }
                .buttonStyle(ScaleButtonStyle())

                VStack(spacing: 2) {
                    Text("\(bottleAmountMl)")
                        .font(.nSerif(36))
                        .foregroundStyle(c.bottleAccent)
                        .contentTransition(.numericText())
                    Text("ml")
                        .font(.nSans(11))
                        .foregroundStyle(c.bottleAccent.opacity(0.7))
                }
                .frame(maxWidth: .infinity)

                Button {
                    withAnimation { bottleAmountMl = min(500, bottleAmountMl + 1) }
                } label: {
                    Text("+")
                        .font(.nSans(22))
                        .foregroundStyle(c.muted)
                        .frame(maxWidth: .infinity, minHeight: 56)
                }
                .buttonStyle(ScaleButtonStyle())

                Divider().frame(height: 32).overlay(c.border)

                Button {
                    withAnimation { bottleAmountMl = min(500, bottleAmountMl + 10) }
                } label: {
                    Text("+10")
                        .font(.nSans(14, weight: .semibold))
                        .foregroundStyle(c.muted)
                        .frame(maxWidth: .infinity, minHeight: 56)
                }
                .buttonStyle(ScaleButtonStyle())
            }
            .background(c.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(c.border, lineWidth: 1))
        }
        .padding(.bottom, 18)
    }

    // MARK: Save

    private var saveButton: some View {
        Button(action: saveSession) {
            Text(editing == nil ? "Save session" : "Save changes")
                .font(.nSans(18, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 58)
                .background(c.leftAccent)
                .clipShape(Capsule())
                .shadow(color: c.leftShadow, radius: 10, y: 4)
        }
        .buttonStyle(ScaleButtonStyle())
        .padding(.top, 6)
    }

    private func saveSession() {
        if isBreast && leftDurationMins == 0 && rightDurationMins == 0 {
            withAnimation { showDurationError = true }
            return
        }

        let left  = isBreast ? leftDurationMins  : nil as Int?
        let right = isBreast ? rightDurationMins : nil as Int?
        let totalMins = isBreast ? (leftDurationMins + rightDurationMins) : 0
        let computedEnd = startTime.addingTimeInterval(TimeInterval(totalMins * 60))

        let target: FeedingSession
        if let editing {
            editing.startTime         = startTime
            editing.feedType          = resolvedFeedType
            editing.endTime           = isBreast ? computedEnd : nil
            editing.bottleContentType = feedType == .bottle ? bottleContentType : nil
            editing.bottleAmountMl    = feedType == .bottle ? bottleAmountMl : nil
            editing.leftDurationMins  = left
            editing.rightDurationMins = right
            target = editing
        } else {
            let session = FeedingSession(
                startTime: startTime,
                feedType: resolvedFeedType,
                endTime: isBreast ? computedEnd : nil,
                bottleContentType: feedType == .bottle ? bottleContentType : nil,
                bottleAmountMl: feedType == .bottle ? bottleAmountMl : nil,
                leftDurationMins: left,
                rightDurationMins: right
            )
            modelContext.insert(session)
            target = session
        }
        try? modelContext.save()
        Task { await FirestoreService.shared.pushSession(target) }
        NotificationManager.shared.refreshReminder(modelContainer: NourishApp.modelContainer)
        SharedFeedSnapshot.refresh(modelContainer: NourishApp.modelContainer)

        if editing != nil {
            AnalyticsService.sessionEdited()
        } else if isBreast {
            AnalyticsService.sessionCompleted(
                totalSeconds: (leftDurationMins + rightDurationMins) * 60,
                leftSeconds: leftDurationMins * 60,
                rightSeconds: rightDurationMins * 60,
                feedType: "breast"
            )
        } else {
            AnalyticsService.sessionCompleted(totalSeconds: 0, leftSeconds: 0, rightSeconds: 0, feedType: "bottle")
        }

        onSave()
    }

    // MARK: Helpers

    private func sectionLabel(_ label: String) -> some View {
        Text(label.uppercased())
            .font(.nSans(11, weight: .bold))
            .foregroundStyle(c.muted)
            .kerning(0.09 * 11)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
