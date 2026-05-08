import AppKit
#if DEBUG
import Inject
#endif
import SwiftUI

struct NotchGeometry: Equatable {
    var notchSize: CGSize
    var hasRealNotch: Bool

    static let fallback = NotchGeometry(notchSize: CGSize(width: 220, height: 36), hasRealNotch: false)
}

private enum CornerRadii {
    static let collapsed = (top: CGFloat(6), bottom: CGFloat(14))
    static let expanded = (top: CGFloat(19), bottom: CGFloat(24))
}

private enum IslandLayout {
    static let expandedSize = CGSize(width: 540, height: 380)
    static let expandedHorizontalPadding: CGFloat = 38
}

struct IslandRootView: View {
    @ObservedObject var store: AgentSessionStore
    @ObservedObject var presentation: IslandPresentation
    var notch: NotchGeometry
    @State private var selectedID: AgentSession.ID?
    @State private var isHovering = false
    @State private var lastHoverHapticAt = Date.distantPast
#if DEBUG
    @ObserveInjection var inject
#endif

    private var selectedSession: AgentSession? {
        if let selectedID, let session = store.sessions.first(where: { $0.id == selectedID }) {
            return session
        }
        return store.activeSession
    }

    /// Side overhang past the physical notch — gives content room and lets the pill
    /// visually thicken when collapsed.
    private var sideWidth: CGFloat {
        max(0, notch.notchSize.height - 12) + 24
    }

    private var collapsedSize: CGSize {
        let hoverInset: CGFloat = isHovering ? 4 : 0

        return CGSize(
            width: notch.notchSize.width + sideWidth * 2 + hoverInset * 2,
            height: notch.notchSize.height + hoverInset
        )
    }

    private var expandedSize: CGSize {
        CGSize(
            width: IslandLayout.expandedSize.width + IslandLayout.expandedHorizontalPadding,
            height: IslandLayout.expandedSize.height
        )
    }

    private var size: CGSize {
        presentation.isExpanded ? expandedSize : collapsedSize
    }

    private var topCornerRadius: CGFloat {
        presentation.isExpanded ? CornerRadii.expanded.top : CornerRadii.collapsed.top
    }

    private var bottomCornerRadius: CGFloat {
        presentation.isExpanded ? CornerRadii.expanded.bottom : CornerRadii.collapsed.bottom
    }

    private var expandSpring: Animation { .spring(response: 0.5, dampingFraction: 0.78) }
    private var collapseSpring: Animation { .spring(response: 0.36, dampingFraction: 0.88) }
    private var expandedContentTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity.animation(.easeOut(duration: 0.16).delay(0.18)),
            removal: .scale(scale: 0.94, anchor: .top)
                .combined(with: .opacity)
                .animation(.easeIn(duration: 0.1))
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            island
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea()
#if DEBUG
        .enableInjection()
#endif
    }

    private var island: some View {
        let shape = NotchShape(topCornerRadius: topCornerRadius, bottomCornerRadius: bottomCornerRadius)

        return ZStack {
            if presentation.isExpanded {
                expandedContent
                    .padding(.horizontal, CornerRadii.expanded.top)
                    .padding(.bottom, 12)
                    .transition(expandedContentTransition)
            } else {
                collapsedContent
                    .padding(.horizontal, CornerRadii.collapsed.bottom)
                    .transition(.opacity.animation(.easeOut(duration: 0.08)))
            }
        }
        .frame(width: size.width, height: size.height)
        .background(.black, in: shape)
        .shadow(
            color: .black.opacity(presentation.isExpanded ? 0.55 : 0.28),
            radius: presentation.isExpanded ? 18 : (isHovering ? 10 : 8),
            y: presentation.isExpanded ? 10 : (isHovering ? 5 : 4)
        )
        .contentShape(shape)
        .offset(y: isHovering && !presentation.isExpanded ? 2 : 0)
        .onHover { isHovering in
            if isHovering, !presentation.isExpanded {
                performHoverHaptic()
            }

            withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                self.isHovering = isHovering
            }
        }
        .onTapGesture {
            withAnimation(presentation.isExpanded ? collapseSpring : expandSpring) {
                presentation.isExpanded.toggle()
            }
        }
        .animation(presentation.isExpanded ? expandSpring : collapseSpring, value: presentation.isExpanded)
    }

    private func performHoverHaptic() {
        let now = Date()
        guard now.timeIntervalSince(lastHoverHapticAt) > 0.8 else { return }

        lastHoverHapticAt = now
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    private var collapsedContent: some View {
        HStack(spacing: 6) {
            BrandSpark(state: selectedSession?.state ?? .idle)

            Spacer(minLength: 0)

            if !store.sessions.isEmpty {
                Text("\(store.sessions.count)")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(.white.opacity(0.7))
                    .monospacedDigit()
            }
        }
    }

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            topStrip
            sessionList
        }
    }

    private var topStrip: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.mint)

            Text("Vibenion")
                .font(.system(size: 13, weight: .semibold))

            Text("\(store.sessions.count)")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.mint)

            Text("sessions")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                withAnimation(.spring(response: 0.36, dampingFraction: 0.88)) {
                    presentation.isExpanded = false
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(width: 22, height: 22)
                    .background(.white.opacity(0.08), in: Circle())
            }
            .buttonStyle(.plain)
            .help("Collapse")
        }
        .foregroundStyle(.white)
        .padding(.top, 4)
    }

    @ViewBuilder
    private var sessionList: some View {
        if store.sessions.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(store.sessions) { session in
                        Button {
                            selectedID = session.id
                        } label: {
                            SessionRow(
                                session: session,
                                isSelected: selectedSession?.id == session.id
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.never)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "terminal")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.secondary)
            Text("No Claude sessions")
                .font(.system(size: 14, weight: .semibold))
            Text("Start Claude Code and Vibenion will pick it up.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(.white)
    }

}

