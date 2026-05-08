import Foundation
import Testing
@testable import Vibenion

@Test func decodesClaudeSessionMetadata() throws {
    let json = """
    {
      "pid": 51920,
      "sessionId": "c5da9633-9ed3-47cd-863e-b4471de9d527",
      "cwd": "/Users/example/Projects/DashFrame",
      "startedAt": 1778180179449,
      "status": "busy",
      "updatedAt": 1778192732258,
      "name": "layout-refactor",
      "version": "2.1.132"
    }
    """

    let metadata = try JSONDecoder().decode(ClaudeSessionMetadata.self, from: Data(json.utf8))

    #expect(metadata.pid == 51920)
    #expect(metadata.sessionID == "c5da9633-9ed3-47cd-863e-b4471de9d527")
    #expect(metadata.status == "busy")
    #expect(metadata.name == "layout-refactor")
}

@Test func discoversClaudeProjectIndexSessions() throws {
    let root = try temporaryDirectory()
    let sessions = root.appending(path: "sessions")
    let projects = root.appending(path: "projects")
    let project = projects.appending(path: "-Users-example-Projects-DashFrame")
    try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)

    let index = """
    {
      "version": 1,
      "entries": [
        {
          "sessionId": "indexed-session",
          "fullPath": "\(project.path)/indexed-session.jsonl",
          "fileMtime": 1778192732258,
          "firstPrompt": "layout refactor",
          "messageCount": 19,
          "created": "2026-05-07T18:56:19.449Z",
          "modified": "2026-05-07T22:25:32.258Z",
          "gitBranch": "main",
          "projectPath": "\(root.path)",
          "isSidechain": false
        }
      ]
    }
    """
    try index.write(to: project.appending(path: "sessions-index.json"), atomically: true, encoding: .utf8)

    let discovery = ClaudeSessionDiscovery(sessionsDirectory: sessions, projectsDirectory: projects)
    let discovered = discovery.discover()

    #expect(discovered.count == 1)
    #expect(discovered.first?.metadata.sessionID == "indexed-session")
    #expect(discovered.first?.metadata.name == "layout refactor")
    #expect(discovered.first?.metadata.cwd == root.path)
    #expect(discovered.first?.messageCount == 19)
    #expect(discovered.first?.isProcessAlive == nil)
}

@Test func activeClaudeSessionOverridesIndexedSession() throws {
    let root = try temporaryDirectory()
    let sessions = root.appending(path: "sessions")
    let projects = root.appending(path: "projects")
    let project = projects.appending(path: "-Users-example-Projects-DashFrame")
    try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)

    let index = """
    {
      "version": 1,
      "entries": [
        {
          "sessionId": "same-session",
          "firstPrompt": "old indexed prompt",
          "messageCount": 4,
          "created": "2026-05-07T18:56:19.449Z",
          "modified": "2026-05-07T22:25:32.258Z",
          "gitBranch": "main",
          "projectPath": "\(root.path)",
          "isSidechain": false
        }
      ]
    }
    """
    let active = """
    {
      "pid": 1,
      "sessionId": "same-session",
      "cwd": "\(root.path)",
      "startedAt": 1778180179449,
      "status": "busy",
      "updatedAt": 1778253440952,
      "version": "2.1.132"
    }
    """
    try index.write(to: project.appending(path: "sessions-index.json"), atomically: true, encoding: .utf8)
    try active.write(to: sessions.appending(path: "1.json"), atomically: true, encoding: .utf8)

    let discovery = ClaudeSessionDiscovery(sessionsDirectory: sessions, projectsDirectory: projects)
    let discovered = discovery.discover()

    #expect(discovered.count == 1)
    #expect(discovered.first?.metadata.status == "busy")
    #expect(discovered.first?.metadata.version == "2.1.132")
    #expect(discovered.first?.messageCount == nil)
}

@Test func ignoresOldIndexedClaudeSessions() throws {
    let root = try temporaryDirectory()
    let sessions = root.appending(path: "sessions")
    let projects = root.appending(path: "projects")
    let project = projects.appending(path: "-Users-example-Projects-old")
    try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)

    let index = """
    {
      "version": 1,
      "entries": [
        {
          "sessionId": "old-session",
          "firstPrompt": "ancient cleanup",
          "messageCount": 4,
          "created": "2026-01-01T00:00:00.000Z",
          "modified": "2026-01-01T00:01:00.000Z",
          "gitBranch": "main",
          "projectPath": "\(root.path)",
          "isSidechain": false
        }
      ]
    }
    """
    try index.write(to: project.appending(path: "sessions-index.json"), atomically: true, encoding: .utf8)

    let discovery = ClaudeSessionDiscovery(sessionsDirectory: sessions, projectsDirectory: projects)

    #expect(discovery.discover().isEmpty)
}

@Test func keepsOldActiveClaudeSessions() throws {
    let root = try temporaryDirectory()
    let sessions = root.appending(path: "sessions")
    let projects = root.appending(path: "projects")
    try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)

    let active = """
    {
      "pid": 1,
      "sessionId": "old-active-session",
      "cwd": "\(root.path)",
      "startedAt": 1767225600000,
      "status": "idle",
      "updatedAt": 1767225660000,
      "version": "2.1.132"
    }
    """
    try active.write(to: sessions.appending(path: "1.json"), atomically: true, encoding: .utf8)

    let discovery = ClaudeSessionDiscovery(sessionsDirectory: sessions, projectsDirectory: projects)

    #expect(discovery.discover().count == 1)
}

private func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appending(path: "VibenionTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
