import Foundation
import Combine
import CloudKit

private struct PhoneCache: Codable {
    let account: String; let snapshots: [DeviceSnapshot]; let fetchedAt: Date
}

@MainActor final class PhoneModel: ObservableObject {
    @Published private(set) var snapshots: [DeviceSnapshot] = []
    @Published private(set) var refreshing = false
    @Published private(set) var message = ""
    @Published private(set) var lastFetch: Date?
    @Published private(set) var cached = false
    @Published private(set) var resetToken = UUID()
    let preview: Bool
    private let cloud: SnapshotCloud
    private let cache: URL
    private var account: String?
    private var generation = 0
    private var observer: NSObjectProtocol?
    private var nextAttempt = Date.distantPast
    private var failures = 0

    init(cloud: SnapshotCloud = CloudKitTransport(), cache: URL? = nil, preview: Bool = false) {
        self.cloud = cloud; self.preview = preview
        self.cache = cache ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("QuestlogPhone/snapshots.json")
        observer = NotificationCenter.default.addObserver(forName: .CKAccountChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.accountChanged() }
        }
    }
    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }
    func accountChanged() {
        generation += 1; account = nil; snapshots = []; lastFetch = nil; cached = false; nextAttempt = .distantPast
        resetToken = UUID()
        failures = 0
        try? FileManager.default.removeItem(at: cache)
        message = CloudFailure.changedAccount.localizedDescription
    }
    func refresh(manual: Bool = false) async {
        guard !preview, !refreshing, Date() >= nextAttempt || (manual && failures == 0) else { return }
        refreshing = true
        let revision = generation
        defer { refreshing = false }
        do {
            let identity = try await cloud.identity()
            guard revision == generation else { return }
            if let account, identity != account { accountChanged(); return }
            if account == nil {
                account = identity
                loadCache(account: identity)
            }
            let values = try await cloud.fetch()
            try Task.checkCancellation()
            guard revision == generation, identity == account else { return }
            for snapshot in values { try snapshot.validate() }
            snapshots = values; lastFetch = Date(); cached = false; message = ""
            failures = 0; nextAttempt = Date().addingTimeInterval(50)
            do { try saveCache(account: identity) }
            catch { message = cloudText("Updated, but the offline copy could not be saved.", "已更新，但无法保存离线副本。", "Mise à jour réussie, mais la copie hors ligne n’a pas pu être enregistrée.") }
        } catch is CancellationError { return }
        catch {
            guard revision == generation else { return }
            if (error as? CloudFailure).map({ [.noAccount, .restricted, .changedAccount].contains($0) }) == true || (error as? CKError)?.code == .notAuthenticated {
                accountChanged()
            }
            cached = !snapshots.isEmpty
            message = cloudFailureMessage(error)
            nextAttempt = Date().addingTimeInterval(cloudRetryDelay(error, failures: failures)); failures += 1
        }
    }
    private func loadCache(account: String) {
        guard let data = try? Data(contentsOf: cache), data.count <= 4_000_000,
              let saved = try? JSONDecoder().decode(PhoneCache.self, from: data), saved.account == account,
              saved.snapshots.count <= 100, saved.snapshots.allSatisfy({ (try? $0.validate()) != nil }) else {
            try? FileManager.default.removeItem(at: cache); return
        }
        snapshots = saved.snapshots; lastFetch = saved.fetchedAt; cached = !snapshots.isEmpty
    }
    private func saveCache(account: String) throws {
        let data = try JSONEncoder().encode(PhoneCache(account: account, snapshots: snapshots, fetchedAt: lastFetch ?? Date()))
        guard data.count <= 4_000_000 else { throw SnapshotFailure.invalid }
        try FileManager.default.createDirectory(at: cache.deletingLastPathComponent(), withIntermediateDirectories: true)
        #if os(iOS)
        try data.write(to: cache, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: cache, options: .atomic)
        #endif
    }
    func clearCache() {
        snapshots = []; cached = false; lastFetch = nil
        resetToken = UUID()
        try? FileManager.default.removeItem(at: cache)
    }
    #if DEBUG
    func showPreview(_ snapshots: [DeviceSnapshot]) {
        guard preview else { return }
        self.snapshots = snapshots; lastFetch = Date()
    }
    #endif
}
