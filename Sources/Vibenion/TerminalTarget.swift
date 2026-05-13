import Foundation

struct TerminalTarget: Decodable, Equatable, Sendable {
    var appName: String?
    var bundleID: String?
    var processID: Int32?
    var windowID: Int?
    var windowTitle: String?
    var tabTitle: String?
    var workspaceID: String?
    var surfaceID: String?
    var socketPath: String?
    var threadID: String?

    var displayName: String {
        appName ?? bundleDisplayName ?? "Terminal"
    }

    private var bundleDisplayName: String? {
        switch bundleID {
        case "com.cmuxterm.app": "cmux"
        case "com.mitchellh.ghostty": "Ghostty"
        case "com.googlecode.iterm2": "iTerm2"
        case "com.apple.Terminal": "Terminal"
        case "com.openai.codex": "Codex"
        default: nil
        }
    }

    enum CodingKeys: String, CodingKey {
        case appName = "app_name"
        case bundleID = "bundle_id"
        case processID = "pid"
        case windowID = "window_id"
        case windowTitle = "window_title"
        case tabTitle = "tab_title"
        case workspaceID = "workspace_id"
        case surfaceID = "surface_id"
        case socketPath = "socket_path"
        case threadID = "thread_id"
    }
}