private struct SessionRow: View {
    let session: AgentSession
    let isSelected: Bool
#if DEBUG
    @ObserveInjection var inject
#endif

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            StatusDot(state: session.state)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(session.title)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    StateBadge(state: session.state)

                    AgentBadge(agent: session.agent)

                    Text(session.elapsed)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }

                Text(session.summary)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)

                contextLine
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(isSelected ? .white.opacity(0.08) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
#if DEBUG
        .enableInjection()
#endif
    }

    private var contextLine: some View {
        HStack(spacing: 6) {
            if let branch = session.branch {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 9, weight: .semibold))
                Text(branch)
                    .lineLimit(1)
            }

            if let cwd = session.cwd {
                Text(cwd)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.secondary)
    }
}

private struct AgentBadge: View {
    let agent: AgentKind
#if DEBUG
    @ObserveInjection var inject
#endif

    var body: some View {
        HStack(spacing: 4) {
            Text(mark)
                .font(.system(size: 9, weight: .black))
                .baselineOffset(0.5)

            Text(agent.rawValue)
                .font(.system(size: 10, weight: .bold))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(color.opacity(0.22))
        .foregroundStyle(color)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
#if DEBUG
        .enableInjection()
#endif
    }

    private var mark: String {
        switch agent {
        case .claude: "✶"
        case .codex: "⌘"
        case .gemini: "✦"
        case .cursor: "›"
        case .unknown: "•"
        }
    }

    private var color: Color {
        switch agent {
        case .claude: Color(red: 0.82, green: 0.42, blue: 0.26)
        case .codex: .mint
        case .gemini: .purple
        case .cursor: .blue
        case .unknown: .secondary
        }
    }
}

private struct StateBadge: View {
    let state: SessionState
#if DEBUG
    @ObserveInjection var inject
#endif

    var body: some View {
        Text(state.rawValue.uppercased())
            .font(.system(size: 9, weight: .black))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(color.opacity(0.18))
            .foregroundStyle(color)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
#if DEBUG
            .enableInjection()
#endif
    }

    private var color: Color {
        switch state {
        case .running: .mint
        case .idle: .secondary
        case .stale: .purple
        case .needsApproval: .orange
        case .question: .yellow
        case .done: .green
        case .error: .red
        }
    }
}

private struct BrandSpark: View {
    let state: SessionState

    @State private var pulse = false
#if DEBUG
    @ObserveInjection var inject
#endif

    var body: some View {
        Image(systemName: "sparkles")
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(color)
            .symbolEffect(.variableColor.iterative.reversing, options: .repeating, isActive: shouldPulse)
            .opacity(pulse ? 1.0 : 0.92)
            .onAppear {
                if shouldPulse {
                    withAnimation(.easeInOut(duration: 1.0).repeatForever()) {
                        pulse = true
                    }
                }
            }
#if DEBUG
            .enableInjection()
#endif
    }

    private var shouldPulse: Bool {
        switch state {
        case .running, .needsApproval, .question: true
        default: false
        }
    }

    private var color: Color {
        switch state {
        case .running: .mint
        case .idle: Color.white.opacity(0.5)
        case .stale: .purple
        case .needsApproval: .orange
        case .question: .yellow
        case .done: .green
        case .error: .red
        }
    }
}

private struct StatusDot: View {
    let state: SessionState

    @State private var pulsing = false
#if DEBUG
    @ObserveInjection var inject
#endif

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .overlay(
                Circle()
                    .stroke(color.opacity(0.45), lineWidth: 2)
                    .scaleEffect(pulsing ? 2.0 : 1.0)
                    .opacity(pulsing ? 0 : 0.8)
            )
            .onAppear {
                if shouldPulse {
                    withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) {
                        pulsing = true
                    }
                }
            }
#if DEBUG
            .enableInjection()
#endif
    }

    private var shouldPulse: Bool {
        switch state {
        case .running, .needsApproval, .question: true
        default: false
        }
    }

    private var color: Color {
        switch state {
        case .running: .mint
        case .idle: .gray
        case .stale: .purple
        case .needsApproval: .orange
        case .question: .yellow
        case .done: .green
        case .error: .red
        }
    }
}

#if DEBUG
#Preview("Island expanded") {
    let presentation = IslandPresentation()
    presentation.isExpanded = true

    return IslandRootView(
        store: .preview(),
        presentation: presentation,
        notch: .fallback
    )
    .frame(width: 600, height: 420)
    .background(.black)
}

#Preview("Island collapsed") {
    IslandRootView(
        store: .preview(),
        presentation: IslandPresentation(),
        notch: .fallback
    )
    .frame(width: 600, height: 120)
    .background(.black)
}
#endif
