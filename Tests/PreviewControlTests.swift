import Foundation

@main struct PreviewControlTests {
    static func main() throws {
        if let operation = ProcessInfo.processInfo.environment["TEST_OPERATION"] {
            do {
                let result = try ControlSocket.request(ControlRequest(operation: operation, mode: .off,
                    settings: PowerSettings(enabled: true, threshold: 20, restore: false)))
                print(String(decoding: try ControlWire.encoder().encode(result), as: UTF8.self))
            } catch {
                print(String(describing: error))
                exit(1)
            }
            return
        }
        precondition(tryPath(false, nil) == ControlSocket.productionPath)
        precondition(tryPath(false, "/tmp/custom.sock") == "/tmp/custom.sock")
        for path: String? in [nil, "", ControlSocket.productionPath,
                             "/private/var/run/com.macminimode/control.sock",
                             "/var/run/com.macminimode/../com.macminimode/control.sock"] {
            do {
                _ = try ControlSocket.clientPath(preview: true, override: path)
                preconditionFailure("Preview accepted a production or missing socket")
            } catch {}
        }
        precondition(tryPath(true, "/tmp/preview.sock") == "/tmp/preview.sock")
        print("PASS: preview requires an explicit isolated socket; normal routing preserved")
    }
    static func tryPath(_ preview: Bool, _ override: String?) -> String {
        try! ControlSocket.clientPath(preview: preview, override: override)
    }
}
