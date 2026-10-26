import SwiftUI

private func tr(_ en: String, _ zh: String, _ fr: String) -> String { cloudText(en, zh, fr) }

@main struct QuestlogPhone: App {
    @StateObject private var model: PhoneModel
    @Environment(\.scenePhase) private var phase
    init() {
        #if DEBUG
        let preview = ProcessInfo.processInfo.arguments.contains("--preview")
        let model = PhoneModel(preview: preview)
        if preview { model.showPreview(previewSnapshots()) }
        #else
        let model = PhoneModel()
        #endif
        _model = StateObject(wrappedValue: model)
    }
    var body: some Scene {
        WindowGroup {
            PhoneHome(model: model)
                .tint(Color(red: 0.29, green: 0.38, blue: 0.66))
                .task(id: phase) {
                    guard phase == .active else { return }
                    await model.refresh()
                    while !Task.isCancelled {
                        do { try await Task.sleep(nanoseconds: 60_000_000_000) } catch { return }
                        guard phase == .active else { return }; await model.refresh()
                    }
                }
        }
    }
}

private struct PhoneHome: View {
    @ObservedObject var model: PhoneModel
    @State private var settings = false
    var body: some View {
        NavigationStack {
            List {
                if model.preview { Text(tr("Preview · fictional projects · no iCloud connection", "预览 · 虚构项目 · 未连接 iCloud", "Aperçu · projets fictifs · sans connexion iCloud")).font(.footnote).foregroundStyle(.secondary) }
                if !model.message.isEmpty {
                    Section { Label(model.message, systemImage: model.cached ? "wifi.slash" : "icloud.slash").font(.callout) }
                }
                if model.refreshing && model.snapshots.isEmpty { HStack { ProgressView(); Text(tr("Reading iCloud…", "正在读取 iCloud…", "Lecture d’iCloud…")) } }
                if !model.refreshing && model.snapshots.isEmpty {
                    Section {
                        Image(systemName: "laptopcomputer.and.iphone").font(.system(size: 40)).foregroundStyle(.tint).padding(.vertical, 8).accessibilityHidden(true)
                        Text(tr("Your Mac’s progress, here.", "在这里查看 Mac 项目进度", "L’avancement de votre Mac, ici.")).font(.title2.weight(.semibold))
                        Text(tr("On your Mac, open Questlog → iPhone sync, choose projects and save. Sign in to the same iCloud account on both devices.", "在 Mac 打开 Questlog → iPhone 同步，选择项目并保存。两台设备需使用同一个 iCloud 账号。", "Sur le Mac, ouvrez Questlog → Synchronisation iPhone, choisissez des projets et enregistrez. Utilisez le même compte iCloud sur les deux appareils."))
                            .font(.callout).foregroundStyle(.secondary)
                        Text(tr("The Mac must stay awake with Questlog running to send updates.", "Mac 需要保持唤醒且 Questlog 正在运行，才能发送新状态。", "Le Mac doit rester éveillé et Questlog ouvert pour envoyer les mises à jour.")).font(.footnote).foregroundStyle(.secondary)
                    }.listRowSeparator(.hidden)
                }
                ForEach(model.snapshots) { snapshot in
                    Section {
                        ForEach(snapshot.projects) { project in
                            NavigationLink {
                                ProjectDestination(model: model, deviceID: snapshot.id, projectID: project.id)
                            } label: { ProjectRow(project: project) }
                        }
                        if snapshot.projects.isEmpty { Text(tr("No projects shared from this Mac.", "这台 Mac 尚未分享项目。", "Aucun projet partagé depuis ce Mac.")).foregroundStyle(.secondary) }
                    } header: {
                        Text(snapshot.name).textCase(nil)
                    } footer: { Freshness(device: snapshot) }
                }
                if let lastFetch = model.lastFetch {
                    Section { Text((model.cached ? tr("Offline copy · last fetched ", "离线副本 · 上次读取 ", "Copie hors ligne · dernière lecture ") : tr("Phone last fetched ", "手机上次读取 ", "Dernière lecture sur l’iPhone ")) + lastFetch.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary) }
                }
            }
            .navigationTitle("Questlog")
            .refreshable { await model.refresh(manual: true) }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { settings = true } label: { Image(systemName: "gearshape") }.accessibilityLabel(tr("Settings", "设置", "Réglages"))
                }
                ToolbarItem(placement: .topBarLeading) {
                    if model.refreshing { ProgressView() }
                    else { Button { Task { await model.refresh(manual: true) } } label: { Image(systemName: "arrow.clockwise") }.accessibilityLabel(tr("Refresh", "刷新", "Actualiser")) }
                }
            }
            .sheet(isPresented: $settings) { PhoneSettings(model: model) }
        }.id(model.resetToken)
    }
}

