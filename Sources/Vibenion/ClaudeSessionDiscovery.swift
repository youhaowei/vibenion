import Foundation

struct ClaudeSessionMetadata: Decodable, Sendable {
    let pid: Int?
    let sessionID: String
    let cwd: String
    let startedAt: Double?
    let status: String
    let updatedAt: Double?
    let name: String?
    let version: String?

    enum CodingKeys: String, CodingKey {
        case pid
        case sessionID = "sessionId"
        case cwd
        case startedAt
        case status
        case updatedAt
        case name
        case version
    }
}

struct RepoContext: Equatable, Sendable {
    let root: String
    let name: String
    let branch: String?
}

struct ClaudeDiscoveredSession: Sendable {
    let metadata: ClaudeSessionMetadata
    let repo: RepoContext
    let isProcessAlive: Bool?
    let messageCount: Int?
    let transcriptModifiedAt: Date?
}

struct ClaudeSessionDiscovery: Sendable {
    private static let maxIndexedSessions = 20
    private static let indexedSessionRecencyLimit: TimeInterval = 24 * 60 * 60

    static let `default` = ClaudeSessionDiscovery(
        sessionsDirectory: FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/sessions"),
        projectsDirectory: FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects")
    )

    let sessionsDirectory: URL
    let projectsDirectory: URL

    init(sessionsDirectory: URL, projectsDirectory: URL) {
        self.sessionsDirectory = sessionsDirectory
        self.projectsDirectory = projectsDirectory
    }

    func discover() -> [ClaudeDiscoveredSession] {
        var sessionsByID: [String: ClaudeDiscoveredSession] = [:]
        for session in readIndexedSessions() {
            sessionsByID[session.metadata.sessionID] = session
        }

        for session in readActiveSessions() {
            sessionsByID[session.metadata.sessionID] = session
        }

        return Array(sessionsByID.values)
            .sorted { lhs, rhs in
                (lhs.metadata.updatedAt ?? lhs.metadata.startedAt ?? 0)
                    > (rhs.metadata.updatedAt ?? rhs.metadata.startedAt ?? 0)
            }
    }

