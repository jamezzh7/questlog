import SwiftUI

@main struct QuestlogPhone: App {
    @StateObject private var model: PhoneModel
    @Environment(\.scenePhase) private var phase
    init() {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        let preview = arguments.contains { ["--preview", "--preview-empty", "--preview-no-text", "--preview-offline"].contains($0) }
        let model = PhoneModel(preview: preview)
        if preview && !arguments.contains("--preview-empty") {
            model.showPreview(previewSnapshots(includeText: !arguments.contains("--preview-no-text")), cached: arguments.contains("--preview-offline"))
        }
        #else
        let model = PhoneModel()
        #endif
        _model = StateObject(wrappedValue: model)
    }
    var body: some Scene {
        WindowGroup {
            PhoneHome(model: model)
                .tint(Palette.accent)
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

private struct ProjectRoute: Hashable { let deviceID: String; let projectID: String }

private struct PhoneHome: View {
    @ObservedObject var model: PhoneModel
    @State private var settings = false
    @Namespace private var zoom
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if model.preview {
                        Label(tr("Preview · fictional projects · no iCloud connection", "预览 · 虚构项目 · 未连接 iCloud", "Aperçu · projets fictifs · sans connexion iCloud"), systemImage: "sparkles")
                            .font(.footnote.weight(.medium)).foregroundStyle(Palette.accent)
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(Palette.accentSoft, in: Capsule())
                    }
                    if !model.message.isEmpty {
                        Label(model.message, systemImage: model.cached ? "wifi.slash" : "icloud.slash")
                            .font(.callout).foregroundStyle(Palette.warn)
                            .card(padding: 14)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    if model.refreshing && model.snapshots.isEmpty {
                        ForEach(0..<3, id: \.self) { _ in SkeletonCard() }
                        Label(tr("Reading iCloud…", "正在读取 iCloud…", "Lecture d’iCloud…"), systemImage: "icloud").font(.footnote).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                    }
                    if !model.refreshing && model.snapshots.isEmpty { EmptyState().reveal(0) }
                    if !model.snapshots.isEmpty { Overview(snapshots: model.snapshots).reveal(0) }
                    ForEach(Array(model.snapshots.enumerated()), id: \.element.id) { section, snapshot in
                        DeviceHeader(device: snapshot, cached: model.cached).padding(.top, 10).reveal(section + 1)
                        ForEach(Array(snapshot.projects.enumerated()), id: \.element.id) { index, project in
                            let route = ProjectRoute(deviceID: snapshot.id, projectID: project.id)
                            NavigationLink(value: route) { ProjectCard(project: project) }
                                .buttonStyle(PressableStyle())
                                .zoomSource(route, in: zoom)
                                .reveal(section + index + 2)
                        }
                        if snapshot.projects.isEmpty {
                            Text(tr("No projects shared from this Mac.", "这台 Mac 尚未分享项目。", "Aucun projet partagé depuis ce Mac.")).foregroundStyle(.secondary).card()
                        }
                    }
                    if model.refreshing && !model.snapshots.isEmpty {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.mini)
                            Text(tr("Syncing with iCloud…", "正在与 iCloud 同步…", "Synchronisation avec iCloud…"))
                        }
                        .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.top, 8)
                        .transition(.opacity)
                    } else if let lastFetch = model.lastFetch {
                        VStack(spacing: 3) {
                            Text((model.cached ? tr("Offline copy · last fetched ", "离线副本 · 上次读取 ", "Copie hors ligne · dernière lecture ") : tr("Phone last fetched ", "手机上次读取 ", "Dernière lecture sur l’iPhone ")) + lastFetch.formatted(date: .abbreviated, time: .shortened))
                                .contentTransition(.numericText())
                            Label(tr("Pull down to refresh", "下拉即可刷新", "Tirez vers le bas pour actualiser"), systemImage: "arrow.down").labelStyle(CompactLabel())
                        }
                        .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.top, 8)
                        .transition(.opacity)
                    }
                }
                .padding(.horizontal, 16).padding(.bottom, 28)
                .animation(.snappy(duration: 0.35), value: model.snapshots)
                .animation(.snappy(duration: 0.35), value: model.message)
                .animation(.snappy(duration: 0.35), value: model.refreshing)
            }
            .background(Palette.page)
            .navigationTitle("Questlog")
            .refreshable { await model.refresh(manual: true) }
            .navigationDestination(for: ProjectRoute.self) { route in
                ProjectDestination(model: model, deviceID: route.deviceID, projectID: route.projectID).zoomDestination(route, in: zoom)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { settings = true } label: { Image(systemName: "gearshape") }.accessibilityLabel(tr("Settings", "设置", "Réglages"))
                }
            }
            .accessibilityAction(named: tr("Refresh", "刷新", "Actualiser")) { Task { await model.refresh(manual: true) } }
            .sheet(isPresented: $settings) { PhoneSettings(model: model) }
        }.id(model.resetToken)
    }
}

