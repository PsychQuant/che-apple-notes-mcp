import Foundation
import MCP

/// Handles --cli mode: parse CLI args or stdin JSON, dispatch to tool handler, print result.
enum CLIRunner {

    enum CLIError: LocalizedError {
        case missingToolName
        case danglingKey(String)
        case missingToolField
        case invalidJSON(String)

        var errorDescription: String? {
            switch self {
            case .missingToolName:
                return "Missing tool name. Usage: CheAppleNotesMCP --cli <tool_name> [--key value ...]"
            case .danglingKey(let key):
                return "Argument '--\(key)' has no value. All arguments require a value."
            case .missingToolField:
                return "JSON input must contain a 'tool' field. Expected: {\"tool\":\"...\",\"arguments\":{...}}"
            case .invalidJSON(let detail):
                return "Invalid JSON input: \(detail)"
            }
        }
    }

    static func parseArgs(_ args: [String]) throws -> (tool: String, arguments: [String: String]) {
        guard let cliIndex = args.firstIndex(of: "--cli"),
              cliIndex + 1 < args.count
        else {
            throw CLIError.missingToolName
        }

        let toolName = args[cliIndex + 1]

        var arguments: [String: String] = [:]
        var i = cliIndex + 2
        while i < args.count {
            let arg = args[i]
            guard arg.hasPrefix("--") else {
                i += 1
                continue
            }
            let key = String(arg.dropFirst(2))
            guard i + 1 < args.count else {
                throw CLIError.danglingKey(key)
            }
            arguments[key] = args[i + 1]
            i += 2
        }

        return (toolName, arguments)
    }

    static func inferValue(_ str: String) -> Value {
        if str == "true" { return .bool(true) }
        if str == "false" { return .bool(false) }
        if let intVal = Int(str) { return .int(intVal) }
        if str.contains("."), let dblVal = Double(str) { return .double(dblVal) }
        if (str.hasPrefix("[") || str.hasPrefix("{")),
           let data = str.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: data)
        {
            return jsonToValue(parsed)
        }
        return .string(str)
    }

    static func toMCPArguments(_ args: [String: String]) -> [String: Value] {
        var result: [String: Value] = [:]
        for (key, value) in args {
            result[key] = inferValue(value)
        }
        return result
    }

    static func jsonToValue(_ obj: Any) -> Value {
        switch obj {
        case let str as String:
            return .string(str)
        case let num as NSNumber:
            if CFGetTypeID(num) == CFBooleanGetTypeID() {
                return .bool(num.boolValue)
            }
            if num.doubleValue == Double(num.intValue) && !"\(num)".contains(".") {
                return .int(num.intValue)
            }
            return .double(num.doubleValue)
        case let arr as [Any]:
            return .array(arr.map { jsonToValue($0) })
        case let dict as [String: Any]:
            return .object(dict.mapValues { jsonToValue($0) })
        case is NSNull:
            return .string("")
        default:
            return .string("\(obj)")
        }
    }

    static func parseJSONInputToValues(_ input: String) throws -> (tool: String, arguments: [String: Value]) {
        guard let data = input.data(using: .utf8),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw CLIError.invalidJSON("could not parse as JSON object")
        }

        guard let toolName = json["tool"] as? String else {
            throw CLIError.missingToolField
        }

        var arguments: [String: Value] = [:]
        if let args = json["arguments"] as? [String: Any] {
            for (key, value) in args {
                arguments[key] = jsonToValue(value)
            }
        }

        return (toolName, arguments)
    }

    private static func hasToolNameInArgs(_ args: [String]) -> Bool {
        guard let cliIndex = args.firstIndex(of: "--cli"),
              cliIndex + 1 < args.count
        else { return false }
        return !args[cliIndex + 1].hasPrefix("--")
    }

    static func run(server: CheAppleNotesMCPServer, args: [String]) async {
        do {
            let toolName: String
            let mcpArgs: [String: Value]

            if hasToolNameInArgs(args) {
                let (tool, strArgs) = try parseArgs(args)
                toolName = tool
                mcpArgs = toMCPArguments(strArgs)
            } else if isatty(fileno(stdin)) == 0 {
                let inputData = FileHandle.standardInput.readDataToEndOfFile()
                guard let input = String(data: inputData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !input.isEmpty
                else {
                    throw CLIError.missingToolName
                }
                (toolName, mcpArgs) = try parseJSONInputToValues(input)
            } else {
                throw CLIError.missingToolName
            }

            let result = try await server.executeToolCall(name: toolName, arguments: mcpArgs)
            print(result)
        } catch {
            let errorJSON: [String: Any] = [
                "error": true,
                "message": error.localizedDescription,
            ]
            if let data = try? JSONSerialization.data(withJSONObject: errorJSON, options: [.sortedKeys]),
               let str = String(data: data, encoding: .utf8)
            {
                print(str)
            } else {
                let escaped = error.localizedDescription
                    .replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "\"", with: "\\\"")
                    .replacingOccurrences(of: "\n", with: "\\n")
                print("{\"error\":true,\"message\":\"\(escaped)\"}")
            }
            exit(1)
        }
    }
}
