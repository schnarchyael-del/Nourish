import SwiftUI

struct SessionDetailSheet: View {
    @Environment(\.nourishColors) private var c
    @Environment(\.dismiss) private var dismiss

    let session: FeedingSession
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(c.muted.opacity(0.28))
                .frame(width: 36, height: 4)
                .padding(.top, 12)
                .padding(.bottom, 20)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    headerSection
                    detailCard
                    if let notes = session.notes, !notes.isEmpty {
                        notesCard(notes)
                    }
                    actionButtons
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
        }
        .background(c.bg.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(28)
        .presentationBackground(c.bg)
    }

    private var headerSection: some View {
        HStack(spacing: 14) {
            typeIcon
            VStack(alignment: .leading, spacing: 3) {
                Text(typeTitle)
                    .font(.nSerif(22))
                    .foregroundStyle(c.ink)
                Text(session.startTime.formatted(
                    .dateTime.weekday(.wide).month(.wide).day().year().hour().minute()
                ))
                .font(.nSans(13))
                .foregroundStyle(c.muted)
            }
            Spacer()
        }
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private var typeIcon: some View {
        switch session.feedType {
        case .bottle:
            Text("🍼")
                .font(.nSans(24))
                .frame(width: 52, height: 52)
                .background(c.bottleBg)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(c.bottleBorder, lineWidth: 1.5))
        case .pump:
            Image("pump_icon")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundStyle(c.pumpAccent)
                .padding(10)
                .frame(width: 52, height: 52)
                .background(c.pumpBg)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(c.pumpBorder, lineWidth: 1.5))
        case .sleep:
            Text("🌙")
                .font(.nSans(24))
                .frame(width: 52, height: 52)
                .background(SleepView.sleepBg)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(SleepView.sleepBorder, lineWidth: 1.5))
        default:
            Text(session.feedType.shortLabel)
                .font(.nSans(20, weight: .bold))
                .foregroundStyle(session.feedType == .left ? c.leftText : c.rightText)
                .frame(width: 52, height: 52)
                .background(session.feedType == .left ? c.leftBg : c.rightBg)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(
                    session.feedType == .left ? c.leftAccent.opacity(0.25) : c.rightAccent.opacity(0.25),
                    lineWidth: 1.5
                ))
        }
    }

    private var typeTitle: String {
        switch session.feedType {
        case .bottle: return "Bottle feed"
        case .pump:   return "Pump session"
        case .left:   return "Left breast"
        case .right:  return "Right breast"
        case .sleep:  return "Sleep"
        }
    }

    private var detailCard: some View {
        VStack(spacing: 0) {
            switch session.feedType {
            case .left, .right:
                if session.leftMinutesResolved > 0 {
                    detailRow(label: "Left", value: "\(session.leftMinutesResolved) min")
                }
                if session.leftMinutesResolved > 0 && session.rightMinutesResolved > 0 {
                    Divider().overlay(c.border)
                }
                if session.rightMinutesResolved > 0 {
                    detailRow(label: "Right", value: "\(session.rightMinutesResolved) min")
                }
            case .pump:
                detailRow(label: "Duration", value: "\(session.totalActiveMinutes) min")
                if let vol = session.pumpVolumeMl {
                    Divider().overlay(c.border)
                    detailRow(label: "Volume", value: "\(vol) ml")
                }
                if let side = session.pumpSide {
                    Divider().overlay(c.border)
                    detailRow(label: "Side", value: side.displayName)
                }
            case .bottle:
                if let ml = session.bottleAmountMl {
                    detailRow(label: "Amount", value: "\(ml) ml")
                    if let type = session.bottleContentType {
                        Divider().overlay(c.border)
                        detailRow(label: "Content", value: type.displayName)
                    }
                } else if let type = session.bottleContentType {
                    detailRow(label: "Content", value: type.displayName)
                } else {
                    detailRow(label: "Amount", value: "—")
                }
            case .sleep:
                detailRow(label: "Duration", value: SleepView.formatHM(session.totalActiveMinutes))
                if let end = session.endTime {
                    Divider().overlay(c.border)
                    detailRow(label: "Woke up", value: end.formatted(date: .omitted, time: .shortened))
                }
            }
        }
        .background(c.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(c.border, lineWidth: 1))
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.nSans(14))
                .foregroundStyle(c.muted)
            Spacer()
            Text(value)
                .font(.nSans(14, weight: .semibold))
                .foregroundStyle(c.ink)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    private func notesCard(_ notes: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("NOTE")
                .font(.nSans(11, weight: .bold))
                .foregroundStyle(c.muted)
                .kerning(0.09 * 11)
            Text(notes)
                .font(.nSans(14))
                .foregroundStyle(c.ink)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(c.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(c.border, lineWidth: 1))
    }

    private var actionButtons: some View {
        VStack(spacing: 10) {
            Button {
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { onEdit() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "pencil").font(.nSans(15))
                    Text("Edit session").font(.nSans(16, weight: .semibold))
                }
                .foregroundStyle(c.ink)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(c.surface)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(c.border, lineWidth: 1.5))
            }
            .buttonStyle(ScaleButtonStyle())

            Button {
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { onDelete() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "trash").font(.nSans(15))
                    Text("Delete session").font(.nSans(16, weight: .semibold))
                }
                .foregroundStyle(.red.opacity(0.8))
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Color.red.opacity(0.06))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.red.opacity(0.18), lineWidth: 1.5))
            }
            .buttonStyle(ScaleButtonStyle())
        }
        .padding(.top, 8)
    }
}
