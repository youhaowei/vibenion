import Foundation

struct ClaudeSessionMetadata: Decodable {
    let pid: Int
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

struct RepoContext: Equatable {
    let root: String
    let name: String
    let branch: String?
}

struct ClaudeDiscoveredSession {
    let metadata: ClaudeSessionMetadata
    let repo: RepoContext
    let isProcessAlive: Bool
}

struct ClaudeSessionDiscovery: Sendable {
    static let `default` = ClaudeSessionDiscovery(
        sessionsDirectory: FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/sessions")
    )

    let sessionsDirectory: URL
    func discover() -> [ClaudeDiscoveredSession] {
        let fileURLs = (try? FileManager.default.contentsOfDirectory(
            at: sessionsDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        return fileURLs
            .filter { $0.pathExtension == "json" }
            .compactMap(readSession)
            .sorted { lhs, rhs in
                (lhs.metadata.updatedAt ?? lhs.metadata.startedAt ?? 0)
                    > (rhs.metadata.updatedAt ?? rhs.metadata.startedAt ?? 0)
            }
    }

    private func readSession(from url: URL) -> ClaudeDiscoveredSession? {
        guard
            let data = try? Data(contentsOf: url),
            let metadata = try? JSONDecoder().decode(ClaudeSessionMetadata.self, from: data)
        else {
            return nil
        }

        return ClaudeDiscoveredSession(
            metadata: metadata,
            repo: resolveRepoContext(cwd: metadata.cwd),
            isProcessAlive: isProcessAlive(pid: metadata.pid)
        )
    }

    private func resolveRepoContext(cwd: String) -> RepoContext {
        let root = runGit(cwd: cwd, arguments: ["rev-parse", "--show-toplevel"]) ?? cwd
        let branch = runGit(cwd: cwd, arguments: ["branch", "--show-current"])
        let name = URL(fileURLWithPath: root).lastPathComponent
        return RepoContext(root: root, name: name.isEmpty ? cwd : name, branch: branch)
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
