import SwiftUI
import SwiftData

struct ContentView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("accentVariant")          private var accentVariant          = "terra"
    @AppStorage("rightAccentVariant")     private var rightAccentVariant     = "blue"
    @AppStorage("darkActiveScreen")       private var darkActiveScreen       = true
    @AppStorage("showEncouragements")     private var showEncouragements     = true

    @State private var sessionStore  = SessionStore()
    @State private var selectedTab   = 0
    @State private var showLogScreen = false

    private var colors: NourishColors {
        NourishColors(
            accent: AccentVariant(rawValue: accentVariant) ?? .terra,
            rightAccent: RightAccentVariant(rawValue: rightAccentVariant) ?? .blue
        )
    }

    private var showTabBar: Bool {
        !sessionStore.isActive && !showLogScreen && selectedTab != 1
    }

    var body: some View {
        Group {
            if !hasCompletedOnboarding {
                OnboardingView(onComplete: { hasCompletedOnboarding = true })
                    .environment(\.nourishColors, colors)
            } else {
                mainContent
            }
        }
        .animation(.easeInOut(duration: 0.22), value: hasCompletedOnboarding)
    }

    // MARK: Main app shell

    private var mainContent: some View {
        VStack(spacing: 0) {
            screenContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(.spring(response: 0.35, dampingFraction: 0.82), value: sessionStore.isActive)
                .animation(.spring(response: 0.35, dampingFraction: 0.82), value: showLogScreen)
                .animation(.spring(response: 0.35, dampingFraction: 0.82), value: selectedTab)

            if showTabBar {
                BottomTabBar(selectedTab: $selectedTab, colors: colors)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(colors.bg.ignoresSafeArea())
        .environment(\.nourishColors, colors)
    }

    // MARK: Screen resolver

    private static let tabTransition = AnyTransition.asymmetric(
        insertion: .opacity.combined(with: .scale(scale: 0.97)),
        removal: .opacity
    )

    @ViewBuilder
    private var screenContent: some View {
        if showLogScreen {
            LogSessionView(
                onBack: { showLogScreen = false },
                onSave: { showLogScreen = false }
            )
            .transition(Self.tabTransition)

        } else if sessionStore.isActive {
            ActiveSessionView(
                store: sessionStore,
                darkMode: darkActiveScreen,
                showEncouragements: showEncouragements
            )
            .transition(Self.tabTransition)

        } else {
            switch selectedTab {
            case 0:
                HomeView(store: sessionStore, onLog: { showLogScreen = true })
                    .transition(Self.tabTransition)

            case 1:
                LogSessionView(
                    onBack: { selectedTab = 0 },
                    onSave: { selectedTab = 0 }
                )
                .transition(Self.tabTransition)

            case 2:
                StatsView(onLogFirstSession: { showLogScreen = true })
                    .transition(Self.tabTransition)

            case 3:
                SettingsView()
                    .transition(Self.tabTransition)

            default:
                HomeView(store: sessionStore, onLog: { showLogScreen = true })
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: FeedingSession.self, inMemory: true)
}
