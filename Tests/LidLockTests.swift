import Foundation
import CoreGraphics
import Darwin

final class Fixture {
    var lid: Bool? = false
    var session = ScreenSessionState.unlocked
    var requests = 0
    var canRequest = true
    var time: TimeInterval = 0
    var jobs: [() -> Void] = []
    lazy var controller = LidLockController(readSession: { self.session }, readLid: { self.lid },
        requestLock: { self.requests += 1; return self.canRequest }, timeout: 1,
        now: { self.time }, schedule: { _, action in self.jobs.append(action) })

    func observe(_ closed: Bool?) { lid = closed; controller.observe(closed) }
    func tick(_ advance: TimeInterval = 0.1) {
        time += advance
        let ready = jobs
        jobs.removeAll()
        ready.forEach { $0() }
    }
}

@main
struct LidLockTests {
    static func main() {
        let f = Fixture()
        f.controller.setEnabled(true)
        f.observe(false)
        f.observe(true)
        f.observe(true)
        precondition(f.requests == 0, "Startup/open baseline and closing must not lock")
        f.observe(false)
        precondition(f.requests == 1 && f.controller.pending, "Reopening must immediately request a lock")
        f.observe(false)
        precondition(f.requests == 1, "Duplicate open notifications must not restart locking")
        f.session = .locked
        f.tick()
        precondition(!f.controller.pending && f.controller.failure == nil)
        f.session = .unlocked
        f.observe(false)
        f.tick(1)
        precondition(f.requests == 1, "Unlocking while the lid stays open must not relock")
        print("PASS: close records state, reopening locks, duplicates and later unlock do not relock")

        let startup = Fixture()
        startup.controller.setEnabled(true)
        startup.observe(true)
        precondition(startup.requests == 0)
        startup.observe(false)
        precondition(startup.requests == 1, "Startup with a closed lid must arm the next opening")
        startup.session = .locked
        startup.controller.screenDidLock()
        startup.session = .unlocked
        startup.tick()
        precondition(startup.requests == 1 && !startup.controller.pending,
                     "A confirmed lock followed by immediate Touch ID unlock must not relock")
        print("PASS: starts safely with lid closed and accepts lock notification before rapid unlock")

        for state in [ScreenSessionState.locked, .inactive] {
            let f = Fixture()
            f.session = state
            f.controller.setEnabled(true)
            f.observe(true)
            f.observe(false)
            precondition(f.requests == 0 && !f.controller.pending)
        }
        let disabled = Fixture()
        disabled.observe(true)
        disabled.observe(false)
        precondition(disabled.requests == 0)
        print("PASS: opt-in, already locked, and another user's session never request a lock")

        for closeAgain in [false, true] {
            let f = Fixture()
            f.controller.setEnabled(true)
            f.observe(true)
            f.observe(false)
            if closeAgain { f.observe(true) } else { f.controller.setEnabled(false) }
            f.tick(2)
            precondition(f.requests == 1 && !f.controller.pending && f.controller.failure == nil)
        }
        let stale = Fixture()
        stale.controller.setEnabled(true)
        stale.observe(true)
        stale.observe(false)
        stale.controller.setEnabled(false)
        stale.controller.setEnabled(true)
        stale.observe(false)
        stale.tick(2)
        precondition(stale.requests == 1, "Callbacks from an earlier activation must not lock")
        print("PASS: closing, disabling, and toggling cancel all stale retries")

        let failure = Fixture()
        failure.controller.setEnabled(true)
        failure.observe(true)
        failure.observe(false)
        failure.tick(0.6)
        precondition(failure.requests == 1, "An issued request must not relock a rapidly unlocked session")
        failure.tick(0.5)
        precondition(failure.controller.failure == .locking && !failure.controller.pending)
        failure.observe(true)
        failure.observe(false)
        failure.session = .locked
        failure.tick()
        precondition(failure.controller.failure == nil && !failure.controller.pending)
        let rejected = Fixture()
        rejected.canRequest = false
        rejected.controller.setEnabled(true)
        rejected.observe(true)
        rejected.observe(false)
        rejected.tick(0.6)
        precondition(rejected.requests == 2, "A request not issued must be retryable")
        rejected.canRequest = true
        rejected.tick(0.5)
        precondition(rejected.controller.failure == .locking)
        let unknown = Fixture()
        unknown.session = .unknown
        unknown.controller.setEnabled(true)
        unknown.observe(true)
        unknown.observe(false)
        unknown.tick(2)
        precondition(unknown.requests == 0 && unknown.controller.failure == .locking)
        let staleNotification = Fixture()
        staleNotification.controller.setEnabled(true)
        staleNotification.observe(true)
        staleNotification.observe(false)
        staleNotification.controller.screenDidLock()
        precondition(staleNotification.controller.pending, "Stale notification must not confirm an unlocked session")
        staleNotification.session = .unknown
        staleNotification.controller.screenDidLock()
        precondition(staleNotification.controller.pending, "Unknown state must not confirm locking")
        staleNotification.tick(2)
        precondition(staleNotification.requests == 1 && staleNotification.controller.failure == .locking)
        print("PASS: retry and timeout report failure, a new lid cycle retries, unknown sessions are safe")

        let missingLid = Fixture()
        missingLid.controller.setEnabled(true)
        missingLid.observe(true)
        missingLid.observe(nil)
        precondition(missingLid.requests == 0 && missingLid.controller.failure == .monitoring)
        missingLid.observe(false)
        precondition(missingLid.requests == 1, "Reading open after a known close can recover a missed event")
        missingLid.lid = nil
        missingLid.tick()
        precondition(!missingLid.controller.pending && missingLid.controller.failure == .monitoring)
        print("PASS: unknown lid states never invent a close or silently confirm locking")

        let message = LidMonitor.stateChangedMessage
        precondition(LidMonitor.closed(message: message, argument: nil) == false)
        precondition(LidMonitor.closed(message: message, argument: UnsafeMutableRawPointer(bitPattern: 1)) == true)
        precondition(LidMonitor.closed(message: message, argument: UnsafeMutableRawPointer(bitPattern: 2)) == false)
        precondition(LidMonitor.closed(message: message, argument: UnsafeMutableRawPointer(bitPattern: 3)) == true)
        precondition(LidMonitor.closed(message: 0, argument: nil) == nil)
        print("PASS: native clamshell bitfield handles nil/open and ignores unrelated messages")

        var session: [String: Any] = [kCGSessionUserIDKey as String: getuid(), kCGSessionOnConsoleKey as String: true]
        precondition(ScreenLock.sessionState(in: session, uid: getuid()) == .unlocked)
        session["CGSSessionScreenIsLocked"] = true
        precondition(ScreenLock.sessionState(in: session, uid: getuid()) == .locked)
        session[kCGSessionOnConsoleKey as String] = false
        precondition(ScreenLock.sessionState(in: session, uid: getuid()) == .inactive)
        precondition(ScreenLock.sessionState(in: session, uid: getuid() + 1) == .inactive)
        precondition(ScreenLock.sessionState(in: nil, uid: getuid()) == .unknown)
        print("PASS: session parsing checks current UID and active console")
    }
}