private struct EmptyState: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SyncIllustration()
            Text(tr("Your Mac’s progress, here.", "在这里查看 Mac 项目进度", "L’avancement de votre Mac, ici.")).font(.title2.weight(.bold))
            Text(tr("Connect a project in Questlog on your Mac. Its progress syncs here automatically when both devices use the same iCloud account.", "在 Mac 的 Questlog 中连接项目，进度就会自动同步到这里。两台设备使用同一个 iCloud 账号即可。", "Connectez un projet dans Questlog sur votre Mac. Son avancement apparaît ici automatiquement si les deux appareils utilisent le même compte iCloud."))
                .font(.callout).foregroundStyle(.secondary)
            Label(tr("The Mac must stay awake with Questlog running to send updates.", "Mac 需要保持唤醒且 Questlog 正在运行，才能发送新状态。", "Le Mac doit rester éveillé et Questlog ouvert pour envoyer les mises à jour."), systemImage: "bolt.horizontal.circle")
                .font(.footnote).foregroundStyle(.secondary)
        }.card(padding: 18)
    }
}

private struct SkeletonCard: View {
    var body: some View {
        HStack(spacing: 14) {
            Circle().fill(Palette.track).frame(width: 54, height: 54)
            VStack(alignment: .leading, spacing: 9) {
                Capsule().fill(Palette.track).frame(width: 120, height: 12)
                Capsule().fill(Palette.track).frame(width: 180, height: 10)
            }
        }.shimmer().card().accessibilityHidden(true)
    }
}

private struct Overview: View {
    let snapshots: [DeviceSnapshot]
    var body: some View {
        let summary = SnapshotOverview(snapshots)
        HStack(spacing: 0) {
            stat(summary.projects, tr("Projects", "项目", "Projets"), "square.stack.3d.up.fill", Palette.accent)
            Divider().frame(height: 34)
            stat(summary.inProgress, tr("In progress", "进行中", "En cours"), "circle.lefthalf.filled", Palette.active)
            Divider().frame(height: 34)
            stat(summary.attention, tr("Attention", "需关注", "À surveiller"), "exclamationmark.triangle.fill", summary.attention > 0 ? Palette.warn : .secondary)
        }.card(padding: 14)
    }
    private func stat(_ value: Int, _ title: String, _ symbol: String, _ color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value.formatted()).font(.system(.title2, design: .rounded).weight(.bold)).monospacedDigit().contentTransition(.numericText(value: Double(value)))
            Label(title, systemImage: symbol).font(.caption.weight(.medium)).foregroundStyle(color).labelStyle(CompactLabel())
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

private struct CompactLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) { configuration.icon.imageScale(.small); configuration.title.foregroundStyle(Color(uiColor: .secondaryLabel)) }
    }
}

private struct DeviceHeader: View {
    let device: DeviceSnapshot
    let cached: Bool
    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let freshness = device.freshness(cached: cached, at: context.date)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "laptopcomputer").foregroundStyle(.secondary)
                    Text(device.name).font(.headline).lineLimit(1)
                    Spacer()
                    HStack(spacing: 6) {
                        FreshnessDot(recent: freshness == .recent)
                        Text(freshnessLabel(freshness, capturedAt: device.capturedAt, now: context.date)).monospacedDigit().contentTransition(.numericText())
                    }
                    .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(Palette.card, in: Capsule())
                }
                FreshnessNote(freshness: freshness)
                    .transition(.opacity)
            }
            .accessibilityElement(children: .combine)
            .accessibilityHint(tr("Mac updated ", "Mac 更新于 ", "Mac mis à jour le ") + device.capturedAt.formatted(date: .abbreviated, time: .shortened))
        }
    }
}

