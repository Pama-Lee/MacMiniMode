// 合盖后关掉盖子里那块屏幕的背光，开盖时恢复原来的亮度。
// Mac mini 模式下系统不睡眠，如果显示器睡眠被设成「永不」（远程桌面软件常这么做），合盖后屏幕会一直亮着。
// 只关背光、不让显示器睡眠：显示器一睡就会触发锁屏，还会打断视频通话和远程桌面这类正在用屏幕的应用。
// 亮度会被系统记住，所以原来的值存进偏好设置，开盖、退出、被终止、下次启动时都会尝试恢复。

import AppKit

final class LidScreen {
    static let enabledKey = "screenOffWhenLidClosed"
    static let savedKey = "brightnessBeforeLidClosed"

    private typealias GetBrightness = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetBrightness = @convention(c) (CGDirectDisplayID, Float) -> Int32
    private let getBrightness: GetBrightness?
    private let setBrightness: SetBrightness?

    init() {
        // 系统自带的亮度接口，没有公开头文件，运行时查找；找不到就什么都不做。
        let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)
        getBrightness = handle.flatMap { dlsym($0, "DisplayServicesGetBrightness") }.map { unsafeBitCast($0, to: GetBrightness.self) }
        setBrightness = handle.flatMap { dlsym($0, "DisplayServicesSetBrightness") }.map { unsafeBitCast($0, to: SetBrightness.self) }
    }

    var enabled: Bool {
        get { UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Self.enabledKey) }
    }

    private var saved: Float? {
        get { UserDefaults.standard.object(forKey: Self.savedKey) as? Float }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue, forKey: Self.savedKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.savedKey)
            }
        }
    }

    private func displays() -> (builtin: CGDirectDisplayID?, external: Bool) {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(16, &ids, &count) == .success else { return (nil, false) }
        let online = ids.prefix(Int(count))
        return (online.first { CGDisplayIsBuiltin($0) != 0 }, online.contains { CGDisplayIsBuiltin($0) == 0 })
    }

    /// 接着外接显示器时不动：那时系统自己会关掉内建屏幕。
    static func shouldDim(enabled: Bool, lidClosed: Bool, modeOn: Bool, hasBuiltin: Bool, hasExternal: Bool) -> Bool {
        enabled && lidClosed && modeOn && hasBuiltin && !hasExternal
    }

    func tick(modeOn: Bool, lidClosed: Bool) {
        guard let getBrightness, let setBrightness else { return }
        let (builtin, external) = displays()
        if Self.shouldDim(enabled: enabled, lidClosed: lidClosed, modeOn: modeOn, hasBuiltin: builtin != nil, hasExternal: external),
           let builtin {
            var current: Float = 0
            guard getBrightness(builtin, &current) == 0, current > 0.001 else { return }
            // 只在第一次记下原来的亮度；之后如果亮度被别的东西调高，再压回 0，但不覆盖记下的值。
            if saved == nil { saved = current }
            _ = setBrightness(builtin, 0)
        } else if !lidClosed || !enabled {
            restore()
        }
    }

    /// 把亮度恢复成合盖前的值。内建屏幕暂时不在线时保留记录，下次再试。
    func restore() {
        guard let setBrightness, let value = saved, let builtin = displays().builtin else { return }
        if setBrightness(builtin, value) == 0 { saved = nil }
    }

    /// 应急用（命令行 `macminimode screen-on`）：先按记录恢复；没有记录而屏幕仍然是黑的，就直接调到一个看得见的亮度。
    func forceOn() -> Bool {
        restore()
        guard let getBrightness, let setBrightness, let builtin = displays().builtin else { return false }
        var current: Float = 0
        guard getBrightness(builtin, &current) == 0 else { return false }
        if current < 0.05 { return setBrightness(builtin, 0.7) == 0 }
        return true
    }
}
