// macmini-moded — 插电时禁止睡眠（合盖也继续跑），拔电时恢复正常睡眠。
// 以 root 身份作为 LaunchDaemon 运行；--dry-run 只打印不执行。
// 测试用参数（仅 --dry-run 下生效）：--simulate-power=ac|battery、--simulate-battery=<百分比>；--log-file=<路径> 把日志写到指定文件。
// 菜单栏通过 Darwin 通知切换模式：<prefix>.set-auto / set-on / set-off，当前模式发布在 <prefix>.state。

import Foundation
import IOKit
import IOKit.ps
import IOKit.pwr_mgt
import notify

let dryRun = CommandLine.arguments.contains("--dry-run")
let notifyPrefix = dryRun ? "com.macminimode.dryrun" : "com.macminimode"
let modeFile = "/var/db/macmini-mode"
setvbuf(stdout, nil, _IOLBF, 0)

func argValue(_ name: String) -> String? {
    CommandLine.arguments.first { $0.hasPrefix(name + "=") }.map { String($0.dropFirst(name.count + 1)) }
}
let logFile = argValue("--log-file") ?? "/var/log/macmini-mode.log"
let logToFile = !dryRun || argValue("--log-file") != nil
let simulatedPower = dryRun ? argValue("--simulate-power") : nil
let simulatedBattery = dryRun ? argValue("--simulate-battery").flatMap { Int($0) } : nil

// 界面和日志跟随系统首选语言：中文环境用中文，其余用英文。
let isChinese = Locale.preferredLanguages.first?.hasPrefix("zh") ?? false
func L(_ zh: String, _ en: String) -> String { isChinese ? zh : en }

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
        case .auto: return L("自动", "Automatic")
        case .on: return L("始终开启", "Always On")
        case .off: return L("始终关闭", "Always Off")
        }
    }
}

enum State {
    nonisolated(unsafe) static var mode = Mode.auto
    nonisolated(unsafe) static var applied: Bool?
    nonisolated(unsafe) static var stateToken: Int32 = 0
    nonisolated(unsafe) static var assertion: IOPMAssertionID = 0
    nonisolated(unsafe) static var overrides = 0
    nonisolated(unsafe) static var burstStart = Date.distantPast
    nonisolated(unsafe) static var burst = 0
    nonisolated(unsafe) static var overridesToken: Int32 = 0
    nonisolated(unsafe) static var lowBattery = false
}

func log(_ message: String) {
    let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
    guard logToFile else {
        print(line, terminator: "")
        return
    }
    // 每写一行都重新打开文件：清理类软件会删掉 /var/log 下的文件，这样删了也能自己重建。
    var info = stat()
    if stat(logFile, &info) == 0, info.st_size > 1_000_000 {
        rename(logFile, logFile + ".1")
    }
    let fd = open(logFile, O_WRONLY | O_APPEND | O_CREAT, 0o644)
    guard fd >= 0 else { return }
    _ = line.withCString { write(fd, $0, strlen($0)) }
    close(fd)
}

func onACPower() -> Bool {
    if let simulatedPower { return simulatedPower == "ac" }
    let info = IOPSCopyPowerSourcesInfo().takeRetainedValue()
    let type = IOPSGetProvidingPowerSourceType(info).takeUnretainedValue() as String
    return type == kIOPSACPowerValue
}

func batteryPercent() -> Int? {
    if let simulatedBattery { return simulatedBattery }
    let info = IOPSCopyPowerSourcesInfo().takeRetainedValue()
    for source in IOPSCopyPowerSourcesList(info).takeRetainedValue() as [CFTypeRef] {
        guard let desc = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
              desc[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
              let percent = desc[kIOPSCurrentCapacityKey] as? Int else { continue }
        return percent
    }
    return nil
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
        log("pmset \(args.joined(separator: " ")) \(L("启动失败", "failed to launch")): \(error.localizedDescription)")
        return false
    }
    if task.terminationStatus != 0 {
        log("pmset \(args.joined(separator: " ")) \(L("退出码", "exited with status")) \(task.terminationStatus)")
        return false
    }
    return true
}

// 「始终开启」时用电池硬撑，电量降到 10% 就放行睡眠，免得直接断电。回到 15% 以上或接上电源后恢复。
func updateLowBattery() {
    let was = State.lowBattery
    if State.mode == .on, !onACPower(), let percent = batteryPercent() {
        if percent <= 10 {
            State.lowBattery = true
        } else if percent >= 15 {
            State.lowBattery = false
        }
    } else {
        State.lowBattery = false
    }
    // 是切换模式导致的解除就不用记了，模式切换本身已经有一行日志。
    guard State.lowBattery != was, State.mode == .on else { return }
    log(State.lowBattery
        ? L("电量降到 10%，暂时放行睡眠，免得直接断电", "Battery at 10%: allowing sleep for now to avoid a hard power-off")
        : L("电量或供电已恢复，低电量保护解除", "Battery or power is back: low-battery protection lifted"))
}

func wantsMacMiniMode() -> Bool {
    switch State.mode {
    case .auto: return onACPower()
    case .on: return !State.lowBattery
    case .off: return false
    }
}

// 第二道保险。disablesleep 管的是合盖睡眠，但别的程序改电源设置时会把它清掉；
// 这个断言管空闲睡眠，在 disablesleep 被清掉到我们补回去之间，机器不会因为没人操作而睡着。
func holdAssertion(_ on: Bool) {
    if on, State.assertion == 0 {
        var id: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(
            "PreventSystemSleep" as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "Mac mini Mode" as CFString, &id)
        if result == kIOReturnSuccess {
            State.assertion = id
        } else {
            log(L("创建防睡眠断言失败", "Could not create the sleep assertion") + " (\(result))")
        }
    } else if !on, State.assertion != 0 {
        IOPMAssertionRelease(State.assertion)
        State.assertion = 0
    }
}

