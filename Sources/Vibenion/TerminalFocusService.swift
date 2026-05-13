import AppKit
import ApplicationServices

@MainActor
protocol TerminalFocusing {
    func focusTerminal(for session: AgentSession)
}

@MainActor
struct TerminalFocusService: TerminalFocusing {
    static let shared = TerminalFocusService()

    func focusTerminal(for session: AgentSession) {
        let target = session.terminalTarget ?? TerminalTarget(
            appName: session.terminal,
            bundleID: bundleID(forTerminalName: session.terminal),
            processID: nil,
            windowID: nil,
            windowTitle: nil,
            tabTitle: nil,
            workspaceID: nil,
            surfaceID: nil,
            socketPath: nil,
            threadID: session.agent == .codex ? session.id : nil
        )

        if isCodex(target), openCodexDeepLinkIfPossible(target) {
            return
        }

        if isCmux(target) {
            focusCmuxTarget(target, session: session)
        }

        guard let app = runningApplication(for: target) else {
            openApplication(for: target) { app in
                Task { @MainActor in
                    guard let app else { return }
                    activate(app, matching: target)
                    if isCodex(target) {
                        resumeCodexThreadIfPossible(target)
                        selectVisibleCodexThread(in: app, matching: session)
                    }
                }
            }
            return
        }

        activate(app, matching: target)
        if isCodex(target) {
            resumeCodexThreadIfPossible(target)
            selectVisibleCodexThread(in: app, matching: session)
        }
    }

    private func runningApplication(for target: TerminalTarget) -> NSRunningApplication? {
        if isCmux(target) {
            return NSRunningApplication.runningApplications(withBundleIdentifier: "com.cmuxterm.app").first
        }

        if let processID = target.processID,
            let app = NSRunningApplication(processIdentifier: processID)
        {
            return app
        }

        if let bundleID = target.bundleID {
            return NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
        }

        let normalizedName = target.displayName.lowercased()
        return NSWorkspace.shared.runningApplications.first { app in
            [app.localizedName, app.bundleIdentifier]
                .compactMap(\.self)
                .contains { $0.lowercased() == normalizedName || $0.lowercased() == target.bundleID?.lowercased() }
        }
    }

    private func isCmux(_ target: TerminalTarget) -> Bool {
        let appName = target.displayName.lowercased()
        return appName == "cmux" || appName == "mux" || target.workspaceID != nil || target.surfaceID != nil
    }

    private func isCodex(_ target: TerminalTarget) -> Bool {
        target.bundleID == "com.openai.codex" || target.displayName.lowercased() == "codex"
    }

    private func openCodexDeepLinkIfPossible(_ target: TerminalTarget) -> Bool {
        guard let threadID = target.threadID?.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
            let url = URL(string: "codex://local/\(threadID)")
        else {
            return false
        }

        return NSWorkspace.shared.open(url)
    }

    private func resumeCodexThreadIfPossible(_ target: TerminalTarget) {
        guard let threadID = target.threadID else { return }
        guard FileManager.default.fileExists(atPath: codexAppServerSocketPath) else { return }

        let request = """
        {"id":1,"method":"thread/resume","params":{"threadId":"\(threadID)"}}

        """
        runCodexAppServerProxy(input: request)
    }

