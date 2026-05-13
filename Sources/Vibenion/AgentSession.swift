import Foundation

enum AgentKind: String, CaseIterable, Identifiable, Sendable {
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

enum SessionState: String, Sendable {
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

struct AgentSession: Identifiable, Equatable, Sendable {
    let id: String
    var title: String
    var agent: AgentKind
    var terminal: String
    var terminalTarget: TerminalTarget?
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

private struct CmuxLocationIndex: Sendable {
    private let byPID: [Int: CmuxAgentLocation]
    private let claudeLocations: [CmuxAgentLocation]
    private let codexLocations: [CmuxAgentLocation]

    init(locations: [CmuxAgentLocation]) {
        var byPID: [Int: CmuxAgentLocation] = [:]
        for location in locations where location.rootPID > 0 {
            byPID[location.rootPID] = location
        }
        self.byPID = byPID
        self.claudeLocations = locations.filter { $0.agent == .claude }
        self.codexLocations = locations.filter { $0.agent == .codex }
    }

    func locateClaude(pid: Int?) -> CmuxAgentLocation? {
        guard let pid, let location = byPID[pid], location.agent == .claude else {
            return nil
        }
        return location
    }

    func locateCodex() -> CmuxAgentLocation? {
        codexLocations.count == 1 ? codexLocations.first : nil
    }
}

private struct DiscoveredAgentSessions: Sendable {
    let claude: [ClaudeDiscoveredSession]
    let codex: [CodexDiscoveredSession]
    let cmuxLocations: [CmuxAgentLocation]
}

@MainActor
final class AgentSessionStore: ObservableObject {
    @Published var sessions: [AgentSession] = []

    private let eventLog: AgentEventLog
    private let claudeDiscovery: ClaudeSessionDiscovery
    private let codexDiscovery: CodexSessionDiscovery
    private let cmuxDiscovery: CmuxSessionDiscovery
    private var refreshTask: Task<Void, Never>?
    private var latestEventOffset = 0
    private var isRefreshingDiscoveredSessions = false

