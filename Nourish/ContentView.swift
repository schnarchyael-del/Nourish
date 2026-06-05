import SwiftUI
import SwiftData

struct ContentView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("accentVariant")          private var accentVariant          = "terra"
    @AppStorage("rightAccentVariant")     private var rightAccentVariant     = "blue"
    @AppStorage("darkActiveScreen")       private var darkActiveScreen       = true
    @AppStorage("appTheme")               private var appThemeRaw            = AppTheme.system.rawValue

    @Environment(\.colorScheme) private var systemColorScheme

    @State private var sessionStore  = SessionStore()
    @State private var pumpStore     = PumpStore()
    @State private var selectedTab   = 0
    @State private var showLogScreen = false
    @State private var showPumpScreen = false
    @StateObject private var tooltips = TooltipManager()
    @Environment(\.scenePhase) private var scenePhase

    private var appTheme: AppTheme {
        AppTheme(rawValue: appThemeRaw) ?? .system
    }

    private var darkMode: Bool {
        switch appTheme {
        case .light:  return false
        case .dark:   return true
        case .system: return systemColorScheme == .dark
        }
    }

    private var colors: NourishColors {
        NourishColors(
            accent: AccentVariant(rawValue: accentVariant) ?? .terra,
            rightAccent: RightAccentVariant(rawValue: rightAccentVariant) ?? .blue,
            darkMode: darkMode
        )
    }

    private var showTabBar: Bool {
        !sessionStore.isActive && !pumpStore.isActive && !showLogScreen && !showPumpScreen && selectedTab != 1
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
        .preferredColorScheme(appTheme.preferredScheme)
        .environmentObject(tooltips)
        .tooltipOverlay(tooltips)
        .onChange(of: selectedTab)             { _, _ in tooltips.clearActiveWithoutMarking() }
        .onChange(of: showLogScreen)           { _, _ in tooltips.clearActiveWithoutMarking() }
        .onChange(of: showPumpScreen)          { _, _ in tooltips.clearActiveWithoutMarking() }
        .onChange(of: sessionStore.isActive)   { _, _ in tooltips.clearActiveWithoutMarking() }
        .onChange(of: pumpStore.isActive)      { _, _ in tooltips.clearActiveWithoutMarking() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                tooltips.clearOnNavigateAway()
                tooltips.resetAppLaunchGate()
            }
        }
    }

    // MARK: Main app shell

    private var mainContent: some View {
        VStack(spacing: 0) {
            screenContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(.spring(response: 0.35, dampingFraction: 0.82), value: sessionStore.isActive)
                .animation(.spring(response: 0.35, dampingFraction: 0.82), value: pumpStore.isActive)
                .animation(.spring(response: 0.35, dampingFraction: 0.82), value: showLogScreen)
                .animation(.spring(response: 0.35, dampingFraction: 0.82), value: showPumpScreen)
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
        if pumpStore.isActive || showPumpScreen {
            PumpSessionView(
                store: pumpStore,
                onDismiss: { showPumpScreen = false }
            )
            .transition(Self.tabTransition)

        } else if showLogScreen {
            LogSessionView(
                onBack: { showLogScreen = false },
                onSave: { showLogScreen = false }
            )
            .transition(Self.tabTransition)

        } else if sessionStore.isActive {
            ActiveSessionView(
                store: sessionStore,
                darkMode: darkActiveScreen
            )
            .transition(Self.tabTransition)

        } else {
            switch selectedTab {
            case 0:
                HomeView(
                    store: sessionStore,
                    onLog: { showLogScreen = true },
                    onPump: { showPumpScreen = true }
                )
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
                HomeView(
                    store: sessionStore,
                    onLog: { showLogScreen = true },
                    onPump: { showPumpScreen = true }
                )
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: FeedingSession.self, inMemory: true)
}
