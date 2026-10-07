// macmini-moded — 插电时禁止睡眠（合盖也继续跑），拔电时恢复正常睡眠。
// 以 root 身份作为 LaunchDaemon 运行；--dry-run 只打印不执行。
// 菜单栏通过 Darwin 通知切换模式：<prefix>.set-auto / set-on / set-off，当前模式发布在 <prefix>.state。

import Foundation
import IOKit
import IOKit.ps
import notify

let dryRun = CommandLine.arguments.contains("--dry-run")
let notifyPrefix = dryRun ? "com.macminimode.dryrun" : "com.macminimode"
let modeFile = "/var/db/macmini-mode"
setvbuf(stdout, nil, _IOLBF, 0)

enum Mode: UInt64, CaseIterable {
    case auto = 0, on = 1, off = 2

    var name: String {
        switch self {
        case .auto: return "auto"
        case .on: return "on"
        case .off: return "off"
        }
    }

    var label: String {
        switch self {
        case .auto: return "自动"
        case .on: return "始终开启"
        case .off: return "始终关闭"
        }
    }
}

enum State {
    nonisolated(unsafe) static var mode = Mode.auto
    nonisolated(unsafe) static var applied: Bool?
    nonisolated(unsafe) static var stateToken: Int32 = 0
}

func log(_ message: String) {
    let stamp = ISO8601DateFormatter().string(from: Date())
    print("\(stamp) \(message)")
}

func onACPower() -> Bool {
    let info = IOPSCopyPowerSourcesInfo().takeRetainedValue()
    let type = IOPSGetProvidingPowerSourceType(info).takeUnretainedValue() as String
    return type == kIOPSACPowerValue
}

func rootDomainFlag(_ key: String) -> Bool {
    let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
    guard root != 0 else { return false }
    defer { IOObjectRelease(root) }
    let value = IORegistryEntryCreateCFProperty(root, key as CFString, kCFAllocatorDefault, 0)?
        .takeRetainedValue()
    return (value as? Bool) ?? false
}

@discardableResult
func pmset(_ args: [String]) -> Bool {
    if dryRun {
        log("[dry-run] pmset \(args.joined(separator: " "))")
        return true
    }
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
    task.arguments = args
    do {
        try task.run()
        task.waitUntilExit()
    } catch {
        log("pmset \(args.joined(separator: " ")) 启动失败: \(error.localizedDescription)")
        return false
    }
    if task.terminationStatus != 0 {
        log("pmset \(args.joined(separator: " ")) 退出码 \(task.terminationStatus)")
        return false
    }
    return true
}

func wantsMacMiniMode() -> Bool {
    switch State.mode {
    case .auto: return onACPower()
    case .on: return true
    case .off: return false
    }
}

func sync() {
    let want = wantsMacMiniMode()
    // 以系统里的真实值为准，别的工具或手动 pmset 改掉了也能在下一轮对账时纠正回来。
    let current = dryRun ? State.applied : rootDomainFlag("SleepDisabled")
    guard want != current else { return }
    guard pmset(["-a", "disablesleep", want ? "1" : "0"]) else { return }
    State.applied = want
    let reason = State.mode == .auto ? (want ? "接入电源" : "使用电池") : State.mode.label
    log("\(reason) → Mac mini 模式\(want ? "开启 (disablesleep 1)" : "关闭 (disablesleep 0)")")

    // 清掉 disablesleep 并不会让已经合盖的机器自己睡下去，这里补一脚，免得在包里发热。
    // AppleClamshellCausesSleep 是内核自己的判断：接着外接显示器时为 No，就不打扰。
    if !want {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            guard !wantsMacMiniMode(),
                  rootDomainFlag("AppleClamshellState"),
                  rootDomainFlag("AppleClamshellCausesSleep") else { return }
            log("已合盖且允许睡眠 → 立即睡眠")
            pmset(["sleepnow"])
        }
    }
}

func publishMode() {
    notify_set_state(State.stateToken, State.mode.rawValue)
    notify_post("\(notifyPrefix).state")
}

func setMode(_ mode: Mode) {
    guard mode != State.mode else { return }
    State.mode = mode
    log("模式切换为：\(mode.label)")
    if !dryRun {
        do {
            try mode.name.write(toFile: modeFile, atomically: true, encoding: .utf8)
        } catch {
            log("保存模式失败: \(error.localizedDescription)")
        }
    }
    publishMode()
    sync()
}

func shutdown(_ name: String) {
    log("收到 \(name)，恢复 disablesleep 0 后退出")
    pmset(["-a", "disablesleep", "0"])
    exit(0)
}

var signalSources: [DispatchSourceSignal] = []
for (sig, name) in [(SIGTERM, "SIGTERM"), (SIGINT, "SIGINT")] {
    signal(sig, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
    source.setEventHandler { shutdown(name) }
    source.resume()
    signalSources.append(source)
}

guard let runLoopSource = IOPSNotificationCreateRunLoopSource({ _ in sync() }, nil)?.takeRetainedValue() else {
    log("无法注册电源变化通知")
    exit(1)
}
CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .defaultMode)

if !dryRun,
   let saved = try? String(contentsOfFile: modeFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
   let mode = Mode.allCases.first(where: { $0.name == saved }) {
    State.mode = mode
}

notify_register_check("\(notifyPrefix).state", &State.stateToken)
var commandTokens: [Int32] = []
for mode in Mode.allCases {
    var token: Int32 = 0
    notify_register_dispatch("\(notifyPrefix).set-\(mode.name)", &token, .main) { _ in setMode(mode) }
    commandTokens.append(token)
}

// 兜底：万一漏掉一次通知（比如睡眠期间拔电），每分钟对一次账。
let timer = DispatchSource.makeTimerSource(queue: .main)
timer.schedule(deadline: .now() + 60, repeating: 60)
timer.setEventHandler { sync() }
timer.resume()

log("macmini-moded 启动\(dryRun ? "（dry-run）" : "")，模式：\(State.mode.label)")
publishMode()
sync()
CFRunLoopRun()
