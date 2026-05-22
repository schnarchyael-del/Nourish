import SwiftUI
import SwiftData

private enum SessionCategory {
    case breast, bottle, pump
}

struct LogSessionView: View {
    @Environment(\.nourishColors) private var c
    @Environment(\.modelContext) private var modelContext

    let onBack: () -> Void
    let onSave: () -> Void
    let editing: FeedingSession?

    @State private var sessionCategory: SessionCategory
    @State private var breastStartingSide: FeedSide
    @State private var startTime: Date
    @State private var leftDurationMins: Int
    @State private var rightDurationMins: Int
    @State private var bottleAmountMl: Int
    @State private var bottleDurationMins: Int
    @State private var pumpSide: PumpSide
    @State private var pumpLeftDurationMins: Int
    @State private var pumpRightDurationMins: Int
    @State private var pumpVolumeMl: Int
    @State private var notes: String
    @State private var showDurationError = false

    init(editing: FeedingSession? = nil,
         onBack: @escaping () -> Void,
         onSave: @escaping () -> Void) {
        self.editing = editing
        self.onBack = onBack
        self.onSave = onSave

        if let s = editing {
            let category: SessionCategory
            let startingSide: FeedSide
            switch s.feedType {
            case .left:   category = .breast; startingSide = .left
            case .right:  category = .breast; startingSide = .right
            case .bottle: category = .bottle; startingSide = .left
            case .pump:   category = .pump;   startingSide = .left
            }
            _sessionCategory    = State(initialValue: category)
            _breastStartingSide = State(initialValue: startingSide)
            _startTime          = State(initialValue: s.startTime)
            _leftDurationMins   = State(initialValue: s.leftDurationMins ?? 0)
            _rightDurationMins  = State(initialValue: s.rightDurationMins ?? 0)
            _bottleAmountMl     = State(initialValue: s.bottleAmountMl ?? 120)
            _bottleDurationMins = State(initialValue: {
                guard s.feedType == .bottle, let end = s.endTime else { return 0 }
                return max(0, Int(end.timeIntervalSince(s.startTime) / 60))
            }())
            _pumpSide              = State(initialValue: s.pumpSide ?? .both)
            let total = s.totalActiveMinutes
            let side  = s.pumpSide ?? .both
            _pumpLeftDurationMins  = State(initialValue: side == .right ? 0 : (side == .both ? total / 2 : total))
            _pumpRightDurationMins = State(initialValue: side == .left  ? 0 : (side == .both ? total - total / 2 : total))
            _pumpVolumeMl          = State(initialValue: s.pumpVolumeMl ?? 0)
            _notes                 = State(initialValue: s.notes ?? "")
        } else {
            _sessionCategory    = State(initialValue: .breast)
            _breastStartingSide = State(initialValue: .left)
            _startTime          = State(initialValue: Calendar.current.date(byAdding: .minute, value: -24, to: .now) ?? .now)
            _leftDurationMins   = State(initialValue: 5)
            _rightDurationMins  = State(initialValue: 5)
            _bottleAmountMl     = State(initialValue: 120)
            _bottleDurationMins = State(initialValue: 15)
            _pumpSide              = State(initialValue: .both)
            _pumpLeftDurationMins  = State(initialValue: 15)
            _pumpRightDurationMins = State(initialValue: 15)
            _pumpVolumeMl          = State(initialValue: 0)
            _notes                 = State(initialValue: "")
        }
    }

    private var resolvedFeedType: FeedType {
        switch sessionCategory {
        case .bottle: return .bottle
        case .pump:   return .pump
        case .breast:
            if leftDurationMins > 0 && rightDurationMins == 0 { return .left }
            if rightDurationMins > 0 && leftDurationMins == 0 { return .right }
            return breastStartingSide == .left ? .left : .right
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    categorySection
                    contentFields
                    startTimeSection
                    notesSection
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
        .animation(.easeInOut(duration: 0.18), value: sessionCategory)
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

    // MARK: Step 1 — Session type (Breast / Bottle / Pump)

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Session type")
            HStack(spacing: 10) {
                categoryButton(.breast)
                categoryButton(.bottle)
                categoryButton(.pump)
            }
        }
        .padding(.bottom, 20)
    }

