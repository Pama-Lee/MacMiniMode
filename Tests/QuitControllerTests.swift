import Foundation
import CoreServices
import IOKit.pwr_mgt

@main
struct QuitControllerTests {
    @MainActor
    static func wait(until finished: () -> Bool) {
        let deadline = Date().addingTimeInterval(1)
        while !finished(), Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.005))
        }
        precondition(finished(), "Timed out waiting for quit completion")
    }

    @MainActor
    static func main() {
        precondition(!QuitPolicy.isSystemQuit(nil))
        let event = NSAppleEventDescriptor.appleEvent(withEventClass: AEEventClass(kCoreEventClass),
            eventID: AEEventID(kAEQuitApplication), targetDescriptor: nil,
            returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
        precondition(!QuitPolicy.isSystemQuit(event), "A normal app quit must stop the policy")
        for reason in [kAEQuitAll, kAEShutDown, kAERestart, kAEReallyLogOut] {
            event.setParam(NSAppleEventDescriptor(enumCode: OSType(reason)), forKeyword: AEKeyword(kAEQuitReason))
            precondition(QuitPolicy.isSystemQuit(event), "System termination must preserve the selected mode")
        }
        print("PASS: distinguishes user quit from system shutdown, restart and logout")

        var requests = 0
        var stopped = false
        var result: Bool?
        var duplicateCallback = false
        let quit = QuitController(requestStop: { requests += 1 }, hasStopped: { stopped },
                                  timeout: 0.2, interval: 0.005)
        quit.begin { result = $0 }
        precondition(requests == 1 && quit.pending && result == nil,
                     "Quit must request stop and return before replying to AppKit")
        quit.begin { _ in duplicateCallback = true }
        precondition(requests == 1, "Repeated quit must not start another request")
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        precondition(result == nil && quit.pending, "Quit must wait for the actual stop")
        stopped = true
        wait { result != nil }
        precondition(result == true && !quit.pending && !duplicateCallback)
        print("PASS: waits for stop, replies asynchronously, ignores duplicate quit")

        stopped = false
        result = nil
        let retry = QuitController(requestStop: { requests += 1 }, hasStopped: { stopped },
                                   timeout: 0.02, interval: 0.005)
        retry.begin { result = $0 }
        wait { result != nil }
        precondition(result == false && !retry.pending, "Failure must cancel termination")
        print("PASS: failed or unavailable background service cancels termination")
        stopped = true
        result = nil
        retry.begin { result = $0 }
        wait { result != nil }
        precondition(result == true && requests == 3, "Quit must be retryable after failure")
        print("PASS: retries a failed quit")

        let owned: [String: Any] = [kIOPMAssertionNameKey as String: "Mac mini Mode",
                                   kIOPMAssertionTypeKey as String: "PreventSystemSleep",
                                   kIOPMAssertionLevelKey as String: Int(kIOPMAssertionLevelOn)]
        let unrelated: [String: Any] = [kIOPMAssertionNameKey as String: "Unrelated app",
                                       kIOPMAssertionTypeKey as String: "PreventSystemSleep",
                                       kIOPMAssertionLevelKey as String: Int(kIOPMAssertionLevelOn)]
        precondition(QuitPolicy.assertionsReleased(in: [1: [owned]]) == false,
                     "An active Mac mini Mode assertion must block quit")
        precondition(QuitPolicy.assertionsReleased(in: [1: [unrelated]]) == true,
                     "Unrelated apps must not block quit")
        var inactive = owned
        inactive[kIOPMAssertionLevelKey as String] = Int(kIOPMAssertionLevelOff)
        precondition(QuitPolicy.assertionsReleased(in: [1: [inactive]]) == true)
        precondition(QuitPolicy.assertionsReleased(in: [:]) == true)
        print("PASS: checks Mac mini Mode assertions without changing unrelated assertions")

        var unknown = owned
        unknown.removeValue(forKey: kIOPMAssertionLevelKey as String)
        precondition(QuitPolicy.assertionsReleased(in: [1: [unknown]]) == nil)
        precondition(QuitPolicy.assertionsReleased(in: [1: "unreadable"]) == nil)
        print("PASS: unreadable assertion state cannot confirm a successful quit")
    }
}
