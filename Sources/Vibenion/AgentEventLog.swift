import Foundation

struct AgentEvent: Decodable {
    let sessionID: String
    let agent: String
    let state: String
    let summary: String
    let title: String?
    let terminal: String?
    let terminalTarget: TerminalTarget?
    let elapsed: String?
    let message: String?

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case agent
        case state
        case summary
        case title
        case terminal
        case terminalTarget = "terminal_metadata"
        case elapsed
        case message
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sessionID = try container.decode(String.self, forKey: .sessionID)
        agent = try container.decode(String.self, forKey: .agent)
        state = try container.decode(String.self, forKey: .state)
        summary = try container.decode(String.self, forKey: .summary)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        elapsed = try container.decodeIfPresent(String.self, forKey: .elapsed)
        message = try container.decodeIfPresent(String.self, forKey: .message)

        if let label = try? container.decodeIfPresent(String.self, forKey: .terminal) {
            terminal = label
            if var target = try container.decodeIfPresent(TerminalTarget.self, forKey: .terminalTarget) {
                target.appName = target.appName ?? label
                terminalTarget = target
            } else {
                terminalTarget = nil
            }
        } else if let target = try? container.decodeIfPresent(TerminalTarget.self, forKey: .terminal) {
            terminal = target.displayName
            terminalTarget = target
        } else {
            terminal = nil
            terminalTarget = try container.decodeIfPresent(TerminalTarget.self, forKey: .terminalTarget)
        }
    }
}

struct AgentEventReadResult {
    let events: [AgentEvent]
    let nextOffset: Int
}

struct AgentEventLog {
    static let `default` = AgentEventLog(
        url: FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".vibenion/events.jsonl")
    )

    let url: URL

    func readEvents(after offset: Int) -> AgentEventReadResult {
        guard let data = try? Data(contentsOf: url), data.count >= offset else {
            return AgentEventReadResult(events: [], nextOffset: 0)
        }

        let unread = data.dropFirst(offset)
        guard let text = String(data: unread, encoding: .utf8) else {
            return AgentEventReadResult(events: [], nextOffset: data.count)
        }

        let decoder = JSONDecoder()
        let events = text
            .split(separator: "\n")
            .compactMap { line in
                try? decoder.decode(AgentEvent.self, from: Data(line.utf8))
            }

        return AgentEventReadResult(events: events, nextOffset: data.count)
    }
}
