// macmini-menubar — 菜单栏图标，显示 Mac mini 模式当前状态，并可手动切换模式（不需要 root）。
// 检查更新的逻辑在 Updater.swift，体检窗口在 Health.swift。
// 切换通过 Darwin 通知发给 macmini-moded，由它去改系统设置。

import AppKit
import IOKit
import IOKit.ps
import notify

let logPath = "/var/log/macmini-mode.log"
let notifyPrefix = "com.macminimode"

// 界面和日志跟随系统首选语言：中文环境用中文，其余用英文。
let isChinese = Locale.preferredLanguages.first?.hasPrefix("zh") ?? false
func L(_ zh: String, _ en: String) -> String { isChinese ? zh : en }

// 与 macmini-moded 里 Mode 的 rawValue / name 对应。
let modes: [(name: String, title: String)] = [
    ("auto", L("自动（插电开启，拔电关闭）", "Automatic (on when plugged in)")),
    ("on", L("始终开启（用电池也不睡眠）", "Always On (stays awake on battery)")),
    ("off", L("始终关闭", "Always Off")),
]

func rootDomainFlag(_ key: String) -> Bool {
    let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
    guard root != 0 else { return false }
    defer { IOObjectRelease(root) }
    let value = IORegistryEntryCreateCFProperty(root, key as CFString, kCFAllocatorDefault, 0)?
        .takeRetainedValue()
    return (value as? Bool) ?? false
}

func powerDescription() -> String {
    let info = IOPSCopyPowerSourcesInfo().takeRetainedValue()
    let type = IOPSGetProvidingPowerSourceType(info).takeUnretainedValue() as String
    var text = type == kIOPSACPowerValue ? L("电源适配器", "Power Adapter") : L("电池", "Battery")
    let sources = IOPSCopyPowerSourcesList(info).takeRetainedValue() as [CFTypeRef]
    for source in sources {
        guard let desc = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
              desc[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
              let percent = desc[kIOPSCurrentCapacityKey] as? Int else { continue }
        text += " · \(percent)%"
        break
    }
    return text
}

func daemonRunning() -> Bool {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
    task.arguments = ["-x", "macmini-moded"]
    task.standardOutput = FileHandle.nullDevice
    do {
        try task.run()
        task.waitUntilExit()
    } catch {
        return false
    }
    return task.terminationStatus == 0
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let modeItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    let powerItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    let daemonItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    var switchItems: [NSMenuItem] = []
    let updater = Updater()
    let health = HealthWindowController()
    let installItem = NSMenuItem(title: "", action: #selector(installUpdate), keyEquivalent: "")
    let autoCheckItem = NSMenuItem(title: L("自动检查更新", "Check for Updates Automatically"), action: #selector(toggleAutoCheck), keyEquivalent: "")
    var stateToken: Int32 = 0
    var timer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        for item in [modeItem, powerItem, daemonItem] {
            item.isEnabled = false
            menu.addItem(item)
        }
        menu.addItem(.separator())
        for (index, mode) in modes.enumerated() {
            let item = NSMenuItem(title: mode.title, action: #selector(selectMode(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            switchItems.append(item)
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let healthItem = NSMenuItem(title: L("体检…", "Health Check…"), action: #selector(openHealth), keyEquivalent: "")
        healthItem.target = self
        menu.addItem(healthItem)
        let logItem = NSMenuItem(title: L("查看日志", "View Log"), action: #selector(openLog), keyEquivalent: "l")
        logItem.target = self
        menu.addItem(logItem)
        menu.addItem(.separator())
        installItem.target = self
        installItem.isHidden = true
        menu.addItem(installItem)
        let checkItem = NSMenuItem(title: L("检查更新…", "Check for Updates…"), action: #selector(checkForUpdates), keyEquivalent: "")
        checkItem.target = self
        menu.addItem(checkItem)
        autoCheckItem.target = self
        menu.addItem(autoCheckItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: L("退出", "Quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu

        updater.onChange = { [weak self] in self?.refresh() }
        updater.start()
        if CommandLine.arguments.contains("--health-check") { health.show() }

        notify_register_dispatch("\(notifyPrefix).state", &stateToken, .main) { [weak self] _ in
            self?.refreshSoon()
        }

        let context = Unmanaged.passUnretained(self).toOpaque()
        if let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            Unmanaged<AppDelegate>.fromOpaque(context).takeUnretainedValue().refreshSoon()
        }, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        }
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.refresh() }
        refresh()
    }

    func menuWillOpen(_ menu: NSMenu) {
        refresh()
    }

    // 守护进程收到通知后才去改设置，立即读一次，稍等再读一次。
    func refreshSoon() {
        refresh()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.refresh() }
    }

    func refresh() {
        let enabled = rootDomainFlag("SleepDisabled")
        let running = daemonRunning()
        var rawMode: UInt64 = 0
        notify_get_state(stateToken, &rawMode)

        let symbol = !running ? "exclamationmark.triangle" : (enabled ? "macmini.fill" : "laptopcomputer")
        let name = L("Mac mini 模式", "Mac mini Mode")
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: name)
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.toolTip = name + L("：", ": ") + (enabled ? L("开启", "On") : L("关闭", "Off"))

        modeItem.title = name + L("：", ": ") + (enabled
            ? L("开启（合盖继续运行）", "On (keeps running with the lid closed)")
            : L("关闭（正常睡眠）", "Off (sleeps normally)"))
        powerItem.title = L("供电：", "Power: ") + powerDescription()
        daemonItem.title = L("后台服务：", "Background service: ") + (running ? L("运行中", "Running") : L("未运行", "Not running"))
        for item in switchItems {
            item.isEnabled = running
            item.state = running && item.tag == Int(rawMode) ? .on : .off
        }
        installItem.isHidden = updater.ready == nil
        if let ready = updater.ready {
            installItem.title = L("安装新版本 \(ready.version)…", "Install Version \(ready.version)…")
        }
        autoCheckItem.state = updater.autoCheck ? .on : .off
    }

    @objc func checkForUpdates() {
        updater.check(manual: true)
    }

    @objc func installUpdate() {
        updater.installReady()
    }

    @objc func toggleAutoCheck() {
        updater.autoCheck.toggle()
        refresh()
    }

    @objc func selectMode(_ sender: NSMenuItem) {
        notify_post("\(notifyPrefix).set-\(modes[sender.tag].name)")
    }

    @objc func openHealth() {
        health.show()
    }

    @objc func openLog() {
        NSWorkspace.shared.open(URL(fileURLWithPath: logPath))
    }
}

// 命令行的 `macminimode check` 走这里：把体检结果和诊断信息打印出来就退出，不启动界面。
if CommandLine.arguments.contains("--print-diagnostics") {
    print(Health.report(Health.run()))
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