private func age(_ date: Date, now: Date) -> String {
    if abs(now.timeIntervalSince(date)) < 60 { return tr("Just now", "刚刚", "À l’instant") }
    return date.formatted(.relative(presentation: .named, unitsStyle: .abbreviated))
}

private func freshnessLabel(_ freshness: SnapshotFreshness, capturedAt: Date, now: Date) -> String {
    switch freshness {
    case .cached: return tr("Offline copy", "离线副本", "Copie hors ligne")
    case .clockSkew: return tr("Check clock", "核对时间", "Vérifier l’heure")
    case .recent, .stale: return tr("Captured ", "采集于 ", "Capturé ") + age(capturedAt, now: now)
    }
}

private struct FreshnessNote: View {
    let freshness: SnapshotFreshness
    @ViewBuilder var body: some View {
        switch freshness {
        case .recent: EmptyView()
        case .cached:
            Label(tr("Saved data. Connect to iCloud to check for updates.", "正在显示保存的副本，连接 iCloud 后可检查更新。", "Copie enregistrée. Connectez-vous à iCloud pour vérifier les mises à jour."), systemImage: "wifi.slash").font(.caption).foregroundStyle(.secondary)
        case .stale:
            Label(tr("Older snapshot. The Mac may be asleep or offline.", "快照较旧，Mac 可能已休眠或离线。", "Instantané ancien. Le Mac peut être en veille ou hors ligne."), systemImage: "moon.zzz").font(.caption).foregroundStyle(.secondary)
        case .clockSkew:
            Label(tr("The Mac’s capture time is ahead. Check its date and time.", "Mac 的采集时间超前，请核对其日期与时间。", "L’heure de capture du Mac est dans le futur. Vérifiez sa date et son heure."), systemImage: "clock.badge.exclamationmark").font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct ProjectDestination: View {
    @ObservedObject var model: PhoneModel
    let deviceID: String; let projectID: String
    var body: some View {
        if let device = model.snapshots.first(where: { $0.id == deviceID }), let project = device.projects.first(where: { $0.id == projectID }) {
            ProjectDetail(project: project, device: device, cached: model.cached)
        } else {
            VStack(spacing: 12) {
                Image(systemName: "eye.slash").font(.largeTitle).foregroundStyle(.secondary)
                Text(tr("This project is no longer shared.", "此项目已停止分享。", "Ce projet n’est plus partagé.")).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, maxHeight: .infinity).background(Palette.page)
        }
    }
}

private func showsPercent(_ p: SnapshotProject) -> Int? {
    p.state == "ready" && p.mode == "measured" ? p.percent : nil
}

private func projectBadge(_ p: SnapshotProject) -> (String, Color) {
    if p.state == "permission" { return ("lock.fill", Palette.warn) }
    if p.state != "ready" { return ("exclamationmark.triangle.fill", Palette.warn) }
    switch p.mode {
    case "tasks": return ("checklist", Palette.accent)
    case "status": return (p.blocked ? "hand.raised.fill" : "text.bubble.fill", p.blocked ? Palette.warn : Palette.accent)
    default: return ("questionmark", .secondary)
    }
}

private struct ProjectCard: View {
    let project: SnapshotProject
    var body: some View {
        HStack(spacing: 14) {
            if let percent = showsPercent(project) { ProgressRing(percent: percent) }
            else { let badge = projectBadge(project); IconBadge(symbol: badge.0, color: badge.1) }
            VStack(alignment: .leading, spacing: 6) {
                Text(project.name).font(.headline).foregroundStyle(.primary).lineLimit(1)
                Text(projectStatus(project)).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                if showsPercent(project) == nil, project.state == "ready", let c = project.counts, c.total > 0 {
                    TaskBar(counts: c).padding(.top, 2)
                }
                if let signal = project.signals.first(where: { $0.kind == "blocker" }) ?? project.signals.first {
                    Label(signal.text, systemImage: signalSymbol(signal.kind))
                        .font(.footnote).foregroundStyle(signal.kind == "blocker" ? Palette.warn : .secondary)
                        .lineLimit(2).multilineTextAlignment(.leading)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .card()
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

private func projectStatus(_ p: SnapshotProject) -> String {
    if p.state == "permission" { return tr("Folder access required on Mac", "需要在 Mac 重新授权目录", "Autorisez le dossier sur le Mac") }
    if p.state != "ready" { return tr("Unable to read on Mac", "Mac 暂时无法读取", "Lecture impossible sur le Mac") }
    if p.needsReview { return tr("Source states need review", "来源状态待核对", "États des sources à vérifier") }
    if let c = p.counts, c.total > 0 {
        return p.mode == "measured" ? "\(p.scope) · \(c.done)/\(c.total)" : tr("\(c.done)/\(c.total) detected · scope unknown", "已识别 \(c.done)/\(c.total) · 范围未知", "\(c.done)/\(c.total) détectées · périmètre inconnu")
    }
    if p.mode == "status", p.blocked { return tr("Blocked · no defined scope", "有阻塞 · 尚无明确范围", "Blocage · sans périmètre défini") }
    if p.mode == "status", p.inProgress { return tr("In progress · no defined scope", "进行中 · 尚无明确范围", "En cours · sans périmètre défini") }
    return p.mode == "status" ? tr("Project state · no defined scope", "项目近况 · 尚无明确范围", "État du projet · sans périmètre défini") : tr("More project information needed", "等待补充项目资料", "Informations supplémentaires nécessaires")
}

private func signalSymbol(_ kind: String) -> String {
    switch kind {
    case "current": return "play.circle.fill"
    case "blocker": return "hand.raised.fill"
    case "next": return "arrow.right.circle.fill"
    case "delivery": return "shippingbox.fill"
    default: return "text.bubble.fill"
    }
}

private func signalTitle(_ kind: String) -> String {
    switch kind {
    case "current": return tr("Current", "当前", "En cours")
    case "blocker": return tr("Blocker", "阻塞", "Blocage")
    case "next": return tr("Next", "下一步", "Suite")
    case "delivery": return tr("Recent delivery", "近期交付", "Livraison récente")
    default: return tr("Status", "状态", "État")
    }
}

private struct ProjectDetail: View {
    let project: SnapshotProject; let device: DeviceSnapshot
    let cached: Bool
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                hero.reveal(0)
                if project.needsReview {
                    Label(tr("Source states need review", "来源状态待核对", "États des sources à vérifier"), systemImage: "exclamationmark.bubble.fill")
                        .font(.callout.weight(.medium)).foregroundStyle(Palette.warn).card(padding: 14).reveal(1)
                }
                if let c = project.counts, c.total > 0 {
                    sectionTitle(tr("Observed tasks", "任务统计", "Tâches observées"))
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        StatTile(title: tr("Completed", "已完成", "Terminées"), value: c.done, symbol: "checkmark.circle.fill", color: Palette.accent).reveal(2)
                        StatTile(title: tr("In progress", "进行中", "En cours"), value: c.active, symbol: "circle.lefthalf.filled", color: Palette.active).reveal(3)
                        StatTile(title: tr("Blocked", "有阻塞", "Bloquées"), value: c.blocked, symbol: "hand.raised.fill", color: c.blocked > 0 ? Palette.warn : .secondary).reveal(4)
                        StatTile(title: tr("Pending", "待完成", "À faire"), value: c.pending, symbol: "circle.dotted", color: .secondary).reveal(5)
                        if c.unknown > 0 { StatTile(title: tr("Unknown", "状态未知", "État inconnu"), value: c.unknown, symbol: "questionmark.circle.fill", color: .secondary).reveal(6) }
                    }
                }
                if !project.signals.isEmpty {
                    sectionTitle(tr("Shared status text", "已分享的近况原文", "Textes partagés"))
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(project.signals.enumerated()), id: \.offset) { index, signal in
                            SignalRow(signal: signal, last: index == project.signals.count - 1)
                        }
                    }.card().reveal(7)
                }
                sectionTitle(device.name)
                VStack(alignment: .leading, spacing: 10) {
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        let freshness = device.freshness(cached: cached, at: context.date)
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                FreshnessDot(recent: freshness == .recent)
                                Text(tr("Mac updated ", "Mac 更新于 ", "Mac mis à jour le ") + device.capturedAt.formatted(date: .abbreviated, time: .shortened)).font(.subheadline)
                            }
                            FreshnessNote(freshness: freshness)
                        }
                    }
                    Text(tr("Read-only snapshot. Updates depend on the Mac’s source files; this does not measure a running job directly.", "这里只读展示快照。更新取决于 Mac 上的项目资料，不直接测量正在运行的工作。", "Instantané en lecture seule. Les mises à jour dépendent des documents sur le Mac ; elles ne mesurent pas directement une tâche en cours."))
                        .font(.footnote).foregroundStyle(.secondary)
                }.card().reveal(8)
            }
            .padding(.horizontal, 16).padding(.bottom, 28)
            .animation(.snappy, value: project)
        }
        .background(Palette.page)
        .navigationTitle(project.name).navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder private var hero: some View {
        VStack(spacing: 14) {
            if let percent = showsPercent(project) {
                ProgressRing(percent: percent, size: 172, lineWidth: 16, font: .system(size: 46, weight: .bold, design: .rounded))
                    .padding(.top, 8)
            } else {
                let badge = projectBadge(project)
                IconBadge(symbol: badge.0, color: badge.1, size: 76).padding(.top, 8)
            }
            VStack(spacing: 4) {
                Text(project.name).font(.title2.weight(.bold)).multilineTextAlignment(.center)
                Text(projectStatus(project)).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            if showsPercent(project) == nil, project.state == "ready", let c = project.counts, c.total > 0 {
                VStack(spacing: 10) {
                    TaskBar(counts: c, height: 10)
                    Legend(counts: c)
                }.padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .card(padding: 20)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text).font(.footnote.weight(.semibold)).foregroundStyle(.secondary).padding(.top, 8).padding(.leading, 4)
    }
}

private struct Legend: View {
    let counts: SnapshotCounts
    var body: some View {
        let names = [tr("Completed", "已完成", "Terminées"), tr("In progress", "进行中", "En cours"), tr("Blocked", "有阻塞", "Bloquées"), tr("Pending", "待完成", "À faire"), tr("Unknown", "状态未知", "État inconnu")]
        let items = zip(names, TaskBar.segments(counts)).filter { $0.1.0 > 0 }
        HStack(spacing: 12) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(spacing: 5) { Circle().fill(item.1.1).frame(width: 7, height: 7); Text("\(item.0) \(item.1.0)") }
            }
        }.font(.caption).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.75)
    }
}

