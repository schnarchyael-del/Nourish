import SwiftUI

private struct ManualSection: Identifiable {
    let id: String
    let icon: String
    let title: String
    let bullets: [String]
}

private let manualSections: [ManualSection] = [
    ManualSection(
        id: "tracking_a_feed",
        icon: "🤱",
        title: "Tracking a Feed",
        bullets: [
            "Tap **L** or **R** on the home screen to start a breastfeed",
            "The timer starts automatically",
            "Tap the switch button to change sides — each side is tracked separately",
            "Tap **Stop** when done to save the session",
            "Total time = left + right combined"
        ]
    ),
    ManualSection(
        id: "bottle_feeds",
        icon: "🍼",
        title: "Bottle Feeds",
        bullets: [
            "Tap **Bottle feed** on the home screen",
            "Enter the amount (ml) and duration",
            "Bottle feeds show separately in your stats"
        ]
    ),
    ManualSection(
        id: "pump_sessions",
        icon: "💧",
        title: "Pump Sessions",
        bullets: [
            "Tap **Pump session** on the home screen",
            "Choose your side: Left, Right, or Both",
            "Track duration and volume (ml)",
            "Add notes like \"for freezer\" or \"morning pump\"",
            "Pump sessions appear in your history but don't affect your last feed timer or reminders"
        ]
    ),
    ManualSection(
        id: "logging_past_session",
        icon: "🕐",
        title: "Logging a Past Session",
        bullets: [
            "Tap **+ Log a past session** on the home screen",
            "Choose the type: Breast, Bottle, or Pump",
            "Set the date, time, duration, and any other details",
            "Great for when you forgot to start the timer"
        ]
    ),
    ManualSection(
        id: "your_stats",
        icon: "📊",
        title: "Your Stats",
        bullets: [
            "The Stats tab shows your feeding patterns",
            "Switch between Day, Week, and Month views",
            "Tap the calendar icon to view past periods",
            "See feed breakdown by side, average session times, and more",
            "Smart insights surface interesting patterns as you log more feeds"
        ]
    ),
    ManualSection(
        id: "history",
        icon: "📋",
        title: "History",
        bullets: [
            "The History tab shows all your sessions grouped by date",
            "Tap any session to see full details and notes",
            "Swipe left to edit or delete a session"
        ]
    ),
    ManualSection(
        id: "widgets",
        icon: "📱",
        title: "Widgets",
        bullets: [
            "Add Nourish to your home screen or lock screen",
            "Widgets show your last feed time and which side to start next",
            "To add: long press your home or lock screen → tap **+** → search \"Nourish\""
        ]
    ),
    ManualSection(
        id: "reminders",
        icon: "🔔",
        title: "Reminders",
        bullets: [
            "Set up feed reminders in Settings",
            "Get notified when it's time for the next feed",
            "Reminders are based on your last feed, not pump sessions"
        ]
    ),
    ManualSection(
        id: "cloud_sync",
        icon: "☁️",
        title: "Cloud Sync & Accounts",
        bullets: [
            "Sign in with Apple or email in Settings to sync your data",
            "Your feeds sync automatically across your devices",
            "Sign out anytime — your local data stays on the device"
        ]
    ),
    ManualSection(
        id: "partner_sharing",
        icon: "👨‍👩‍👧",
        title: "Partner Sharing",
        bullets: [
            "Generate a partner code in Settings",
            "Share it with your partner — they enter it on their phone",
            "Both of you see the same feeds and baby profile in real time"
        ]
    ),
    ManualSection(
        id: "dark_mode",
        icon: "🌙",
        title: "Dark Mode",
        bullets: [
            "Switch between Light, Dark, or System theme in **Settings → Appearance**"
        ]
    ),
    ManualSection(
        id: "export_data",
        icon: "📤",
        title: "Export Your Data",
        bullets: [
            "Export all your sessions as a CSV file",
            "Go to **Settings → Export Data**",
            "Great for sharing with your doctor or keeping records"
        ]
    )
]

struct HowToUseView: View {
    @Environment(\.nourishColors) private var c
    @Environment(\.dismiss) private var dismiss
    @State private var expandedSection: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("How to Use Nourish")
                        .font(.nSerif(22))
                        .foregroundStyle(c.ink)
                    Text("Tap any topic to learn more")
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

            ScrollView {
                VStack(spacing: 10) {
                    ForEach(manualSections) { section in
                        sectionCard(section)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
        }
        .background(c.bg.ignoresSafeArea())
        .onAppear { AnalyticsService.log("manual_opened") }
    }

    private func sectionCard(_ section: ManualSection) -> some View {
        let isExpanded = expandedSection == section.id
        return VStack(spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                    if isExpanded {
                        expandedSection = nil
                    } else {
                        expandedSection = section.id
                        AnalyticsService.log("manual_section_viewed", ["section_name": section.id])
                    }
                }
            } label: {
                HStack(spacing: 14) {
                    Text(section.icon)
                        .font(.nSans(19))
                        .frame(width: 32)
                    Text(section.title)
                        .font(.nSans(15, weight: .semibold))
                        .foregroundStyle(c.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(c.muted.opacity(0.6))
                        .animation(.easeInOut(duration: 0.2), value: isExpanded)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider()
                    .overlay(c.border)
                    .padding(.horizontal, 18)

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(section.bullets.enumerated()), id: \.offset) { _, bullet in
                        HStack(alignment: .top, spacing: 10) {
                            Text("•")
                                .font(.nSans(14))
                                .foregroundStyle(c.leftAccent)
                                .padding(.top, 1)
                            Text(LocalizedStringKey(bullet))
                                .font(.nSans(14))
                                .foregroundStyle(c.ink)
                                .lineSpacing(3)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(c.surface)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(isExpanded ? c.leftAccent.opacity(0.3) : c.border, lineWidth: 1))
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: isExpanded)
    }
}
