// 退出前确认后台已停止防休眠；不把「收到关闭请求」当作「已恢复睡眠」。

import Foundation
import CoreServices
import IOKit
import IOKit.pwr_mgt
import notify

@MainActor
final class QuitController {
    private let requestStop: () -> Void
    private let hasStopped: () -> Bool
    private let timeout: TimeInterval
    private let interval: TimeInterval
    private(set) var pending = false

    init(requestStop: @escaping () -> Void, hasStopped: @escaping () -> Bool,
         timeout: TimeInterval = 5, interval: TimeInterval = 0.1) {
        self.requestStop = requestStop
        self.hasStopped = hasStopped
        self.timeout = timeout
        self.interval = interval
    }

    func begin(completion: @escaping (Bool) -> Void) {
        guard !pending else { return }
        pending = true
        requestStop()
        let deadline = DispatchTime.now() + timeout
        // AppKit 必须先收到 terminateLater，再收到退出结果。
        DispatchQueue.main.async { self.poll(until: deadline, completion: completion) }
    }

    private func poll(until deadline: DispatchTime, completion: @escaping (Bool) -> Void) {
        if hasStopped() {
            pending = false
            completion(true)
        } else if DispatchTime.now() >= deadline {
            pending = false
            completion(false)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + interval) {
                self.poll(until: deadline, completion: completion)
            }
        }
    }
}

enum QuitPolicy {
    static func isSystemQuit(_ event: NSAppleEventDescriptor?) -> Bool {
        guard event?.eventID == kAEQuitApplication,
              let reason = event?.paramDescriptor(forKeyword: AEKeyword(kAEQuitReason))?.enumCodeValue else { return false }
        return [kAEQuitAll, kAEShutDown, kAERestart, kAEReallyLogOut].contains(reason)
    }

    static func isStopped(prefix: String) -> Bool {
        var token: Int32 = 0
        guard notify_register_check("\(prefix).state", &token) == NOTIFY_STATUS_OK else { return false }
        defer { notify_cancel(token) }
        var mode: UInt64 = 0
        guard notify_get_state(token, &mode) == NOTIFY_STATUS_OK, mode == 2,
              let saved = try? String(contentsOfFile: "/var/db/macmini-mode", encoding: .utf8),
              saved.trimmingCharacters(in: .whitespacesAndNewlines) == "off",
              sleepDisabled() == false else { return false }
        return assertionsReleased() == true
    }

    private static func sleepDisabled() -> Bool? {
        let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard root != 0 else { return nil }
        defer { IOObjectRelease(root) }
        return IORegistryEntryCreateCFProperty(root, "SleepDisabled" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? Bool
    }

    static func assertionsReleased() -> Bool? {
        var assertions: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&assertions) == kIOReturnSuccess,
              let byProcess = assertions?.takeRetainedValue() as? [AnyHashable: Any] else { return nil }
        return assertionsReleased(in: byProcess)
    }

    static func assertionsReleased(in byProcess: [AnyHashable: Any]) -> Bool? {
        for value in byProcess.values {
            guard let assertions = value as? [[String: Any]] else { return nil }
            for assertion in assertions {
                guard assertion[kIOPMAssertionNameKey as String] as? String == "Mac mini Mode",
                      assertion[kIOPMAssertionTypeKey as String] as? String == "PreventSystemSleep" else { continue }
                // 无法读取断言状态时保留界面，不能误报退出成功。
                guard let level = assertion[kIOPMAssertionLevelKey as String] as? Int else { return nil }
                if level != Int(kIOPMAssertionLevelOff) { return false }
            }
        }
        return true
    }
}
