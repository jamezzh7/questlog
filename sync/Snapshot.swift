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
struct SnapshotActivity: Codable, Equatable {
    let active: Bool
    let blocked: Bool
}
struct SnapshotProject: Codable, Equatable, Identifiable {
    var id: String
    let name: String; let state: String; let mode: String; let scope: String
    let counts: SnapshotCounts?; let percent: Int?; let signals: [SnapshotSignal]; let needsReview: Bool
    // Optional for version-1 snapshots written before structured activity existed.
    let activity: SnapshotActivity?
    init(id: String, name: String, state: String, mode: String, scope: String, counts: SnapshotCounts?, percent: Int?, signals: [SnapshotSignal], needsReview: Bool, activity: SnapshotActivity? = nil) {
        self.id = id; self.name = name; self.state = state; self.mode = mode; self.scope = scope
        self.counts = counts; self.percent = percent; self.signals = signals; self.needsReview = needsReview; self.activity = activity
    }
    var inProgress: Bool { state == "ready" && ((counts?.active ?? 0) > 0 || activity?.active == true) }
    var blocked: Bool { state == "ready" && ((counts?.blocked ?? 0) > 0 || activity?.blocked == true || signals.contains { $0.kind == "blocker" }) }
    var needsAttention: Bool { state != "ready" || needsReview || blocked }
    var valid: Bool {
        guard UUID(uuidString: id) != nil, !name.isEmpty, name.count <= 100, scope.count <= 100,
              ["ready", "unavailable", "permission"].contains(state), ["measured", "tasks", "status", "unknown"].contains(mode),
              signals.count <= 4, signals.allSatisfy(\.valid) else { return false }
        if state != "ready" { return counts == nil && percent == nil && signals.isEmpty && activity == nil }
        guard let counts, counts.valid else { return false }
        if let percent {
            guard mode == "measured", counts.total > 0, (0...100).contains(percent),
                  abs(Double(percent) - Double(counts.done) / Double(counts.total) * 100) <= 1 else { return false }
        }
        return mode != "measured" || counts.total == 0 || percent != nil
    }
}
struct SnapshotOverview: Equatable {
    let projects: Int; let inProgress: Int; let attention: Int
    init(_ snapshots: [DeviceSnapshot]) {
        let all = snapshots.flatMap(\.projects)
        projects = all.count; inProgress = all.filter(\.inProgress).count; attention = all.filter(\.needsAttention).count
    }
}

enum SnapshotFreshness: Equatable { case recent, cached, stale, clockSkew }
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
    func freshness(cached: Bool, at date: Date = Date()) -> SnapshotFreshness {
        if date.timeIntervalSince(capturedAt) < -60 { return .clockSkew }
        if cached { return .cached }
        return stale(at: date) ? .stale : .recent
    }
}

struct SyncPreferences: Codable, Equatable {
    var enabled = true
    var deviceID = UUID().uuidString
    var deviceName = "My Mac"
    var projectIDs: [String: String] = [:]
    var selected: [String] = []
    var automaticProjects = true
    var excluded: [String] = []
    var includeText = false
    var pendingDelete = false
    // A restored preference file cannot silently upload to another iCloud account.
    var accountKey: String?
    init() {}
    private enum CodingKeys: String, CodingKey {
        case enabled, deviceID, deviceName, projectIDs, selected, automaticProjects, excluded, includeText, pendingDelete, accountKey
    }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try values.decode(Bool.self, forKey: .enabled)
        deviceID = try values.decode(String.self, forKey: .deviceID)
        deviceName = try values.decode(String.self, forKey: .deviceName)
        projectIDs = try values.decode([String: String].self, forKey: .projectIDs)
        selected = try values.decode([String].self, forKey: .selected)
        automaticProjects = try values.decodeIfPresent(Bool.self, forKey: .automaticProjects) ?? false
        excluded = try values.decodeIfPresent([String].self, forKey: .excluded) ?? []
        includeText = try values.decode(Bool.self, forKey: .includeText)
        pendingDelete = try values.decode(Bool.self, forKey: .pendingDelete)
        accountKey = try values.decodeIfPresent(String.self, forKey: .accountKey)
    }
    // Reconcile connection IDs only; reading project files remains behind the normal access checks.
    mutating func connect(_ ids: [String]) throws {
        let connected = Set(ids)
        guard connected.count <= 5_000, connected.allSatisfy({ !$0.isEmpty && $0.count <= 200 }) else { throw SnapshotFailure.invalid }
        if !automaticProjects {
            // Preserve explicit exclusions from the former manual-selection workflow.
            excluded = Array(Set(excluded).union(connected.subtracting(selected))).sorted()
            automaticProjects = true
        }
        let available = connected.subtracting(excluded).sorted()
        // Keep existing slots stable when more than fifty projects are connected.
        let kept = selected.filter { available.contains($0) }
        select(Array((kept + available.filter { !kept.contains($0) }).prefix(50)))
    }
    static func read(_ url: URL) throws -> SyncPreferences {
        guard FileManager.default.fileExists(atPath: url.path) else { return Self() }
        let data = try Data(contentsOf: url)
        guard data.count <= 100_000 else { throw SnapshotFailure.invalid }
        let value = try JSONDecoder().decode(Self.self, from: data)
        guard UUID(uuidString: value.deviceID) != nil, !value.deviceName.isEmpty, value.deviceName.count <= 60,
              value.selected.count <= 50, Set(value.selected).count == value.selected.count,
              value.selected.allSatisfy({ !$0.isEmpty && $0.count <= 200 && value.projectIDs[$0] != nil }),
              value.excluded.count <= 5_000, Set(value.excluded).count == value.excluded.count,
              value.excluded.allSatisfy({ !$0.isEmpty && $0.count <= 200 }),
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
