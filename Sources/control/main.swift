import Foundation
import Darwin

let args = Array(CommandLine.arguments.dropFirst())
func fail(_ message: String) -> Never {
    let response = ControlResponse(ok: false, saved: false, applied: false, error: message)
    if let data = try? ControlWire.encoder().encode(response) { print(String(decoding: data, as: UTF8.self)) }
    exit(1)
}
let request: ControlRequest
switch args.first ?? "status" {
case "status": request = ControlRequest(operation: "status")
case "auto", "on", "off": request = ControlRequest(operation: "set_mode", mode: ControlMode(rawValue: args[0]))
case "begin":
    guard args.count == 5, let mode = ControlMode(rawValue: args[4]), mode != .off else { fail("Usage: begin ID NAME SOURCE auto|on") }
    request = ControlRequest(operation: "begin_task", mode: mode, id: args[1], name: args[2], source: args[3])
case "end":
    guard args.count == 2 else { fail("Usage: end ID") }
    request = ControlRequest(operation: "end_task", id: args[1])
case "request":
    guard args.count == 2, let data = args[1].data(using: .utf8), let value = try? JSONDecoder().decode(ControlRequest.self, from: data) else { fail("invalid_request") }
    request = value
 default: fail("Usage: status|auto|on|off|begin ID NAME SOURCE auto|on|end ID")
}
do {
    let response = try ControlSocket.request(request)
    let data = try ControlWire.encoder().encode(response)
    print(String(decoding: data, as: UTF8.self))
    exit(response.ok ? 0 : 1)
} catch { fail(String(describing: error)) }
