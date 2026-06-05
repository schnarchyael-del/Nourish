import SwiftUI
import Combine

// MARK: - Tooltip identity

enum TooltipID: String, CaseIterable {
    case startFeed
    case settings
    case widgetTip
    case switchSide
    case endSession
    case statsHint
    case historySwipe
    case pumpButton

    var storageKey: String { "tooltip_\(rawValue)_shown" }

    var text: String {
        switch self {
        case .startFeed:
            return "Tap to start tracking a feed 🍼"
        case .settings:
            return "Set up reminders and customize your experience in Settings ⚙️"
        case .widgetTip:
            return "Tip: Add a Nourish widget to your lock screen to see your last feed at a glance! Go to your lock screen → long press → customize."
        case .switchSide:
            return "Tap to switch sides when you're ready"
        case .endSession:
            return "Tap when done to save your session ✓"
        case .statsHint:
            return "Your feeding patterns will appear here as you log more feeds 📊"
        case .historySwipe:
            return "Swipe left on any session to edit or delete"
        case .pumpButton:
            return "Track pump sessions — duration, volume, and notes"
        }
    }

    /// Banners render at the top of the screen with no arrow.
    var isBanner: Bool {
        switch self {
        case .widgetTip, .statsHint: return true
        default:                     return false
        }
    }

    var isNewInSequence: Bool { self == .pumpButton }

    /// The next tooltip in this screen's sequence, if any. Tooltip bubbles
    /// show a → button when `next` is set, otherwise an X.
    var next: TooltipID? {
        switch self {
        case .startFeed:  return .settings
        case .switchSide: return .endSession
        default:          return nil
        }
    }
}

// MARK: - Manager

@MainActor
final class TooltipManager: ObservableObject {
    @Published var active: TooltipID?

    private var pendingShow: DispatchWorkItem?
    private var shownAt: Date?
    private var didCountHomeAppearanceThisLaunch = false

    /// Bumps the persistent "home appearance with sessions" counter, but
    /// only once per app launch. Idempotent — safe to call from multiple
    /// HomeView lifecycle events. Reset in `resetAppLaunchGate()` when the
    /// app backgrounds.
    func bumpHomeAppearanceIfFirstThisLaunch(haveSessions: Bool) {
        guard !didCountHomeAppearanceThisLaunch,
              haveSessions,
              !hasSeen(.widgetTip) else { return }
        didCountHomeAppearanceThisLaunch = true
        let key = TooltipKey.homeAppearancesAfterFirstSession
        let next = UserDefaults.standard.integer(forKey: key) + 1
        UserDefaults.standard.set(next, forKey: key)
    }

    func resetAppLaunchGate() {
        didCountHomeAppearanceThisLaunch = false
    }

    var homeAppearancesAfterFirstSession: Int {
        UserDefaults.standard.integer(forKey: TooltipKey.homeAppearancesAfterFirstSession)
    }

    /// Schedules a tooltip after a brief delay. No-op if the tooltip has
    /// already been shown, or if another tooltip is currently active —
    /// we never stack tooltips.
    func show(_ id: TooltipID, after delay: TimeInterval = 0.5) {
        guard !hasSeen(id) else { return }
        pendingShow?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard self.active == nil, !self.hasSeen(id) else { return }
            self.shownAt = Date()
            withAnimation(.easeOut(duration: 0.28)) { self.active = id }
        }
        pendingShow = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// Dismiss the current tooltip and mark it as seen. Does NOT auto-advance
    /// — backdrop tap means "I'm done with tooltips for now". Sequenced
    /// tooltips advance only when the user explicitly taps the bubble / arrow.
    func dismiss() {
        pendingShow?.cancel()
        pendingShow = nil
        if let id = active { markSeen(id) }
        shownAt = nil
        withAnimation(.easeOut(duration: 0.2)) { active = nil }
    }

    /// Mark the current tooltip seen and advance immediately to the next
    /// one in the on-screen chain.
    func advance(to next: TooltipID) {
        pendingShow?.cancel()
        pendingShow = nil
        if let id = active { markSeen(id) }
        shownAt = nil
        withAnimation(.easeOut(duration: 0.18)) { active = nil }
        show(next, after: 0.22)
    }

