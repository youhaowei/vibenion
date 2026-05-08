import Foundation

struct CodexDiscoveredSession: Sendable {
    let id: String
    let title: String
    let updatedAt: Date
}

struct CodexSessionDiscovery: Sendable {
    private static let maxSessions = 20
    private static let recencyLimit: TimeInterval = 24 * 60 * 60

    static let `default` = CodexSessionDiscovery(
        sessionIndexURL: FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/session_index.jsonl")
    )

    let sessionIndexURL: URL

    func discover() -> [CodexDiscoveredSession] {
        guard let data = try? Data(contentsOf: sessionIndexURL) else {
            return []
        }

        return (String(data: data, encoding: .utf8) ?? "")
            .split(separator: "\n")
            .compactMap(readIndexEntry)
            .filter(isRecent)
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(Self.maxSessions)
            .map(\.self)
    }

    private func readIndexEntry(_ line: Substring) -> CodexDiscoveredSession? {
        guard
            let data = String(line).data(using: .utf8),
            let entry = try? JSONDecoder().decode(CodexSessionIndexEntry.self, from: data),
            let updatedAt = entry.updatedAtDate
        else {
            return nil
        }

        return CodexDiscoveredSession(
            id: entry.id,
            title: entry.threadName,
            updatedAt: updatedAt
        )
    }

    private func isRecent(_ session: CodexDiscoveredSession) -> Bool {
        Date().timeIntervalSince(session.updatedAt) <= Self.recencyLimit
    }
}

private struct CodexSessionIndexEntry: Decodable {
    let id: String
    let threadName: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case threadName = "thread_name"
        case updatedAt = "updated_at"
    }

    var updatedAtDate: Date? {
        makeDateFormatter(fractionalSeconds: true).date(from: updatedAt)
            ?? makeDateFormatter(fractionalSeconds: false).date(from: updatedAt)
    }

    private func makeDateFormatter(fractionalSeconds: Bool) -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = fractionalSeconds
            ? [.withInternetDateTime, .withFractionalSeconds]
            : [.withInternetDateTime]
        return formatter
    }
}