    private func readActiveSessions() -> [ClaudeDiscoveredSession] {
        let fileURLs = (try? FileManager.default.contentsOfDirectory(
            at: sessionsDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        return fileURLs
            .filter { $0.pathExtension == "json" }
            .compactMap(readActiveSession)
    }

    private func readIndexedSessions() -> [ClaudeDiscoveredSession] {
        let indexURLs = findSessionIndexes(in: projectsDirectory)
        return indexURLs
            .flatMap(readSessionIndex)
            .filter(isRecentIndexedSession)
            .sorted { lhs, rhs in
                (lhs.metadata.updatedAt ?? lhs.metadata.startedAt ?? 0)
                    > (rhs.metadata.updatedAt ?? rhs.metadata.startedAt ?? 0)
            }
            .prefix(Self.maxIndexedSessions)
            .map(\.self)
    }

    private func isRecentIndexedSession(_ session: ClaudeDiscoveredSession) -> Bool {
        guard let lastActivity = session.metadata.updatedAt ?? session.metadata.startedAt else {
            return false
        }
        let age = Date().timeIntervalSince1970 - (lastActivity / 1000)
        return age <= Self.indexedSessionRecencyLimit
    }

    private func findSessionIndexes(in directory: URL) -> [URL] {
        guard
            let enumerator = FileManager.default.enumerator(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            )
        else {
            return []
        }

        var urls: [URL] = []
        for case let url as URL in enumerator where url.lastPathComponent == "sessions-index.json" {
            urls.append(url)
        }
        return urls
    }

    private func readSessionIndex(from url: URL) -> [ClaudeDiscoveredSession] {
        guard
            let data = try? Data(contentsOf: url),
            let index = try? JSONDecoder().decode(ClaudeSessionIndex.self, from: data)
        else {
            return []
        }

        return index.entries
            .filter { $0.isSidechain != true }
            .map { entry in
                let metadata = ClaudeSessionMetadata(
                    pid: nil,
                    sessionID: entry.sessionID,
                    cwd: entry.projectPath,
                    startedAt: entry.createdMilliseconds,
                    status: "done",
                    updatedAt: entry.modifiedMilliseconds,
                    name: entry.firstPrompt,
                    version: nil
                )
                return ClaudeDiscoveredSession(
                    metadata: metadata,
                    repo: indexedRepoContext(projectPath: entry.projectPath, branch: entry.gitBranch),
                    isProcessAlive: nil,
                    messageCount: entry.messageCount,
                    transcriptModifiedAt: transcriptModifiedAt(sessionID: entry.sessionID, cwd: entry.projectPath)
                )
            }
    }

    private func readActiveSession(from url: URL) -> ClaudeDiscoveredSession? {
        guard
            let data = try? Data(contentsOf: url),
            let metadata = try? JSONDecoder().decode(ClaudeSessionMetadata.self, from: data)
        else {
            return nil
        }

        return ClaudeDiscoveredSession(
            metadata: metadata,
            repo: resolveRepoContext(cwd: metadata.cwd, indexedBranch: nil),
            isProcessAlive: metadata.pid.map(isProcessAlive),
            messageCount: nil,
            transcriptModifiedAt: transcriptModifiedAt(sessionID: metadata.sessionID, cwd: metadata.cwd)
        )
    }

    private func transcriptModifiedAt(sessionID: String, cwd: String) -> Date? {
        let encoded = cwd.replacingOccurrences(of: "/", with: "-")
        let url = projectsDirectory
            .appendingPathComponent(encoded)
            .appendingPathComponent("\(sessionID).jsonl")
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return attrs?[.modificationDate] as? Date
    }

    private func resolveRepoContext(cwd: String, indexedBranch: String?) -> RepoContext {
        let root = runGit(cwd: cwd, arguments: ["rev-parse", "--show-toplevel"]) ?? cwd
        let branch = runGit(cwd: cwd, arguments: ["branch", "--show-current"]) ?? indexedBranch
        let name = URL(fileURLWithPath: root).lastPathComponent
        return RepoContext(root: root, name: name.isEmpty ? cwd : name, branch: branch)
    }

    private func indexedRepoContext(projectPath: String, branch: String?) -> RepoContext {
        let name = URL(fileURLWithPath: projectPath).lastPathComponent
        return RepoContext(root: projectPath, name: name.isEmpty ? projectPath : name, branch: branch)
    }

    private func runGit(cwd: String, arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", cwd] + arguments

        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let value = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.isEmpty == false ? value : nil
    }

    private func isProcessAlive(pid: Int) -> Bool {
        kill(pid_t(pid), 0) == 0
    }
}

private struct ClaudeSessionIndex: Decodable {
    let entries: [ClaudeSessionIndexEntry]
}

private struct ClaudeSessionIndexEntry: Decodable {
    let sessionID: String
    let firstPrompt: String?
    let messageCount: Int?
    let created: String?
    let modified: String?
    let gitBranch: String?
    let projectPath: String
    let isSidechain: Bool?

    enum CodingKeys: String, CodingKey {
        case sessionID = "sessionId"
        case firstPrompt
        case messageCount
        case created
        case modified
        case gitBranch
        case projectPath
        case isSidechain
    }

    var createdMilliseconds: Double? {
        milliseconds(from: created)
    }

    var modifiedMilliseconds: Double? {
        milliseconds(from: modified)
    }

    private func milliseconds(from value: String?) -> Double? {
        guard
            let value,
            let date = makeDateFormatter(fractionalSeconds: true).date(from: value)
                ?? makeDateFormatter(fractionalSeconds: false).date(from: value)
        else {
            return nil
        }
        return date.timeIntervalSince1970 * 1000
    }

    private func makeDateFormatter(fractionalSeconds: Bool) -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = fractionalSeconds
            ? [.withInternetDateTime, .withFractionalSeconds]
            : [.withInternetDateTime]
        return formatter
    }
}
