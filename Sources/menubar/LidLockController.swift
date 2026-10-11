// 只在「合盖 -> 开盖」时锁屏。所有调用和定时回调在主线程执行。

import Foundation

final class LidLockController {
    enum Failure { case unavailable, monitoring, locking }
    var onChange: () -> Void = {}
    private(set) var enabled = false
    private(set) var failure: Failure?
    private(set) var pending = false
    private var previousClosed: Bool?
    private var generation = 0
    private var deadline: TimeInterval = 0
    private var nextRequest: TimeInterval = 0
    private var requestIssued = false
    private let readSession: () -> ScreenSessionState
    private let readLid: () -> Bool?
    private let requestLock: () -> Bool
    private let now: () -> TimeInterval
    private let schedule: (TimeInterval, @escaping () -> Void) -> Void
    private let timeout: TimeInterval

    init(readSession: @escaping () -> ScreenSessionState, readLid: @escaping () -> Bool?,
         requestLock: @escaping () -> Bool, timeout: TimeInterval = 3,
         now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         schedule: @escaping (TimeInterval, @escaping () -> Void) -> Void = { delay, action in
             DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: action)
         }) {
        self.readSession = readSession
        self.readLid = readLid
        self.requestLock = requestLock
        self.timeout = timeout
        self.now = now
        self.schedule = schedule
    }

    func setEnabled(_ enabled: Bool) {
        generation += 1
        self.enabled = enabled
        pending = false
        previousClosed = nil
        failure = nil
        onChange()
    }

    func fail(_ reason: Failure) {
        generation += 1
        pending = false
        guard failure != reason else { return }
        failure = reason
        NSLog("[lid-lock] %@", String(describing: reason))
        onChange()
    }

    func observe(_ closed: Bool?) {
        guard enabled else { return }
        guard let closed else { fail(.monitoring); return }
        let opened = previousClosed == true && !closed
        previousClosed = closed
        if closed {
            // 合盖只记录状态，并取消过期重试；不能在合盖期间执行锁屏。
            generation += 1
            pending = false
        }
        guard opened else { return }
        generation += 1
        pending = true
        failure = nil
        deadline = now() + timeout
        nextRequest = now()
        requestIssued = false
        onChange()
        check(generation)
    }

    // 通知加上实际会话状态确认结果；不能把过期通知或未知状态当作已锁屏。
    func screenDidLock() {
        guard pending, readSession() == .locked else { return }
        finish()
    }

    private func finish() {
        generation += 1
        pending = false
        failure = nil
        onChange()
    }

    private func check(_ expectedGeneration: Int) {
        guard enabled, pending, generation == expectedGeneration else { return }
        guard let closed = readLid() else { fail(.monitoring); return }
        guard !closed else { finish(); return }
        switch readSession() {
        case .locked, .inactive:
            finish()
            return
        case .unknown: break
        case .unlocked:
            if !requestIssued, now() < deadline, now() >= nextRequest {
                nextRequest = now() + 0.5
                // 发出请求后只确认结果，不重复锁屏，避免用户快速解锁后被再次锁住。
                // 尚未发出的请求（例如会话切换导致预检失败）才允许重试。
                requestIssued = requestLock()
                // 请求可能同步产生锁屏通知；不得继续一个已经完成的尝试。
                guard pending, generation == expectedGeneration else { return }
            }
        }
        if now() >= deadline { fail(.locking); return }
        schedule(0.1) { [weak self] in self?.check(expectedGeneration) }
    }
}