private struct ProjectDestination: View {
    @ObservedObject var model: PhoneModel
    let deviceID: String; let projectID: String
    var body: some View {
        if let device = model.snapshots.first(where: { $0.id == deviceID }), let project = device.projects.first(where: { $0.id == projectID }) {
            ProjectDetail(project: project, device: device)
        } else { Text(tr("This project is no longer shared.", "此项目已停止分享。", "Ce projet n’est plus partagé.")).foregroundStyle(.secondary).padding() }
    }
}

private struct ProjectRow: View {
    let project: SnapshotProject
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(project.name).font(.headline)
                Spacer(minLength: 12)
                if let percent = project.percent, project.mode == "measured" { Text("\(percent)%").font(.headline.monospacedDigit()).foregroundStyle(.tint) }
            }
            Text(projectStatus(project)).font(.subheadline).foregroundStyle(.secondary)
            if project.state == "ready", project.mode == "measured", let percent = project.percent {
                ProgressView(value: Double(percent), total: 100).accessibilityLabel(project.scope)
            }
            if let signal = project.signals.first(where: { $0.kind == "blocker" }) ?? project.signals.first {
                Text(signal.text).font(.footnote).foregroundStyle(signal.kind == "blocker" ? Color.orange : .secondary).lineLimit(2)
            }
        }.padding(.vertical, 5)
    }
}

private func projectStatus(_ p: SnapshotProject) -> String {
    if p.state == "permission" { return tr("Folder access required on Mac", "需要在 Mac 重新授权目录", "Autorisez le dossier sur le Mac") }
    if p.state != "ready" { return tr("Unable to read on Mac", "Mac 暂时无法读取", "Lecture impossible sur le Mac") }
    if p.needsReview { return tr("Source states need review", "来源状态待核对", "États des sources à vérifier") }
    if let c = p.counts, c.total > 0 {
        return p.mode == "measured" ? "\(p.scope) · \(c.done)/\(c.total)" : tr("\(c.done)/\(c.total) detected · scope unknown", "已识别 \(c.done)/\(c.total) · 范围未知", "\(c.done)/\(c.total) détectées · périmètre inconnu")
    }
    return p.mode == "status" ? tr("Project state · no defined scope", "项目近况 · 尚无明确范围", "État du projet · sans périmètre défini") : tr("More project information needed", "等待补充项目资料", "Informations supplémentaires nécessaires")
}

private struct Freshness: View {
    let device: DeviceSnapshot
    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(alignment: .leading, spacing: 4) {
                Text(tr("Mac updated ", "Mac 更新于 ", "Mac mis à jour le ") + device.capturedAt.formatted(date: .abbreviated, time: .shortened))
                if device.stale(at: context.date) {
                    Label(tr("Older snapshot. The Mac may be asleep or offline.", "快照较旧，Mac 可能已休眠或离线。", "Instantané ancien. Le Mac peut être en veille ou hors ligne."), systemImage: "clock")
                }
            }.font(.caption).foregroundStyle(Color(uiColor: .secondaryLabel))
        }
    }
}

private struct ProjectDetail: View {
    let project: SnapshotProject; let device: DeviceSnapshot
    var body: some View {
        List {
            Section { ProjectRow(project: project) }
            if let c = project.counts, c.total > 0 {
                Section(tr("Observed tasks", "任务统计", "Tâches observées")) {
                    count(tr("Completed", "已完成", "Terminées"), c.done)
                    count(tr("In progress", "进行中", "En cours"), c.active)
                    count(tr("Blocked", "有阻塞", "Bloquées"), c.blocked)
                    count(tr("Pending", "待完成", "À faire"), c.pending)
                    if c.unknown > 0 { count(tr("Unknown", "状态未知", "État inconnu"), c.unknown) }
                }
            }
            if !project.signals.isEmpty {
                Section(tr("Shared status text", "已分享的近况原文", "Textes partagés")) {
                    ForEach(Array(project.signals.enumerated()), id: \.offset) { _, signal in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(signalTitle(signal.kind)).font(.caption).foregroundStyle(.secondary)
                            Text(signal.text).textSelection(.enabled)
                        }.padding(.vertical, 4)
                    }
                }
            }
            Section(device.name) {
                Freshness(device: device)
                Text(tr("Read-only snapshot. Updates depend on the Mac’s source files; this does not measure a running job directly.", "这里只读展示快照。更新取决于 Mac 上的项目资料，不直接测量正在运行的工作。", "Instantané en lecture seule. Les mises à jour dépendent des documents sur le Mac ; elles ne mesurent pas directement une tâche en cours."))
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }.navigationTitle(project.name).navigationBarTitleDisplayMode(.inline)
    }
    private func count(_ name: String, _ number: Int) -> some View { HStack { Text(name); Spacer(); Text(number.formatted()).monospacedDigit().foregroundStyle(.secondary) } }
    private func signalTitle(_ kind: String) -> String {
        switch kind {
        case "current": return tr("Current", "当前", "En cours")
        case "blocker": return tr("Blocker", "阻塞", "Blocage")
        case "next": return tr("Next", "下一步", "Suite")
        case "delivery": return tr("Recent delivery", "近期交付", "Livraison récente")
        default: return tr("Status", "状态", "État")
        }
    }
}

