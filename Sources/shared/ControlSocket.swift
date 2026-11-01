import Foundation
import Darwin

enum ControlWire {
    static func encoder() -> JSONEncoder {
        let value = JSONEncoder(); value.dateEncodingStrategy = .iso8601; return value
    }
    static func decoder() -> JSONDecoder {
        let value = JSONDecoder(); value.dateDecodingStrategy = .iso8601; return value
    }
}

enum ControlSocket {
    static let productionPath = "/var/run/com.macminimode/control.sock"
    static func clientPath(preview: Bool, override: String?) throws -> String {
        guard preview else { return override ?? productionPath }
        guard let override, !override.isEmpty else { throw ControlFailure("preview_socket_required") }
        let target = URL(fileURLWithPath: override).standardizedFileURL.resolvingSymlinksInPath().path
        let production = URL(fileURLWithPath: productionPath).resolvingSymlinksInPath().path
        guard target != production else { throw ControlFailure("preview_requires_isolated_socket") }
        return override
    }
    static func address(_ path: String) throws -> sockaddr_un {
        var value = sockaddr_un()
        value.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8) + [0]
        guard bytes.count <= MemoryLayout.size(ofValue: value.sun_path) else { throw ControlFailure("socket_path_too_long") }
        withUnsafeMutableBytes(of: &value.sun_path) { dest in dest.copyBytes(from: bytes) }
        value.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        return value
    }
    static func configure(_ fd: Int32) {
        var noSignal: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout.size(ofValue: noSignal)))
        var timeout = timeval(tv_sec: 5, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout.size(ofValue: timeout)))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout.size(ofValue: timeout)))
    }
    static func send(_ data: Data, fd: Int32) throws {
        let bytes = Array(data) + [10]
        var sent = 0
        while sent < bytes.count {
            let n = bytes.withUnsafeBytes { Darwin.write(fd, $0.baseAddress!.advanced(by: sent), bytes.count - sent) }
            if n < 0 && errno == EINTR { continue }
            guard n > 0 else { throw ControlFailure("socket_write_failed") }
            sent += n
        }
    }
    static func read(_ fd: Int32) throws -> Data {
        let deadline = DispatchTime.now().uptimeNanoseconds + 5_000_000_000
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while data.count <= 1048576 {
            // Bound the whole message, including clients that keep sending partial data.
            let now = DispatchTime.now().uptimeNanoseconds
            guard now < deadline else { throw ControlFailure("socket_read_failed_or_timeout") }
            let remainingMicroseconds = (deadline - now + 999) / 1000
            var timeout = timeval(tv_sec: Int(remainingMicroseconds / 1_000_000),
                                  tv_usec: Int32(remainingMicroseconds % 1_000_000))
            guard setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout,
                             socklen_t(MemoryLayout.size(ofValue: timeout))) == 0 else {
                throw ControlFailure("socket_timeout_configuration_failed")
            }
            let n = Darwin.read(fd, &buffer, buffer.count)
            if n < 0 && errno == EINTR { continue }
            guard n > 0, DispatchTime.now().uptimeNanoseconds < deadline else {
                throw ControlFailure("socket_read_failed_or_timeout")
            }
            if let end = buffer[..<n].firstIndex(of: 10) { data.append(contentsOf: buffer[..<end]); return data }
            data.append(contentsOf: buffer[..<n])
        }
        throw ControlFailure("message_too_large")
    }
    static func request(_ request: ControlRequest, path: String? = nil) throws -> ControlResponse {
        let preview = CommandLine.arguments.contains("--preview")
        let target = try clientPath(preview: preview,
                                   override: path ?? ProcessInfo.processInfo.environment["MACMINIMODE_SOCKET"])
        if preview {
            let status = try exchange(ControlRequest(operation: "status"), path: target)
            guard status.status?.simulated == true else { throw ControlFailure("preview_requires_simulated_service") }
            if request.operation == "status" { return status }
        }
        return try exchange(request, path: target)
    }
    private static func exchange(_ request: ControlRequest, path: String) throws -> ControlResponse {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw ControlFailure("socket_unavailable") }
        defer { close(fd) }
        configure(fd)
        var addr = try address(path)
        let result = withUnsafePointer(to: &addr) { p in
            p.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard result == 0 else { throw ControlFailure("service_unavailable") }
        try send(ControlWire.encoder().encode(request), fd: fd)
        return try ControlWire.decoder().decode(ControlResponse.self, from: read(fd))
    }
}
