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
    var signedIn = true
    func identity() async throws -> String { calls += 1; if !signedIn { throw CloudFailure.noAccount }; return account }
    func publish(_ snapshot: DeviceSnapshot) async throws {
        calls += 1; if failing { throw CheckFailure.offline }
        try snapshot.validate(); values = [snapshot]
    }
    func remove(deviceID: String) async throws {
        calls += 1; if failing { throw CheckFailure.offline }
        values.removeAll { $0.id == deviceID }
    }
    func fetch() async throws -> [DeviceSnapshot] { calls += 1; if failing { throw CheckFailure.offline }; return values }
    func setSignedIn(_ value: Bool) { signedIn = value }
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

        // Additive metadata remains compatible with version-1 snapshots and caches.
        let activity = SnapshotActivity(active: true, blocked: true)
        let flagged = SnapshotProject(id: UUID().uuidString, name: "Beacon", state: "ready", mode: "status", scope: "", counts: SnapshotCounts(done: 0, total: 0, active: 0, blocked: 0, pending: 0, unknown: 0), percent: nil, signals: [], needsReview: false, activity: activity)
        try expect(flagged.valid && flagged.inProgress && flagged.blocked && flagged.needsAttention, "Status flags work without any shared prose")
        let newSnapshot = DeviceSnapshot(version: 1, id: snapshot.id, name: snapshot.name, capturedAt: snapshot.capturedAt, projects: [flagged])
        let newDecoded = try DeviceSnapshot.decode(newSnapshot.encoded())
        try expect(newDecoded.projects[0].activity == activity, "Structured flags survive the payload round trip")
        var oldJSON = try JSONSerialization.jsonObject(with: newSnapshot.encoded()) as! [String: Any]
        var oldProjects = oldJSON["projects"] as! [[String: Any]]; oldProjects[0].removeValue(forKey: "activity"); oldJSON["projects"] = oldProjects
        let oldDecoded = try DeviceSnapshot.decode(JSONSerialization.data(withJSONObject: oldJSON))
        try expect(oldDecoded.projects[0].activity == nil && !oldDecoded.projects[0].inProgress, "Old version-1 payloads decode with unknown activity")
        oldProjects[0]["activity"] = ["active": "true", "blocked": true]; oldJSON["projects"] = oldProjects
        try expect((try? DeviceSnapshot.decode(JSONSerialization.data(withJSONObject: oldJSON))) == nil, "Activity flags must be booleans")
        let manyTasks = SnapshotProject(id: UUID().uuidString, name: "Many tasks", state: "ready", mode: "tasks", scope: "", counts: SnapshotCounts(done: 1, total: 10, active: 8, blocked: 1, pending: 0, unknown: 0), percent: nil, signals: [], needsReview: false)
        let overview = SnapshotOverview([DeviceSnapshot(version: 1, id: snapshot.id, name: snapshot.name, capturedAt: Date(), projects: [manyTasks, flagged])])
        try expect(overview.projects == 2 && overview.inProgress == 2 && overview.attention == 2, "All overview statistics count projects, with active and blocked allowed to overlap")
        let unreadable = SnapshotProject(id: UUID().uuidString, name: "Gone", state: "permission", mode: "unknown", scope: "", counts: nil, percent: nil, signals: [], needsReview: false)
        try expect(unreadable.valid && !unreadable.inProgress && unreadable.needsAttention, "Revoked sources cannot appear active")
        try expect(snapshot.freshness(cached: false, at: snapshot.capturedAt) == .recent, "Fresh capture is recent")
        try expect(snapshot.freshness(cached: true, at: snapshot.capturedAt) == .cached, "Recent cached data never receives the recent indicator")
        try expect(snapshot.freshness(cached: false, at: snapshot.capturedAt.addingTimeInterval(181)) == .stale, "Old capture is stale")
        try expect(snapshot.freshness(cached: true, at: snapshot.capturedAt.addingTimeInterval(-61)) == .clockSkew, "Future timestamps require a clock check even when cached")
        try expect(!CloudKitTransport.cloudEnabled("NO") && !CloudKitTransport.cloudEnabled("$(CODE_SIGNING_ALLOWED)") && !CloudKitTransport.cloudEnabled(nil), "Unsigned and unresolved build metadata fail closed")
        try expect(CloudKitTransport.cloudEnabled("YES") && CloudKitTransport.cloudEnabled(true), "Signed and legacy build flags are accepted")

        let prefsFile = directory.appendingPathComponent("sync.json")
        var preferences = try SyncPreferences.read(prefsFile)
        try expect(preferences.enabled && preferences.automaticProjects && !FileManager.default.fileExists(atPath: prefsFile.path), "Automatic sync by default, no write before connecting")
        preferences.select(["private-local-id"]); let opaque = preferences.projectIDs["private-local-id"]!
        preferences.select([]); preferences.select(["private-local-id"])
        try expect(preferences.projectIDs["private-local-id"] == opaque, "Stable opaque project ID")
        try preferences.save(prefsFile)
        let savedPreferences = try SyncPreferences.read(prefsFile)
        try expect(savedPreferences == preferences, "Private settings persist")

        // New projects follow connections without a sync settings visit.
        var autoPreferences = SyncPreferences()
        try autoPreferences.connect(["first"])
        let firstID = autoPreferences.projectIDs["first"]
        try autoPreferences.connect(["first", "second"])
        try expect(autoPreferences.selected == ["first", "second"] && autoPreferences.projectIDs["first"] == firstID, "New connections auto-join with stable IDs")
        autoPreferences.excluded = ["second"]
        try autoPreferences.connect(["first", "second", "third"])
        try expect(autoPreferences.selected == ["first", "third"], "Exclusions do not prevent future projects auto-joining")
        try autoPreferences.connect(["third"])
        try expect(autoPreferences.selected == ["third"], "Disconnected projects leave the snapshot")
        try autoPreferences.connect((0..<60).map { "project-\($0)" })
        try expect(autoPreferences.selected.count == 50, "Automatic selection respects the payload limit")
        let slots = autoPreferences.selected
        try autoPreferences.connect(["a-new-project"] + (0..<60).map { "project-\($0)" })
        try expect(autoPreferences.selected == slots, "Overflow does not displace projects already on the phone")

        var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(preferences)) as! [String: Any]
        legacy.removeValue(forKey: "automaticProjects"); legacy.removeValue(forKey: "excluded")
        legacy["enabled"] = true
        let legacyBytes = try JSONSerialization.data(withJSONObject: legacy)
        var migrated = try JSONDecoder().decode(SyncPreferences.self, from: legacyBytes)
        try migrated.connect(["private-local-id", "previously-unselected"])
        try expect(migrated.selected == ["private-local-id"] && migrated.excluded == ["previously-unselected"], "Upgrade retains old explicit exclusions")
        try expect(migrated.projectIDs["private-local-id"] == opaque, "Upgrade preserves remote project identity")
        migrated.enabled = false
        try migrated.connect(["private-local-id", "previously-unselected", "future-project"])
        try expect(!migrated.enabled && migrated.selected.contains("future-project"), "An explicit stop survives new connections")

        let autoCloud = FakeCloud()
        let autoFile = directory.appendingPathComponent("automatic.json")
        let automatic = MacPublisher(file: autoFile, cloud: autoCloud, supported: true)
        var connections = ["first"]
        automatic.connectedProjects = { connections }
        automatic.read = { ids, _, completion in
            completion(Result { try JSONEncoder().encode(["projects": ids.map { id -> SnapshotProject in var local = project; local.id = id; return local }]) })
        }
        automatic.start()
        try await wait { await autoCloud.values.first?.projects.count == 1 }
        connections = ["first", "second"]; automatic.tick()
        try await wait { await autoCloud.values.first?.projects.count == 2 }
        let automaticIDs = automatic.preferences.projectIDs
        try automatic.save(enabled: true, name: "Test Mac", selected: ["first"], includeText: false, displayed: connections)
        try await wait { await autoCloud.values.first?.projects.count == 1 }
        connections.append("third"); automatic.tick()
        try await wait { await autoCloud.values.first?.projects.count == 2 }
        try expect(automatic.preferences.selected == ["first", "third"] && !automatic.preferences.includeText, "New connections sync without sharing excluded projects or status text")
        connections = ["third"]; automatic.tick()
        try await wait { await autoCloud.values.first?.projects.count == 1 }
        try automatic.save(enabled: false, name: "Test Mac", selected: automatic.preferences.selected, includeText: false)
        try await wait { !automatic.preferences.pendingDelete }
        automatic.stop()
        let paused = MacPublisher(file: autoFile, cloud: autoCloud, supported: true)
        connections.append("fourth"); paused.connectedProjects = { connections }
        let pausedCalls = await autoCloud.calls
        paused.start(); try await Task.sleep(nanoseconds: 30_000_000)
        try expect(!paused.preferences.enabled && paused.preferences.projectIDs["first"] == automaticIDs["first"], "Pause and identity persist after restarting")
        let stillPausedCalls = await autoCloud.calls
        try expect(stillPausedCalls == pausedCalls, "Paused sync does not contact CloudKit")
        paused.stop()
        let unsupportedCloud = FakeCloud()
        let unsupported = MacPublisher(file: directory.appendingPathComponent("local-only.json"), cloud: unsupportedCloud, supported: false)
        unsupported.connectedProjects = { ["first"] }; unsupported.start()
        try await Task.sleep(nanoseconds: 30_000_000)
        let unsupportedCalls = await unsupportedCloud.calls
        try expect(unsupportedCalls == 0, "Unprovisioned local builds never call CloudKit")
        unsupported.stop()

        let signInCloud = FakeCloud(); await signInCloud.setSignedIn(false)
        let signIn = MacPublisher(file: directory.appendingPathComponent("sign-in.json"), cloud: signInCloud, supported: true)
        signIn.connectedProjects = { ["first"] }
        signIn.read = automatic.read
        signIn.start()
        try await wait { signIn.status == CloudFailure.noAccount.message(language: signIn.language()) }
        await signInCloud.setSignedIn(true)
        NotificationCenter.default.post(name: .CKAccountChanged, object: nil)
        try await wait { signIn.lastSuccess != nil }
        try expect(signIn.preferences.enabled, "First iCloud sign-in resumes automatically without a settings visit")
        let boundAccount = signIn.preferences.accountKey
        NotificationCenter.default.post(name: .CKAccountChanged, object: nil)
        try await wait { signIn.lastSuccess != nil }
        try expect(signIn.preferences.enabled && signIn.preferences.accountKey == boundAccount, "Repeated same-account notifications do not turn sync off")
        // Stopping and deletion must not depend on a readable project configuration.
        signIn.connectedProjects = { throw SnapshotFailure.invalid }
        try signIn.save(enabled: false, name: "Test Mac", selected: signIn.preferences.selected, includeText: false)
        try await wait { !signIn.preferences.pendingDelete }
        let signInValues = await signInCloud.values
        try expect(signInValues.isEmpty, "Stop/remove works even if local connection settings are unreadable")
        signIn.stop()
        let corruptFile = directory.appendingPathComponent("corrupt.json")
        let corruptBytes = Data("invalid settings".utf8); try corruptBytes.write(to: corruptFile)
        let corruptCloud = FakeCloud()
        let corrupt = MacPublisher(file: corruptFile, cloud: corruptCloud, supported: true)
        corrupt.connectedProjects = { ["first"] }; corrupt.start()
        try await Task.sleep(nanoseconds: 30_000_000)
        let corruptCalls = await corruptCloud.calls
        let retainedBytes = try Data(contentsOf: corruptFile)
        try expect(!corrupt.preferences.enabled && corruptCalls == 0 && retainedBytes == corruptBytes, "Unreadable sync preferences remain off and are preserved for recovery")
        corrupt.stop()

        let fake = FakeCloud()
        let publisherFile = directory.appendingPathComponent("publisher.json")
        let publisher = MacPublisher(file: publisherFile, cloud: fake, supported: true)
        var reads = 0
        publisher.read = { _, _, completion in
            reads += 1
            var local = flagged; local.id = "local-id"
            completion(Result { try JSONEncoder().encode(["projects": [local]]) })
        }
        publisher.start()
        try await Task.sleep(nanoseconds: 30_000_000)
        let offCalls = await fake.calls
        try expect(offCalls == 0 && reads == 0, "No connected projects makes no requests or project reads")
        try publisher.save(enabled: true, name: "Test Mac", selected: ["local-id"], includeText: false)
        try await wait { publisher.lastSuccess != nil }
        let uploaded = await fake.values
        try expect(uploaded.count == 1 && uploaded[0].projects[0].id != "local-id", "Publisher replaces local IDs")
        try expect(UUID(uuidString: uploaded[0].projects[0].id) != nil, "Publisher IDs are UUIDs")
        try expect(uploaded[0].projects[0].activity == activity, "Publisher preserves structured activity when replacing local IDs")

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
        var changingConnections = ["old"]
        gated.connectedProjects = { changingConnections }; gated.start()
        try await wait { firstReply != nil }
        changingConnections = ["new"]; gated.tick()
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
        print("Sync checks passed: validation, opaque IDs, automatic connections, exclusions, migration, pause, publish, deletion retry, selection race, account changes, offline cache and preview isolation.")
    }
}
