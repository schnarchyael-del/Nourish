import SwiftUI

enum NourishTab: Int, CaseIterable {
    case feed = 0, sleep = 1, log = 2, stats = 3, settings = 4

    var label: String {
        switch self {
        case .feed:     "Feed"
        case .sleep:    "Sleep"
        case .log:      "Log"
        case .stats:    "Stats"
        case .settings: "Me"
        }
    }
}

struct BottomTabBar: View {
    @Binding var selectedTab: Int
    let colors: NourishColors

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(colors.border)
                .frame(height: 1)

            HStack(spacing: 0) {
                ForEach(NourishTab.allCases, id: \.rawValue) { tab in
                    tabButton(tab)
                        .tooltipTargetIf(tab == .settings, .settings)
                        .tooltipTargetIf(tab == .sleep,    .sleepTab)
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 14)
        }
        .background(colors.bg)
    }

    private func tabButton(_ tab: NourishTab) -> some View {
        let isActive = selectedTab == tab.rawValue
        let tint: Color = tab == .sleep ? Color(hex: "534AB7") : colors.leftAccent
        return Button {
            selectedTab = tab.rawValue
        } label: {
            VStack(spacing: 3) {
                tabIcon(tab, active: isActive, tint: tint)
                Text(tab.label)
                    .font(.nSans(11, weight: .semibold))
                    .kerning(0.04 * 11)
                    .foregroundStyle(isActive ? tint : colors.muted)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func tabIcon(_ tab: NourishTab, active: Bool, tint: Color) -> some View {
        let color: Color = active ? tint : colors.ink.opacity(0.25)
        switch tab {
        case .feed:
            // Circle with center dot — kept from the previous Home icon.
            ZStack {
                Circle()
                    .stroke(color, lineWidth: 1.5)
                    .frame(width: 20, height: 20)
                Circle()
                    .fill(color)
                    .frame(width: 5, height: 5)
            }
        case .sleep:
            Image(systemName: "moon.fill")
                .font(.nSans(17))
                .foregroundStyle(color)
        case .log:
            Image(systemName: "plus")
                .font(.nSans(18, weight: .medium))
                .foregroundStyle(color)
        case .stats:
            Image(systemName: "chart.bar.fill")
                .font(.nSans(17))
                .foregroundStyle(color)
        case .settings:
            Image(systemName: "person.crop.circle")
                .font(.nSans(19))
                .foregroundStyle(color)
        }
    }
}
