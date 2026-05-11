import SwiftUI

enum NourishTab: Int, CaseIterable {
    case home = 0, log = 1, stats = 2, settings = 3

    var label: String {
        switch self {
        case .home:     "Home"
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
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 14)
        }
        .background(colors.bg)
    }

    private func tabButton(_ tab: NourishTab) -> some View {
        let isActive = selectedTab == tab.rawValue
        return Button {
            selectedTab = tab.rawValue
        } label: {
            VStack(spacing: 3) {
                tabIcon(tab, active: isActive)
                Text(tab.label)
                    .font(.nSans(11, weight: .semibold))
                    .kerning(0.04 * 11)
                    .foregroundStyle(isActive ? colors.leftAccent : colors.muted)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func tabIcon(_ tab: NourishTab, active: Bool) -> some View {
        let color: Color = active ? colors.leftAccent : colors.ink.opacity(0.25)
        switch tab {
        case .home:
            // Circle with center dot
            ZStack {
                Circle()
                    .stroke(color, lineWidth: 1.5)
                    .frame(width: 20, height: 20)
                Circle()
                    .fill(color)
                    .frame(width: 5, height: 5)
            }
        case .log:
            Image(systemName: "plus")
                .font(.nSans(18, weight: .medium))
                .foregroundStyle(color)
        case .stats:
            Image(systemName: "square.split.2x1")
                .font(.nSans(18))
                .foregroundStyle(color)
        case .settings:
            ZStack {
                Circle()
                    .stroke(color, lineWidth: 1.5)
                    .frame(width: 20, height: 20)
                Circle()
                    .stroke(color, lineWidth: 1.5)
                    .frame(width: 10, height: 10)
            }
        }
    }
}
