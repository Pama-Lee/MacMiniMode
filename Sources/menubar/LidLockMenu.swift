// 可选的开盖锁屏设置。留在用户会话，不让 root 守护进程操作登录窗口。

import AppKit

final class LidLockMenu: NSObject {
    static let preferenceKey = "lockWhenLidOpens"
    private let item = NSMenuItem(title: L("开盖时自动锁屏", "Lock When Lid Opens"), action: nil, keyEquivalent: "")
    private let warning = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let defaults: UserDefaults
    private let screenLock = ScreenLock()
    private let monitor = LidMonitor()
    private var observer: NSObjectProtocol?
    private lazy var controller = LidLockController(readSession: { ScreenLock.sessionState() },
        readLid: { LidMonitor.currentClosed() }, requestLock: { [weak self] in self?.screenLock.request() ?? false })

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        super.init()
        item.target = self
        item.action = #selector(toggle)
        warning.isEnabled = false
        warning.isHidden = true
    }

    deinit {
        monitor.stop()
        if let observer { DistributedNotificationCenter.default().removeObserver(observer) }
    }

    func add(to menu: NSMenu) {
        menu.addItem(item)
        menu.addItem(warning)
    }

    func start() {
        controller.onChange = { [weak self] in self?.refresh() }
        monitor.onChange = { [weak self] closed in self?.controller.observe(closed) }
        observer = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
                self?.controller.screenDidLock()
            }
        configure()
    }

    private func configure() {
        monitor.stop()
        let enabled = defaults.bool(forKey: Self.preferenceKey)
        controller.setEnabled(enabled)
        guard enabled else { return }
        guard screenLock.available else { controller.fail(.unavailable); return }
        if !monitor.start() { controller.fail(.monitoring) }
    }

    func refresh() {
        item.state = defaults.bool(forKey: Self.preferenceKey) ? .on : .off
        let available = screenLock.available && LidMonitor.currentClosed() != nil
        // 已开启但不可用时仍允许取消勾选；不能把故障的已开启功能困在禁用状态。
        item.isEnabled = item.state == .on || available
        item.toolTip = available
            ? L("合盖时不锁屏，再次开盖时锁屏；不改变防休眠模式。", "Locks on reopening, not on closing; the keep-awake mode stays unchanged.")
            : L("此 Mac 无法检测盖子状态或执行锁屏。", "Lid detection or screen locking is unavailable on this Mac.")
        warning.isHidden = controller.failure == nil
        warning.title = controller.failure == .locking
            ? L("未能确认锁屏，请手动锁屏", "Lock not confirmed; lock manually")
            : L("开盖锁屏不可用，请手动锁屏", "Lid lock unavailable; lock manually")
    }

    @objc private func toggle() {
        defaults.set(!defaults.bool(forKey: Self.preferenceKey), forKey: Self.preferenceKey)
        configure()
    }
}
