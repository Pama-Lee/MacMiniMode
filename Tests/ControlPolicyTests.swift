import Foundation
@main struct ControlPolicyTests {
    static func main() throws {
        var s = ControlState()
        precondition(!s.settings.enabled && s.settings.threshold == 20 && !s.settings.restore)
        s.manual(.on); s.evaluate(ac: false, battery: 5); precondition(s.mode == .on)
        try s.configure(PowerSettings(enabled: true, threshold: 20, restore: false))
        s.evaluate(ac: true, battery: 1); precondition(s.mode == .on)
        s.evaluate(ac: false, battery: nil); precondition(s.mode == .on)
        s.evaluate(ac: false, battery: 21); precondition(s.mode == .on)
        s.evaluate(ac: false, battery: 20); precondition(s.mode == .auto)
        s.evaluate(ac: true, battery: 100); precondition(s.mode == .auto)
        print("PASS: defaults, threshold boundary, AC, unknown battery and permanent downgrade")
        try s.configure(PowerSettings(enabled: true, threshold: 20, restore: true))
        s.manual(.on); s.evaluate(ac: false, battery: 20); precondition(s.restoreManual)
        s.evaluate(ac: false, battery: 24); precondition(s.mode == .auto)
        s.evaluate(ac: false, battery: 25); precondition(s.mode == .on && !s.restoreManual)
        s.evaluate(ac: false, battery: 10); s.manual(.off); s.evaluate(ac: true, battery: 80); precondition(s.mode == .off)
        s.manual(.on); s.evaluate(ac: false, battery: 10)
        try s.configure(PowerSettings(enabled: false, threshold: 20, restore: true))
        s.evaluate(ac: true, battery: 80); precondition(s.mode == .auto)
        print("PASS: recovery hysteresis, manual cancellation, disabling does not restore")
        try s.begin(id: "a", uid: 501, name: "build", source: "Codex", mode: .auto, ac: true, battery: 80)
        try s.begin(id: "b", uid: 501, name: "test", source: "Claude", mode: .on, ac: true, battery: 80)
        precondition(s.mode == .on && s.tasks.count == 2)
        try s.begin(id: "a", uid: 501, name: "build", source: "Codex", mode: .auto, ac: true, battery: 80)
        precondition(s.tasks.count == 2)
        do { try s.end(id: "b", uid: 502); preconditionFailure("wrong user") } catch {}
        try s.end(id: "a", uid: 501); precondition(s.mode == .on)
        try s.end(id: "b", uid: 501); precondition(s.mode == .off)
        s.manual(.auto); try s.end(id: "b", uid: 501); precondition(s.mode == .auto)
        do { try s.begin(id: "b", uid: 501, name: "test", source: "Claude", mode: .on, ac: true, battery: 80); preconditionFailure("retired") } catch {}
        print("PASS: mixed clients, idempotency, ownership, last release, stale requests")
        try s.configure(PowerSettings(enabled: true, threshold: 20, restore: true))
        try s.begin(id: "c", uid: 501, name: "build", source: "Codex", mode: .on, ac: true, battery: 80)
        try s.begin(id: "d", uid: 502, name: "test", source: "Claude", mode: .auto, ac: true, battery: 80)
        s.evaluate(ac: false, battery: 20); precondition(s.mode == .auto && s.tasks[0].suspended)
        let data = try JSONEncoder().encode(s); s = try JSONDecoder().decode(ControlState.self, from: data)
        try s.end(id: "c", uid: 501); s.evaluate(ac: true, battery: 80); precondition(s.mode == .auto)
        try s.end(id: "d", uid: 502); precondition(s.mode == .off)
        do { try s.begin(id: "e", uid: 501, name: "test", source: "Codex", mode: .on, ac: false, battery: 10); preconditionFailure("low battery") } catch {}
        try s.begin(id: "f", uid: 501, name: "test", source: "Codex", mode: .on, ac: true, battery: 80)
        s.manual(.on); try s.end(id: "f", uid: 501); precondition(s.mode == .on && s.tasks.isEmpty)
        print("PASS: persistent suspension, task-end cancellation, protection priority, manual takeover")
        for threshold in [9, 51] { do { try s.configure(PowerSettings(enabled: true, threshold: threshold, restore: false)); preconditionFailure("invalid threshold") } catch {} }
        print("PASS: setting validation")
    }
}