    /// Mark the active tooltip seen and clear it. Use only for genuine
    /// "user closed the app" events — not transient view lifecycle.
    func clearOnNavigateAway() {
        guard let id = active, let shown = shownAt,
              Date().timeIntervalSince(shown) >= 0.6 else { return }
        markSeen(id)
        shownAt = nil
        active = nil
    }

    /// Clear the active tooltip without marking it seen. Use on within-app
    /// navigation so the tooltip can re-appear next time the target screen
    /// is shown.
    func clearActiveWithoutMarking() {
        pendingShow?.cancel()
        pendingShow = nil
        shownAt = nil
        active = nil
    }

    func markSeen(_ id: TooltipID) {
        UserDefaults.standard.set(true, forKey: id.storageKey)
    }

    func hasSeen(_ id: TooltipID) -> Bool {
        UserDefaults.standard.bool(forKey: id.storageKey)
    }
}

// MARK: - Storage keys

enum TooltipKey {
    static let homeAppearancesAfterFirstSession = "homeAppearancesAfterFirstSession"
}

// MARK: - Anchor preference

struct TooltipAnchorEntry: Equatable {
    let id: TooltipID
    let bounds: Anchor<CGRect>

    static func == (lhs: TooltipAnchorEntry, rhs: TooltipAnchorEntry) -> Bool {
        lhs.id == rhs.id
    }
}

struct TooltipAnchorKey: PreferenceKey {
    static var defaultValue: [TooltipAnchorEntry] = []
    static func reduce(value: inout [TooltipAnchorEntry],
                       nextValue: () -> [TooltipAnchorEntry]) {
        value.append(contentsOf: nextValue())
    }
}

extension View {
    /// Marks this view as the visual target a tooltip points at.
    func tooltipTarget(_ id: TooltipID) -> some View {
        anchorPreference(key: TooltipAnchorKey.self, value: .bounds) {
            [TooltipAnchorEntry(id: id, bounds: $0)]
        }
    }

    @ViewBuilder
    func tooltipTargetIf(_ condition: Bool, _ id: TooltipID) -> some View {
        if condition {
            self.tooltipTarget(id)
        } else {
            self
        }
    }

    /// Renders any active tooltip on top of this view.
    func tooltipOverlay(_ manager: TooltipManager) -> some View {
        modifier(TooltipOverlayModifier(manager: manager))
    }
}

// MARK: - Overlay rendering

private struct TooltipOverlayModifier: ViewModifier {
    @ObservedObject var manager: TooltipManager

    func body(content: Content) -> some View {
        content
            .overlayPreferenceValue(TooltipAnchorKey.self) { entries in
                GeometryReader { proxy in
                    if let active = manager.active {
                        let entry = entries.first { $0.id == active }
                        let target = entry.map { proxy[$0.bounds] }
                        TooltipPresenter(
                            id: active,
                            target: target,
                            screenSize: proxy.size,
                            manager: manager
                        )
                    }
                }
                .ignoresSafeArea()
            }
    }
}

private struct TooltipPresenter: View {
    let id: TooltipID
    let target: CGRect?
    let screenSize: CGSize
    @ObservedObject var manager: TooltipManager

    @State private var bubbleSize: CGSize = .zero

    private var arrowDirection: TooltipBubble.Arrow {
        if id.isBanner { return .none }
        guard let t = target else { return .none }
        return t.midY > screenSize.height / 2 ? .down : .up
    }

    private var resolvedX: CGFloat {
        let bubbleW = max(bubbleSize.width, 1)
        if let t = target, !id.isBanner {
            let centered = t.midX - bubbleW / 2
            let safeMin: CGFloat = 16
            let safeMax = max(safeMin, screenSize.width - bubbleW - 16)
            return min(max(safeMin, centered), safeMax)
        }
        return max(16, (screenSize.width - bubbleW) / 2)
    }

    private var resolvedY: CGFloat {
        if id.isBanner {
            return 90
        }
        guard let t = target else { return 90 }
        let gap: CGFloat = 12
        if arrowDirection == .down {
            return max(60, t.minY - bubbleSize.height - gap)
        } else {
            return min(screenSize.height - bubbleSize.height - 60, t.maxY + gap)
        }
    }

