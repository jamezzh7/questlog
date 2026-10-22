import AppKit
import WebKit

private let paper = NSColor(calibratedRed: 0.975, green: 0.981, blue: 0.991, alpha: 1)

private enum WidgetStyle {
    static let size = NSSize(width: 300, height: 120)
    static let surface = NSColor(calibratedWhite: 0.985, alpha: 1)
    static let ink = NSColor(calibratedWhite: 0.14, alpha: 1)
    static let secondary = NSColor(calibratedWhite: 0.40, alpha: 1)
    static let control = NSColor(calibratedWhite: 0.45, alpha: 1)
    static let accent = NSColor(calibratedRed: 0.34, green: 0.44, blue: 0.65, alpha: 1)
    static let track = NSColor(calibratedWhite: 0.90, alpha: 1)
}

enum InterfaceLanguage: String {
    case en, zh, fr
    static func resolve(_ preference: String, systemLanguage: String = Locale.preferredLanguages.first ?? "en") -> InterfaceLanguage {
        if let explicit = InterfaceLanguage(rawValue: preference) { return explicit }
        let base = systemLanguage.lowercased().components(separatedBy: CharacterSet(charactersIn: "-_"))[0]
        return InterfaceLanguage(rawValue: base) ?? .en
    }
}

struct ProjectChoice: Decodable { let id: String; let name: String }
struct ProgressCount: Decodable { let done: Int; let total: Int; let percent: Int }
struct CurrentStage: Decodable { let title: String; let done: Int?; let total: Int; let kind: String? }
struct WorkOverview: Decodable { let kind: String; let groupCount: Int; let taskCount: Int; let activeCount: Int }
struct WorkWarning: Decodable { let file: String; let message: String; let code: String? }
struct TimeEstimate: Decodable {
    let available: Bool; let label: String; let detail: String
    let complete: Bool?; let days: [Double]?; let hours: [Double]?
}
struct ProjectSummary: Decodable {
    let id: String; let name: String; let overall: ProgressCount
    let current: CurrentStage?; let eta: TimeEstimate
    let work: WorkOverview?; let watchFiles: [String]?; let warning: String?; let warnings: [WorkWarning]?
}
struct SummaryResponse: Decodable { let language: String?; let projects: [ProjectChoice]; let project: ProjectSummary? }

final class CompanionWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override func keyDown(with event: NSEvent) {
        // Borderless windows do not get the titled-window Tab loop by default.
        if let widget = contentView as? WidgetView, event.keyCode == 48,
           event.modifierFlags.intersection([.command, .control, .option]).isEmpty {
            let buttons = [widget.pin, widget.expand, widget.quit]
            let backwards = event.modifierFlags.contains(.shift)
            let current = buttons.firstIndex { $0 === firstResponder }
            let next = current.map { ($0 + (backwards ? 2 : 1)) % buttons.count } ?? (backwards ? 2 : 0)
            makeFirstResponder(buttons[next]); return
        }
        super.keyDown(with: event)
    }
}
final class PassiveLabel: NSTextField {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
final class WindowDragView: NSView {
    var regions: [NSRect] = []
    var exclusions: [NSRect] = []
    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard bounds.contains(local), regions.contains(where: { $0.contains(local) }),
              !exclusions.contains(where: { $0.contains(local) }) else { return nil }
        // Window controls live outside the content view and keep their native hit targets.
        for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            if let button = window?.standardWindowButton(kind),
               button.convert(button.bounds, to: self).contains(local) { return nil }
        }
        return self
    }
    override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
    func update(from message: [String: Any]) {
        func rectangles(_ key: String) -> [NSRect] {
            guard let values = message[key] as? [[Double]] else { return [] }
            return values.prefix(64).compactMap { value in
                guard value.count == 4, value.allSatisfy({ $0.isFinite }), value[2] > 0, value[3] > 0 else { return nil }
                return NSRect(x: value[0], y: value[1], width: value[2], height: value[3])
            }
        }
        regions = rectangles("regions"); exclusions = rectangles("excluded")
    }
}
final class WidgetButton: NSButton {
    override var acceptsFirstResponder: Bool { true }
    var selected = false { didSet { state = selected ? .on : .off; updateAppearance() } }
    private var hovered = false
    private var hoverArea: NSTrackingArea?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 5
        imagePosition = .imageOnly
        bezelStyle = .inline
        isBordered = false
        focusRingType = .exterior
        setButtonType(.momentaryChange)
        updateAppearance()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area = hoverArea { removeTrackingArea(area) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area); hoverArea = area
    }
    override func mouseEntered(with event: NSEvent) { hovered = true; updateAppearance() }
    override func mouseExited(with event: NSEvent) { hovered = false; updateAppearance() }
    override func highlight(_ flag: Bool) { super.highlight(flag); updateAppearance() }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 76 { performClick(nil); return }
        super.keyDown(with: event)
    }
    func setSymbol(_ name: String) {
        image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 11, weight: .medium))
    }
    private func updateAppearance() {
        let alpha: CGFloat = isHighlighted ? 0.10 : hovered ? 0.055 : selected ? 0.055 : 0
        layer?.backgroundColor = (selected ? WidgetStyle.accent : WidgetStyle.ink).withAlphaComponent(alpha).cgColor
        contentTintColor = selected ? WidgetStyle.accent : hovered || isHighlighted ? WidgetStyle.ink : WidgetStyle.control
    }
}
final class ProgressTrack: NSView {
    private var displayedPercent: CGFloat = 0
    private var targetPercent: CGFloat = 0
    private var animationTimer: Timer?
    deinit { animationTimer?.invalidate() }
    func setProgress(_ percent: Int, animated: Bool) {
        let target = CGFloat(min(100, max(0, percent)))
        guard target != targetPercent || !animated else { return }
        targetPercent = target
        animationTimer?.invalidate()
        animationTimer = nil
        guard animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            displayedPercent = target; needsDisplay = true; return
        }
        let start = displayedPercent
        let began = ProcessInfo.processInfo.systemUptime
        let timer = Timer(timeInterval: 1 / 60, repeats: true) { [weak self] timer in
            guard let self = self else { timer.invalidate(); return }
            let progress = min(1, (ProcessInfo.processInfo.systemUptime - began) / 0.36)
            self.displayedPercent = start + (target - start) * CGFloat(1 - pow(1 - progress, 3))
            self.needsDisplay = true
            if progress >= 1 { timer.invalidate(); self.animationTimer = nil }
        }
        animationTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }
    override func draw(_ dirtyRect: NSRect) {
        let radius = bounds.height / 2
        let path = NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius)
        WidgetStyle.track.setFill(); path.fill()
        guard displayedPercent > 0 else { return }
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        WidgetStyle.accent.setFill()
        let fill = NSRect(x: 0, y: 0, width: bounds.width * displayedPercent / 100, height: bounds.height)
        NSBezierPath(roundedRect: fill, xRadius: radius, yRadius: radius).fill()
        NSGraphicsContext.restoreGraphicsState()
    }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
