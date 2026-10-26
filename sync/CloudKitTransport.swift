import Foundation
import CloudKit
import CryptoKit
#if os(macOS)
import Security
#endif

enum CloudFailure: LocalizedError, Equatable {
    case build, noAccount, restricted, temporary, changedAccount
    var errorDescription: String? { message() }
    func message(language: String = Locale.preferredLanguages.first ?? "en") -> String {
        func text(_ en: String, _ zh: String, _ fr: String) -> String { cloudText(en, zh, fr, language: language) }
        switch self {
        case .build: return text("iCloud sync requires a signed build with the Questlog CloudKit capability. See docs/icloud-sync.md.", "iCloud 同步需要带 Questlog CloudKit 权限的签名构建，配置方法见 docs/icloud-sync.md。", "La synchronisation iCloud nécessite une version signée avec la capacité CloudKit de Questlog. Voir docs/icloud-sync.md.")
        case .noAccount: return text("Sign in to iCloud in system settings on both devices.", "请在两台设备的系统设置中登录同一个 iCloud 账号。", "Connectez les deux appareils au même compte iCloud dans les réglages système.")
        case .restricted: return text("iCloud access is restricted on this device.", "这台设备的 iCloud 访问受到限制。", "L’accès à iCloud est restreint sur cet appareil.")
        case .temporary: return text("iCloud is temporarily unavailable. Your local projects are unaffected.", "iCloud 暂时不可用，本地项目不受影响。", "iCloud est temporairement indisponible. Vos projets locaux restent accessibles.")
        case .changedAccount: return text("The iCloud account changed. Review the selected projects and enable sync again.", "iCloud 账号已变化，请核对项目后重新启用同步。", "Le compte iCloud a changé. Vérifiez les projets sélectionnés et réactivez la synchronisation.")
        }
    }
}

protocol SnapshotCloud: AnyObject {
    func identity() async throws -> String
    func publish(_ snapshot: DeviceSnapshot) async throws
    func remove(deviceID: String) async throws
    func fetch() async throws -> [DeviceSnapshot]
}

