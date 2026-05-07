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
