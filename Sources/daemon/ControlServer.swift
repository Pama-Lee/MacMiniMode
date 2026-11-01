import Foundation
import Darwin

final class ControlServer: @unchecked Sendable {
    private let fd: Int32
    private let path: String
    private let handler: (ControlRequest, UInt32) -> ControlResponse
    init(path: String, handler: @escaping (ControlRequest, UInt32) -> ControlResponse) throws {
        self.path = path
        self.handler = handler
        let directory = URL(fileURLWithPath: path).deletingLastPathComponent().path
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o755])
        // Only remove a stale socket, never an arbitrary file or symbolic link.
        var existing = stat()
        if lstat(path, &existing) == 0 {
            guard (existing.st_mode & S_IFMT) == S_IFSOCK, existing.st_uid == geteuid() else { throw ControlFailure("unsafe_socket_path") }
            let probe = socket(AF_UNIX, SOCK_STREAM, 0)
            var addr = try ControlSocket.address(path)
            let connected = withUnsafePointer(to: &addr) { p in p.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(probe, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) == 0
            }}
            close(probe)
            guard !connected else { throw ControlFailure("service_already_running") }
            unlink(path)
        }
        fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw ControlFailure("socket_creation_failed") }
        var addr = try ControlSocket.address(path)
        let result = withUnsafePointer(to: &addr) { p in p.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
        }}
        guard result == 0, chmod(path, 0o666) == 0, listen(fd, 16) == 0 else {
            close(fd); throw ControlFailure("socket_bind_failed")
        }
    }
    func start() {
        DispatchQueue.global(qos: .utility).async { [self] in
            while true {
                let client = accept(fd, nil, nil)
                if client < 0 { if errno == EINTR { continue }; break }
                // Serial, bounded reads prevent an unbounded worker/thread queue.
                ControlSocket.configure(client)
                defer { close(client) }
                do {
                    var uid: uid_t = 0; var gid: gid_t = 0
                    guard getpeereid(client, &uid, &gid) == 0, uid == 0 || uid >= 500 else { throw ControlFailure("permission_denied") }
                    let request = try JSONDecoder().decode(ControlRequest.self, from: ControlSocket.read(client))
                    let response = DispatchQueue.main.sync { handler(request, uid) }
                    try ControlSocket.send(ControlWire.encoder().encode(response), fd: client)
                } catch {
                    let response = ControlResponse(ok: false, saved: false, applied: false, error: String(describing: error))
                    if let data = try? ControlWire.encoder().encode(response) { try? ControlSocket.send(data, fd: client) }
                }
            }
        }
    }
}
