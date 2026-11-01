import Foundation
import Logging
import MCP

/// Swift MCP SDK 0.12.1 decodes experimental capabilities as [String: String],
/// although MCP permits arbitrary JSON values. This server implements none of
/// those extensions, so leave them unnegotiated rather than rejecting clients.
/// Remove this adapter when the pinned SDK accepts structured capabilities.
actor CompatibleTransport: Transport {
    private let transport = StdioTransport()
    nonisolated let logger = Logger(label: "cc.jasonstu.macminimode.mcp")

    func connect() async throws { try await transport.connect() }
    func disconnect() async { await transport.disconnect() }
    func send(_ data: Data) async throws { try await transport.send(data) }

    nonisolated static func normalize(_ data: Data) -> Data {
        guard var message = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              message["method"] as? String == "initialize",
              var params = message["params"] as? [String: Any],
              var capabilities = params["capabilities"] as? [String: Any],
              capabilities["experimental"] is [String: Any] else { return data }
        capabilities.removeValue(forKey: "experimental")
        params["capabilities"] = capabilities
        message["params"] = params
        return (try? JSONSerialization.data(withJSONObject: message)) ?? data
    }

    func receive() -> AsyncThrowingStream<Data, Swift.Error> {
        AsyncThrowingStream { continuation in
            let reader = Task {
                do {
                    for try await data in await transport.receive() {
                        continuation.yield(Self.normalize(data))
                    }
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in reader.cancel() }
        }
    }
}
