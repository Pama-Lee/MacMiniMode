// 编译真实的菜单和控制器；替换硬件接口，避免测试锁住当前用户。
import AppKit

func L(_ zh: String, _ en: String) -> String { en }
enum ScreenSessionState { case unlocked, locked, inactive, unknown }

final class ScreenLock {
    static var supported = true
    static var state = ScreenSessionState.unlocked
    static var requests = 0
    var available: Bool { Self.supported }
    static func sessionState() -> ScreenSessionState { state }
    func request() -> Bool { Self.requests += 1; Self.state = .locked; return true }
}

final class LidMonitor {
    static var state: Bool? = false
    static weak var active: LidMonitor?
    var onChange: (Bool?) -> Void = { _ in }
    static func currentClosed() -> Bool? { state }
    func start() -> Bool { Self.active = self; onChange(Self.state); return true }
    func stop() { if Self.active === self { Self.active = nil } }
    static func observe(_ closed: Bool?) { state = closed; active?.onChange(closed) }
}

@main
struct LidLockMenuTests {
    static func toggle(_ item: NSMenuItem) {
        precondition(item.isEnabled)
        precondition(NSApplication.shared.sendAction(item.action!, to: item.target, from: item))
    }

    static func main() {
        let suite = "com.macminimode.test-lid-menu.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let menu = NSMenu()
        let component = LidLockMenu(defaults: defaults)
        component.add(to: menu)
        component.start()
        let item = menu.items[0], warning = menu.items[1]
        precondition(item.title == "Lock When Lid Opens" && item.state == .off && item.isEnabled)
        precondition(warning.isHidden && !warning.isEnabled)
        precondition(LidMonitor.active == nil, "Disabled feature must not monitor")
        toggle(item)
        precondition(item.state == .on && defaults.bool(forKey: LidLockMenu.preferenceKey))
        LidMonitor.observe(true)
        precondition(ScreenLock.requests == 0)
        LidMonitor.observe(false)
        precondition(ScreenLock.requests == 1)
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        precondition(warning.isHidden)
        print("PASS: real AppKit selector enables opt-in, closing stays unlocked, reopening locks")

        let restoredMenu = NSMenu()
        let restored = LidLockMenu(defaults: defaults)
        restored.add(to: restoredMenu)
        restored.start()
        precondition(restoredMenu.items[0].state == .on && ScreenLock.requests == 1,
                     "Restoring preference with lid already open must not lock")
        toggle(restoredMenu.items[0])
        precondition(!defaults.bool(forKey: LidLockMenu.preferenceKey) && LidMonitor.active == nil)
        print("PASS: preference survives recreation and disabling stops monitoring")

        ScreenLock.supported = false
        defaults.set(true, forKey: LidLockMenu.preferenceKey)
        let failedMenu = NSMenu()
        let failed = LidLockMenu(defaults: defaults)
        failed.add(to: failedMenu)
        failed.start()
        precondition(failedMenu.items[0].state == .on && failedMenu.items[0].isEnabled)
        precondition(!failedMenu.items[1].isHidden)
        toggle(failedMenu.items[0])
        precondition(failedMenu.items[0].state == .off && !failedMenu.items[0].isEnabled)
        precondition(failedMenu.items[1].isHidden && ScreenLock.requests == 1)
        print("PASS: missing lock interface shows warning and still allows disabling")

        ScreenLock.supported = true
        LidMonitor.state = nil
        let desktopMenu = NSMenu()
        let desktop = LidLockMenu(defaults: defaults)
        desktop.add(to: desktopMenu)
        desktop.start()
        precondition(!desktopMenu.items[0].isEnabled && LidMonitor.active == nil)
        print("PASS: unsupported lid hardware cannot enable the option")
    }
}
