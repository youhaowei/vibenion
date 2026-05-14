import Foundation
import Testing
@testable import Vibenion

@Test func discoversRecentCodexSessions() throws {
    let indexURL = try temporaryDirectory().appending(path: "session_index.jsonl")
    let recent = isoDate(Date())
    let jsonl = """
    {"id":"old","thread_name":"Old work","updated_at":"2026-01-01T00:00:00Z"}
    {"id":"recent","thread_name":"Wire up Codex","updated_at":"\(recent)"}
    """
    try jsonl.write(to: indexURL, atomically: true, encoding: .utf8)

    let discovery = CodexSessionDiscovery(sessionIndexURL: indexURL, appServerClient: nil)
    let discovered = discovery.discover()

    #expect(discovered.count == 1)
    #expect(discovered.first?.id == "recent")
    #expect(discovered.first?.title == "Wire up Codex")
}

@Test func ignoresInvalidCodexIndexLines() throws {
    let indexURL = try temporaryDirectory().appending(path: "session_index.jsonl")
    let recent = isoDate(Date())
    let jsonl = """
    not json
    {"id":"recent","thread_name":"Valid","updated_at":"\(recent)"}
    """
    try jsonl.write(to: indexURL, atomically: true, encoding: .utf8)

    let discovery = CodexSessionDiscovery(sessionIndexURL: indexURL, appServerClient: nil)

    #expect(discovery.discover().count == 1)
}

@Test func activeCodexThreadWithoutWaitFlagsStopsWorkingAfterFreshnessWindow() {
    let now = Date()
    let session = codexSession(
        updatedAt: now.addingTimeInterval(-60),
        statusType: "active",
        activeFlags: []
    )

    #expect(CodexSessionStateMapper.state(for: session, now: now) == .idle)
}

@Test func activeCodexThreadWithWaitFlagsMapsToAttentionStates() {
    let now = Date()

    #expect(CodexSessionStateMapper.state(
        for: codexSession(updatedAt: now.addingTimeInterval(-60), statusType: "active", activeFlags: ["waitingOnApproval"]),
        now: now
    ) == .asking)

    #expect(CodexSessionStateMapper.state(
        for: codexSession(updatedAt: now.addingTimeInterval(-60), statusType: "active", activeFlags: ["waitingOnUserInput"]),
        now: now
    ) == .ready)
}

private func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appending(path: "VibenionCodexTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func isoDate(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date)
}

private func codexSession(
    updatedAt: Date,
    statusType: String?,
    activeFlags: [String]?
) -> CodexDiscoveredSession {
    CodexDiscoveredSession(
        id: UUID().uuidString,
        title: "Codex",
        preview: nil,
        updatedAt: updatedAt,
        cwd: nil,
        branch: nil,
        path: nil,
        statusType: statusType,
        activeFlags: activeFlags,
        isLoaded: true
    )
}
