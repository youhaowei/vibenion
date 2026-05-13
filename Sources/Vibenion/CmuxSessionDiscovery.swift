import Foundation

enum CmuxAgentKind: Sendable {
    case claude
    case codex
}

struct CmuxAgentLocation: Sendable {
    let agent: CmuxAgentKind
    let rootPID: Int
    let surfaceUUID: String
    let workspaceUUID: String
    let surfaceRef: String
    let workspaceRef: String
    let paneRef: String
    let title: String?
}

struct CmuxSessionDiscovery: Sendable {
    static let `default` = CmuxSessionDiscovery(
        executable: URL(fileURLWithPath: "/Applications/cmux.app/Contents/Resources/bin/cmux")
    )

    let executable: URL

    func discover() -> [CmuxAgentLocation] {
        guard FileManager.default.isExecutableFile(atPath: executable.path),
            let data = runTop()
        else {
            return []
        }
        return parse(data)
    }

    private func runTop() -> Data? {
        let process = Process()
        process.executableURL = executable
        process.arguments = ["top", "--all", "--processes", "--json"]

        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return nil
        }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0, !data.isEmpty else { return nil }
        return data
    }

    private func parse(_ data: Data) -> [CmuxAgentLocation] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }
        let windows = (root["windows"] as? [[String: Any]]) ?? []

        var locations: [CmuxAgentLocation] = []
        for window in windows {
            let workspaces = (window["workspaces"] as? [[String: Any]]) ?? []
            for workspace in workspaces {
                let workspaceRef = workspace["ref"] as? String ?? ""
                let panes = (workspace["panes"] as? [[String: Any]]) ?? []
                for pane in panes {
                    let paneRef = pane["ref"] as? String ?? ""
                    let surfaces = (pane["surfaces"] as? [[String: Any]]) ?? []
                    for surface in surfaces {
                        let surfaceRef = surface["ref"] as? String ?? ""
                        let title = surface["title"] as? String
                        let processes = (surface["processes"] as? [[String: Any]]) ?? []
                        guard let match = findAgent(in: processes) else { continue }
                        locations.append(
                            CmuxAgentLocation(
                                agent: match.agent,
                                rootPID: match.pid,
                                surfaceUUID: match.surfaceUUID ?? "",
                                workspaceUUID: match.workspaceUUID ?? "",
                                surfaceRef: surfaceRef,
                                workspaceRef: workspaceRef,
                                paneRef: paneRef,
                                title: title
                            )
                        )
                    }
                }
            }
        }
        return locations
    }

    private struct AgentMatch {
        let agent: CmuxAgentKind
        let pid: Int
        let surfaceUUID: String?
        let workspaceUUID: String?
    }

    private func findAgent(in processes: [[String: Any]]) -> AgentMatch? {
        var best: AgentMatch?
        collectAgents(in: processes, into: &best)
        return best
    }

    private func collectAgents(in processes: [[String: Any]], into best: inout AgentMatch?) {
        for proc in processes {
            if let match = classify(proc) {
                if best == nil || match.pid > (best?.pid ?? 0) {
                    best = match
                }
            }
            if let children = proc["children"] as? [[String: Any]] {
                collectAgents(in: children, into: &best)
            }
        }
    }

    private func classify(_ proc: [String: Any]) -> AgentMatch? {
        let name = (proc["name"] as? String ?? "").lowercased()
        let path = (proc["path"] as? String ?? "").lowercased()
        let pid = proc["pid"] as? Int ?? 0
        let surfaceUUID = proc["cmux_surface_id"] as? String
        let workspaceUUID = proc["cmux_workspace_id"] as? String

        if path.contains("/.local/share/claude/versions/") || name == "claude"
            || path.hasSuffix("/claude")
        {
            return AgentMatch(
                agent: .claude,
                pid: pid,
                surfaceUUID: surfaceUUID,
                workspaceUUID: workspaceUUID
            )
        }

        if name == "codex" || path.hasSuffix("/codex")
            || path.contains("/codex.app/contents/resources/codex")
        {
            return AgentMatch(
                agent: .codex,
                pid: pid,
                surfaceUUID: surfaceUUID,
                workspaceUUID: workspaceUUID
            )
        }

        return nil
    }
}