final class WidgetView: NSView {
    // Route passive content to AppKit's window-background drag handling.
    // Buttons keep their own hit targets and continue to receive clicks.
    override var mouseDownCanMoveWindow: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    let title = PassiveLabel(labelWithString: "Questlog")
    let value = PassiveLabel(labelWithString: "—")
    let scope = PassiveLabel(labelWithString: "")
    let stage = PassiveLabel(labelWithString: "正在读取任务…")
    let eta = PassiveLabel(labelWithString: "")
    let track = ProgressTrack()
    let pin = WidgetButton()
    let expand = WidgetButton()
    let quit = WidgetButton()
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        // Keep this instrument legible and opaque regardless of the desktop beneath it.
        appearance = NSAppearance(named: .aqua)
        layer?.backgroundColor = WidgetStyle.surface.cgColor
        layer?.cornerRadius = 12
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor.black.withAlphaComponent(0.12).cgColor
        title.font = .systemFont(ofSize: 13, weight: .medium)
        title.textColor = WidgetStyle.ink
        title.lineBreakMode = .byTruncatingTail
        value.font = .monospacedDigitSystemFont(ofSize: 34, weight: .medium)
        value.textColor = WidgetStyle.ink
        scope.font = .systemFont(ofSize: 11)
        scope.textColor = WidgetStyle.secondary
        scope.alignment = .right
        scope.lineBreakMode = .byTruncatingTail
        stage.font = .systemFont(ofSize: 11)
        stage.textColor = WidgetStyle.secondary
        stage.lineBreakMode = .byTruncatingTail
        eta.font = .systemFont(ofSize: 11)
        eta.textColor = WidgetStyle.secondary
        eta.alignment = .right
        eta.lineBreakMode = .byTruncatingTail
        for label in [title, value, scope, stage, eta] {
            label.isSelectable = false
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            addSubview(label)
        }
        for (button, symbol, tip) in [(pin, "pin", "置顶：已关闭（仅当前桌面）"),
                                      (expand, "arrow.up.right", "打开详情"), (quit, "xmark", "退出 Questlog")] {
            button.setSymbol(symbol)
            button.toolTip = tip
            button.setAccessibilityLabel(tip)
            addSubview(button)
        }
        addSubview(track)
        nextKeyView = pin; pin.nextKeyView = expand; expand.nextKeyView = quit; quit.nextKeyView = pin
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layout() {
        super.layout()
        let width = bounds.width
        title.frame = NSRect(x: 16, y: 90, width: width - 108, height: 18)
        value.frame = NSRect(x: 15, y: 41, width: 133, height: 44)
        scope.frame = NSRect(x: 148, y: 50, width: width - 164, height: 17)
        pin.frame = NSRect(x: width - 86, y: 88, width: 22, height: 22)
        expand.frame = NSRect(x: width - 62, y: 88, width: 22, height: 22)
        quit.frame = NSRect(x: width - 38, y: 88, width: 22, height: 22)
        track.frame = NSRect(x: 16, y: 33, width: width - 32, height: 4)
        let etaWidth = eta.stringValue.isEmpty ? 0 : min(132, ceil(eta.intrinsicContentSize.width) + 6)
        stage.frame = NSRect(x: 16, y: 9, width: width - 32 - etaWidth - (etaWidth > 0 ? 12 : 0), height: 17)
        eta.frame = NSRect(x: width - 16 - etaWidth, y: 9, width: etaWidth, height: 17)
    }
    func setProgressValue(_ percent: Int?, french: Bool = false) {
        let text = NSMutableAttributedString(string: percent.map(String.init) ?? "—", attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 34, weight: .medium), .foregroundColor: WidgetStyle.ink, .kern: -1
        ])
        if percent != nil { text.append(NSAttributedString(string: french ? " %" : "%", attributes: [
            .font: NSFont.systemFont(ofSize: 17, weight: .medium), .foregroundColor: WidgetStyle.secondary, .baselineOffset: 1
        ])) }
        value.attributedStringValue = text
    }
}

