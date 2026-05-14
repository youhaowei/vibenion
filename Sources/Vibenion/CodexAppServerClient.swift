import Foundation
import Darwin

struct CodexThread: Decodable, Sendable {
    let id: String
    let name: String?
    let preview: String?
    let cwd: String?
    let path: String?
    let source: String?
    let createdAt: Double?
    let updatedAt: Double?
    let gitInfo: GitInfo?
    let status: Status?

    struct GitInfo: Decodable, Sendable {
        let sha: String?
        let branch: String?
        let originUrl: String?
    }

    struct Status: Decodable, Sendable {
        let type: String
        let activeFlags: [String]?
    }
}

/// Long-lived JSON-RPC 2.0 client for `codex app-server`.
/// Tries the Codex Desktop control socket first; falls back to spawning
/// `codex app-server` as a subprocess. Communication is newline-delimited
/// JSON over stdin/stdout (or socket).
final class CodexAppServerClient: @unchecked Sendable {
    static let shared = CodexAppServerClient()

    private static let controlSocketPath: String = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/app-server-control/app-server-control.sock")
            .path
    }()

    private static let binaryCandidates = [
        "/opt/homebrew/bin/codex",
        "/usr/local/bin/codex",
        NSHomeDirectory() + "/.cargo/bin/codex",
        NSHomeDirectory() + "/.local/bin/codex",
    ]

    private let lock = NSLock()
    private var process: Process?
    private var readHandle: FileHandle?
    private var writeHandle: FileHandle?
    private var nextID = 1
    private var pendingResponses: [Int: Data] = [:]
    private var readBuffer = Data()
    private var initialized = false

    private init() {}

    func listThreads(limit: Int = 50) -> [CodexThread]? {
        lock.lock(); defer { lock.unlock() }
        guard ensureConnectedLocked() else { return nil }

        let params: [String: Any] = [
            "archived": false,
            "limit": limit,
            "sortKey": "updated_at",
            "sortDirection": "desc",
        ]
        guard let raw = sendLocked(method: "thread/list", params: params) else {
            disconnectLocked()
            return nil
        }

        struct ListResponse: Decodable {
            let data: [CodexThread]
        }
        guard let resp = try? JSONDecoder().decode(ListResponse.self, from: raw) else {
            return []
        }
        return resp.data
    }

    func listLoaded() -> [String]? {
        lock.lock(); defer { lock.unlock() }
        guard ensureConnectedLocked() else { return nil }
        guard let raw = sendLocked(method: "thread/loaded/list", params: [String: Any]()) else {
            return nil
        }
        struct LoadedResponse: Decodable {
            let data: [Item]
            struct Item: Decodable { let id: String }
        }
        guard let resp = try? JSONDecoder().decode(LoadedResponse.self, from: raw) else {
            return []
        }
        return resp.data.map(\.id)
    }

    // MARK: - Connection

    private func ensureConnectedLocked() -> Bool {
        if initialized, writeHandle != nil { return true }
        disconnectLocked()

        if connectControlSocketLocked() {
            if initializeLocked() { initialized = true; return true }
            disconnectLocked()
        }

        if spawnSubprocessLocked() {
            if initializeLocked() { initialized = true; return true }
            disconnectLocked()
        }

        return false
    }

    private func connectControlSocketLocked() -> Bool {
        let path = Self.controlSocketPath
        guard FileManager.default.fileExists(atPath: path) else { return false }

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(path.utf8)
        let maxLen = MemoryLayout.size(ofValue: addr.sun_path) - 1
        guard pathBytes.count <= maxLen else { close(fd); return false }
        withUnsafeMutablePointer(to: &addr.sun_path) { tuple in
            tuple.withMemoryRebound(to: UInt8.self, capacity: maxLen + 1) { ptr in
                for (i, byte) in pathBytes.enumerated() { ptr[i] = byte }
                ptr[pathBytes.count] = 0
            }
        }

        var tv = timeval(tv_sec: 0, tv_usec: 500_000)
        _ = setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        _ = setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        let size = socklen_t(MemoryLayout<sockaddr_un>.size)
        let result = withUnsafePointer(to: &addr) { ap in
            ap.withMemoryRebound(to: sockaddr.self, capacity: 1) { sp in
                Darwin.connect(fd, sp, size)
            }
        }
        if result != 0 {
            close(fd); return false
        }

        var tv0 = timeval(tv_sec: 5, tv_usec: 0)
        _ = setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv0, socklen_t(MemoryLayout<timeval>.size))
        _ = setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv0, socklen_t(MemoryLayout<timeval>.size))

        let readFD = dup(fd)
        let writeFD = dup(fd)
        close(fd)
        readHandle = FileHandle(fileDescriptor: readFD, closeOnDealloc: true)
        writeHandle = FileHandle(fileDescriptor: writeFD, closeOnDealloc: true)
        return true
    }

    private func spawnSubprocessLocked() -> Bool {
        guard let binary = Self.binaryCandidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            return false
        }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: binary)
        proc.arguments = ["app-server"]
        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        proc.standardInput = stdin
        proc.standardOutput = stdout
        proc.standardError = stderr

        do {
            try proc.run()
        } catch {
            return false
        }

        process = proc
        readHandle = stdout.fileHandleForReading
        writeHandle = stdin.fileHandleForWriting
        return true
    }

    private func initializeLocked() -> Bool {
        let params: [String: Any] = [
            "clientInfo": ["name": "vibenion", "version": "0.1"]
        ]
        return sendLocked(method: "initialize", params: params) != nil
    }

    private func disconnectLocked() {
        initialized = false
        readBuffer.removeAll()
        pendingResponses.removeAll()
        try? writeHandle?.close()
        try? readHandle?.close()
        writeHandle = nil
        readHandle = nil
        if let proc = process {
            if proc.isRunning { proc.terminate() }
            process = nil
        }
    }

    // MARK: - JSON-RPC

    private func sendLocked(method: String, params: Any) -> Data? {
        guard let write = writeHandle else { return nil }

        let id = nextID
        nextID += 1

        let payload: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id,
            "method": method,
            "params": params,
        ]
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return nil }
        var line = body
        line.append(0x0A)
        do {
            try write.write(contentsOf: line)
        } catch {
            return nil
        }

        return readResponseLocked(matchingID: id, timeout: 5.0)
    }

    private func readResponseLocked(matchingID id: Int, timeout: TimeInterval) -> Data? {
        if let cached = pendingResponses.removeValue(forKey: id) { return cached }
        guard let read = readHandle else { return nil }

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let line = nextLineLocked() {
                guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
                if let respID = obj["id"] as? Int, let result = obj["result"] {
                    let resultData = (try? JSONSerialization.data(withJSONObject: result)) ?? Data()
                    if respID == id { return resultData }
                    pendingResponses[respID] = resultData
                }
                continue
            }
            // `availableData` returns as soon as any bytes arrive (or EOF).
            // `read(upToCount:)` blocks on macOS pipes until the buffer fills.
            let chunk = read.availableData
            if chunk.isEmpty {
                if !readBuffer.isEmpty { continue }
                return nil
            }
            readBuffer.append(chunk)
        }
        return nil
    }

    private func nextLineLocked() -> Data? {
        guard let nlIndex = readBuffer.firstIndex(of: 0x0A) else { return nil }
        let line = readBuffer.subdata(in: readBuffer.startIndex..<nlIndex)
        readBuffer.removeSubrange(readBuffer.startIndex...nlIndex)
        return line
    }
}