actor CloudKitTransport: SnapshotCloud {
    static let containerID = "iCloud.com.jamezzh7.questlog"
    static var supported: Bool {
        #if os(macOS)
        guard let task = SecTaskCreateFromSelf(nil),
              let services = SecTaskCopyValueForEntitlement(task, "com.apple.developer.icloud-services" as CFString, nil) as? [String],
              let containers = SecTaskCopyValueForEntitlement(task, "com.apple.developer.icloud-container-identifiers" as CFString, nil) as? [String] else { return false }
        return services.contains("CloudKit") && containers.contains(containerID)
        #else
        return Bundle.main.object(forInfoDictionaryKey: "QuestlogCloudEnabled") as? Bool == true
        #endif
    }
    private let zoneID = CKRecordZone.ID(zoneName: "QuestlogSnapshots", ownerName: CKCurrentUserDefaultName)
    private let pageSize: Int
    init(pageSize: Int = 50) { self.pageSize = max(1, min(50, pageSize)) }
    private func container() throws -> CKContainer {
        guard Self.supported else { throw CloudFailure.build }
        return CKContainer(identifier: Self.containerID)
    }
    func identity() async throws -> String {
        let container = try container()
        switch try await container.accountStatus() {
        case .available: break
        case .noAccount: throw CloudFailure.noAccount
        case .restricted: throw CloudFailure.restricted
        default: throw CloudFailure.temporary
        }
        let id = try await container.userRecordID()
        return SHA256.hash(data: Data(id.recordName.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    func publish(_ snapshot: DeviceSnapshot) async throws {
        let data = try snapshot.encoded()
        let database = try container().privateCloudDatabase
        _ = try await database.save(CKRecordZone(zoneID: zoneID))
        let id = CKRecord.ID(recordName: snapshot.id, zoneID: zoneID)
        let record: CKRecord
        do { record = try await database.record(for: id) }
        catch let error as CKError where error.code == .unknownItem { record = CKRecord(recordType: "QuestlogDeviceSnapshot", recordID: id) }
        record["payload"] = data as CKRecordValue
        _ = try await database.save(record)
    }
    func remove(deviceID: String) async throws {
        guard UUID(uuidString: deviceID) != nil else { throw SnapshotFailure.invalid }
        let database = try container().privateCloudDatabase
        do { _ = try await database.deleteRecord(withID: CKRecord.ID(recordName: deviceID, zoneID: zoneID)) }
        catch let error as CKError where [.unknownItem, .zoneNotFound].contains(error.code) { return }
    }
    func fetch() async throws -> [DeviceSnapshot] {
        let database = try container().privateCloudDatabase
        let query = CKQuery(recordType: "QuestlogDeviceSnapshot", predicate: NSPredicate(value: true))
        var result: [DeviceSnapshot] = []
        var cursor: CKQueryOperation.Cursor?
        var bytes = 0
        repeat {
            try Task.checkCancellation()
            let page: (matchResults: [(CKRecord.ID, Result<CKRecord, Error>)], queryCursor: CKQueryOperation.Cursor?)
            do {
                if let cursor {
                    page = try await database.records(continuingMatchFrom: cursor, desiredKeys: ["payload"], resultsLimit: pageSize)
                } else {
                    page = try await database.records(matching: query, inZoneWith: zoneID, desiredKeys: ["payload"], resultsLimit: pageSize)
                }
            } catch let error as CKError where error.code == .zoneNotFound { return [] }
            for (id, recordResult) in page.matchResults {
                let record = try recordResult.get()
                guard let payload = record["payload"] as? Data else { throw SnapshotFailure.invalid }
                bytes += payload.count
                guard bytes <= 4_000_000 else { throw SnapshotFailure.invalid }
                let snapshot = try DeviceSnapshot.decode(payload)
                guard snapshot.id == id.recordName, !result.contains(where: { $0.id == snapshot.id }) else { throw SnapshotFailure.invalid }
                result.append(snapshot)
                guard result.count <= 100 else { throw SnapshotFailure.invalid }
            }
            cursor = page.queryCursor
        } while cursor != nil
        // Full replacement on the phone also removes deleted/unselected data.
        return result.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

func cloudRetryDelay(_ error: Error, failures: Int) -> TimeInterval {
    let suggested = (error as? CKError)?.retryAfterSeconds ?? 0
    return max(suggested, min(900, 30 * pow(2, Double(min(failures, 5)))))
}

func cloudFailureMessage(_ error: Error, language: String = Locale.preferredLanguages.first ?? "en") -> String {
    func text(_ en: String, _ zh: String, _ fr: String) -> String { cloudText(en, zh, fr, language: language) }
    if let failure = error as? CloudFailure { return failure.message(language: language) }
    if error is SnapshotFailure { return text("The snapshot could not be read. Update Questlog on both devices and try again.", "无法读取快照，请更新两端 Questlog 后重试。", "L’instantané est illisible. Mettez Questlog à jour sur les deux appareils, puis réessayez.") }
    if let cloud = error as? CKError {
        switch cloud.code {
        case .networkUnavailable, .networkFailure, .serviceUnavailable, .zoneBusy, .requestRateLimited:
            return text("iCloud is unavailable. Keep the device online; Questlog will retry automatically.", "iCloud 暂时不可用；请保持联网，Questlog 会自动重试。", "iCloud est indisponible. Restez en ligne ; Questlog réessaiera automatiquement.")
        case .notAuthenticated: return CloudFailure.noAccount.message(language: language)
        case .badContainer, .badDatabase, .missingEntitlement, .permissionFailure:
            return text("Check this build’s iCloud signing, container and development/production environment. See docs/icloud-sync.md.", "请检查此构建的 iCloud 签名、容器及开发／生产环境，配置方法见 docs/icloud-sync.md。", "Vérifiez la signature iCloud, le conteneur et l’environnement de cette version. Voir docs/icloud-sync.md.")
        case .invalidArguments:
            return text("Check the CloudKit schema: QuestlogDeviceSnapshot needs a queryable recordName index.", "请检查 CloudKit schema：QuestlogDeviceSnapshot 需要 recordName 的 Queryable 索引。", "Vérifiez le schéma CloudKit : QuestlogDeviceSnapshot nécessite un index queryable sur recordName.")
        case .quotaExceeded:
            return text("iCloud storage is full. Free some space and try again.", "iCloud 储存空间已满，请释放空间后重试。", "Le stockage iCloud est plein. Libérez de l’espace et réessayez.")
        case .serverRejectedRequest:
            return text("iCloud rejected the request (CloudKit 15). Questlog will retry; check the container setup if this persists.", "iCloud 拒绝了请求（CloudKit 15），Questlog 会重试；若持续出现，请检查容器配置。", "iCloud a refusé la requête (CloudKit 15). Questlog réessaiera ; vérifiez le conteneur si le problème persiste.")
        default: break
        }
    }
    return error.localizedDescription
}