private struct StatTile: View {
    let title: String; let value: Int; let symbol: String; let color: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: symbol).font(.title3).foregroundStyle(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(value.formatted()).font(.system(.title, design: .rounded).weight(.bold)).monospacedDigit()
                    .contentTransition(.numericText(value: Double(value)))
                Text(title).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .card(padding: 14)
        .accessibilityElement(children: .combine)
    }
}

private struct SignalRow: View {
    let signal: SnapshotSignal; let last: Bool
    var body: some View {
        let color = signal.kind == "blocker" ? Palette.warn : Palette.accent
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 4) {
                Image(systemName: signalSymbol(signal.kind)).font(.body).foregroundStyle(color)
                    .frame(width: 30, height: 30).background(color.opacity(0.14), in: Circle())
                if !last { Rectangle().fill(Palette.track).frame(width: 2).frame(maxHeight: .infinity) }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(signalTitle(signal.kind)).font(.caption.weight(.semibold)).foregroundStyle(color)
                Text(signal.text).font(.callout).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }.padding(.top, 5).padding(.bottom, last ? 0 : 16)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct PhoneSettings: View {
    @ObservedObject var model: PhoneModel
    @Environment(\.dismiss) private var dismiss
    @State private var cleared = 0
    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        IconBadge(symbol: "laptopcomputer.and.iphone", color: Palette.accent, size: 52)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Questlog").font(.headline)
                            Text(tr("Read-only companion for your Mac", "Mac 进度的只读伴侣", "Compagnon en lecture seule du Mac")).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }.padding(.vertical, 4)
                }
                Section {
                    Label { Text(tr("Uses your existing iCloud account. No Questlog registration is needed.", "使用现有 iCloud 账号，无需注册 Questlog。", "Utilise votre compte iCloud existant, sans inscription à Questlog.")) } icon: { Image(systemName: "icloud.fill").foregroundStyle(Palette.accent) }
                    Label { Text(tr("Projects connected on your Mac sync automatically. Use iCloud sync on that Mac to exclude projects or stop syncing and remove its cloud snapshot.", "Mac 上连接的项目会自动同步。可在对应 Mac 的“iCloud 同步”中排除项目，或“停止并移除”该 Mac 的云端快照。", "Les projets connectés sur le Mac se synchronisent automatiquement. Utilisez Synchronisation iCloud sur ce Mac pour exclure des projets ou arrêter et supprimer son instantané cloud.")) } icon: { Image(systemName: "laptopcomputer").foregroundStyle(Palette.accent) }
                } header: { Text("iCloud") }
                Section {
                    Label { Text(tr("Connected project summaries, including activity and blocker flags, sync through your private iCloud database. Original files, paths and permissions stay on the Mac. Status text is a separate opt-in.", "已连接项目的摘要和进行中／阻塞标记同步到自己的 iCloud 私有数据库。原始文件、路径和权限留在 Mac；近况原文需单独开启。", "Les résumés et indicateurs d’activité et de blocage sont synchronisés via votre base iCloud privée. Fichiers, chemins et autorisations restent sur le Mac. Les textes sont une option distincte.")) } icon: { Image(systemName: "lock.shield.fill").foregroundStyle(Palette.accent) }
                    Link(destination: URL(string: "https://github.com/jamezzh7/questlog/blob/main/docs/privacy.md")!) {
                        Label(tr("Full privacy policy", "完整隐私政策", "Politique de confidentialité"), systemImage: "doc.text")
                    }
                    Button(role: .destructive) { model.clearCache(); cleared += 1 } label: {
                        Label(tr("Clear offline copy on this iPhone", "清除这台 iPhone 的离线副本", "Effacer la copie hors ligne de cet iPhone"), systemImage: "trash")
                    }
                } header: { Text(tr("Privacy", "隐私", "Confidentialité")) }
            }
            .font(.subheadline)
            .sensoryFeedback(.success, trigger: cleared)
            .navigationTitle(tr("Settings", "设置", "Réglages"))
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button(tr("Done", "完成", "Terminé")) { dismiss() } } }
        }
    }
}

