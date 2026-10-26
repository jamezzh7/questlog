#if os(macOS)
import AppKit
import CloudKit

final class MacPublisher {
    let file: URL
    let supported: Bool
    var language: () -> String = { Locale.preferredLanguages.first ?? "en" }
    private func text(_ en: String, _ zh: String, _ fr: String) -> String { cloudText(en, zh, fr, language: language()) }
    private let cloud: SnapshotCloud
    private(set) var preferences: SyncPreferences
    private(set) var status = ""
    private(set) var lastSuccess: Date?
    var onChange: (() -> Void)?
    var read: (([String], Bool, @escaping (Result<Data, Error>) -> Void) -> Void)?
    private var timer: Timer?
    private var observer: NSObjectProtocol?
    private var task: Task<Void, Never>?
    private var generation = 0
    private var nextAttempt = Date.distantPast
    private var failures = 0
    private var requested = false
    private var stopped = false

    init(file: URL, cloud: SnapshotCloud = CloudKitTransport(), supported: Bool = CloudKitTransport.supported) {
        self.file = file; self.cloud = cloud; self.supported = supported
        do { preferences = try SyncPreferences.read(file) }
        catch {
            preferences = SyncPreferences()
            status = text("Sync settings could not be read. Sync is off; review and save your selection.", "同步设置无法读取，已关闭同步；请核对后重新保存。", "Impossible de lire les réglages de synchronisation. Vérifiez-les et enregistrez-les à nouveau.")
        }
    }
    deinit { timer?.invalidate(); task?.cancel(); if let observer { NotificationCenter.default.removeObserver(observer) } }
    func start() {
        guard timer == nil else { return }
        observer = NotificationCenter.default.addObserver(forName: .CKAccountChanged, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.generation += 1; self.preferences.enabled = false; self.preferences.pendingDelete = false; self.preferences.accountKey = nil
            self.lastSuccess = nil
            do { try self.preferences.save(self.file); self.status = CloudFailure.changedAccount.message(language: self.language()) }
            catch { self.status = error.localizedDescription }
            self.onChange?()
        }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.tick() }
        timer?.tolerance = 10; tick()
    }
    func stop() { stopped = true; timer?.invalidate(); timer = nil; task?.cancel() }
    func save(enabled: Bool, name: String, selected: [String], includeText: Bool) throws {
        let label = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty, label.count <= 60, selected.count <= 50, selected.allSatisfy({ !$0.isEmpty && $0.count <= 200 }), !enabled || !selected.isEmpty else { throw SnapshotFailure.invalid }
        if enabled && !supported { throw CloudFailure.build }
        var updated = preferences
        updated.enabled = enabled; updated.deviceName = label; updated.select(selected); updated.includeText = includeText
        updated.pendingDelete = !enabled && (preferences.enabled || preferences.pendingDelete || preferences.accountKey != nil)
        // Explicitly enabling after an account change consents to this account.
        if enabled && !preferences.enabled { updated.accountKey = nil }
        try updated.save(file); preferences = updated
        generation += 1; failures = 0; nextAttempt = .distantPast; requested = true
        status = enabled ? text("Waiting to sync…", "等待同步…", "En attente de synchronisation…") : updated.pendingDelete ? text("Removal pending; keep this Mac online.", "等待从 iCloud 移除，请保持这台 Mac 联网。", "Suppression en attente ; gardez ce Mac en ligne.") : text("Sync is off.", "同步已关闭。", "Synchronisation désactivée.")
        onChange?(); tick(force: true)
    }
    func tick(force: Bool = false) {
        guard !stopped, preferences.enabled || preferences.pendingDelete else { return }
        if force { requested = true; if failures == 0 { nextAttempt = .distantPast } }
        guard task == nil, Date() >= nextAttempt else { return }
        requested = false
        let revision = generation
        let selection = preferences.selected; let includeText = preferences.includeText
        task = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.task = nil
                if self.requested && !self.stopped { self.tick() }
            }
            do {
                let account = try await self.cloud.identity()
                try Task.checkCancellation()
                guard revision == self.generation else { return }
                if let bound = self.preferences.accountKey, bound != account { throw CloudFailure.changedAccount }
                if self.preferences.accountKey == nil {
                    var bound = self.preferences; bound.accountKey = account
                    try bound.save(self.file); self.preferences = bound
                }
                if !self.preferences.enabled {
                    try await self.cloud.remove(deviceID: self.preferences.deviceID)
                    guard revision == self.generation else { self.requested = true; return }
                    var removed = self.preferences; removed.pendingDelete = false; removed.accountKey = nil
                    try removed.save(self.file); self.preferences = removed; self.lastSuccess = nil
                    self.status = text("This Mac’s snapshot was removed from iCloud.", "这台 Mac 的快照已从 iCloud 移除。", "L’instantané de ce Mac a été supprimé d’iCloud.")
                } else {
                    self.status = text("Syncing…", "正在同步…", "Synchronisation…"); self.onChange?()
                    let bytes: Data = try await withCheckedThrowingContinuation { continuation in
                        guard let read = self.read else { continuation.resume(throwing: SnapshotFailure.invalid); return }
                        read(selection, includeText) { continuation.resume(with: $0) }
                    }
                    struct LocalSnapshot: Decodable { let projects: [SnapshotProject] }
                    let local = try JSONDecoder().decode(LocalSnapshot.self, from: bytes)
                    guard revision == self.generation else { self.requested = true; return }
                    let projects = try local.projects.map { project -> SnapshotProject in
                        guard selection.contains(project.id), let id = self.preferences.projectIDs[project.id] else { throw SnapshotFailure.invalid }
                        var remote = project; remote.id = id; return remote
                    }
                    let snapshot = DeviceSnapshot(version: 1, id: self.preferences.deviceID, name: self.preferences.deviceName, capturedAt: Date(), projects: projects)
                    try snapshot.validate(); try Task.checkCancellation()
                    guard try await self.cloud.identity() == account else { throw CloudFailure.changedAccount }
                    guard revision == self.generation else { self.requested = true; return }
                    try await self.cloud.publish(snapshot)
                    guard revision == self.generation else { self.requested = true; return }
                    self.lastSuccess = Date()
                    self.status = text("Synced. The iPhone must use the same iCloud account.", "已同步；请在 iPhone 使用同一个 iCloud 账号。", "Synchronisé. Utilisez le même compte iCloud sur l’iPhone.")
                }
                self.failures = 0; self.nextAttempt = Date().addingTimeInterval(55)
                self.onChange?()
            } catch is CancellationError { return }
            catch {
                guard revision == self.generation else { self.requested = true; return }
                if case CloudFailure.changedAccount = error {
                    self.preferences.enabled = false; self.preferences.pendingDelete = false; self.preferences.accountKey = nil
                    do { try self.preferences.save(self.file) } catch { /* disabled in memory; never publish in this run */ }
                    self.lastSuccess = nil
                }
                self.nextAttempt = Date().addingTimeInterval(cloudRetryDelay(error, failures: self.failures)); self.failures += 1
                self.status = cloudFailureMessage(error, language: self.language())
                self.onChange?()
            }
        }
    }
}

#endif
