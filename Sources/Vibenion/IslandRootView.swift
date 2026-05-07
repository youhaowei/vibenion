import AppKit
import SwiftUI

struct IslandRootView: View {
    @ObservedObject var store: AgentSessionStore
    @State private var selectedID: AgentSession.ID?

    private var selectedSession: AgentSession? {
        if let selectedID, let session = store.sessions.first(where: { $0.id == selectedID }) {
            return session
        }
        return store.activeSession
    }

    var body: some View {
        ZStack(alignment: .top) {
            VisualEffectView()
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))

            VStack(spacing: 14) {
                topStrip

                HStack(alignment: .top, spacing: 14) {
                    sessionList
                    detailPanel
                }
            }
            .padding(16)
        }
        .frame(width: 560, height: 360)
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(.white.opacity(0.16), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.28), radius: 28, y: 16)
        .onAppear {
            selectedID = store.activeSession?.id
        }
    }

    private var topStrip: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.mint)

            Text("Vibenion")
                .font(.system(size: 14, weight: .semibold))

            Spacer()

            Text("\(store.sessions.count) sessions")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            Button {
                NSApplication.shared.hide(nil)
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .help("Hide")
        }
        .foregroundStyle(.white)
    }

    private var sessionList: some View {
        VStack(spacing: 8) {
            ForEach(store.sessions) { session in
                Button {
                    selectedID = session.id
                } label: {
                    SessionRow(session: session, isSelected: selectedSession?.id == session.id)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: 210)
    }

    @ViewBuilder
    private var detailPanel: some View {
        if let session = selectedSession {
            SessionDetail(session: session, store: store)
        } else {
            ContentUnavailableView("No sessions", systemImage: "terminal")
                .foregroundStyle(.secondary)
        }
    }
}

private struct SessionRow: View {
    let session: AgentSession
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            StateDot(state: session.state)

            VStack(alignment: .leading, spacing: 3) {
                Text(session.title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)

                Text("\(session.agent.rawValue) · \(session.terminal) · \(session.elapsed)")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if let branch = session.branch {
                    Text(branch)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(isSelected ? .white.opacity(0.14) : .white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .foregroundStyle(.white)
    }
}

private struct SessionDetail: View {
    let session: AgentSession
    @ObservedObject var store: AgentSessionStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.state.rawValue)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(statusColor)

                    Text(session.summary)
                        .font(.system(size: 18, weight: .semibold))
                        .lineLimit(2)
                }

                Spacer()

                Button {
                    jumpToTerminal()
                } label: {
                    Image(systemName: "arrow.up.forward.app")
                        .font(.system(size: 16, weight: .semibold))
                }
                .buttonStyle(.borderless)
                .help("Jump to terminal")
            }

            if session.state == .needsApproval {
                approvalCard
            } else if session.state == .question {
                questionCard
            } else {
                timeline
            }

            Spacer()
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .foregroundStyle(.white)
    }

    private var approvalCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("+ if !token { throw AuthError.missing }\n+ return try verify(token, secret)")
                .font(.system(size: 12, design: .monospaced))
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.black.opacity(0.24))
                .clipShape(RoundedRectangle(cornerRadius: 10))

            HStack {
                Button("Deny") {
                    store.deny(session)
                }
                .keyboardShortcut("n", modifiers: .command)

                Button("Allow") {
                    store.allow(session)
                }
                .keyboardShortcut("y", modifiers: .command)
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var questionCard: some View {
        HStack {
            ForEach(["Production", "Staging", "Local"], id: \.self) { option in
                Button(option) {
                    store.answer(session, option: option)
                }
            }
        }
    }

    private var timeline: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(session.events, id: \.self) { event in
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.mint)
                    Text(event)
                        .font(.system(size: 12))
                }
            }
        }
    }

    private var statusColor: Color {
        switch session.state {
        case .running: .cyan
        case .idle: .secondary
        case .stale: .purple
        case .needsApproval: .orange
        case .question: .yellow
        case .done: .mint
        case .error: .red
        }
    }

    private func jumpToTerminal() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Utilities/Terminal.app"))
    }
}

private struct StateDot: View {
    let state: SessionState

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 9, height: 9)
    }

    private var color: Color {
        switch state {
        case .running: .cyan
        case .idle: .gray
        case .stale: .purple
        case .needsApproval: .orange
        case .question: .yellow
        case .done: .mint
        case .error: .red
        }
    }
}

private struct VisualEffectView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