    private func categoryButton(_ category: SessionCategory) -> some View {
        let isSelected = sessionCategory == category
        let accent: Color
        let bg: Color
        let label: String
        let emoji: String?
        let sfIcon: String?
        switch category {
        case .breast: accent = c.leftAccent;   bg = c.leftBg;   label = "Breast"; emoji = nil;   sfIcon = nil
        case .bottle: accent = c.bottleAccent; bg = c.bottleBg; label = "Bottle"; emoji = "🍼";  sfIcon = nil
        case .pump:   accent = c.pumpAccent;   bg = c.pumpBg;   label = "Pump";   emoji = nil;   sfIcon = "fuelpump.fill"
        }
        return Button {
            sessionCategory = category
            showDurationError = false
        } label: {
            HStack(spacing: 5) {
                if let emoji { Text(emoji).font(.nSans(15)) }
                if let sfIcon {
                    Image("pump_icon")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(height: 16)
                        .foregroundStyle(isSelected ? accent : c.muted)
                }
                Text(label)
                    .font(.nSans(15, weight: .bold))
                    .foregroundStyle(isSelected ? accent : c.muted)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(isSelected ? bg : c.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(
                isSelected ? accent.opacity(0.38) : c.border,
                lineWidth: 1.5
            ))
            .shadow(color: isSelected ? accent.opacity(0.10) : .clear, radius: 6, y: 2)
        }
        .buttonStyle(ScaleButtonStyle())
    }

    // MARK: Step 2 — Context-dependent fields

    @ViewBuilder
    private var contentFields: some View {
        switch sessionCategory {
        case .breast:
            startingSideSection
            breastDurationSection
        case .bottle:
            bottleVolumeSection
            bottleDurationSection
        case .pump:
            pumpSideSection
            pumpDurationSection
            pumpVolumeSection
        }
    }

    // MARK: Starting side (Breast)

    private var startingSideSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Starting side")
            HStack(spacing: 10) {
                startingSideButton(.left)
                startingSideButton(.right)
            }
        }
        .padding(.bottom, 18)
    }

    private func startingSideButton(_ side: FeedSide) -> some View {
        let isSelected = breastStartingSide == side
        let accent: Color = side == .left ? c.leftAccent : c.rightAccent
        let bg: Color     = side == .left ? c.leftBg     : c.rightBg
        return Button { breastStartingSide = side } label: {
            Text(side.name)
                .font(.nSans(15, weight: .bold))
                .foregroundStyle(isSelected ? accent : c.muted)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(isSelected ? bg : c.surface)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(
                    isSelected ? accent.opacity(0.38) : c.border,
                    lineWidth: 1.5
                ))
        }
        .buttonStyle(ScaleButtonStyle())
    }

    // MARK: Breast duration

    private var breastDurationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Duration")
            VStack(spacing: 0) {
                durationRow(sideLabel: "Left",  accent: c.leftAccent,  accentBg: c.leftBg,  minutes: $leftDurationMins)
                Divider().overlay(c.border)
                durationRow(sideLabel: "Right", accent: c.rightAccent, accentBg: c.rightBg, minutes: $rightDurationMins)
            }
            .background(c.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(c.border, lineWidth: 1))
        }
        .padding(.bottom, 18)
    }

    // MARK: Bottle volume

    private var bottleVolumeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Volume (ml)")
            HStack(spacing: 0) {
                Button { withAnimation { bottleAmountMl = max(10, bottleAmountMl - 10) } } label: {
                    Text("−10").font(.nSans(14, weight: .semibold)).foregroundStyle(c.muted)
                        .frame(maxWidth: .infinity, minHeight: 56)
                }
                .buttonStyle(ScaleButtonStyle())
                Divider().frame(height: 32).overlay(c.border)
                Button { withAnimation { bottleAmountMl = max(10, bottleAmountMl - 1) } } label: {
                    Text("−").font(.nSans(22)).foregroundStyle(c.muted)
                        .frame(maxWidth: .infinity, minHeight: 56)
                }
                .buttonStyle(ScaleButtonStyle())
                VStack(spacing: 2) {
                    Text("\(bottleAmountMl)").font(.nSerif(36)).foregroundStyle(c.bottleAccent)
                        .contentTransition(.numericText())
                    Text("ml").font(.nSans(11)).foregroundStyle(c.bottleAccent.opacity(0.7))
                }
                .frame(maxWidth: .infinity)
                Button { withAnimation { bottleAmountMl = min(500, bottleAmountMl + 1) } } label: {
                    Text("+").font(.nSans(22)).foregroundStyle(c.muted)
                        .frame(maxWidth: .infinity, minHeight: 56)
                }
                .buttonStyle(ScaleButtonStyle())
                Divider().frame(height: 32).overlay(c.border)
                Button { withAnimation { bottleAmountMl = min(500, bottleAmountMl + 10) } } label: {
                    Text("+10").font(.nSans(14, weight: .semibold)).foregroundStyle(c.muted)
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

    // MARK: Bottle duration

    private var bottleDurationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Duration (optional)")
            VStack(spacing: 0) {
                durationRow(sideLabel: "Feed", bodyLabel: "Feed time", accent: c.bottleAccent, accentBg: c.bottleBg, minutes: $bottleDurationMins)
            }
            .background(c.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(c.border, lineWidth: 1))
        }
        .padding(.bottom, 18)
    }

    // MARK: Pump side selector

    private var pumpSideSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Which side?")
            HStack(spacing: 10) {
                ForEach(PumpSide.allCases, id: \.rawValue) { side in
                    let isSelected = pumpSide == side
                    Button { pumpSide = side } label: {
                        Text(side.displayName)
                            .font(.nSans(15, weight: .bold))
                            .foregroundStyle(isSelected ? c.pumpAccent : c.muted)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(isSelected ? c.pumpBg : c.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(
                                isSelected ? c.pumpBorder : c.border,
                                lineWidth: 1.5
                            ))
                    }
                    .buttonStyle(ScaleButtonStyle())
                }
            }
        }
        .padding(.bottom, 18)
    }

    // MARK: Pump duration

    private var pumpDurationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Duration")
            VStack(spacing: 0) {
                if pumpSide != .right {
                    durationRow(sideLabel: "Left",  bodyLabel: "Left pump",  accent: c.pumpAccent, accentBg: c.pumpBg, minutes: $pumpLeftDurationMins)
                }
                if pumpSide == .both {
                    Divider().overlay(c.border)
                }
                if pumpSide != .left {
                    durationRow(sideLabel: "Right", bodyLabel: "Right pump", accent: c.pumpAccent, accentBg: c.pumpBg, minutes: $pumpRightDurationMins)
                }
            }
            .background(c.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(c.border, lineWidth: 1))
        }
        .padding(.bottom, 18)
    }

    // MARK: Pump volume

    private var pumpVolumeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Volume (optional)")
            HStack(spacing: 0) {
                Button { withAnimation { pumpVolumeMl = max(0, pumpVolumeMl - 10) } } label: {
                    Text("−10").font(.nSans(14, weight: .semibold)).foregroundStyle(c.muted)
                        .frame(maxWidth: .infinity, minHeight: 56)
                }
                .buttonStyle(ScaleButtonStyle())
                Divider().frame(height: 32).overlay(c.border)
                Button { withAnimation { pumpVolumeMl = max(0, pumpVolumeMl - 1) } } label: {
                    Text("−").font(.nSans(22)).foregroundStyle(c.muted)
                        .frame(maxWidth: .infinity, minHeight: 56)
                }
                .buttonStyle(ScaleButtonStyle())
                VStack(spacing: 2) {
                    if pumpVolumeMl == 0 {
                        Text("—").font(.nSerif(36)).foregroundStyle(c.muted.opacity(0.5))
                    } else {
                        Text("\(pumpVolumeMl)").font(.nSerif(36)).foregroundStyle(c.pumpAccent)
                            .contentTransition(.numericText())
                    }
                    Text("ml").font(.nSans(11)).foregroundStyle(c.pumpAccent.opacity(0.7))
                }
                .frame(maxWidth: .infinity)
                Button { withAnimation { pumpVolumeMl = min(500, pumpVolumeMl + 1) } } label: {
                    Text("+").font(.nSans(22)).foregroundStyle(c.muted)
                        .frame(maxWidth: .infinity, minHeight: 56)
                }
                .buttonStyle(ScaleButtonStyle())
                Divider().frame(height: 32).overlay(c.border)
                Button { withAnimation { pumpVolumeMl = min(500, pumpVolumeMl + 10) } } label: {
                    Text("+10").font(.nSans(14, weight: .semibold)).foregroundStyle(c.muted)
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

    // MARK: Notes

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Notes (optional)")
            HStack(spacing: 10) {
                Image(systemName: "note.text")
                    .font(.nSans(14))
                    .foregroundStyle(c.muted)
                TextField("e.g. baby was fussy, for freezer...", text: $notes)
                    .font(.nSans(14))
                    .foregroundStyle(c.ink)
                    .tint(c.leftAccent)
                    .submitLabel(.done)
            }
            .padding(.horizontal, 14)
            .frame(height: 48)
            .background(c.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(c.border, lineWidth: 1))
        }
        .padding(.bottom, 18)
    }

    // MARK: Save button

    private var saveButton: some View {
        let accent: Color
        let shadow: Color
        switch sessionCategory {
        case .breast: accent = c.leftAccent;   shadow = c.leftShadow
        case .bottle: accent = c.bottleAccent; shadow = c.bottleAccent.opacity(0.28)
        case .pump:   accent = c.pumpAccent;   shadow = c.pumpAccent.opacity(0.28)
        }
        return Button(action: saveSession) {
            Text(editing == nil ? "Save session" : "Save changes")
                .font(.nSans(18, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 58)
                .background(accent)
                .clipShape(Capsule())
                .shadow(color: shadow, radius: 10, y: 4)
        }
        .buttonStyle(ScaleButtonStyle())
        .padding(.top, 6)
    }

    private func saveSession() {
        switch sessionCategory {
        case .breast:
            if leftDurationMins == 0 && rightDurationMins == 0 {
                withAnimation { showDurationError = true }
                return
            }
        case .pump:
            let total = pumpSide == .left  ? pumpLeftDurationMins
                      : pumpSide == .right ? pumpRightDurationMins
                      : pumpLeftDurationMins + pumpRightDurationMins
            if total == 0 {
                withAnimation { showDurationError = true }
                return
            }
        case .bottle:
            break
        }

        let target: FeedingSession
        if let editing {
            editing.startTime = startTime
            editing.notes     = notes.isEmpty ? nil : notes
            switch sessionCategory {
            case .breast:
                let totalMins = leftDurationMins + rightDurationMins
                editing.feedType          = resolvedFeedType
                editing.leftDurationMins  = leftDurationMins
                editing.rightDurationMins = rightDurationMins
                editing.endTime           = startTime.addingTimeInterval(TimeInterval(totalMins * 60))
                editing.bottleContentType = nil
                editing.bottleAmountMl    = nil
                editing.pumpSide          = nil
                editing.pumpVolumeMl      = nil
            case .bottle:
                editing.feedType          = .bottle
                editing.bottleContentType = nil
                editing.bottleAmountMl    = bottleAmountMl
                editing.endTime           = bottleDurationMins > 0 ? startTime.addingTimeInterval(TimeInterval(bottleDurationMins * 60)) : nil
                editing.leftDurationMins  = nil
                editing.rightDurationMins = nil
                editing.pumpSide          = nil
                editing.pumpVolumeMl      = nil
            case .pump:
                let totalMins = pumpSide == .left  ? pumpLeftDurationMins
                              : pumpSide == .right ? pumpRightDurationMins
                              : pumpLeftDurationMins + pumpRightDurationMins
                editing.feedType          = .pump
                editing.pumpSide          = pumpSide
                editing.pumpVolumeMl      = pumpVolumeMl > 0 ? pumpVolumeMl : nil
                editing.endTime           = startTime.addingTimeInterval(TimeInterval(totalMins * 60))
                editing.leftDurationMins  = nil
                editing.rightDurationMins = nil
                editing.bottleContentType = nil
                editing.bottleAmountMl    = nil
            }
            target = editing
        } else {
            let session: FeedingSession
            switch sessionCategory {
            case .breast:
                let totalMins = leftDurationMins + rightDurationMins
                session = FeedingSession(
                    startTime: startTime,
                    feedType: resolvedFeedType,
                    endTime: startTime.addingTimeInterval(TimeInterval(totalMins * 60)),
                    leftDurationMins: leftDurationMins,
                    rightDurationMins: rightDurationMins,
                    notes: notes.isEmpty ? nil : notes
                )
            case .bottle:
                let endTime = bottleDurationMins > 0 ? startTime.addingTimeInterval(TimeInterval(bottleDurationMins * 60)) : nil
                session = FeedingSession(
                    startTime: startTime,
                    feedType: .bottle,
                    endTime: endTime,
                    bottleAmountMl: bottleAmountMl,
                    notes: notes.isEmpty ? nil : notes
                )
            case .pump:
                let totalMins = pumpSide == .left  ? pumpLeftDurationMins
                              : pumpSide == .right ? pumpRightDurationMins
                              : pumpLeftDurationMins + pumpRightDurationMins
                session = FeedingSession(
                    startTime: startTime,
                    feedType: .pump,
                    endTime: startTime.addingTimeInterval(TimeInterval(totalMins * 60)),
                    pumpSide: pumpSide,
                    pumpVolumeMl: pumpVolumeMl > 0 ? pumpVolumeMl : nil,
                    notes: notes.isEmpty ? nil : notes
                )
            }
            modelContext.insert(session)
            target = session
        }

        try? modelContext.save()
        Task { await FirestoreService.shared.pushSession(target) }
        NotificationManager.shared.refreshReminder(modelContainer: NourishApp.modelContainer)
        SharedFeedSnapshot.refresh(modelContainer: NourishApp.modelContainer)

        if editing != nil {
            AnalyticsService.sessionEdited()
        } else {
            switch sessionCategory {
            case .breast:
                AnalyticsService.sessionCompleted(
                    totalSeconds: (leftDurationMins + rightDurationMins) * 60,
                    leftSeconds: leftDurationMins * 60,
                    rightSeconds: rightDurationMins * 60,
                    feedType: "breast"
                )
            case .bottle:
                AnalyticsService.sessionCompleted(totalSeconds: 0, leftSeconds: 0, rightSeconds: 0, feedType: "bottle")
            case .pump:
                let totalSecs = (pumpSide == .left  ? pumpLeftDurationMins
                               : pumpSide == .right ? pumpRightDurationMins
                               : pumpLeftDurationMins + pumpRightDurationMins) * 60
                AnalyticsService.pumpSessionCompleted(
                    side: pumpSide.rawValue,
                    durationSeconds: totalSecs,
                    volumeMl: pumpVolumeMl > 0 ? pumpVolumeMl : nil
                )
            }
        }

        onSave()
    }

    // MARK: Duration stepper row

    private func durationRow(sideLabel: String, bodyLabel: String? = nil, accent: Color, accentBg: Color, minutes: Binding<Int>) -> some View {
        HStack(spacing: 12) {
            Text(String(sideLabel.prefix(1)))
                .font(.nSans(12, weight: .semibold))
                .foregroundStyle(c.muted)
                .frame(width: 28, height: 28)
                .clipShape(Circle())
                .overlay(Circle().stroke(c.border, lineWidth: 1.5))

            Text(bodyLabel ?? "\(sideLabel) breast")
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

    // MARK: Helpers

    private func sectionLabel(_ label: String) -> some View {
        Text(label.uppercased())
            .font(.nSans(11, weight: .bold))
            .foregroundStyle(c.muted)
            .kerning(0.09 * 11)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
