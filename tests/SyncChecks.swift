// Run with scripts/check_sync.sh. All cloud access is an injected in-memory fake.
import Foundation
import CloudKit

enum CheckFailure: Error { case assertion(String), offline }
func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw CheckFailure.assertion(message) }
}
actor FakeCloud: SnapshotCloud {
    var account = "account-one"
    var values: [DeviceSnapshot] = []
    var calls = 0
    var failing = false
    func identity() async throws -> String { calls += 1; return account }
    func publish(_ snapshot: DeviceSnapshot) async throws {
        calls += 1; if failing { throw CheckFailure.offline }
        try snapshot.validate(); values = [snapshot]
    }
    func remove(deviceID: String) async throws {
        calls += 1; if failing { throw CheckFailure.offline }
        values.removeAll { $0.id == deviceID }
    }
    func fetch() async throws -> [DeviceSnapshot] { calls += 1; if failing { throw CheckFailure.offline }; return values }
    func setFailing(_ value: Bool) { failing = value }
    func setAccount(_ value: String) { account = value }
    func setValues(_ value: [DeviceSnapshot]) { values = value }
}

@main struct SyncChecks {
    @MainActor static func wait(_ condition: () async -> Bool) async throws {
        for _ in 0..<400 { if await condition() { return }; try await Task.sleep(nanoseconds: 10_000_000) }
        throw CheckFailure.assertion("Timed out waiting for publisher")
    }
    @MainActor static func main() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("questlog-sync-check-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let counts = SnapshotCounts(done: 1, total: 2, active: 0, blocked: 0, pending: 1, unknown: 0)
        let project = SnapshotProject(id: UUID().uuidString, name: "Orbit", state: "ready", mode: "measured", scope: "Release", counts: counts, percent: 50, signals: [], needsReview: false)
        let snapshot = DeviceSnapshot(version: 1, id: UUID().uuidString, name: "Test Mac", capturedAt: Date(), projects: [project])
        let decoded = try DeviceSnapshot.decode(snapshot.encoded())
        try expect(decoded.projects == snapshot.projects, "Payload round trip")
        try expect(!snapshot.stale(at: snapshot.capturedAt.addingTimeInterval(60)), "Fresh snapshot")
        try expect(snapshot.stale(at: snapshot.capturedAt.addingTimeInterval(181)), "Stale snapshot")
        try expect(snapshot.stale(at: snapshot.capturedAt.addingTimeInterval(-61)), "Clock skew is stale")
        var bad = project; bad.id = "/Users/private/project"
        try expect(!bad.valid, "Local path is not a remote project ID")
        let partial = SnapshotProject(id: project.id, name: "Orbit", state: "ready", mode: "tasks", scope: "", counts: counts, percent: 50, signals: [], needsReview: false)
        try expect(!partial.valid, "Partial tasks cannot carry a percentage")
        try expect(!SnapshotCounts(done: 0, total: 1, active: 2, blocked: 0, pending: 0, unknown: 0).valid, "Counts cannot exceed the scope")
        try expect(CloudFailure.noAccount.message(language: "zh").contains("登录"), "Explicit Chinese cloud status")
        try expect(CloudFailure.noAccount.message(language: "fr").contains("Connectez"), "Explicit French cloud status")
        let duplicate = DeviceSnapshot(version: 1, id: snapshot.id, name: snapshot.name, capturedAt: Date(), projects: [project, project])
        try expect((try? duplicate.encoded()) == nil, "Duplicate project IDs rejected")
        try expect((try? DeviceSnapshot.decode(Data(repeating: 0, count: DeviceSnapshot.byteLimit + 1))) == nil, "Oversized payload rejected")
        let future = DeviceSnapshot(version: 2, id: snapshot.id, name: snapshot.name, capturedAt: Date(), projects: [])
        try expect((try? future.encoded()) == nil, "Unsupported version rejected")

        let prefsFile = directory.appendingPathComponent("sync.json")
        var preferences = try SyncPreferences.read(prefsFile)
        try expect(!preferences.enabled && !FileManager.default.fileExists(atPath: prefsFile.path), "Default off, no write")
        preferences.select(["private-local-id"]); let opaque = preferences.projectIDs["private-local-id"]!
        preferences.select([]); preferences.select(["private-local-id"])
        try expect(preferences.projectIDs["private-local-id"] == opaque, "Stable opaque project ID")
        try preferences.save(prefsFile)
        let savedPreferences = try SyncPreferences.read(prefsFile)
        try expect(savedPreferences == preferences, "Private settings persist")

        let fake = FakeCloud()
        let publisherFile = directory.appendingPathComponent("publisher.json")
        let publisher = MacPublisher(file: publisherFile, cloud: fake, supported: true)
        var reads = 0
        publisher.read = { _, _, completion in
            reads += 1
            var local = project; local.id = "local-id"
            completion(Result { try JSONEncoder().encode(["projects": [local]]) })
        }
        publisher.start()
        try await Task.sleep(nanoseconds: 30_000_000)
        let offCalls = await fake.calls
        try expect(offCalls == 0 && reads == 0, "Disabled publisher makes no requests or project reads")
        try publisher.save(enabled: true, name: "Test Mac", selected: ["local-id"], includeText: false)
        try await wait { publisher.lastSuccess != nil }
        let uploaded = await fake.values
        try expect(uploaded.count == 1 && uploaded[0].projects[0].id != "local-id", "Publisher replaces local IDs")
        try expect(UUID(uuidString: uploaded[0].projects[0].id) != nil, "Publisher IDs are UUIDs")

        await fake.setFailing(true)
        try publisher.save(enabled: false, name: "Test Mac", selected: [], includeText: false)
        try await wait { publisher.status.contains("offline") || publisher.status.contains("operation") }
        try expect(publisher.preferences.pendingDelete && !publisher.preferences.enabled, "Offline deletion is durable and sync stays off")
        publisher.stop()
        await fake.setFailing(false)
        let retry = MacPublisher(file: publisherFile, cloud: fake, supported: true)
        retry.start()
        try await wait { !retry.preferences.pendingDelete }
        let removed = await fake.values
        try expect(removed.isEmpty, "Pending deletion retries after restart")
        retry.stop()

        // A selection changed during an asynchronous read never uploads the old read.
        let gatedFile = directory.appendingPathComponent("gated.json")
        let gated = MacPublisher(file: gatedFile, cloud: fake, supported: true)
        var firstReply: ((Result<Data, Error>) -> Void)?
        gated.read = { ids, _, reply in
            if ids == ["old"] { firstReply = reply }
            else { reply(.success(Data("{\"projects\":[]}".utf8))) }
        }
        try gated.save(enabled: true, name: "Test Mac", selected: ["old"], includeText: false)
        try await wait { firstReply != nil }
        try gated.save(enabled: true, name: "Test Mac", selected: ["new"], includeText: false)
        firstReply?(.success(Data("{\"projects\":[]}".utf8)))
        try await wait { gated.lastSuccess != nil }
        let selection = await fake.values
        try expect(selection.first?.projects.isEmpty == true, "Old selection cannot republish removed projects")
        await fake.setAccount("account-two")
        // Simulate a subsequent launch with persisted account binding.
        gated.stop()
        let changed = MacPublisher(file: gatedFile, cloud: fake, supported: true)
        changed.start(); try await wait { !changed.preferences.enabled }
        try expect(!changed.preferences.pendingDelete, "Account switch disables publishing and cannot delete another account’s data")
        changed.stop()

        let phoneFile = directory.appendingPathComponent("phone.json")
        await fake.setValues([snapshot])
        let phone = PhoneModel(cloud: fake, cache: phoneFile)
        await phone.refresh(manual: true)
        try expect(phone.snapshots == [snapshot] && !phone.cached, "Phone fetches snapshots")
        await fake.setFailing(true)
        let offline = PhoneModel(cloud: fake, cache: phoneFile)
        await offline.refresh(manual: true)
        try expect(offline.snapshots == [snapshot] && offline.cached, "Verified account can read offline cache")
        await fake.setAccount("account-three")
        offline.accountChanged()
        await offline.refresh(manual: true)
        try expect(offline.snapshots.isEmpty && !FileManager.default.fileExists(atPath: phoneFile.path), "Account change clears display and disk cache")
        await fake.setFailing(false); await fake.setValues([])
        await phone.refresh(manual: true) // account change clears old display first
        await phone.refresh(manual: true)
        try expect(phone.snapshots.isEmpty, "Deleted Mac disappears on next fetch")
        let previewCloud = FakeCloud()
        let preview = PhoneModel(cloud: previewCloud, cache: directory.appendingPathComponent("preview.json"), preview: true)
        await preview.refresh(manual: true)
        let previewCalls = await previewCloud.calls
        try expect(previewCalls == 0, "Preview cannot contact CloudKit")
        print("Sync checks passed: validation, opaque IDs, default off, publish, deletion retry, selection race, account changes, offline cache and preview isolation.")
    }
}