func sync() {
    updateLowBattery()
    let want = wantsMacMiniMode()
    holdAssertion(want)
    // 以系统里的真实值为准，别的工具或手动 pmset 改掉了也要纠正回来。
    let current = dryRun ? State.applied : rootDomainFlag("SleepDisabled")
    guard want != current else {
        State.applied = want
        return
    }
    let overridden = State.applied == want
    if overridden {
        // 万一对方也是一被改就立刻改回去，两边会无休止地拉锯。每 10 秒最多纠正 5 次，其余的留给下一轮。
        let now = Date()
        if now.timeIntervalSince(State.burstStart) > 10 {
            State.burstStart = now
            State.burst = 0
        }
        State.burst += 1
        guard State.burst <= 5 else { return }
    }
    guard pmset(["-a", "disablesleep", want ? "1" : "0"]) else { return }
    State.applied = want
    if overridden {
        // 有的机器上每隔几分钟就会被改一次，只记前几次和之后每 50 次，免得日志刷屏。
        State.overrides += 1
        notify_set_state(State.overridesToken, UInt64(State.overrides))
        if State.overrides <= 3 || State.overrides % 50 == 0 {
            log(L("睡眠设置被其他程序改动，已恢复为 disablesleep \(want ? 1 : 0)（第 \(State.overrides) 次）",
                  "Sleep setting was changed by another program; restored disablesleep \(want ? 1 : 0) (#\(State.overrides))"))
        }
        return
    }
    let reason: String
    if State.mode == .auto {
        reason = want ? L("接入电源", "On AC power") : L("使用电池", "On battery")
    } else if State.mode == .on, State.lowBattery {
        reason = L("电量不足", "Battery low")
    } else {
        reason = State.mode.label
    }
    let outcome = want
        ? L("Mac mini 模式开启 (disablesleep 1)", "Mac mini mode on (disablesleep 1)")
        : L("Mac mini 模式关闭 (disablesleep 0)", "Mac mini mode off (disablesleep 0)")
    log("\(reason) → \(outcome)")

    // 清掉 disablesleep 并不会让已经合盖的机器自己睡下去，这里补一脚，免得在包里发热。
    // AppleClamshellCausesSleep 是内核自己的判断：接着外接显示器时为 No，就不打扰。
    if !want {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            guard !wantsMacMiniMode(),
                  rootDomainFlag("AppleClamshellState"),
                  rootDomainFlag("AppleClamshellCausesSleep") else { return }
            log(L("已合盖且允许睡眠 → 立即睡眠", "Lid closed and sleep allowed → sleeping now"))
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
    log(L("模式切换为：", "Mode set to: ") + mode.label)
    if !dryRun {
        do {
            try mode.name.write(toFile: modeFile, atomically: true, encoding: .utf8)
        } catch {
            log(L("保存模式失败", "Failed to save mode") + ": \(error.localizedDescription)")
        }
    }
    publishMode()
    sync()
}

func shutdown(_ name: String) {
    log(L("收到 \(name)，恢复 disablesleep 0 后退出", "Received \(name), restoring disablesleep 0 and exiting"))
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
    log(L("无法注册电源变化通知", "Could not register for power source notifications"))
    exit(1)
}
CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .defaultMode)

if !dryRun,
   let saved = try? String(contentsOfFile: modeFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
   let mode = Mode.allCases.first(where: { $0.name == saved }) {
    State.mode = mode
}

notify_register_check("\(notifyPrefix).state", &State.stateToken)
// 菜单栏的体检窗口从这里读「被其他程序改动了多少次」。
notify_register_check("\(notifyPrefix).overrides", &State.overridesToken)
notify_set_state(State.overridesToken, 0)
var commandTokens: [Int32] = []
for mode in Mode.allCases {
    var token: Int32 = 0
    notify_register_dispatch("\(notifyPrefix).set-\(mode.name)", &token, .main) { _ in setMode(mode) }
    commandTokens.append(token)
}

// 别的程序改电源设置时会顺带清掉 disablesleep（实测有机器每 10 分钟被清一次）。
// 系统在设置变化时会发这个通知，但通知到达时新值还没写进内核，所以收到后隔一小会儿再对几次账。
var prefsToken: Int32 = 0
notify_register_dispatch("com.apple.system.powermanagement.prefschange", &prefsToken, .main) { _ in
    for delay in [0, 0.2, 1, 2.5] {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { sync() }
    }
}

// 兜底：万一漏掉通知（比如睡眠期间拔电），每 5 秒对一次账。只读一个系统属性，开销可以忽略。
let timer = DispatchSource.makeTimerSource(queue: .main)
timer.schedule(deadline: .now() + 5, repeating: 5)
timer.setEventHandler { sync() }
timer.resume()

// 只记录，不据此自动睡眠：过热保护交给系统自己，这里留痕方便事后排查。
var thermalWasHigh = false
NotificationCenter.default.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main) { _ in
    let state = ProcessInfo.processInfo.thermalState
    let high = state == .serious || state == .critical
    if high {
        log(state == .critical
            ? L("机器温度过高（危险级别）", "Thermal state: critical")
            : L("机器温度偏高", "Thermal state: serious"))
    } else if thermalWasHigh {
        log(L("机器温度恢复正常", "Thermal state back to normal"))
    }
    thermalWasHigh = high
}

log(L("macmini-moded 启动", "macmini-moded started") + (dryRun ? " (dry-run)" : "")
    + L("，模式：", ", mode: ") + State.mode.label)
publishMode()
sync()
CFRunLoopRun()
