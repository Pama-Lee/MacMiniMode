// 体检：把「当 Mac mini 用」需要的几样东西逐项查一遍，并能把诊断信息复制出来。
// 全部是只读检查，不改任何设置。

import AppKit
import notify

struct HealthCheck {
    enum Level { case ok, warn, info }
    let level: Level
    let title: String
    let detail: String
}

enum Health {
    static func shell(_ command: String) -> (status: Int32, output: String) {
        let task = Process()
        let pipe = Pipe()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", command]
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do { try task.run() } catch { return (-1, "") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        return (task.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }

    static func notifyState(_ name: String) -> UInt64 {
        var token: Int32 = 0
        var value: UInt64 = 0
        guard notify_register_check(name, &token) == NOTIFY_STATUS_OK else { return 0 }
        notify_get_state(token, &value)
        notify_cancel(token)
        return value
    }

    static func portOpen(_ port: Int) -> Bool {
        shell("/usr/bin/nc -z -G 1 127.0.0.1 \(port)").status == 0
    }

    /// 会跑几个系统命令，放在后台线程调用。
    static func run() -> [HealthCheck] {
        var checks: [HealthCheck] = []
        let running = daemonRunning()
        checks.append(running
            ? HealthCheck(level: .ok, title: L("后台服务运行中", "Background service is running"), detail: "")
            : HealthCheck(level: .warn, title: L("后台服务没有运行", "Background service is not running"),
                          detail: L("重新安装一次即可恢复。", "Reinstalling the app will bring it back.")))

        let awake = rootDomainFlag("SleepDisabled")
        checks.append(awake
            ? HealthCheck(level: .ok, title: L("Mac mini 模式已开启", "Mac mini Mode is on"),
                          detail: L("现在合上盖子，电脑会继续运行。", "Close the lid now and the Mac keeps running."))
            : HealthCheck(level: .info, title: L("Mac mini 模式当前关闭", "Mac mini Mode is currently off"),
                          detail: L("没插电，或设定为「始终关闭」。现在合盖会正常睡眠。", "On battery, or set to Always Off. Closing the lid will sleep as usual.")))

        let overrides = notifyState("com.macminimode.overrides")
        checks.append(overrides == 0
            ? HealthCheck(level: .ok, title: L("没有其他软件改动电源设置", "No other software has changed power settings"), detail: "")
            : HealthCheck(level: .info, title: L("其他软件改动过电源设置 \(overrides) 次，都已自动恢复", "Other software changed power settings \(overrides) times; all restored"),
                          detail: L("常见于远程桌面、清理优化类软件，不影响使用。", "Usually a remote desktop or cleaner app. Nothing to do.")))

        checks.append(portOpen(22)
            ? HealthCheck(level: .ok, title: L("远程登录（SSH）已开启", "Remote Login (SSH) is on"), detail: "")
            : HealthCheck(level: .info, title: L("远程登录（SSH）未开启", "Remote Login (SSH) is off"),
                          detail: L("需要的话，到 系统设置 → 通用 → 共享 打开「远程登录」。", "If you need it, turn on Remote Login in System Settings → General → Sharing.")))
        checks.append(portOpen(5900)
            ? HealthCheck(level: .ok, title: L("屏幕共享已开启", "Screen Sharing is on"), detail: "")
            : HealthCheck(level: .info, title: L("屏幕共享未开启", "Screen Sharing is off"),
                          detail: L("需要远程看桌面的话，到 系统设置 → 通用 → 共享 打开「屏幕共享」。", "To view the desktop remotely, turn on Screen Sharing in System Settings → General → Sharing.")))

        let battery = shell("/usr/bin/pmset -g ps").output
        if let range = battery.range(of: #"[0-9]+%"#, options: .regularExpression),
           let percent = Int(battery[range].dropLast()) {
            let plugged = battery.contains("AC Power")
            checks.append(plugged && percent >= 95
                ? HealthCheck(level: .warn, title: L("电量 \(percent)%，一直充到接近满电", "Battery at \(percent)% and held near full"),
                              detail: L("长期插电建议到 系统设置 → 电池 把充电上限设为 80%，对电池更好。", "If it stays plugged in, set the charge limit to 80% in System Settings → Battery."))
                : HealthCheck(level: .ok, title: L("电量 \(percent)%", "Battery at \(percent)%"), detail: ""))
        }

        if shell("/usr/bin/fdesetup status").output.contains("FileVault is On") {
            checks.append(HealthCheck(level: .info, title: L("已开启 FileVault", "FileVault is on"),
                                      detail: L("断电重启后，要先在这台电脑上输入一次密码，远程才连得上。", "After a power loss and restart, the Mac needs its password typed locally before you can connect remotely.")))
        }

        switch ProcessInfo.processInfo.thermalState {
        case .serious, .critical:
            checks.append(HealthCheck(level: .warn, title: L("机器温度偏高", "The Mac is running hot"),
                                      detail: L("合盖运行时把它放在通风的地方，最好竖起来放。", "Keep it somewhere ventilated when running with the lid closed, ideally upright.")))
        default:
            checks.append(HealthCheck(level: .ok, title: L("温度正常", "Temperature is normal"), detail: ""))
        }
        return checks
    }

    /// 给用户贴到反馈里的文本。只读取，不上传。
    static func report(_ checks: [HealthCheck]) -> String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let system = ProcessInfo.processInfo.operatingSystemVersionString
        let model = shell("/usr/sbin/sysctl -n hw.model").output.trimmingCharacters(in: .whitespacesAndNewlines)
        var lines = ["Mac mini Mode \(version) · macOS \(system) · \(model)",
                     ISO8601DateFormatter().string(from: Date()), ""]
        lines.append("[checks]")
        for check in checks {
            let mark = check.level == .ok ? "✓" : check.level == .warn ? "!" : "-"
            lines.append("\(mark) \(check.title)")
        }
        lines.append("\n[setting] mode=\(notifyState("com.macminimode.state")) (0 auto, 1 on, 2 off)")
        lines.append("\n[pmset]")
        lines.append(shell("/usr/bin/pmset -g | grep -E 'SleepDisabled|hibernatemode|standby |powernap| sleep |displaysleep|lidwake|womp' | cut -c1-110").output)
        lines.append("[assertions]")
        // 我们自己的那条放最前面，其余按进程去重，免得被同一个进程的十几条刷掉。
        lines.append(shell("/usr/bin/pmset -g assertions | grep 'pid ' | grep -E 'PreventSystemSleep|PreventUserIdleSystemSleep' | awk '/macmini-moded/ {print; next} !seen[$2]++ {rest[n++] = $0} END {for (i = 0; i < n && i < 8; i++) print rest[i]}' | cut -c1-150").output)
        lines.append("[sleep / wake, last 15]")
        lines.append(shell("/usr/bin/pmset -g log | grep -E '^[0-9-]+ [0-9:]+ [+-][0-9]+ (Sleep|Wake|DarkWake)  ' | tail -n 15 | cut -c1-170").output)
        lines.append("[service log, last 40]")
        lines.append(shell("/usr/bin/tail -n 40 /var/log/macmini-mode.log").output)
        return lines.joined(separator: "\n")
    }
}

final class HealthWindowController: NSObject {
    private var window: NSWindow?
    private let rows = NSStackView()
    private let copyButton = NSButton(title: "", target: nil, action: nil)
    private let refreshButton = NSButton(title: "", target: nil, action: nil)
    private var checks: [HealthCheck] = []

    func show() {
        if window == nil { build() }
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        refresh()
    }

    private func build() {
        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 12

        copyButton.title = L("复制诊断信息", "Copy Diagnostics")
        copyButton.target = self
        copyButton.action = #selector(copyReport)
        copyButton.bezelStyle = .rounded
        refreshButton.title = L("重新检查", "Check Again")
        refreshButton.target = self
        refreshButton.action = #selector(refresh)
        refreshButton.bezelStyle = .rounded

        let note = NSTextField(wrappingLabelWithString: L(
            "反馈问题时，点「复制诊断信息」把结果贴给开发者。内容只会放进剪贴板，不会上传。",
            "When reporting a problem, use Copy Diagnostics and paste the result. It only goes to your clipboard; nothing is uploaded."))
        note.font = .systemFont(ofSize: 11)
        note.textColor = .secondaryLabelColor
        note.preferredMaxLayoutWidth = 420

        let buttons = NSStackView(views: [copyButton, refreshButton])
        buttons.spacing = 10

        let content = NSStackView(views: [rows, NSBox.separator(), note, buttons])
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 14
        content.edgeInsets = NSEdgeInsets(top: 20, left: 22, bottom: 20, right: 22)
        content.translatesAutoresizingMaskIntoConstraints = false

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 468, height: 300),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = L("体检", "Health Check")
        window.isReleasedWhenClosed = false
        let host = NSView()
        host.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: host.topAnchor),
            content.bottomAnchor.constraint(equalTo: host.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            content.widthAnchor.constraint(equalToConstant: 468),
        ])
        window.contentView = host
        self.window = window
    }

    private func row(_ check: HealthCheck) -> NSView {
        let (symbol, color): (String, NSColor) = switch check.level {
        case .ok: ("checkmark.circle.fill", .systemGreen)
        case .warn: ("exclamationmark.triangle.fill", .systemOrange)
        case .info: ("info.circle.fill", .secondaryLabelColor)
        }
        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
        icon.contentTintColor = color
        icon.setContentHuggingPriority(.required, for: .horizontal)
        icon.widthAnchor.constraint(equalToConstant: 22).isActive = true

        let title = NSTextField(wrappingLabelWithString: check.title)
        title.font = .systemFont(ofSize: 13, weight: .medium)
        title.preferredMaxLayoutWidth = 390
        let text = NSStackView(views: [title])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 2
        if !check.detail.isEmpty {
            let detail = NSTextField(wrappingLabelWithString: check.detail)
            detail.font = .systemFont(ofSize: 12)
            detail.textColor = .secondaryLabelColor
            detail.preferredMaxLayoutWidth = 390
            text.addArrangedSubview(detail)
        }
        let line = NSStackView(views: [icon, text])
        line.alignment = .top
        line.spacing = 8
        return line
    }

    private func setRows(_ views: [NSView]) {
        rows.arrangedSubviews.forEach { $0.removeFromSuperview() }
        views.forEach { rows.addArrangedSubview($0) }
    }

    @objc private func refresh() {
        copyButton.isEnabled = false
        refreshButton.isEnabled = false
        copyButton.title = L("复制诊断信息", "Copy Diagnostics")
        setRows([row(HealthCheck(level: .info, title: L("正在检查…", "Checking…"), detail: ""))])
        DispatchQueue.global(qos: .userInitiated).async {
            let checks = Health.run()
            DispatchQueue.main.async {
                self.checks = checks
                self.setRows(checks.map(self.row))
                self.copyButton.isEnabled = true
                self.refreshButton.isEnabled = true
            }
        }
    }

    @objc private func copyReport() {
        copyButton.isEnabled = false
        let checks = self.checks
        DispatchQueue.global(qos: .userInitiated).async {
            let report = Health.report(checks)
            DispatchQueue.main.async {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(report, forType: .string)
                self.copyButton.title = L("已复制", "Copied")
                self.copyButton.isEnabled = true
            }
        }
    }
}

private extension NSBox {
    static func separator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        box.widthAnchor.constraint(equalToConstant: 424).isActive = true
        return box
    }
}
