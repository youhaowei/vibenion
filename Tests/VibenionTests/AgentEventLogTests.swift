import Foundation
import Testing
@testable import Vibenion

@Test func decodesLegacyTerminalStringEvent() throws {
    let json = """
    {"session_id":"codex-api","agent":"codex","state":"running","summary":"Running tests","terminal":"Terminal"}
    """

    let event = try JSONDecoder().decode(AgentEvent.self, from: Data(json.utf8))

    #expect(event.terminal == "Terminal")
    #expect(event.terminalTarget == nil)
}

@Test func decodesTerminalMetadataObjectEvent() throws {
    let json = """
    {
      "session_id": "codex-api",
      "agent": "codex",
      "state": "running",
      "summary": "Running tests",
      "terminal": {
        "app_name": "Ghostty",
        "bundle_id": "com.mitchellh.ghostty",
        "pid": 9123,
        "window_id": 77,
        "window_title": "vibenion",
        "tab_title": "codex"
      }
    }
    """

    let event = try JSONDecoder().decode(AgentEvent.self, from: Data(json.utf8))

    #expect(event.terminal == "Ghostty")
    #expect(event.terminalTarget?.appName == "Ghostty")
    #expect(event.terminalTarget?.bundleID == "com.mitchellh.ghostty")
    #expect(event.terminalTarget?.processID == 9123)
    #expect(event.terminalTarget?.windowID == 77)
    #expect(event.terminalTarget?.windowTitle == "vibenion")
    #expect(event.terminalTarget?.tabTitle == "codex")
}

@Test func decodesSeparateTerminalMetadataEvent() throws {
    let json = """
    {
      "session_id": "codex-api",
      "agent": "codex",
      "state": "running",
      "summary": "Running tests",
      "terminal": "iTerm2",
      "terminal_metadata": {
        "bundle_id": "com.googlecode.iterm2",
        "window_id": 42
      }
    }
    """

    let event = try JSONDecoder().decode(AgentEvent.self, from: Data(json.utf8))

    #expect(event.terminal == "iTerm2")
    #expect(event.terminalTarget?.bundleID == "com.googlecode.iterm2")
    #expect(event.terminalTarget?.windowID == 42)
}

@Test func decodesCmuxTerminalMetadataEvent() throws {
    let json = """
    {
      "session_id": "codex-api",
      "agent": "codex",
      "state": "running",
      "summary": "Running tests",
      "terminal": "cmux",
      "terminal_metadata": {
        "workspace_id": "workspace:2",
        "surface_id": "surface:4",
        "socket_path": "/tmp/cmux.sock",
        "thread_id": "019e0850-8f41-7e90-b6c9-a67946f7b2a7"
      }
    }
    """

    let event = try JSONDecoder().decode(AgentEvent.self, from: Data(json.utf8))

    #expect(event.terminal == "cmux")
    #expect(event.terminalTarget?.appName == "cmux")
    #expect(event.terminalTarget?.workspaceID == "workspace:2")
    #expect(event.terminalTarget?.surfaceID == "surface:4")
    #expect(event.terminalTarget?.socketPath == "/tmp/cmux.sock")
    #expect(event.terminalTarget?.threadID == "019e0850-8f41-7e90-b6c9-a67946f7b2a7")
}
