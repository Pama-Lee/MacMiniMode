// 监听真实合盖事件，合盖不休眠时也能工作。仅在用户启用开盖锁屏时运行。

import Foundation
import IOKit

final class LidMonitor {
    // IOPM.h 的 kIOPMMessageClamshellStateChange 宏不能导入 Swift：
    // iokit_family_msg(sub_iokit_powermanagement, 0x100) = (0x38 << 26) | (13 << 14) | 0x100。
    static let stateChangedMessage: UInt32 = 0xe0034100
    var onChange: (Bool?) -> Void = { _ in }
    private var root: io_service_t = 0
    private var notification: io_object_t = 0
    private var port: IONotificationPortRef?
    private var timer: Timer?

    deinit { stop() }

    static func currentClosed() -> Bool? {
        let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard root != 0 else { return nil }
        defer { IOObjectRelease(root) }
        return IORegistryEntryCreateCFProperty(root, "AppleClamshellState" as CFString,
                                              kCFAllocatorDefault, 0)?.takeRetainedValue() as? Bool
    }

    // 消息参数本身就是位域，开盖时可能为 nil（值 0），不能把它当成缺失消息。
    static func closed(message: UInt32, argument: UnsafeMutableRawPointer?) -> Bool? {
        guard message == stateChangedMessage else { return nil }
        return UInt(bitPattern: argument) & 1 != 0
    }

    @discardableResult
    func start() -> Bool {
        stop()
        guard let initial = Self.currentClosed() else { return false }
        root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard root != 0, let created = IONotificationPortCreate(kIOMainPortDefault) else {
            stop()
            return false
        }
        port = created
        let result = IOServiceAddInterestNotification(created, root, kIOGeneralInterest, {
            context, _, message, argument in
            guard let context, let closed = LidMonitor.closed(message: message, argument: argument) else { return }
            let monitor = Unmanaged<LidMonitor>.fromOpaque(context).takeUnretainedValue()
            monitor.onChange(closed)
        }, Unmanaged.passUnretained(self).toOpaque(), &notification)
        guard result == kIOReturnSuccess,
              let source = IONotificationPortGetRunLoopSource(created)?.takeUnretainedValue() else {
            stop()
            return false
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        // 先建立基线；初次启动时盖子已经打开不应锁屏。
        onChange(initial)
        // 通知注册期间或从正常睡眠恢复时可能漏掉变化，读取状态作为补救。
        onChange(Self.currentClosed())
        let fallback = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.onChange(Self.currentClosed())
        }
        fallback.tolerance = 0.1
        RunLoop.main.add(fallback, forMode: .common)
        timer = fallback
        return true
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if notification != 0 { IOObjectRelease(notification); notification = 0 }
        if let port {
            if let source = IONotificationPortGetRunLoopSource(port)?.takeUnretainedValue() {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            }
            IONotificationPortDestroy(port)
        }
        port = nil
        if root != 0 { IOObjectRelease(root); root = 0 }
    }
}
