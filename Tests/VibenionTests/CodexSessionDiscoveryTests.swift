import Foundation
import Testing
@testable import Vibenion

@Test func discoversRecentCodexSessions() throws {
    let indexURL = try temporaryDirectory().appending(path: "session_index.jsonl")
    let jsonl = """
    {"id":"old","thread_name":"Old work","updated_at":"2026-01-01T00:00:00Z"}
    {"id":"recent","thread_name":"Wire up Codex","updated_at":"2026-05-08T15:47:00.895892Z"}
    """
    try jsonl.write(to: indexURL, atomically: true, encoding: .utf8)

    let discovery = CodexSessionDiscovery(sessionIndexURL: indexURL)
    let discovered = discovery.discover()

    #expect(discovered.count == 1)
    #expect(discovered.first?.id == "recent")
    #expect(discovered.first?.title == "Wire up Codex")
}

@Test func ignoresInvalidCodexIndexLines() throws {
    let indexURL = try temporaryDirectory().appending(path: "session_index.jsonl")
    let jsonl = """
    not json
    {"id":"recent","thread_name":"Valid","updated_at":"2026-05-08T15:47:00Z"}
    """
    try jsonl.write(to: indexURL, atomically: true, encoding: .utf8)

    let discovery = CodexSessionDiscovery(sessionIndexURL: indexURL)

    #expect(discovery.discover().count == 1)
}

private func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appending(path: "VibenionCodexTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