final class CompanionApp: NSObject, NSApplicationDelegate, NSWindowDelegate, WKScriptMessageHandler {
    var window: CompanionWindow!
    var widget = WidgetView(frame: NSRect(origin: .zero, size: WidgetStyle.size))
    var detailsWindow: NSWindow?
    var webView: WKWebView?
    var detailsDragView: WindowDragView?
    var service: Process?
    var serviceOutput = Data()
    var serviceGeneration = 0
    var timer: Timer?
    var pinned = false
    var exiting = false
    var reading = false
    var selectedID: String?
    var displayedProjectID: String?
    var watchedSourceFiles: [String] = []
    var choices: [ProjectChoice] = []
    var lastSignature = ""
    var lastReadAt = Date.distantPast
    var autoPlanPolling = false
    var settings: [String: String] = [:]
    #if APP_STORE
    var storeRuntime: StoreRuntime?
    #endif
    var languagePreference = "auto"
    var language: InterfaceLanguage { InterfaceLanguage.resolve(languagePreference) }
    func localized(_ chinese: String, _ englishText: String, _ french: String) -> String {
        switch language { case .zh: return chinese; case .en: return englishText; case .fr: return french }
    }
    lazy var errorTranslations: [String: [String]] = {
        guard let url = Bundle.main.url(forResource: "errors", withExtension: "json"),
              let bytes = try? Data(contentsOf: url),
              let values = try? JSONDecoder().decode([String: [String]].self, from: bytes) else { return [:] }
        return values
    }()
    func localizedError(_ message: String) -> String {
        guard language != .zh, let translations = errorTranslations[message], translations.count == 2 else { return message }
        return translations[language == .fr ? 1 : 0]
    }
    func localizedNumber(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: language == .fr ? "fr_FR" : "en_CA")
        formatter.numberStyle = .decimal; formatter.usesGroupingSeparator = false
        formatter.maximumFractionDigits = 10
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }
    func updateNativeLabels() {
        let pinLabel = pinned ? localized("置顶：已开启（仅当前桌面，不跨全屏）", "Pinned on this desktop; excluded from fullscreen", "Épinglé sur ce bureau ; masqué en plein écran") : localized("置顶：已关闭（仅当前桌面）", "Pin off; this desktop only", "Non épinglé ; uniquement sur ce bureau")
        widget.pin.toolTip = pinLabel; widget.pin.setAccessibilityLabel(pinLabel)
        for (button, label) in [(widget.expand, localized("打开详情", "Open details", "Ouvrir les détails")), (widget.quit, localized("退出 Questlog", "Quit Questlog", "Quitter Questlog"))] {
            button.toolTip = label; button.setAccessibilityLabel(label)
        }
        window?.title = localized("Questlog · 项目进度", "Questlog · Project progress", "Questlog · Avancement du projet")
        detailsWindow?.title = localized("Questlog · 项目详情", "Questlog · Project details", "Questlog · Détails du projet")
    }
    func reveal(_ target: NSWindow) {
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        target.alphaValue = reduce ? 1 : 0
        target.makeKeyAndOrderFront(nil)
        if !reduce { NSAnimationContext.runAnimationGroup { context in context.duration = 0.16; target.animator().alphaValue = 1 } }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        do {
            #if APP_STORE
            let runtime = try StoreRuntime(); runtime.owner = self; storeRuntime = runtime
            settings = ["config": runtime.configuration.path]
            #else
            let file = Bundle.main.resourceURL!.appendingPathComponent("runtime.json")
            settings = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: file))
            #endif
            if let path = settings["config"], let bytes = try? Data(contentsOf: URL(fileURLWithPath: path)),
               let config = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any] {
                languagePreference = config["language"] as? String ?? "auto"
            }
        } catch { showFailure("\(localized("无法读取本地配置", "Unable to read local configuration", "Impossible de lire les réglages locaux")): \(error.localizedDescription)"); return }
        setupMenu()
        drawIcon()
        window = CompanionWindow(contentRect: NSRect(origin: .zero, size: WidgetStyle.size),
                                 styleMask: [.borderless], backing: .buffered, defer: false)
        window.title = "Questlog · 项目进度"
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .normal
        // Never join another application's fullscreen space or all desktop spaces.
        window.collectionBehavior = [.managed, .fullScreenNone]
        window.isMovable = true
        window.isMovableByWindowBackground = true
        window.hasShadow = true
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = widget
        for (button, action) in [(widget.pin, #selector(togglePin)), (widget.expand, #selector(openDetails)), (widget.quit, #selector(quit))] {
            button.target = self; button.action = action
        }
        if let area = NSScreen.main?.visibleFrame {
            window.setFrameOrigin(NSPoint(x: area.maxX - 324, y: area.minY + 30))
        }
        updateNativeLabels()
        widget.stage.stringValue = localized("正在读取任务…", "Reading tasks…", "Lecture des tâches…")
        reveal(window)
        NSApp.activate(ignoringOtherApps: true)
        refreshSummary(force: true)
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.refreshSummary() }
        timer?.tolerance = 1
    }
    func setupMenu() {
        let menu = NSMenu()
        let appItem = NSMenuItem()
        menu.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: localized("显示进度条", "Show widget", "Afficher la mini-fenêtre"), action: #selector(showWidget), keyEquivalent: "0")
        appMenu.addItem(withTitle: localized("打开详情", "Open details", "Ouvrir les détails"), action: #selector(openDetails), keyEquivalent: "d")
        appMenu.addItem(withTitle: localized("刷新进度", "Refresh progress", "Actualiser l’avancement"), action: #selector(forceRefresh), keyEquivalent: "r")
        #if STORE_SCREENSHOTS
        appMenu.addItem(withTitle: "Save Store Screenshot", action: #selector(saveStoreScreenshot), keyEquivalent: "s")
        #endif
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: localized("退出 Questlog", "Quit Questlog", "Quitter Questlog"), action: #selector(quit), keyEquivalent: "q")
        appItem.submenu = appMenu
        let editItem = NSMenuItem()
        menu.addItem(editItem)
        let editMenu = NSMenu(title: localized("编辑", "Edit", "Édition"))
        editMenu.addItem(withTitle: localized("拷贝", "Copy", "Copier"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: localized("粘贴", "Paste", "Coller"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: localized("全选", "Select All", "Tout sélectionner"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        NSApp.mainMenu = menu
    }
    @objc func togglePin() {
        pinned.toggle()
        window.level = pinned ? .floating : .normal
        widget.pin.setSymbol(pinned ? "pin.fill" : "pin")
        widget.pin.selected = pinned
        updateNativeLabels()
    }
    @objc func forceRefresh() { refreshSummary(force: true) }
    #if STORE_SCREENSHOTS
    @objc func saveStoreScreenshot() {
        guard let web = webView, let directory = storeRuntime?.directory.appendingPathComponent("Screenshots") else { return }
        let snapshot = WKSnapshotConfiguration(); snapshot.rect = web.bounds
        snapshot.afterScreenUpdates = true
        let name = "details-\(language.rawValue).png"
        web.takeSnapshot(with: snapshot) { image, error in
            do {
                guard let tiff = image?.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
                      let png = bitmap.representation(using: .png, properties: [:]) else {
                    throw error ?? StoreFailure(message: "Unable to capture store screenshot")
                }
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try png.write(to: directory.appendingPathComponent(name), options: .atomic)
            } catch { self.showFailure(error.localizedDescription) }
        }
    }
    #endif
    func sourceSignature() -> String {
        autoPlanPolling = false
        guard let configPath = settings["config"], let bytes = try? Data(contentsOf: URL(fileURLWithPath: configPath)) else { return "missing" }
        var stamp = bytes.base64EncodedString()
        if let config = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any],
           let projects = config["projects"] as? [[String: Any]] {
            let preference = config["language"] as? String ?? "auto"
            if languagePreference != preference { languagePreference = preference; setupMenu(); updateNativeLabels() }
            for project in projects where selectedID == nil || project["id"] as? String == selectedID {
                #if APP_STORE
                guard let root = project["root"] as? String, storeRuntime?.access.contains(root) == true else { stamp += "/ungranted"; continue }
                #endif
                if project["autoTasks"] as? Bool == true && project["tasksFile"] as? String == nil { autoPlanPolling = true }
                if let root = project["root"] as? String, let relative = project["tasksFile"] as? String {
                    let path = URL(fileURLWithPath: (root as NSString).expandingTildeInPath).appendingPathComponent(relative).path
                    if let attributes = try? FileManager.default.attributesOfItem(atPath: path) {
                        stamp += "\(attributes[.modificationDate] ?? "")/\(attributes[.size] ?? "")"
                    } else { stamp += "/missing" }
                }
            }
        }
        for path in watchedSourceFiles {
            #if APP_STORE
            guard storeRuntime?.access.contains(path) == true else { continue }
            #endif
            if let attributes = try? FileManager.default.attributesOfItem(atPath: path) {
                stamp += "/\(path):\(attributes[.modificationDate] ?? "")/\(attributes[.size] ?? "")"
            } else { stamp += "/\(path):missing" }
        }
        return stamp
    }
    func refreshSummary(force: Bool = false) {
        guard !reading, !exiting else { return }
        let signature = sourceSignature()
        guard force || signature != lastSignature || (autoPlanPolling && Date().timeIntervalSince(lastReadAt) >= 30) else { return }
        reading = true; lastReadAt = Date()
        let project = selectedID
        let finish: (Result<Data, Error>) -> Void = { [weak self] result in
            guard let self = self else { return }
            self.reading = false
            guard self.selectedID == project else { self.refreshSummary(force: true); return }
            self.lastSignature = signature
            do {
                let bytes = try result.get()
                let summary = try JSONDecoder().decode(SummaryResponse.self, from: bytes)
                self.apply(summary)
            } catch {
                #if APP_STORE
                self.widget.setProgressValue(nil); self.widget.track.setProgress(0, animated: false)
                self.widget.scope.stringValue = ""; self.widget.eta.stringValue = ""
                self.widget.track.setAccessibilityElement(false)
                self.displayedProjectID = nil; self.watchedSourceFiles = []
                #endif
                self.widget.stage.stringValue = self.localized("暂时无法读取 · ⌘R 重试", "Unable to read · ⌘R to retry", "Lecture impossible · réessayer avec ⌘R")
                self.widget.stage.toolTip = self.localizedError(error.localizedDescription)
            }
        }
        #if APP_STORE
        storeRuntime?.summary(project: project, completion: finish)
        #else
        guard let python = settings["python"], let config = settings["config"] else { reading = false; return }
        DispatchQueue.global(qos: .utility).async {
            let process = Process(); process.executableURL = URL(fileURLWithPath: python)
            process.arguments = [Bundle.main.resourceURL!.appendingPathComponent("read_summary.py").path, "--config", config]
            if let project = project { process.arguments! += ["--project", project] }
            var environment = ProcessInfo.processInfo.environment
            environment["PYTHONDONTWRITEBYTECODE"] = "1"; process.environment = environment
            let output = Pipe(); process.standardOutput = output; process.standardError = FileHandle.nullDevice
            do {
                try process.run()
                let bytes = output.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
                if process.terminationStatus != 0 {
                    let failure = try? JSONSerialization.jsonObject(with: bytes) as? [String: String]
                    throw NSError(domain: "Questlog", code: 1, userInfo: [NSLocalizedDescriptionKey: failure?["error"] ?? "读取失败"])
                }
                DispatchQueue.main.async { finish(.success(bytes)) }
            } catch { DispatchQueue.main.async { finish(.failure(error)) } }
        }
        #endif
    }
    func apply(_ response: SummaryResponse) {
        let preference = response.language ?? "auto"
        if languagePreference != preference { languagePreference = preference; setupMenu() }
        updateNativeLabels()
        choices = response.projects
        guard let project = response.project else {
            selectedID = nil
            displayedProjectID = nil
            watchedSourceFiles = []
            widget.title.stringValue = "Questlog"; widget.title.toolTip = "Questlog"
            widget.setProgressValue(nil); widget.track.setProgress(0, animated: false)
            let empty = localized("尚未连接项目", "No projects connected", "Aucun projet connecté")
            widget.scope.stringValue = empty; widget.scope.toolTip = empty
            widget.stage.stringValue = localized("展开以连接项目", "Open details to connect", "Ouvrir les détails pour connecter un projet"); widget.stage.toolTip = widget.stage.stringValue
            widget.eta.stringValue = ""; widget.eta.toolTip = nil
            widget.value.toolTip = empty; widget.track.toolTip = empty
            widget.track.setAccessibilityElement(false)
            widget.needsLayout = true
            rebuildProjectMenu()
            return
        }
        let sameProject = displayedProjectID == project.id
        selectedID = project.id
        displayedProjectID = project.id
        watchedSourceFiles = project.watchFiles ?? []
        widget.title.stringValue = project.name; widget.title.toolTip = project.name
        widget.setProgressValue(project.overall.total > 0 ? project.overall.percent : nil, french: language == .fr)
        widget.scope.stringValue = project.overall.total > 0 ? localized("主清单 \(project.overall.done)/\(project.overall.total)", "Main list \(project.overall.done)/\(project.overall.total)", "Liste \(project.overall.done)/\(project.overall.total)") : localized("尚无清单", "No checklist", "Aucune liste")
        widget.track.setProgress(project.overall.percent, animated: sameProject)
        let count = project.overall.total > 0 ? localized("主清单已完成 \(project.overall.done)/\(project.overall.total)；等权任务比例，非工时比例", "\(project.overall.done)/\(project.overall.total) main items complete; not an estimate of work hours", "\(project.overall.done)/\(project.overall.total) éléments principaux terminés ; ce pourcentage ne mesure pas les heures de travail") : localized("已连接项目，等待任务清单；暂不计算完成比例", "Connected; waiting for a checklist. Progress has not been calculated.", "Projet connecté ; en attente d’une liste. L’avancement n’a pas été calculé.")
        widget.value.toolTip = count; widget.scope.toolTip = count; widget.track.toolTip = count
        widget.track.setAccessibilityElement(project.overall.total > 0)
        widget.track.setAccessibilityRole(.progressIndicator)
        widget.track.setAccessibilityLabel(count)
        widget.track.setAccessibilityValue(project.overall.percent)
        widget.track.setAccessibilityMinValue(0); widget.track.setAccessibilityMaxValue(100)
        if let work = project.work {
            if let stage = project.current, work.activeCount == 1 {
                widget.stage.stringValue = stage.title
                widget.stage.toolTip = localized("模块进行中：\(stage.title)", "Module in progress: \(stage.title)", "Module en cours : \(stage.title)")
            } else {
                let modules = work.groupCount == 1 ? "module" : "modules"
                let tasks = work.taskCount == 1 ? "task" : "tasks"
                let frenchTasks = work.taskCount <= 1 ? "tâche" : "tâches"
                widget.stage.stringValue = work.activeCount > 1 ? localized("\(work.activeCount) 个模块进行中", "\(work.activeCount) active modules", "\(work.activeCount) modules en cours") : localized("\(work.groupCount) 个模块 · \(work.taskCount) 项任务", "\(work.groupCount) \(modules) · \(work.taskCount) \(tasks)", "\(work.groupCount) \(modules) · \(work.taskCount) \(frenchTasks)")
                widget.stage.toolTip = localized("按任务台账原文状态展示；模块不设独立完成百分比。", "Work-plan states are shown as written; modules have no inferred completion percentage.", "Les états reprennent le plan d’origine ; aucun pourcentage d’avancement n’est déduit pour les modules.")
            }
        } else if let stage = project.current, let done = stage.done {
            let match = stage.kind == "stage" ? stage.title.range(of: #"\bM\d+\b"#, options: .regularExpression) : nil
            let code = match.map { String(stage.title[$0]) }
            widget.stage.stringValue = code.map { "\($0) · \(done)/\(stage.total)" } ?? stage.title
            widget.stage.toolTip = "\(stage.title) · \(done)/\(stage.total)"
        } else {
            widget.stage.stringValue = project.overall.total > 0 ? "" : localized("等待任务清单", "Waiting for checklist", "En attente d’une liste")
            widget.stage.toolTip = widget.stage.stringValue.isEmpty ? nil : widget.stage.stringValue
        }
        if let warning = project.warning {
            widget.stage.stringValue = localized("任务来源待检查 · ↗", "Check task sources · ↗", "Vérifier les sources · ↗")
            widget.stage.toolTip = project.warnings?.map { item in
                "\(item.file): \(localizedError(item.message))"
            }.joined(separator: "\n") ?? localizedError(warning)
        }
        if project.overall.total == 0 {
            widget.eta.stringValue = ""; widget.eta.toolTip = nil
        } else if project.eta.complete == true {
            widget.eta.stringValue = localized("清单完成", "Checklist done", "Liste terminée")
            widget.eta.toolTip = count
        } else if project.eta.available, let days = project.eta.days, days.count == 2 {
            let low = localizedNumber(days[0]), high = localizedNumber(days[1])
            let range = low == high ? low : "\(low)–\(high)"
            widget.eta.stringValue = localized("约 \(range) 工作日", "~\(range) workdays", "≈ \(range) j ouvrés")
            widget.eta.toolTip = localized(project.eta.detail, "Work estimate only; external wait time is excluded.", "Estimation du travail uniquement ; délais d’attente externes exclus.")
        } else {
            widget.eta.stringValue = localized("未估算", "No estimate", "Non estimé")
            widget.eta.toolTip = localized("在详情中填写剩余主任务工时后显示估算；不含外部等待时间。", "Add remaining work hours in details to see an estimate. External wait time is excluded.", "Renseignez les heures de travail restantes dans les détails pour obtenir une estimation. Les attentes externes sont exclues.")
        }
        widget.needsLayout = true
        rebuildProjectMenu()
    }
    func rebuildProjectMenu() {
        let menu = NSMenu()
        for choice in choices {
            let item = NSMenuItem(title: choice.name, action: #selector(selectProject(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = choice.id; item.state = choice.id == selectedID ? .on : .off
            menu.addItem(item)
        }
        if !choices.isEmpty { menu.addItem(.separator()) }
        let refresh = NSMenuItem(title: localized("刷新进度", "Refresh progress", "Actualiser l’avancement"), action: #selector(forceRefresh), keyEquivalent: "")
        refresh.target = self; menu.addItem(refresh)
        widget.menu = menu
    }
    @objc func selectProject(_ sender: NSMenuItem) {
        selectedID = sender.representedObject as? String; refreshSummary(force: true)
    }
    @objc func openDetails() {
        if let details = detailsWindow { details.makeKeyAndOrderFront(nil); return }
        let config = WKWebViewConfiguration()
        config.preferences.tabFocusesLinks = true
        config.userContentController.add(self, name: "questlog")
        #if APP_STORE
        if let runtime = storeRuntime {
            config.userContentController.addScriptMessageHandler(runtime, contentWorld: .page, name: "questlogAPI")
        }
        #endif
        let web = WKWebView(frame: .zero, configuration: config)
        webView = web
        #if APP_STORE
        web.navigationDelegate = storeRuntime
        #endif
        let area = window.screen?.visibleFrame ?? NSScreen.main!.visibleFrame
        #if STORE_SCREENSHOTS
        let detailsSize = NSSize(width: 1280, height: 800)
        #else
        let detailsSize = NSSize(width: min(1000, area.width - 60), height: min(760, area.height - 60))
        #endif
        let details = NSWindow(contentRect: NSRect(origin: .zero, size: detailsSize),
                               styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView], backing: .buffered, defer: false)
        details.title = localized("Questlog · 项目详情", "Questlog · Project details", "Questlog · Détails du projet")
        details.titleVisibility = .hidden; details.titlebarAppearsTransparent = true
        details.titlebarSeparatorStyle = .none
        details.isMovable = true
        details.minSize = NSSize(width: 860, height: 520)
        details.backgroundColor = paper; details.level = .normal
        details.collectionBehavior = [.managed, .fullScreenNone]
        let content = NSView(frame: NSRect(origin: .zero, size: details.frame.size))
        web.frame = content.bounds; web.autoresizingMask = [.width, .height]
        content.addSubview(web)
        let dragView = WindowDragView(frame: content.bounds)
        dragView.autoresizingMask = [.width, .height]
        dragView.setAccessibilityElement(false)
        content.addSubview(dragView); detailsDragView = dragView
        details.isReleasedWhenClosed = false; details.delegate = self; details.contentView = content
        details.center(); detailsWindow = details; reveal(details); window.orderOut(nil)
        #if APP_STORE
        if let directory = storeRuntime?.resources.appendingPathComponent("public") {
            let rules = "[{\"trigger\":{\"url-filter\":\"^https?://\"},\"action\":{\"type\":\"block\"}}]"
            WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "questlog-local-content", encodedContentRuleList: rules) { [weak self, weak web] rule, error in
                guard let web = web, self?.webView === web else { return }
                guard let rule = rule else { self?.showFailure(error?.localizedDescription ?? "Unable to configure local content"); return }
                web.configuration.userContentController.add(rule)
                web.loadFileURL(directory.appendingPathComponent("index.html"), allowingReadAccessTo: directory)
            }
        }
        #else
        web.loadHTMLString("<html><body style='font:12px -apple-system;background:#f8fafd;color:#7b8798;padding:55px 25px'>\(localized("正在读取项目详情…", "Reading project details…", "Lecture des détails du projet…"))</body></html>", baseURL: nil)
        launchService()
        #endif
    }
    #if !APP_STORE
    func launchService() {
        serviceGeneration += 1
        let generation = serviceGeneration
        serviceOutput = Data()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: settings["python"]!)
        process.arguments = [Bundle.main.resourceURL!.appendingPathComponent("server.py").path, "--port", "0", "--config", settings["config"]!, "--parent-pid", String(ProcessInfo.processInfo.processIdentifier)]
        var environment = ProcessInfo.processInfo.environment
        environment["PYTHONDONTWRITEBYTECODE"] = "1"; process.environment = environment
        let output = Pipe()
        process.standardOutput = output; process.standardError = FileHandle.nullDevice
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { handle.readabilityHandler = nil; return }
            DispatchQueue.main.async {
                guard let self = self, generation == self.serviceGeneration else { return }
                self.serviceOutput.append(chunk)
                if let lineEnd = self.serviceOutput.firstIndex(of: 10),
                   let ready = try? JSONSerialization.jsonObject(with: self.serviceOutput.prefix(upTo: lineEnd)) as? [String: String],
                   let address = ready["url"], var url = URLComponents(string: address) {
                    handle.readabilityHandler = nil
                    url.queryItems = [URLQueryItem(name: "view", value: "full"), URLQueryItem(name: "project", value: self.selectedID)]
                    if let target = url.url { self.webView?.load(URLRequest(url: target)) }
                }
            }
        }
        process.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                guard let self = self, !self.exiting, generation == self.serviceGeneration else { return }
                self.webView?.loadHTMLString("<p style='padding:40px;color:#7b8798;font:13px -apple-system'>\(self.localized("详情服务已退出。请收起后重新打开详情。", "The details service stopped. Return to the widget and open details again.", "Le service de détails s’est arrêté. Revenez à la mini-fenêtre, puis rouvrez les détails."))</p>", baseURL: nil)
            }
        }
        service = process
        do { try process.run() } catch { showFailure("\(localized("无法打开详情", "Unable to open details", "Impossible d’ouvrir les détails")): \(error.localizedDescription)") }
    }
    #endif
    func stopDetails() {
        serviceGeneration += 1
        webView?.stopLoading()
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "questlog")
        #if APP_STORE
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "questlogAPI", contentWorld: .page)
        #endif
        detailsWindow?.delegate = nil; detailsWindow?.close(); detailsWindow?.contentView = nil
        detailsWindow = nil; webView = nil; detailsDragView = nil
        if let process = service, process.isRunning { process.terminate(); process.waitUntilExit() }
        service = nil
    }
    @objc func showWidget() {
        stopDetails(); reveal(window); refreshSummary(force: true)
    }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame else { return }
        #if APP_STORE
        guard storeRuntime?.trusted(message) == true else { return }
        #endif
        if let layout = message.body as? [String: Any], layout["action"] as? String == "window-drag-regions" {
            detailsDragView?.update(from: layout); return
        }
        guard let action = message.body as? String else { return }
        if action == "quit" { NSApp.terminate(nil) }
        else if action == "compact" { showWidget() }
        else if action.hasPrefix("language:") { refreshSummary(force: true) }
        else if action == "projects-changed" { refreshSummary(force: true) }
        else if action.hasPrefix("project:") {
            let value = String(action.dropFirst(8))
            let id: String? = value.isEmpty ? nil : value
            if selectedID != id { selectedID = id; refreshSummary(force: true) }
        }
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if sender === detailsWindow { showWidget(); return false }
        NSApp.terminate(nil); return false
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showWidget() }; return true
    }
    @objc func quit() { NSApp.terminate(nil) }
    func applicationWillTerminate(_ notification: Notification) {
        exiting = true; timer?.invalidate(); stopDetails()
    }
    func showFailure(_ message: String) {
        let alert = NSAlert(); alert.messageText = "Questlog"; alert.informativeText = message
        alert.addButton(withTitle: localized("关闭", "Close", "Fermer")); alert.runModal()
    }
    func drawIcon() {
        if let file = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let image = NSImage(contentsOf: file) { NSApp.applicationIconImage = image }
    }
}
@main
enum QuestlogApplication {
    static func main() {
        #if APP_STORE
        if CommandLine.arguments.contains("--store-smoke") { exit(StoreRuntime.smoke()) }
        #endif
        let app = NSApplication.shared
        let delegate = CompanionApp()
        app.delegate = delegate
        app.run()
    }
}
