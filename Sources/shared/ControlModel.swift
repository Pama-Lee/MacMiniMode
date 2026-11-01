import Foundation

enum ControlMode: String, Codable { case auto, on, off }
struct PowerSettings: Codable, Equatable {
    var enabled = false
    var threshold = 20
    var restore = false
}
struct ManagedTask: Codable, Equatable {
    var id: String
    var uid: UInt32
    var name: String
    var source: String
    var mode: ControlMode
    var started: Date
    var suspended = false
}
struct ControlState: Codable, Equatable {
    var version = 1
    var mode: ControlMode = .auto
    var settings = PowerSettings()
    var tasks: [ManagedTask] = []
    var retired: [String] = []
    var restoreManual = false
    var reason: String?

    mutating func manual(_ value: ControlMode) {
        retired += tasks.map { "\($0.uid):\($0.id)" }
        tasks.removeAll()
        restoreManual = false
        mode = value
        reason = nil
    }
    mutating func aggregate() {
        mode = tasks.isEmpty ? .off : (tasks.contains { $0.mode == .on && !$0.suspended } ? .on : .auto)
    }
    mutating func evaluate(ac: Bool, battery: Int?) {
        guard settings.enabled else { return }
        if ac || (battery.map { $0 >= settings.threshold + 5 } ?? false) {
            if settings.restore {
                let hadSuspended = tasks.contains { $0.suspended }
                for i in tasks.indices { tasks[i].suspended = false }
                if restoreManual { mode = .on; restoreManual = false; reason = nil }
                else if hadSuspended { aggregate(); reason = nil }
            }
        } else if let battery, battery <= settings.threshold, mode == .on {
            restoreManual = tasks.isEmpty && settings.restore
            for i in tasks.indices where tasks[i].mode == .on {
                if settings.restore { tasks[i].suspended = true }
                else { tasks[i].mode = .auto }
            }
            mode = .auto
            reason = "low_battery_automatic"
        }
    }
    mutating func configure(_ value: PowerSettings) throws {
        guard (10...50).contains(value.threshold) else { throw ControlFailure("invalid_threshold") }
        // Changing the policy never resurrects a previously suspended request.
        if value != settings {
            restoreManual = false
            for i in tasks.indices where tasks[i].suspended { tasks[i].mode = .auto; tasks[i].suspended = false }
        }
        settings = value
    }
    mutating func begin(id: String, uid: UInt32, name: String, source: String, mode: ControlMode,
                        ac: Bool, battery: Int?) throws {
        guard !id.isEmpty, id.utf8.count <= 128, !name.isEmpty, name.utf8.count <= 256,
              !source.isEmpty, source.utf8.count <= 128, mode != .off else { throw ControlFailure("invalid_task") }
        if let existing = tasks.first(where: { $0.uid == uid && $0.id == id }) {
            guard existing.name == name && existing.source == source else { throw ControlFailure("task_id_conflict") }
            return
        }
        guard !retired.contains("\(uid):\(id)") else { throw ControlFailure("task_retired_use_new_id") }
        guard tasks.count < 256, retired.count < 100000 else { throw ControlFailure("task_capacity_reached") }
        if mode == .on, settings.enabled, !ac, let battery, battery <= settings.threshold {
            throw ControlFailure("low_battery_blocks_always_on")
        }
        restoreManual = false
        reason = nil
        tasks.append(ManagedTask(id: id, uid: uid, name: name, source: source, mode: mode, started: Date()))
        aggregate()
    }
    mutating func end(id: String, uid: UInt32) throws {
        guard let index = tasks.firstIndex(where: { $0.id == id && $0.uid == uid }) else {
            if tasks.contains(where: { $0.id == id }) { throw ControlFailure("permission_denied") }
            return
        }
        retired.append("\(uid):\(id)")
        tasks.remove(at: index)
        aggregate()
        if tasks.isEmpty { reason = nil; restoreManual = false }
    }
}
struct ControlFailure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}
struct ControlRequest: Codable {
    var operation: String
    var mode: ControlMode?
    var id: String?
    var name: String?
    var source: String?
    var settings: PowerSettings?
}
struct ControlStatus: Codable {
    var mode: ControlMode
    var sleepDisabled: Bool?
    var assertionHeld: Bool?
    var acPower: Bool
    var battery: Int?
    var tasks: [ManagedTask]
    var totalTasks: Int
    var settings: PowerSettings
    var reason: String?
    var waitingForRecovery: Bool
    var simulated: Bool
}
struct ControlResponse: Codable {
    var ok: Bool
    var saved: Bool
    var applied: Bool
    var error: String?
    var status: ControlStatus?
}