private struct PhoneSettings: View {
    @ObservedObject var model: PhoneModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section("iCloud") {
                    Text(tr("Uses your existing iCloud account. No Questlog registration is needed.", "使用现有 iCloud 账号，无需注册 Questlog。", "Utilise votre compte iCloud existant, sans inscription à Questlog."))
                    Text(tr("Select shared projects in Questlog on your Mac. To remove this Mac’s cloud data, choose Stop and remove there and wait for confirmation.", "在 Mac 端选择分享的项目。删除云端数据时，在对应 Mac 点击“停止并移除”，并等待完成提示。", "Choisissez les projets sur le Mac. Pour supprimer ses données iCloud, cliquez sur Arrêter et supprimer sur ce Mac et attendez la confirmation."))
                }
                Section(tr("Privacy", "隐私", "Confidentialité")) {
                    Text(tr("Only selected summaries are shared through your private iCloud database. Original documents, local paths and access permissions stay on the Mac. Status text is a separate opt-in and can contain confidential content.", "只有选定的摘要会进入自己的 iCloud 私有数据库。原始文档、目录路径和访问权限留在 Mac；近况原文需单独开启，可能包含敏感内容。", "Seuls les résumés choisis sont partagés via votre base iCloud privée. Documents, chemins et autorisations restent sur le Mac. Le partage facultatif des textes peut inclure des données confidentielles."))
                    Button(tr("Clear offline copy on this iPhone", "清除这台 iPhone 的离线副本", "Effacer la copie hors ligne de cet iPhone")) { model.clearCache() }
                    Link(tr("Full privacy policy", "完整隐私政策", "Politique de confidentialité"), destination: URL(string: "https://github.com/jamezzh7/questlog/blob/main/docs/privacy.md")!)
                }
            }.navigationTitle(tr("Settings", "设置", "Réglages"))
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button(tr("Done", "完成", "Terminé")) { dismiss() } } }
        }
    }
}

#if DEBUG
private func previewSnapshots() -> [DeviceSnapshot] {
    let known = SnapshotCounts(done: 3, total: 5, active: 1, blocked: 0, pending: 1, unknown: 0)
    let partial = SnapshotCounts(done: 1, total: 4, active: 1, blocked: 1, pending: 1, unknown: 0)
    let empty = SnapshotCounts(done: 0, total: 0, active: 0, blocked: 0, pending: 0, unknown: 0)
    let projects = [
        SnapshotProject(id: "00000000-0000-4000-8000-000000000001", name: "Orbit", state: "ready", mode: "measured", scope: tr("Release 0.2", "0.2 版本", "Version 0.2"), counts: known, percent: 60, signals: [], needsReview: false),
        SnapshotProject(id: "00000000-0000-4000-8000-000000000002", name: "Trail", state: "ready", mode: "tasks", scope: "", counts: partial, percent: nil, signals: [], needsReview: false),
        SnapshotProject(id: "00000000-0000-4000-8000-000000000003", name: "Beacon", state: "ready", mode: "status", scope: "", counts: empty, percent: nil, signals: [SnapshotSignal(kind: "blocker", text: tr("Waiting for review of the export format.", "等待导出格式评审。", "En attente de validation du format d’export.")), SnapshotSignal(kind: "next", text: tr("Verify the sample report.", "验证示例报告。", "Vérifier le rapport d’exemple."))], needsReview: false)
    ]
    return [DeviceSnapshot(version: 1, id: "00000000-0000-4000-8000-000000000010", name: "Studio Mac", capturedAt: Date().addingTimeInterval(-240), projects: projects)]
}
#endif