#if DEBUG
private func previewSnapshots(includeText: Bool = true) -> [DeviceSnapshot] {
    let known = SnapshotCounts(done: 3, total: 5, active: 1, blocked: 0, pending: 1, unknown: 0)
    let partial = SnapshotCounts(done: 1, total: 4, active: 1, blocked: 1, pending: 1, unknown: 0)
    let empty = SnapshotCounts(done: 0, total: 0, active: 0, blocked: 0, pending: 0, unknown: 0)
    let projects = [
        SnapshotProject(id: "00000000-0000-4000-8000-000000000001", name: "Orbit", state: "ready", mode: "measured", scope: tr("Release 0.2", "0.2 版本", "Version 0.2"), counts: known, percent: 60, signals: [], needsReview: false),
        SnapshotProject(id: "00000000-0000-4000-8000-000000000002", name: "Trail", state: "ready", mode: "tasks", scope: "", counts: partial, percent: nil, signals: [], needsReview: false),
        SnapshotProject(id: "00000000-0000-4000-8000-000000000003", name: "Beacon", state: "ready", mode: "status", scope: "", counts: empty, percent: nil, signals: includeText ? [SnapshotSignal(kind: "blocker", text: tr("Waiting for review of the export format.", "等待导出格式评审。", "En attente de validation du format d’export.")), SnapshotSignal(kind: "next", text: tr("Verify the sample report.", "验证示例报告。", "Vérifier le rapport d’exemple."))] : [], needsReview: false, activity: SnapshotActivity(active: false, blocked: true))
    ]
    let shipped = SnapshotCounts(done: 8, total: 8, active: 0, blocked: 0, pending: 0, unknown: 0)
    let laptop = [SnapshotProject(id: "00000000-0000-4000-8000-000000000004", name: "Atlas", state: "ready", mode: "measured", scope: tr("Launch checklist", "发布清单", "Liste de lancement"), counts: shipped, percent: 100, signals: [], needsReview: false)]
    return [DeviceSnapshot(version: 1, id: "00000000-0000-4000-8000-000000000010", name: "Studio Mac", capturedAt: Date().addingTimeInterval(-40), projects: projects),
            DeviceSnapshot(version: 1, id: "00000000-0000-4000-8000-000000000011", name: "MacBook Air", capturedAt: Date().addingTimeInterval(-900), projects: laptop)]
}
#endif
