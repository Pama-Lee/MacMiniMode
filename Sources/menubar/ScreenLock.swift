// 在当前用户的图形会话锁屏，不启动屏保，也不修改睡眠或密码设置。

import CoreGraphics
import Darwin
import Foundation

enum ScreenSessionState { case unlocked, locked, inactive, unknown }

final class ScreenLock {
    private typealias LockFunction = @convention(c) () -> Void
    private let handle: UnsafeMutableRawPointer?
    private let lockFunction: LockFunction?

    init() {
        // macOS 没有公开的立即锁屏 API。运行时绑定，接口缺失时明确禁用此功能。
        handle = dlopen("/System/Library/PrivateFrameworks/login.framework/login", RTLD_NOW | RTLD_LOCAL)
        lockFunction = handle.flatMap { dlsym($0, "SACLockScreenImmediate") }
            .map { unsafeBitCast($0, to: LockFunction.self) }
    }

    deinit { if let handle { dlclose(handle) } }

    var available: Bool { lockFunction != nil }

    func request() -> Bool {
        guard let lockFunction, Self.sessionState() == .unlocked else { return false }
        // 此函数没有成功返回值；由调用者观察实际锁屏状态，不能把发出请求当成已锁屏。
        lockFunction()
        return true
    }

    static func sessionState() -> ScreenSessionState {
        sessionState(in: CGSessionCopyCurrentDictionary() as? [String: Any], uid: getuid())
    }

    static func sessionState(in session: [String: Any]?, uid: uid_t) -> ScreenSessionState {
        guard let session,
              let user = session[kCGSessionUserIDKey as String] as? UInt32,
              let onConsole = session[kCGSessionOnConsoleKey as String] as? Bool else { return .unknown }
        // 快速用户切换后，本用户的后台菜单栏程序不能锁住另一位用户。
        guard user == uid, onConsole else { return .inactive }
        if let value = session["CGSSessionScreenIsLocked"] {
            guard let locked = value as? Bool else { return .unknown }
            return locked ? .locked : .unlocked
        }
        // 活跃且未锁定的图形会话通常不提供这个键。
        return .unlocked
    }
}
