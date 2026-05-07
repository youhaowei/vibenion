import Foundation

struct AgentEvent: Decodable {
    let sessionID: String
    let agent: String
    let state: String
    let summary: String
    let title: String?
    let terminal: String?
    let elapsed: String?
    let message: String?

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case agent
        case state
        case summary
        case title
        case terminal
        case elapsed
        case message
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
