#if os(macOS)
import AppKit

private final class SyncProjectList: NSStackView { override var isFlipped: Bool { true } }

final class SyncSettingsWindow: NSWindowController {
    let publisher: MacPublisher
    let language: String
    private func text(_ en: String, _ zh: String, _ fr: String) -> String { cloudText(en, zh, fr, language: language) }
    let enabled = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    let includeText = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    let deviceName = NSTextField(string: "")
    let status = NSTextField(wrappingLabelWithString: "")
    private var projectButtons: [NSButton] = []
    private var savedEnabled: Bool
    init(owner: CompanionApp, publisher: MacPublisher, choices: [ProjectChoice]) {
        self.publisher = publisher; self.language = owner.language.rawValue; self.savedEnabled = publisher.preferences.enabled
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 640), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        super.init(window: window); window.isReleasedWhenClosed = false
        window.title = owner.localized("iCloud 同步", "iCloud sync", "Synchronisation iCloud")
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false; window.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 24), stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -24), stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 22)])
        func label(_ text: String) -> NSTextField { let field = NSTextField(wrappingLabelWithString: text); field.font = .systemFont(ofSize: 12); field.textColor = .secondaryLabelColor; return field }
        enabled.title = owner.localized("自动同步已连接项目", "Automatically sync connected projects", "Synchroniser automatiquement les projets connectés")
        enabled.state = publisher.preferences.enabled ? .on : .off
        enabled.isEnabled = publisher.supported
        stack.addArrangedSubview(enabled)
        stack.addArrangedSubview(label(owner.localized("连接项目后，同一 iCloud 的 iPhone 会自动看到进度，无需配对。只同步名称、范围与统计；原始文件留在 Mac。", "Connect a project and see its progress on an iPhone using the same iCloud account. No pairing needed. Only names, scopes and counts sync; source files stay on the Mac.", "Connectez un projet : son avancement apparaît sur l’iPhone avec le même compte iCloud, sans jumelage. Seuls les noms, périmètres et statistiques sont partagés ; les fichiers restent sur le Mac.")))
        let nameLabel = label(owner.localized("Mac 显示名称（可选更改）", "Mac display name (optional to change)", "Nom du Mac (modification facultative)")); stack.addArrangedSubview(nameLabel)
        deviceName.stringValue = publisher.preferences.deviceName; deviceName.setAccessibilityLabel(nameLabel.stringValue)
        stack.addArrangedSubview(deviceName); deviceName.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        includeText.title = owner.localized("同时分享当前／阻塞／下一步原文", "Also share current / blocker / next text", "Partager aussi les textes actuels / blocages / suite")
        includeText.state = publisher.preferences.includeText ? .on : .off; stack.addArrangedSubview(includeText)
        stack.addArrangedSubview(label(owner.localized("原文可能包含敏感项目内容；开启前请核对。", "Text may contain confidential project content; review it before enabling.", "Les textes peuvent être confidentiels ; vérifiez-les avant de les partager.")))
        stack.addArrangedSubview(label(owner.localized("新项目自动加入；取消勾选可排除项目。最多同时同步 50 个。", "New projects are included automatically. Uncheck a project to exclude it. Up to 50 sync at once.", "Les nouveaux projets sont inclus automatiquement. Décochez un projet pour l’exclure. Jusqu’à 50 projets à la fois.")))
        let list = SyncProjectList(); list.orientation = .vertical; list.alignment = .leading; list.spacing = 8
        for choice in choices {
            let button = NSButton(checkboxWithTitle: choice.name, target: nil, action: nil); button.identifier = NSUserInterfaceItemIdentifier(choice.id)
            button.state = publisher.preferences.selected.contains(choice.id) ? .on : .off; list.addArrangedSubview(button); projectButtons.append(button)
        }
        if choices.isEmpty { list.addArrangedSubview(label(owner.localized("请先连接一个本地项目。", "Connect a local project first.", "Connectez d’abord un projet local."))) }
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.drawsBackground = false; scroll.documentView = list
        list.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(scroll)
        NSLayoutConstraint.activate([scroll.widthAnchor.constraint(equalTo: stack.widthAnchor), scroll.heightAnchor.constraint(equalToConstant: 145), list.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor), list.topAnchor.constraint(equalTo: scroll.contentView.topAnchor), list.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor)])
        status.font = .systemFont(ofSize: 12); status.textColor = .secondaryLabelColor; stack.addArrangedSubview(status)
        status.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        let actions = NSStackView(); actions.orientation = .horizontal; actions.spacing = 12
        for (title, action) in [(owner.localized("停止并移除", "Stop and remove", "Arrêter et supprimer"), #selector(remove)), (owner.localized("立即同步", "Sync now", "Synchroniser"), #selector(refresh)), (owner.localized("保存", "Save", "Enregistrer"), #selector(save))] {
            let button = NSButton(title: title, target: self, action: action); button.bezelStyle = .rounded; actions.addArrangedSubview(button)
        }
        stack.addArrangedSubview(actions)
        updateStatus(); window.center()
    }
    required init?(coder: NSCoder) { fatalError() }
    func updateStatus() {
        if savedEnabled != publisher.preferences.enabled {
            savedEnabled = publisher.preferences.enabled; enabled.state = savedEnabled ? .on : .off
        }
        if !publisher.supported { status.stringValue = CloudFailure.build.message(language: language) }
        else if !publisher.status.isEmpty { status.stringValue = publisher.status }
        else if publisher.preferences.enabled { status.stringValue = text("Connected projects sync automatically.", "已连接项目会自动同步。", "Les projets connectés se synchronisent automatiquement.") }
        else { status.stringValue = text("Sync is off.", "同步已关闭。", "Synchronisation désactivée.") }
        if let time = publisher.lastSuccess { status.stringValue += "\n" + text("Last upload: ", "上次上传：", "Dernier envoi : ") + DateFormatter.localizedString(from: time, dateStyle: .none, timeStyle: .medium) }
    }
    @objc func save() {
        do {
            let ids = projectButtons.filter { $0.state == .on }.compactMap { $0.identifier?.rawValue }
            try publisher.save(enabled: enabled.state == .on, name: deviceName.stringValue, selected: ids, includeText: includeText.state == .on, displayed: projectButtons.compactMap { $0.identifier?.rawValue })
            updateStatus()
        } catch { status.stringValue = error is SnapshotFailure ? text("Choose up to 50 projects and a name of 1–60 characters.", "最多可同步 50 个项目，显示名称需为 1–60 字。", "Choisissez au plus 50 projets et un nom de 1 à 60 caractères.") : cloudFailureMessage(error, language: language) }
    }
    @objc func remove() {
        do {
            // Stopping sync must also work with an invalid, unsaved form draft.
            try publisher.save(enabled: false, name: publisher.preferences.deviceName, selected: publisher.preferences.selected, includeText: publisher.preferences.includeText)
            enabled.state = .off; updateStatus()
        } catch { status.stringValue = cloudFailureMessage(error, language: language) }
    }
    @objc func refresh() { publisher.tick(force: true); updateStatus() }
}
#endif
