import AppKit
import SwiftUI

struct NotchGeometry: Equatable {
    var notchSize: CGSize
    var hasRealNotch: Bool

    static let fallback = NotchGeometry(notchSize: CGSize(width: 156, height: 30), hasRealNotch: false)
}

private enum CornerRadii {
    static let collapsed = (top: CGFloat(6), bottom: CGFloat(14))
    static let expanded = (top: CGFloat(19), bottom: CGFloat(24))
}

private enum IslandLayout {
    static let expandedWidth: CGFloat = 540
    static let expandedHorizontalPadding: CGFloat = 38
    static let expandedMinHeight: CGFloat = 120
    static let expandedMaxHeight: CGFloat = 620
}

struct IslandRootView: View {
    @ObservedObject var store: AgentSessionStore
    @ObservedObject var presentation: IslandPresentation
    var notch: NotchGeometry
    var terminalFocus: TerminalFocusing = TerminalFocusService.shared
    @State private var selectedID: AgentSession.ID?
    @State private var isHovering = false
    @State private var lastHoverHapticAt = Date.distantPast
    @State private var isIdleExpanded = false

    private var selectedSession: AgentSession? {
        if let selectedID, let session = store.sessions.first(where: { $0.id == selectedID }) {
            return session
        }
        return store.activeSession
    }

    /// Side overhang past the physical notch — gives content room and lets the pill
    /// visually thicken when collapsed.
    private var sideWidth: CGFloat {
        if notch.hasRealNotch {
            return max(0, notch.notchSize.height - 12) + 24
        }

        return 14
    }

    private var collapsedSize: CGSize {
        let hoverInset: CGFloat = isHovering ? 4 : 0

        return CGSize(
            width: notch.notchSize.width + sideWidth * 2 + hoverInset * 2,
            height: notch.notchSize.height + hoverInset
        )
    }

    private var expandedWidth: CGFloat {
        IslandLayout.expandedWidth + IslandLayout.expandedHorizontalPadding
    }

    private var width: CGFloat {
        presentation.isExpanded ? expandedWidth : collapsedSize.width
    }

    private var topCornerRadius: CGFloat {
        presentation.isExpanded ? CornerRadii.expanded.top : CornerRadii.collapsed.top
    }

    private var bottomCornerRadius: CGFloat {
        presentation.isExpanded ? CornerRadii.expanded.bottom : CornerRadii.collapsed.bottom
    }

    private var topInset: CGFloat {
        notch.hasRealNotch ? 0 : 8
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
    }

