import Foundation
import MCP

// The native helper is the single CLI/IPC implementation. No shell interpretation.
func callControl(_ request: [String: String]) throws -> (String, Bool) {
    let helper = ProcessInfo.processInfo.environment["MACMINIMODE_CONTROL"] ??
        URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().appendingPathComponent("macminimode-control").path
    let process = Process()
    process.executableURL = URL(fileURLWithPath: helper)
    let data = try JSONSerialization.data(withJSONObject: request, options: [.sortedKeys])
    process.arguments = ["request", String(decoding: data, as: UTF8.self)]
    let output = Pipe()
    process.standardOutput = output
    process.standardError = FileHandle.standardError
    try process.run()
    let bytes = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return (String(decoding: bytes, as: UTF8.self), process.terminationStatus != 0)
}
func schema(_ properties: [String: Value], required: [String] = []) -> Value {
    .object(["type": .string("object"), "properties": .object(properties),
             "required": .array(required.map { .string($0) }), "additionalProperties": .bool(false)])
}
let string: Value = .object(["type": .string("string"), "minLength": .int(1)])
func modeSchema(_ modes: [String]) -> Value { .object(["type": .string("string"), "enum": .array(modes.map { .string($0) })]) }
let server = Server(name: "macminimode", version: "0.1.3", capabilities: .init(tools: .init()))
await server.withMethodHandler(ListTools.self) { _ in
    .init(tools: [
        Tool(name: "get_status", description: "Read actual sleep prevention, power policy and tasks owned by this macOS user.", inputSchema: schema([:]), annotations: .init(readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false)),
        Tool(name: "begin_task", description: "Register a long-running task. Default auto prevents sleep only on AC. Use on only when the user explicitly requests battery operation. Retain the unique task id for end_task. Registration survives disconnects.", inputSchema: schema(["id": string, "name": string, "source": string, "mode": modeSchema(["auto", "on"])], required: ["id", "name", "source"]), annotations: .init(readOnlyHint: false, destructiveHint: false, idempotentHint: true, openWorldHint: false)),
        Tool(name: "end_task", description: "Release your completed, failed or cancelled task. The last release selects Always Off and may sleep a closed laptop. Wait for background work first. Repeated releases are safe.", inputSchema: schema(["id": string], required: ["id"]), annotations: .init(readOnlyHint: false, destructiveHint: true, idempotentHint: true, openWorldHint: false)),
        Tool(name: "set_mode", description: "Manual override ONLY when explicitly requested by the user. Clears all task registrations, including other tasks, and selects auto/on/off. Never use this for ordinary task cleanup.", inputSchema: schema(["mode": modeSchema(["auto", "on", "off"])], required: ["mode"]), annotations: .init(readOnlyHint: false, destructiveHint: true, idempotentHint: true, openWorldHint: false))
    ])
}
await server.withMethodHandler(CallTool.self) { params in
    do {
        let allowed: [String: Set<String>] = ["get_status": [], "begin_task": ["id", "name", "source", "mode"], "end_task": ["id"], "set_mode": ["mode"]]
        guard let keys = allowed[params.name] else { throw NSError(domain: "Unknown tool", code: 1) }
        let args = params.arguments ?? [:]
        guard Set(args.keys).isSubset(of: keys), args.values.allSatisfy({ $0.stringValue != nil }) else { throw NSError(domain: "Invalid arguments", code: 1) }
        var request = args.mapValues { $0.stringValue! }
        request["operation"] = params.name == "get_status" ? "status" : params.name
        let (text, failed) = try callControl(request)
        let value = try JSONDecoder().decode(Value.self, from: Data(text.utf8))
        return try .init(content: [.text(text: text, annotations: nil, _meta: nil)], structuredContent: value.objectValue, isError: failed)
    } catch {
        return .init(content: [.text(text: "Control request failed: \(error)", annotations: nil, _meta: nil)], isError: true)
    }
}
try await server.start(transport: CompatibleTransport())
await server.waitUntilCompleted()
