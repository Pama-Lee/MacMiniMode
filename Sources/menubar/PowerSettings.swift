import AppKit

/// A small native panel; the privileged service owns settings, not UserDefaults.
final class PowerSettingsController: NSObject {
    private var window: NSWindow?
    private let enabled = NSButton(checkboxWithTitle: L("低电量时切换到自动模式", "Switch to Automatic on low battery"), target: nil, action: nil)
    private let threshold = NSSlider(value: 20, minValue: 10, maxValue: 50, target: nil, action: nil)
    private let valueLabel = NSTextField(labelWithString: "20%")
    private let recovery = NSPopUpButton()
    private let message = NSTextField(wrappingLabelWithString: "")
    private let save = NSButton(title: L("保存", "Save"), target: nil, action: nil)
    private var loading = false

    func show() {
        if window == nil { build() }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        load()
    }
    private func build() {
        let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 310),
                             styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.title = L("设置", "Settings")
        panel.isReleasedWhenClosed = false
        panel.center()
        threshold.target = self; threshold.action = #selector(sliderChanged)
        recovery.addItems(withTitles: [L("保持自动模式", "Keep Automatic"), L("恢复此前的始终开启", "Restore previous Always On")])
        save.target = self; save.action = #selector(saveSettings)
        let row = NSStackView(views: [NSTextField(labelWithString: L("触发电量", "Battery threshold")), threshold, valueLabel])
        row.orientation = .horizontal
        let help = NSTextField(wrappingLabelWithString: L(
            "仅在使用电池时触发。选择恢复时，接通电源或电量达到阈值加 5% 后恢复。手动切换模式会取消恢复。关闭此选项仍保留原有 10% 低电量保护。",
            "Triggers on battery power only. Optional recovery occurs on AC power or at threshold + 5%. Manual mode changes cancel recovery. The original 10% protection remains when this option is off."))
        help.textColor = .secondaryLabelColor
        let stack = NSStackView(views: [enabled, row, recovery, help, message, save])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: panel.contentView!.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: panel.contentView!.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: panel.contentView!.topAnchor, constant: 24),
            row.widthAnchor.constraint(equalTo: stack.widthAnchor), help.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
        window = panel
    }
    @objc private func sliderChanged() { threshold.doubleValue = threshold.doubleValue.rounded(); valueLabel.stringValue = "\(threshold.integerValue)%" }
    private func load() {
        transact(ControlRequest(operation: "status")) { [weak self] response in
            guard let self, let settings = response.status?.settings else { return }
            enabled.state = settings.enabled ? .on : .off
            threshold.integerValue = settings.threshold; sliderChanged()
            recovery.selectItem(at: settings.restore ? 1 : 0)
        }
    }
    @objc private func saveSettings() {
        transact(ControlRequest(operation: "configure", settings: PowerSettings(enabled: enabled.state == .on,
                  threshold: threshold.integerValue, restore: recovery.indexOfSelectedItem == 1))) { [weak self] response in
            if response.ok { self?.message.stringValue = L("已保存", "Saved") }
        }
    }
    private func transact(_ request: ControlRequest, completion: @escaping (ControlResponse) -> Void) {
        guard !loading else { return }; loading = true; save.isEnabled = false
        message.stringValue = L("正在连接后台服务…", "Contacting background service…")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result { try ControlSocket.request(request) }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                loading = false; save.isEnabled = true
                switch result {
                case .success(let response):
                    message.stringValue = response.ok ? "" : L("操作未完成：", "Operation incomplete: ") + (response.error ?? "unknown")
                    completion(response)
                case .failure(let error): message.stringValue = L("无法连接：", "Could not connect: ") + String(describing: error)
                }
            }
        }
    }
}