    private var island: some View {
        let shape = NotchShape(
            topCornerRadius: topCornerRadius,
            bottomCornerRadius: bottomCornerRadius,
            blendsIntoTopEdge: notch.hasRealNotch
        )

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
        .frame(width: width)
        .frame(
            minHeight: presentation.isExpanded ? IslandLayout.expandedMinHeight : collapsedSize.height,
            maxHeight: presentation.isExpanded ? IslandLayout.expandedMaxHeight : collapsedSize.height
        )
        .fixedSize(horizontal: false, vertical: true)
        .background(.black, in: shape)
        .shadow(
            color: .black.opacity(presentation.isExpanded ? 0.55 : 0.28),
            radius: presentation.isExpanded ? 18 : (isHovering ? 10 : 8),
            y: presentation.isExpanded ? 10 : (isHovering ? 5 : 4)
        )
        .contentShape(shape)
        .offset(y: topInset)
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

    private var attentionSessions: [AgentSession] {
        store.sessions.filter(\.needsAttention)
    }

    private var collapsedContent: some View {
        HStack(spacing: 6) {
            BrandSpark(state: attentionSessions.first?.state ?? .idle)

            Spacer(minLength: 0)

            if !attentionSessions.isEmpty {
                Text("\(attentionSessions.count)")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(.white.opacity(0.85))
                    .monospacedDigit()
            } else if !store.sessions.isEmpty {
                Text("\(store.sessions.count)")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(.white.opacity(0.35))
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

    private var grouped: (attention: [AgentSession], running: [AgentSession], idleOrDone: [AgentSession]) {
        var attention: [AgentSession] = []
        var running: [AgentSession] = []
        var idleOrDone: [AgentSession] = []
        for session in store.sessions {
            switch session.group {
            case .attention: attention.append(session)
            case .running: running.append(session)
            case .idleOrDone: idleOrDone.append(session)
            }
        }
        let byRecency: (AgentSession, AgentSession) -> Bool = { a, b in
            (a.lastActivityAt ?? .distantPast) > (b.lastActivityAt ?? .distantPast)
        }
        return (
            attention.sorted(by: byRecency),
            running.sorted(by: byRecency),
            idleOrDone.sorted(by: byRecency)
        )
    }

    @ViewBuilder
    private var sessionList: some View {
        if store.sessions.isEmpty {
            emptyState
        } else {
            let g = grouped
            ScrollView {
                LazyVStack(spacing: 2) {
                    if !g.attention.isEmpty {
                        SectionHeader(title: "Needs attention", count: g.attention.count)
                        rows(for: g.attention)
                    }
                    if !g.running.isEmpty {
                        SectionHeader(title: "Running", count: g.running.count)
                        rows(for: g.running)
                    }
                    if !g.idleOrDone.isEmpty {
                        SectionHeader(
                            title: "Idle",
                            count: g.idleOrDone.count,
                            collapsible: true,
                            isExpanded: isIdleExpanded,
                            onToggle: { isIdleExpanded.toggle() }
                        )
                        if isIdleExpanded {
                            rows(for: g.idleOrDone)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.never)
        }
    }

    @ViewBuilder
    private func rows(for sessions: [AgentSession]) -> some View {
        ForEach(sessions) { session in
            let jump = {
                store.acknowledge(session)
                terminalFocus.focusTerminal(for: session)
            }
            SessionRow(
                session: session,
                isSelected: selectedSession?.id == session.id,
                onSelect: { selectedID = session.id },
                onJump: jump
            )
            .simultaneousGesture(TapGesture(count: 2).onEnded(jump))
            .contextMenu {
                Button("Jump to terminal", action: jump)
                Button("Dismiss") { store.acknowledge(session) }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "terminal")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.secondary)
            Text("No active sessions")
                .font(.system(size: 14, weight: .semibold))
            Text("Start a Claude or Codex session and Vibenion will pick it up.")
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
    let onSelect: () -> Void
    let onJump: () -> Void

    private var isAcknowledged: Bool {
        session.needsHuman && !session.needsAttention
    }

    private var rowOpacity: Double {
        if session.isStale { return 0.5 }
        if isAcknowledged { return 0.7 }
        return 1.0
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            StateGlyph(state: session.state, muted: isAcknowledged)
                .frame(width: 18, height: 18)
                .alignmentGuide(.firstTextBaseline) { d in d[VerticalAlignment.center] + 4 }

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(identity)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    Text(stateLine)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(isAcknowledged ? Color.secondary : session.state.tone)
                        .monospacedDigit()

                    AgentGlyph(agent: session.agent)

                    if let target = session.terminalTarget {
                        JumpButton(target: target, action: onJump)
                    }
                }

                if !session.summary.isEmpty {
                    Text(session.summary)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.72))
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .opacity(rowOpacity)
        .background(isSelected ? .white.opacity(0.08) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onTapGesture(perform: onSelect)
    }

    private var identity: String {
        if let path = session.cwd {
            let name = (path as NSString).lastPathComponent
            if !name.isEmpty { return name }
        }
        return session.title
    }

    private var stateLine: String {
        "\(session.state.verb) · \(session.elapsed)"
    }
}

private struct SectionHeader: View {
    let title: String
    let count: Int
    var collapsible: Bool = false
    var isExpanded: Bool = true
    var onToggle: (() -> Void)? = nil

    var body: some View {
        Button(action: { onToggle?() }) {
            HStack(spacing: 6) {
                if collapsible {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .frame(width: 10)
                }
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(0.6)
                Text("\(count)")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(.white.opacity(0.35))
                    .monospacedDigit()
                Spacer()
            }
            .foregroundStyle(.white.opacity(0.55))
            .padding(.horizontal, 10)
            .padding(.top, 10)
            .padding(.bottom, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!collapsible)
    }
}

private struct JumpButton: View {
    let target: TerminalTarget
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(target.displayName)
                    .font(.system(size: 10, weight: .semibold))
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 9, weight: .bold))
            }
            .foregroundStyle(.white.opacity(0.7))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(tooltip)
    }

    private var tooltip: String {
        let where_ = target.tabTitle ?? target.windowTitle
        if let where_, !where_.isEmpty {
            return "Jump to \(target.displayName) · \(where_)"
        }
        return "Jump to \(target.displayName)"
    }
}

private struct AgentGlyph: View {
    let agent: AgentKind

    var body: some View {
        Text(mark)
            .font(.system(size: 11, weight: .black))
            .foregroundStyle(color)
            .frame(width: 12)
            .help(agent.rawValue)
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

private struct StateGlyph: View {
    let state: SessionState
    var muted: Bool = false

    var body: some View {
        Group {
            if state == .working {
                SpinnerGlyph(tint: muted ? .secondary : state.tone)
            } else {
                Image(systemName: state.symbolName)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(muted ? Color.secondary : state.tone)
                    .symbolEffect(.pulse, options: .repeating, isActive: state.shouldPulse && !muted)
            }
        }
        .help(state.verb)
    }
}

private struct SpinnerGlyph: View {
    let tint: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
            let angle = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.0) * 360
            Circle()
                .trim(from: 0, to: 0.28)
                .stroke(tint, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                .frame(width: 14, height: 14)
                .rotationEffect(.degrees(angle))
        }
    }
}

private struct BrandSpark: View {
    let state: SessionState

    var body: some View {
        Image(systemName: "sparkles")
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(color)
            .symbolEffect(.variableColor.iterative.reversing, options: .repeating, isActive: shouldPulse)
    }

    private var shouldPulse: Bool {
        switch state {
        case .working, .asking: true
        default: false
        }
    }

    private var color: Color {
        switch state {
        case .working: .mint
        case .ready: Color(red: 0.46, green: 0.74, blue: 1.0)
        case .idle: Color.white.opacity(0.5)
        case .asking: .orange
        case .done: .green
        }
    }
}

extension SessionState {
    var symbolName: String {
        switch self {
        case .working: "play.fill"
        case .ready: "ellipsis.circle.fill"
        case .idle: "moon.zzz.fill"
        case .asking: "hand.raised.fill"
        case .done: "checkmark.circle.fill"
        }
    }

    var verb: String {
        switch self {
        case .working: "Working"
        case .ready: "Ready"
        case .idle: "Idle"
        case .asking: "Asking"
        case .done: "Done"
        }
    }

    var tone: Color {
        switch self {
        case .working: .mint
        case .ready: Color(red: 0.46, green: 0.74, blue: 1.0)
        case .idle: .gray
        case .asking: .orange
        case .done: .green
        }
    }

    var shouldPulse: Bool {
        false
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
