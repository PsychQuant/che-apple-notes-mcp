import Foundation

/// MCP JSON-RPC 2.0 client for end-to-end tests.
/// Spawns the debug binary as a child process and exchanges newline-delimited
/// JSON messages over stdio.
///
/// Arguments passed to `callTool` are raw JSON strings to keep the public API
/// `Sendable`-clean under Swift 6 strict concurrency. Callers construct the
/// JSON themselves (string interpolation or `JSONSerialization`).
actor MCPClient {

    // MARK: - Types

    struct ToolInfo: Codable, Sendable {
        let name: String
        let description: String?
    }

    struct CallToolResult: Sendable {
        let text: String
        let isError: Bool
        let rawJSON: String
    }

    enum MCPError: Error, CustomStringConvertible {
        case spawnFailed(String)
        case serverExitedEarly
        case protocolError(String)
        case serverError(code: Int, message: String)
        case responseTimeout

        var description: String {
            switch self {
            case .spawnFailed(let s): return "spawn failed: \(s)"
            case .serverExitedEarly: return "server exited before responding"
            case .protocolError(let s): return "protocol error: \(s)"
            case .serverError(let code, let message): return "server error \(code): \(message)"
            case .responseTimeout: return "response timeout"
            }
        }
    }

    // MARK: - State

    private let process: Process
    private let stdinHandle: FileHandle
    private let stdoutHandle: FileHandle
    private var nextId: Int = 1
    private var stdoutBuffer = Data()
    private let responseTimeout: TimeInterval = 30
    private var closed = false

    // MARK: - Init

    /// Spawn a new MCP server child process.
    /// - Parameter binaryPath: absolute path to the built binary. Defaults to
    ///   `$PWD/.build/debug/CheAppleNotesMCP`.
    init(binaryPath: String = MCPClient.defaultBinaryPath) throws {
        let proc = Process()
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        proc.executableURL = URL(fileURLWithPath: binaryPath)
        proc.standardInput = stdinPipe
        proc.standardOutput = stdoutPipe
        proc.standardError = stderrPipe

        do {
            try proc.run()
        } catch {
            throw MCPError.spawnFailed("\(binaryPath): \(error.localizedDescription)")
        }

        self.process = proc
        self.stdinHandle = stdinPipe.fileHandleForWriting
        self.stdoutHandle = stdoutPipe.fileHandleForReading

        // Drain stderr in background so the server doesn't block on a full pipe.
        // No isolated state mutated here, so this is safe off-actor.
        let stderrHandle = stderrPipe.fileHandleForReading
        Task.detached {
            while true {
                let chunk = stderrHandle.availableData
                if chunk.isEmpty { break }
                // Intentionally discarded; tests do not assert on log output.
                _ = chunk
            }
        }
    }

    deinit {
        if process.isRunning {
            process.terminate()
        }
    }

    static var defaultBinaryPath: String {
        let cwd = FileManager.default.currentDirectoryPath
        return "\(cwd)/.build/debug/CheAppleNotesMCP"
    }

    /// Terminate the child process. Safe to call multiple times.
    func close() {
        guard !closed else { return }
        closed = true
        try? stdinHandle.close()
        if process.isRunning {
            process.terminate()
        }
    }

    // MARK: - Public API

    /// Send `initialize` request per MCP spec. Must be called once before any
    /// other method. Returns the server's `result` as a raw JSON string.
    func initialize() async throws -> String {
        let params = #"{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"CheAppleNotesMCPE2E","version":"1.0"}}"#
        let resultJSON = try await request(method: "initialize", paramsJSON: params)
        // Follow MCP handshake: send the initialized notification (no response).
        try sendNotification(method: "notifications/initialized")
        return resultJSON
    }

    /// Return the tools advertised by the server.
    func listTools() async throws -> [ToolInfo] {
        let resultJSON = try await request(method: "tools/list", paramsJSON: "{}")
        let data = Data(resultJSON.utf8)
        struct Wrapper: Codable { let tools: [ToolInfo] }
        return try JSONDecoder().decode(Wrapper.self, from: data).tools
    }

    /// Invoke a tool with a raw JSON argument object.
    /// Example: `callTool(name: "create_note", arguments: #"{"title":"T"}"#)`.
    func callTool(name: String, arguments: String = "{}") async throws -> CallToolResult {
        // Compose params inline as raw JSON so we don't cross actor boundary
        // with [String: Any].
        let sanitizedArgs = arguments.isEmpty ? "{}" : arguments
        let escapedName = name.replacingOccurrences(of: "\"", with: "\\\"")
        let paramsJSON = #"{"name":"\#(escapedName)","arguments":\#(sanitizedArgs)}"#
        let resultJSON = try await request(method: "tools/call", paramsJSON: paramsJSON)

        // Extract `content[0].text` and `isError` from the raw JSON result.
        struct CallToolRaw: Codable { let content: [ContentItem]; let isError: Bool? }
        struct ContentItem: Codable { let type: String; let text: String? }
        let data = Data(resultJSON.utf8)
        let decoded = try JSONDecoder().decode(CallToolRaw.self, from: data)
        let text = decoded.content.first?.text ?? ""
        return CallToolResult(text: text, isError: decoded.isError ?? false, rawJSON: resultJSON)
    }

    // MARK: - Wire

    private func request(method: String, paramsJSON: String) async throws -> String {
        let id = nextId
        nextId += 1
        let escapedMethod = method.replacingOccurrences(of: "\"", with: "\\\"")
        let message = #"{"jsonrpc":"2.0","id":\#(id),"method":"\#(escapedMethod)","params":\#(paramsJSON)}"#
        try send(message)
        return try await waitForResponse(id: id)
    }

    private func sendNotification(method: String) throws {
        let escapedMethod = method.replacingOccurrences(of: "\"", with: "\\\"")
        let message = #"{"jsonrpc":"2.0","method":"\#(escapedMethod)"}"#
        try send(message)
    }

    private func send(_ jsonLine: String) throws {
        guard !closed else { throw MCPError.serverExitedEarly }
        var data = Data(jsonLine.utf8)
        data.append(0x0A)
        try stdinHandle.write(contentsOf: data)
    }

    private func waitForResponse(id: Int) async throws -> String {
        let deadline = Date().addingTimeInterval(responseTimeout)
        while Date() < deadline {
            guard let line = try readLine() else {
                try await Task.sleep(nanoseconds: 5_000_000)  // 5 ms
                continue
            }
            guard !line.isEmpty else { continue }

            // Parse just enough to match the id and detect error/result.
            guard let json = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else {
                continue  // ignore malformed
            }
            guard let responseId = json["id"] as? Int, responseId == id else {
                continue  // unrelated message
            }

            if let error = json["error"] as? [String: Any] {
                let code = error["code"] as? Int ?? -1
                let message = error["message"] as? String ?? "unknown"
                throw MCPError.serverError(code: code, message: message)
            }

            // Re-serialize just the `result` field so callers can re-parse.
            guard let result = json["result"] else {
                throw MCPError.protocolError("response missing result and error")
            }
            let resultData = try JSONSerialization.data(withJSONObject: result)
            return String(data: resultData, encoding: .utf8) ?? "{}"
        }
        throw MCPError.responseTimeout
    }

    /// Read one newline-terminated JSON line from stdout. Returns nil if none is
    /// available yet.
    private func readLine() throws -> Data? {
        if let idx = stdoutBuffer.firstIndex(of: 0x0A) {
            let line = Data(stdoutBuffer[stdoutBuffer.startIndex..<idx])
            stdoutBuffer.removeSubrange(stdoutBuffer.startIndex...idx)
            return line
        }
        // Pull anything available without blocking indefinitely.
        // availableData blocks until at least 1 byte or EOF; if process died,
        // we'd get empty Data which we translate to "no data yet".
        let chunk = stdoutHandle.availableData
        if chunk.isEmpty {
            if !process.isRunning {
                throw MCPError.serverExitedEarly
            }
            return nil
        }
        stdoutBuffer.append(chunk)

        if let idx = stdoutBuffer.firstIndex(of: 0x0A) {
            let line = Data(stdoutBuffer[stdoutBuffer.startIndex..<idx])
            stdoutBuffer.removeSubrange(stdoutBuffer.startIndex...idx)
            return line
        }
        return nil
    }
}
