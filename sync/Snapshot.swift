import Foundation

enum SnapshotFailure: Error { case invalid, unsupportedVersion }

struct SnapshotCounts: Codable, Equatable {
    let done: Int; let total: Int; let active: Int; let blocked: Int; let pending: Int; let unknown: Int
    var valid: Bool { (0...1_000_000).contains(total) && [done, active, blocked, pending, unknown].allSatisfy { (0...total).contains($0) } }
}
struct SnapshotSignal: Codable, Equatable {
    let kind: String; let text: String
    var valid: Bool { ["current", "blocker", "next", "delivery", "status"].contains(kind) && text.count <= 240 }
}
struct SnapshotProject: Codable, Equatable, Identifiable {
    var id: String
    let name: String; let state: String; let mode: String; let scope: String
    let counts: SnapshotCounts?; let percent: Int?; let signals: [SnapshotSignal]; let needsReview: Bool
    var valid: Bool {
        guard UUID(uuidString: id) != nil, !name.isEmpty, name.count <= 100, scope.count <= 100,
              ["ready", "unavailable", "permission"].contains(state), ["measured", "tasks", "status", "unknown"].contains(mode),
              signals.count <= 4, signals.allSatisfy(\.valid) else { return false }
        if state != "ready" { return counts == nil && percent == nil && signals.isEmpty }
        guard let counts, counts.valid else { return false }
        if let percent {
            guard mode == "measured", counts.total > 0, (0...100).contains(percent),
                  abs(Double(percent) - Double(counts.done) / Double(counts.total) * 100) <= 1 else { return false }
        }
        return mode != "measured" || counts.total == 0 || percent != nil
    }
}
struct DeviceSnapshot: Codable, Equatable, Identifiable {
    let version: Int
    let id: String; let name: String; let capturedAt: Date; let projects: [SnapshotProject]
    static let byteLimit = 400_000
    func validate() throws {
        guard version == 1 else { throw SnapshotFailure.unsupportedVersion }
        guard UUID(uuidString: id) != nil, !name.isEmpty, name.count <= 60, projects.count <= 50,
              Set(projects.map(\.id)).count == projects.count, projects.allSatisfy(\.valid),
              capturedAt.timeIntervalSince1970.isFinite else { throw SnapshotFailure.invalid }
    }
    func encoded() throws -> Data {
        try validate()
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(self)
        guard data.count <= Self.byteLimit else { throw SnapshotFailure.invalid }
        return data
    }
    static func decode(_ data: Data) throws -> DeviceSnapshot {
        guard data.count <= byteLimit else { throw SnapshotFailure.invalid }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let result = try decoder.decode(Self.self, from: data); try result.validate(); return result
    }
    func stale(at date: Date = Date()) -> Bool {
        let age = date.timeIntervalSince(capturedAt)
        return age > 180 || age < -60
    }
}

struct SyncPreferences: Codable, Equatable {
    var enabled = false
    var deviceID = UUID().uuidString
    var deviceName = "My Mac"
    var projectIDs: [String: String] = [:]
    var selected: [String] = []
    var includeText = false
    var pendingDelete = false
    // A restored preference file cannot silently upload to another iCloud account.
    var accountKey: String?
    static func read(_ url: URL) throws -> SyncPreferences {
        guard FileManager.default.fileExists(atPath: url.path) else { return Self() }
        let data = try Data(contentsOf: url)
        guard data.count <= 100_000 else { throw SnapshotFailure.invalid }
        let value = try JSONDecoder().decode(Self.self, from: data)
        guard UUID(uuidString: value.deviceID) != nil, !value.deviceName.isEmpty, value.deviceName.count <= 60,
              value.selected.count <= 50, Set(value.selected).count == value.selected.count,
              value.selected.allSatisfy({ !$0.isEmpty && $0.count <= 200 && value.projectIDs[$0] != nil }),
              value.projectIDs.count <= 5_000, value.projectIDs.values.allSatisfy({ UUID(uuidString: $0) != nil }) else { throw SnapshotFailure.invalid }
        return value
    }
    mutating func select(_ ids: [String]) {
        selected = Array(Set(ids)).sorted()
        for id in selected where projectIDs[id] == nil { projectIDs[id] = UUID().uuidString }
    }
    func save(_ url: URL) throws {
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

func cloudText(_ en: String, _ zh: String, _ fr: String, language: String = Locale.preferredLanguages.first ?? "en") -> String {
    if language.hasPrefix("zh") { return zh }
    if language.hasPrefix("fr") { return fr }
    return en
}