    init(
        eventLog: AgentEventLog = .default,
        claudeDiscovery: ClaudeSessionDiscovery = .default,
        codexDiscovery: CodexSessionDiscovery = .default,
        cmuxDiscovery: CmuxSessionDiscovery = .default
    ) {
        self.eventLog = eventLog
        self.claudeDiscovery = claudeDiscovery
        self.codexDiscovery = codexDiscovery
        self.cmuxDiscovery = cmuxDiscovery
        loadNewEvents()
        refreshTask = Task { [weak self] in
            await self?.refreshDiscoveredSessions()

            var ticksUntilDiscoveryRefresh = 5
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                self?.loadNewEvents()

                ticksUntilDiscoveryRefresh -= 1
                if ticksUntilDiscoveryRefresh <= 0 {
                    ticksUntilDiscoveryRefresh = 5
                    await self?.refreshDiscoveredSessions()
                }
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

    private func refreshDiscoveredSessions() async {
        guard !isRefreshingDiscoveredSessions else { return }
        isRefreshingDiscoveredSessions = true
        defer { isRefreshingDiscoveredSessions = false }

        let claudeDiscovery = claudeDiscovery
        let codexDiscovery = codexDiscovery
        let cmuxDiscovery = cmuxDiscovery
        let discovered = await Task.detached(priority: .utility) {
            DiscoveredAgentSessions(
                claude: claudeDiscovery.discover(),
                codex: codexDiscovery.discover(),
                cmuxLocations: cmuxDiscovery.discover()
            )
        }.value

        loadDiscoveredSessions(discovered)
    }

    private func loadDiscoveredSessions(_ discovered: DiscoveredAgentSessions) {
        let cmuxIndex = CmuxLocationIndex(locations: discovered.cmuxLocations)
        let claudeSessions = discovered.claude.map { makeSession(from: $0, cmuxIndex: cmuxIndex) }
        let codexSessions = discovered.codex.map { makeSession(from: $0, cmuxIndex: cmuxIndex) }
        let discoveredSessions = claudeSessions + codexSessions
        let discoveredIDs = Set(discoveredSessions.map(\.id))
        let manualSessions = sessions.filter { !discoveredIDs.contains($0.id) }
        sessions = sortSessions(discoveredSessions + manualSessions)
    }

    private func makeSession(
        from discovered: ClaudeDiscoveredSession,
        cmuxIndex: CmuxLocationIndex
    ) -> AgentSession {
        let metadata = discovered.metadata
        let state = mapClaudeState(metadata: metadata, isProcessAlive: discovered.isProcessAlive)
        let title = metadata.name ?? discovered.repo.name
        let branch = discovered.repo.branch
        let summaryParts = [
            state == .done ? "Claude session" : "Claude Code \(metadata.status)",
            branch.map { "on \($0)" },
            discovered.messageCount.map { "\($0) messages" },
            metadata.version.map { "v\($0)" },
        ].compactMap(\.self)
        let pidEvent = metadata.pid.map { "pid: \($0)" }
        let cmuxLocation = cmuxIndex.locateClaude(pid: metadata.pid)
        let terminalTarget = cmuxLocation.map(makeCmuxTerminalTarget)
        let terminal = terminalTarget?.displayName ?? "Claude Code"

        return AgentSession(
            id: metadata.sessionID,
            title: title,
            agent: .claude,
            terminal: terminal,
            terminalTarget: terminalTarget,
            elapsed: relativeTime(from: metadata.updatedAt ?? metadata.startedAt),
            state: state,
            summary: summaryParts.joined(separator: " · "),
            events: [
                "cwd: \(metadata.cwd)",
                pidEvent,
            ].compactMap(\.self),
            cwd: metadata.cwd,
            branch: branch
        )
    }

    private func makeSession(
        from discovered: CodexDiscoveredSession,
        cmuxIndex: CmuxLocationIndex
    ) -> AgentSession {
        let cmuxLocation = cmuxIndex.locateCodex()
        let terminalTarget = cmuxLocation.map(makeCmuxTerminalTarget) ?? TerminalTarget(
            appName: "Codex",
            bundleID: "com.openai.codex",
            processID: nil,
            windowID: nil,
            windowTitle: nil,
            tabTitle: nil,
            workspaceID: nil,
            surfaceID: nil,
            socketPath: nil,
            threadID: discovered.id
        )

        return AgentSession(
            id: discovered.id,
            title: discovered.title,
            agent: .codex,
            terminal: terminalTarget.displayName,
            terminalTarget: terminalTarget,
            elapsed: relativeTime(from: discovered.updatedAt),
            state: .idle,
            summary: "Codex session",
            events: [],
            cwd: nil,
            branch: nil
        )
    }

    private func makeCmuxTerminalTarget(_ location: CmuxAgentLocation) -> TerminalTarget {
        TerminalTarget(
            appName: "cmux",
            bundleID: "com.cmuxterm.app",
            processID: Int32(location.rootPID),
            windowID: nil,
            windowTitle: nil,
            tabTitle: location.title,
            workspaceID: location.workspaceUUID.isEmpty ? nil : location.workspaceUUID,
            surfaceID: location.surfaceUUID.isEmpty ? nil : location.surfaceUUID,
            socketPath: nil,
            threadID: nil
        )
    }

    private func mapClaudeState(
        metadata: ClaudeSessionMetadata,
        isProcessAlive: Bool?
    ) -> SessionState {
        guard isProcessAlive ?? false else { return .done }

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
        return relativeTime(fromSeconds: seconds)
    }

    private func relativeTime(from date: Date) -> String {
        relativeTime(fromSeconds: max(0, Int(Date().timeIntervalSince(date))))
    }

    private func relativeTime(fromSeconds seconds: Int) -> String {
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
            sessions[index].terminalTarget = event.terminalTarget ?? sessions[index].terminalTarget
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
                    terminalTarget: event.terminalTarget,
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

#if DEBUG
@MainActor
extension AgentSessionStore {
    static func preview(sessions: [AgentSession] = AgentSession.previewSessions) -> AgentSessionStore {
        let store = AgentSessionStore()
        store.refreshTask?.cancel()
        store.sessions = sessions
        return store
    }
}

extension AgentSession {
    static let previewSessions = [
        AgentSession(
            id: "preview-codex",
            title: "codex/hot-reload",
            agent: .codex,
            terminal: "Codex",
            terminalTarget: nil,
            elapsed: "4m",
            state: .running,
            summary: "Wiring SwiftUI preview flow",
            events: ["Read package manifest", "Added preview fixture"],
            cwd: "/Users/youhaowei/Projects/vibenion",
            branch: "codex/hot-reload"
        ),
        AgentSession(
            id: "preview-claude",
            title: "Claude UI pass",
            agent: .claude,
            terminal: "Claude Code",
            terminalTarget: nil,
            elapsed: "12m",
            state: .needsApproval,
            summary: "Waiting for approval on panel placement",
            events: ["Generated island shape", "Needs approval"],
            cwd: "/Users/youhaowei/Projects/vibenion",
            branch: "main"
        ),
        AgentSession(
            id: "preview-done",
            title: "Settings cleanup",
            agent: .cursor,
            terminal: "Cursor",
            terminalTarget: nil,
            elapsed: "1h",
            state: .done,
            summary: "Finished small settings copy pass",
            events: ["Updated toggles", "Verified build"],
            cwd: "/Users/youhaowei/Projects/vibenion",
            branch: nil
        ),
    ]
}
#endif