    private var codexAppServerSocketPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/app-server-control/app-server-control.sock")
            .path
    }

    private func runCodexAppServerProxy(input: String) {
        let executable = URL(fileURLWithPath: "/Applications/Codex.app/Contents/Resources/codex")
        guard FileManager.default.isExecutableFile(atPath: executable.path) else { return }

        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let process = Process()
        process.executableURL = executable
        process.arguments = ["app-server", "proxy"]
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        do {
            try process.run()
            if let data = input.data(using: .utf8) {
                inputPipe.fileHandleForWriting.write(data)
            }
            try? inputPipe.fileHandleForWriting.close()
            process.waitUntilExit()
        } catch {
            return
        }
    }

    private func focusCmuxTarget(_ target: TerminalTarget, session: AgentSession) {
        guard target.workspaceID != nil || target.surfaceID != nil || target.tabTitle != nil || session.cwd != nil else {
            return
        }

        let script = cmuxFocusScript(target: target, session: session)
        runAppleScript(script)
    }

    private func cmuxFocusScript(target: TerminalTarget, session: AgentSession) -> String {
        let workspaceID = appleScriptString(target.workspaceID)
        let surfaceID = appleScriptString(target.surfaceID)
        let tabTitle = appleScriptString(target.tabTitle ?? target.windowTitle ?? session.title)
        let cwd = appleScriptString(session.cwd)

        return """
        tell application "cmux"
          activate
          repeat with targetWindow in windows
            repeat with targetTab in tabs of targetWindow
              set tabMatches to false
              if \(workspaceID) is not missing value and id of targetTab is \(workspaceID) then set tabMatches to true
              if tabMatches is false and \(tabTitle) is not missing value and name of targetTab contains \(tabTitle) then set tabMatches to true
              repeat with targetTerminal in terminals of targetTab
                set terminalMatches to tabMatches
                if \(surfaceID) is not missing value and id of targetTerminal is \(surfaceID) then set terminalMatches to true
                if terminalMatches is false and \(cwd) is not missing value and working directory of targetTerminal is \(cwd) then set terminalMatches to true
                if terminalMatches is true then
                  select tab targetTab
                  focus targetTerminal
                  return
                end if
              end repeat
              if tabMatches is true then
                select tab targetTab
                activate window targetWindow
                return
              end if
            end repeat
          end repeat
        end tell
        """
    }

    private func runAppleScript(_ script: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try? process.run()
        process.waitUntilExit()
    }

    private func appleScriptString(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "missing value" }
        return "\"\(value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\""
    }

    private func focusWindow(in app: NSRunningApplication, matching target: TerminalTarget) {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        guard let windows = copyAttribute([AXUIElement].self, named: kAXWindowsAttribute, from: appElement) else {
            return
        }

        guard target.windowID != nil || target.windowTitle != nil || target.tabTitle != nil else {
            if let firstWindow = windows.first {
                AXUIElementSetAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, firstWindow)
                AXUIElementPerformAction(firstWindow, kAXRaiseAction as CFString)
            }
            return
        }

        guard let window = windows.first(where: { window in
            if let windowID = target.windowID,
                copyAttribute(NSNumber.self, named: "AXWindowNumber", from: window)?.intValue == windowID
            {
                return true
            }

            let title = copyAttribute(String.self, named: kAXTitleAttribute, from: window)
            if let windowTitle = target.windowTitle, title == windowTitle {
                return true
            }
            if let tabTitle = target.tabTitle, title?.contains(tabTitle) == true {
                return true
            }
            return false
        }) else {
            return
        }

        AXUIElementSetAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, window)
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
    }

    private func copyAttribute<T>(_ type: T.Type, named name: String, from element: AXUIElement) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
            return nil
        }
        return value as? T
    }

    private func activate(_ app: NSRunningApplication, matching target: TerminalTarget) {
        app.activate(options: [.activateAllWindows])
        focusWindow(in: app, matching: target)
    }

    private func selectVisibleCodexThread(in app: NSRunningApplication, matching session: AgentSession) {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        guard let element = findPressableElement(
            in: appElement,
            matchingAnyOf: [session.title, session.id].filter { !$0.isEmpty },
            depth: 0
        ) else {
            return
        }

        AXUIElementPerformAction(element, kAXPressAction as CFString)
    }

    private func findPressableElement(
        in element: AXUIElement,
        matchingAnyOf needles: [String],
        depth: Int
    ) -> AXUIElement? {
        guard depth < 8 else { return nil }

        if elementContainsAnyNeedle(element, needles: needles),
            supportsPressAction(element)
        {
            return element
        }

        if let children = copyAttribute([AXUIElement].self, named: kAXChildrenAttribute, from: element) {
            for child in children {
                if let match = findPressableElement(in: child, matchingAnyOf: needles, depth: depth + 1) {
                    return match
                }
            }
        }

        if elementContainsAnyNeedle(element, needles: needles) {
            return nearestPressableAncestor(from: element, maxHops: 4)
        }

        return nil
    }

    private func elementContainsAnyNeedle(_ element: AXUIElement, needles: [String]) -> Bool {
        let haystack = [
            copyAttribute(String.self, named: kAXTitleAttribute, from: element),
            copyAttribute(String.self, named: kAXDescriptionAttribute, from: element),
            copyAttribute(String.self, named: kAXValueAttribute, from: element),
        ].compactMap(\.self).joined(separator: " ").lowercased()

        guard !haystack.isEmpty else { return false }
        return needles.contains { needle in
            let normalizedNeedle = needle.lowercased()
            return !normalizedNeedle.isEmpty && haystack.contains(normalizedNeedle)
        }
    }

    private func nearestPressableAncestor(from element: AXUIElement, maxHops: Int) -> AXUIElement? {
        var current: AXUIElement? = element
        for _ in 0..<maxHops {
            guard let candidate = current else { return nil }
            if supportsPressAction(candidate) {
                return candidate
            }
            current = copyAttribute(AXUIElement.self, named: kAXParentAttribute, from: candidate)
        }
        return nil
    }

    private func supportsPressAction(_ element: AXUIElement) -> Bool {
        var actions: CFArray?
        guard AXUIElementCopyActionNames(element, &actions) == .success else { return false }
        return (actions as? [String])?.contains(kAXPressAction) == true
    }

    private func openApplication(
        for target: TerminalTarget,
        completion: (@Sendable @escaping (NSRunningApplication?) -> Void)
    ) {
        guard let url = applicationURL(for: target) else {
            completion(nil)
            return
        }

        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { app, _ in
            completion(app)
        }
    }

    private func applicationURL(for target: TerminalTarget) -> URL? {
        if isCmux(target),
            let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.cmuxterm.app")
        {
            return url
        }

        if let bundleID = target.bundleID,
            let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        {
            return url
        }

        let appName = terminalAppName(for: target.displayName)
        if let bundleID = bundleID(forTerminalName: appName),
            let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        {
            return url
        }

        switch appName {
        case "cmux":
            return URL(fileURLWithPath: "/Applications/cmux.app")
        case "Codex":
            return URL(fileURLWithPath: "/Applications/Codex.app")
        case "Ghostty":
            return URL(fileURLWithPath: "/Applications/Ghostty.app")
        case "Terminal":
            return URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
        default:
            return nil
        }
    }

    private func terminalAppName(for name: String) -> String {
        switch name.lowercased() {
        case "cmux", "mux": "cmux"
        case "ghostty": "Ghostty"
        case "iterm", "iterm2": "iTerm2"
        case "codex", "codex app": "Codex"
        case "terminal", "terminal.app": "Terminal"
        default: name
        }
    }

    private func bundleID(forTerminalName name: String) -> String? {
        switch name.lowercased() {
        case "cmux", "mux": "com.cmuxterm.app"
        case "ghostty": "com.mitchellh.ghostty"
        case "iterm", "iterm2": "com.googlecode.iterm2"
        case "codex", "codex app": "com.openai.codex"
        case "terminal", "terminal.app": "com.apple.Terminal"
        default: nil
        }
    }
}
