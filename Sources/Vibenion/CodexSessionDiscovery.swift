import Foundation

struct CodexDiscoveredSession: Sendable {
    let id: String
    let title: String
    let preview: String?
    let updatedAt: Date
    let cwd: String?
    let branch: String?
    let path: String?
    let statusType: String?       // notLoaded, idle, active, systemError — nil when not from app-server
    let activeFlags: [String]?    // waitingOnUserInput, waitingOnApproval, etc.
    let isLoaded: Bool            // true if id appeared in thread/loaded/list
}

struct CodexSessionDiscovery: Sendable {
    private static let maxSessions = 50
    private static let recencyLimit: TimeInterval = 24 * 60 * 60

    static let `default` = CodexSessionDiscovery(
        sessionIndexURL: FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/session_index.jsonl"),
        appServerClient: .shared
    )

    let sessionIndexURL: URL
    let appServerClient: CodexAppServerClient?

    init(sessionIndexURL: URL, appServerClient: CodexAppServerClient? = .shared) {
        self.sessionIndexURL = sessionIndexURL
        self.appServerClient = appServerClient
    }

    func discover() -> [CodexDiscoveredSession] {
        if let appServerClient, let threads = appServerClient.listThreads(limit: Self.maxSessions) {
            let loadedSet = Set(appServerClient.listLoaded() ?? [])
            return threads.compactMap { mapThread($0, loaded: loadedSet) }
                .filter(isRecent)
                .sorted { $0.updatedAt > $1.updatedAt }
        }

        // Fallback: session_index.jsonl
        return readFallbackIndex()
    }

    private func mapThread(_ thread: CodexThread, loaded: Set<String>) -> CodexDiscoveredSession? {
        let updatedAt = thread.updatedAt.map { Date(timeIntervalSince1970: $0) }
            ?? thread.createdAt.map { Date(timeIntervalSince1970: $0) }
        guard let updatedAt else { return nil }

        return CodexDiscoveredSession(
            id: thread.id,
            title: thread.name ?? "Codex session",
            preview: thread.preview,
            updatedAt: updatedAt,
            cwd: thread.cwd,
            branch: thread.gitInfo?.branch,
            path: thread.path,
            statusType: thread.status?.type,
            activeFlags: thread.status?.activeFlags,
            isLoaded: loaded.contains(thread.id)
        )
    }

    private func isRecent(_ session: CodexDiscoveredSession) -> Bool {
        Date().timeIntervalSince(session.updatedAt) <= Self.recencyLimit
    }

    private func readFallbackIndex() -> [CodexDiscoveredSession] {
        guard let data = try? Data(contentsOf: sessionIndexURL) else { return [] }

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
            preview: nil,
            updatedAt: updatedAt,
            cwd: nil,
            branch: nil,
            path: nil,
            statusType: nil,
            activeFlags: nil,
            isLoaded: false
        )
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