    /// Horizontal shift of the arrow from its default centered position so
    /// the tip lands on the actual target, even when the bubble has been
    /// clamped against a screen edge.
    private var arrowOffsetX: CGFloat {
        guard let t = target, !id.isBanner, bubbleSize.width > 0 else { return 0 }
        let bubbleCenterX = resolvedX + bubbleSize.width / 2
        let raw = t.midX - bubbleCenterX
        let maxShift = max(0, bubbleSize.width / 2 - 14)
        return min(max(-maxShift, raw), maxShift)
    }

    private func handleAdvanceOrDismiss(for id: TooltipID) {
        if let next = id.next {
            manager.advance(to: next)
        } else {
            manager.dismiss()
        }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Darkened backdrop. Tap dismisses (acts like the X). The dim
            // pulls focus to the tooltip without fully blocking the UI
            // underneath.
            Color.black.opacity(0.42)
                .frame(width: screenSize.width, height: screenSize.height)
                .contentShape(Rectangle())
                .onTapGesture { manager.dismiss() }
                .transition(.opacity)

            TooltipBubble(
                text: id.text,
                arrow: arrowDirection,
                arrowOffsetX: arrowOffsetX,
                buttonKind: id.next == nil ? .close : .next,
                onButtonTap: { handleAdvanceOrDismiss(for: id) }
            )
            .background(
                GeometryReader { g in
                    Color.clear
                        .onAppear { bubbleSize = g.size }
                        .onChange(of: g.size) { _, new in bubbleSize = new }
                }
            )
            // Tapping the bubble itself advances (or dismisses if no next).
            // The discrete button inside is a visual affordance for the same
            // action — both routes go through handleAdvanceOrDismiss.
            .contentShape(Rectangle())
            .onTapGesture { handleAdvanceOrDismiss(for: id) }
            .opacity(bubbleSize == .zero ? 0 : 1)
            .offset(x: resolvedX, y: resolvedY)
            .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
        }
        .frame(width: screenSize.width, height: screenSize.height, alignment: .topLeading)
    }
}

// MARK: - Bubble view

struct TooltipBubble: View {
    let text: String
    let arrow: Arrow
    /// Horizontal shift of the arrow tip relative to the bubble's center.
    /// 0 = centered. Positive = right. Used to keep the arrow on the actual
    /// target when the bubble itself has been clamped against a screen edge.
    var arrowOffsetX: CGFloat = 0
    var buttonKind: ButtonKind = .close
    var onButtonTap: () -> Void = {}

    enum Arrow { case up, down, none }
    enum ButtonKind { case close, next }

    private var bg: Color { Color(hex: "FAF7F2") }
    private var ink: Color { Color(hex: "1A130E") }
    private var border: Color { Color(hex: "1A130E").opacity(0.10) }

    var body: some View {
        VStack(spacing: 0) {
            if arrow == .up {
                arrowShape
                    .rotationEffect(.degrees(180))
                    .offset(x: arrowOffsetX, y: 1)
                    .zIndex(1)
            }

            card

            if arrow == .down {
                arrowShape
                    .offset(x: arrowOffsetX, y: -1)
                    .zIndex(1)
            }
        }
        .frame(maxWidth: 280)
    }

    private var card: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(text)
                .font(.nSans(14))
                .foregroundStyle(ink)
                .lineSpacing(3)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onButtonTap) {
                Image(systemName: buttonKind == .close ? "xmark" : "arrow.right")
                    .font(.nSans(11, weight: .bold))
                    .foregroundStyle(ink.opacity(0.6))
                    .frame(width: 22, height: 22)
                    .background(ink.opacity(0.06), in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 16)
        .padding(.trailing, 10)
        .padding(.vertical, 11)
        .background(bg)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(border, lineWidth: 1))
        .shadow(color: .black.opacity(0.18), radius: 20, y: 8)
    }

    private var arrowShape: some View {
        TooltipTriangle()
            .fill(bg)
            .overlay(
                TooltipTriangle()
                    .stroke(border, lineWidth: 1)
            )
            .frame(width: 14, height: 8)
    }
}

private struct TooltipTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        p.closeSubpath()
        return p
    }
}
