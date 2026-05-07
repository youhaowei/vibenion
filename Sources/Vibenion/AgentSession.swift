import Foundation

enum AgentKind: String, CaseIterable, Identifiable {
    case codex = "Codex"
    case claude = "Claude"
    case gemini = "Gemini"
    case cursor = "Cursor"
    case unknown = "Agent"

    var id: String { rawValue }

    init(eventValue: String) {
        switch eventValue.lowercased() {
        case "codex": self = .codex
        case "claude", "claude-code": self = .claude
        case "gemini": self = .gemini
        case "cursor": self = .cursor
        default: self = .unknown
        }
    }
}

enum SessionState: String {
    case running = "Running"
    case idle = "Idle"
    case stale = "Stale"
    case needsApproval = "Needs approval"
    case question = "Question"
    case done = "Done"
    case error = "Error"

    init(eventValue: String) {
        switch eventValue.lowercased() {
        case "approval", "needs_approval", "needs-approval": self = .needsApproval
        case "question", "ask": self = .question
        case "done", "complete", "completed": self = .done
        case "idle": self = .idle
        case "stale": self = .stale
        case "error", "failed", "blocked": self = .error
        default: self = .running
        }
    }
}

struct AgentSession: Identifiable, Equatable {
    let id: String
    var title: String
    var agent: AgentKind
    var terminal: String
    var elapsed: String
    var state: SessionState
    var summary: String
    var events: [String]
    var cwd: String?
    var branch: String?

    var needsHuman: Bool {
        state == .needsApproval || state == .question || state == .error
    }
}

@MainActor
final class AgentSessionStore: ObservableObject {
    @Published var sessions: [AgentSession] = []

    private let eventLog: AgentEventLog
    private let claudeDiscovery: ClaudeSessionDiscovery
    private var refreshTask: Task<Void, Never>?
    private var latestEventOffset = 0

    init(
        eventLog: AgentEventLog = .default,
        claudeDiscovery: ClaudeSessionDiscovery = .default
    ) {
        self.eventLog = eventLog
        self.claudeDiscovery = claudeDiscovery
        refresh()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                self?.refresh()
            }
        }
    }

    deinit {
        refreshTask?.cancel()
    }

    var activeSession: AgentSession? {
        sessions.first(where: \.needsHuman) ?? sessions.first
    }

    func allow(_ session: AgentSession) {
        update(session) { item in
            item.state = .running
            item.summary = "Approved. Continuing work."
            item.events.append("Approved from Vibenion")
        }
    }

    func deny(_ session: AgentSession) {
        update(session) { item in
            item.state = .done
            item.summary = "Denied. Agent stopped safely."
            item.events.append("Denied from Vibenion")
        }
    }

    func answer(_ session: AgentSession, option: String) {
        update(session) { item in
            item.state = .running
            item.summary = "Answered: \(option)"
            item.events.append("Selected \(option)")
        }
    }

    private func update(_ session: AgentSession, mutate: (inout AgentSession) -> Void) {
        guard let index = sessions.firstIndex(where: { $0.id == session.id }) else { return }
        mutate(&sessions[index])
    }

    private func refresh() {
        loadClaudeSessions()
        loadNewEvents()
    }

    private func loadClaudeSessions() {
        let discovered = claudeDiscovery.discover().map(makeSession)
        let discoveredIDs = Set(discovered.map(\.id))
        let manualSessions = sessions.filter { !discoveredIDs.contains($0.id) }
        sessions = sortSessions(discovered + manualSessions)
    }

    private func makeSession(from discovered: ClaudeDiscoveredSession) -> AgentSession {
        let metadata = discovered.metadata
        let state = mapClaudeState(metadata: metadata, isProcessAlive: discovered.isProcessAlive)
        let title = metadata.name ?? discovered.repo.name
        let branch = discovered.repo.branch
        let summaryParts = [
            state == .done ? "Claude process is no longer running" : "Claude Code \(metadata.status)",
            branch.map { "on \($0)" },
            metadata.version.map { "v\($0)" },
        ].compactMap(\.self)

        return AgentSession(
            id: metadata.sessionID,
            title: title,
            agent: .claude,
            terminal: "Claude Code",
            elapsed: relativeTime(from: metadata.updatedAt ?? metadata.startedAt),
            state: state,
            summary: summaryParts.joined(separator: " · "),
            events: [
                "cwd: \(metadata.cwd)",
                "pid: \(metadata.pid)",
            ],
            cwd: metadata.cwd,
            branch: branch
        )
    }

    private func mapClaudeState(
        metadata: ClaudeSessionMetadata,
        isProcessAlive: Bool
    ) -> SessionState {
        guard isProcessAlive else { return .done }

        let ageSeconds = Date().timeIntervalSince1970 - ((metadata.updatedAt ?? 0) / 1000)
        if metadata.status == "busy", ageSeconds > 15 * 60 {
            return .stale
        }

        switch metadata.status.lowercased() {
        case "busy": return .running
        case "idle": return .idle
        default: return .running
        }
    }

    private func relativeTime(from milliseconds: Double?) -> String {
        guard let milliseconds else { return "now" }
        let seconds = max(0, Int(Date().timeIntervalSince1970 - (milliseconds / 1000)))

        if seconds < 60 {
            return "<1m"
        }
        if seconds < 60 * 60 {
            return "\(seconds / 60)m"
        }
        return "\(seconds / 3600)h"
    }

    private func sortSessions(_ sessions: [AgentSession]) -> [AgentSession] {
        let priority: [SessionState: Int] = [
            .needsApproval: 0,
            .question: 0,
            .error: 1,
            .running: 2,
            .stale: 3,
            .done: 4,
            .idle: 5,
        ]

        return sessions.sorted {
            (priority[$0.state] ?? 9, $0.title) < (priority[$1.state] ?? 9, $1.title)
        }
    }

    private func loadNewEvents() {
        let result = eventLog.readEvents(after: latestEventOffset)
        latestEventOffset = result.nextOffset

        for event in result.events {
            apply(event)
        }
    }

    private func apply(_ event: AgentEvent) {
        let state = SessionState(eventValue: event.state)
        let agent = AgentKind(eventValue: event.agent)
        let eventLine = event.message ?? event.summary

        if let index = sessions.firstIndex(where: { $0.id == event.sessionID }) {
            sessions[index].title = event.title ?? sessions[index].title
            sessions[index].agent = agent
            sessions[index].terminal = event.terminal ?? sessions[index].terminal
            sessions[index].elapsed = event.elapsed ?? sessions[index].elapsed
            sessions[index].state = state
            sessions[index].summary = event.summary
            sessions[index].events.append(eventLine)
        } else {
            sessions.insert(
                AgentSession(
                    id: event.sessionID,
                    title: event.title ?? event.sessionID,
                    agent: agent,
                    terminal: event.terminal ?? "Terminal",
                    elapsed: event.elapsed ?? "now",
                    state: state,
                    summary: event.summary,
                    events: [eventLine],
                    cwd: nil,
                    branch: nil
                ),
                at: 0
            )
        }

        sessions = sortSessions(sessions)
    }
}
