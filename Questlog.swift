import AppKit
import WebKit

private func adaptive(_ light: NSColor, _ dark: NSColor) -> NSColor {
    NSColor(name: nil) { $0.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light }
}
private let paper = adaptive(NSColor(calibratedRed: 0.975, green: 0.981, blue: 0.991, alpha: 1), NSColor(calibratedWhite: 0.11, alpha: 1))

private enum WidgetStyle {
    static let size = NSSize(width: 300, height: 120)
    static let surface = adaptive(NSColor(calibratedWhite: 0.985, alpha: 1), NSColor(calibratedWhite: 0.14, alpha: 1))
    static let border = adaptive(NSColor.black.withAlphaComponent(0.12), NSColor.white.withAlphaComponent(0.12))
    static let ink = adaptive(NSColor(calibratedWhite: 0.14, alpha: 1), NSColor(calibratedWhite: 0.93, alpha: 1))
    static let secondary = adaptive(NSColor(calibratedWhite: 0.40, alpha: 1), NSColor(calibratedWhite: 0.62, alpha: 1))
    static let control = adaptive(NSColor(calibratedWhite: 0.45, alpha: 1), NSColor(calibratedWhite: 0.60, alpha: 1))
    static let accent = adaptive(NSColor(calibratedRed: 0.29, green: 0.38, blue: 0.66, alpha: 1), NSColor(calibratedRed: 0.56, green: 0.64, blue: 0.86, alpha: 1))
    static let track = adaptive(NSColor(calibratedWhite: 0.90, alpha: 1), NSColor(calibratedWhite: 0.24, alpha: 1))
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
struct DetectedCounts: Decodable { let done: Int; let total: Int; let active: Int; let blocked: Int; let pending: Int; let unknown: Int }
struct StatusEvidence: Decodable { let kind: String; let text: String; let file: String; let line: Int }
struct StatusConflict: Decodable { let file: String; let text: String }
struct TrackingState: Decodable {
    let mode: String; let title: String; let counts: DetectedCounts; let signals: [StatusEvidence]; let conflicts: [StatusConflict]
}
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
    let tracking: TrackingState?
}
struct SummaryResponse: Decodable { let language: String?; let appearance: String?; let projects: [ProjectChoice]; let project: ProjectSummary? }
struct MenuProject: Decodable {
    let id: String; let name: String; let overall: ProgressCount?; let state: String
    let tracking: TrackingState?
}
struct ProjectOverview: Decodable { let language: String?; let appearance: String?; let projects: [MenuProject] }

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
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); updateAppearance() }
    private func updateAppearance() {
        let alpha: CGFloat = isHighlighted ? 0.10 : hovered ? 0.055 : selected ? 0.055 : 0
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = (selected ? WidgetStyle.accent : WidgetStyle.ink).withAlphaComponent(alpha).cgColor
        }
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
        // Opaque in both appearances so the instrument stays legible over any desktop.
        layer?.cornerRadius = 12
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 0.5
        updateSurface()
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
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); updateSurface() }
    private func updateSurface() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = WidgetStyle.surface.cgColor
            layer?.borderColor = WidgetStyle.border.cgColor
        }
    }
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
        track.isHidden = false
        let text = NSMutableAttributedString(string: percent.map(String.init) ?? "—", attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 34, weight: .medium), .foregroundColor: WidgetStyle.ink, .kern: -1
        ])
        if percent != nil { text.append(NSAttributedString(string: french ? " %" : "%", attributes: [
            .font: NSFont.systemFont(ofSize: 17, weight: .medium), .foregroundColor: WidgetStyle.secondary, .baselineOffset: 1
        ])) }
        value.attributedStringValue = text
    }
}

final class ProgressRing: NSView {
    var percent: Int? { didSet { needsDisplay = true } }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) {
        let circle = bounds.insetBy(dx: 3, dy: 3)
        let track = NSBezierPath(ovalIn: circle); track.lineWidth = 3
        // A dashed track marks "no checklist yet", distinct from a measured 0%.
        if percent == nil { track.setLineDash([2.5, 2.5], count: 2, phase: 0); NSColor.labelColor.withAlphaComponent(0.25).setStroke() }
        else { NSColor.labelColor.withAlphaComponent(0.10).setStroke() }
        track.stroke()
        guard let percent = percent, percent > 0 else { return }
        WidgetStyle.accent.setStroke()
        if percent >= 100 { track.stroke(); return }
        let arc = NSBezierPath(); arc.lineWidth = 3; arc.lineCapStyle = .round
        arc.appendArc(withCenter: NSPoint(x: bounds.midX, y: bounds.midY), radius: circle.width / 2,
                      startAngle: 90, endAngle: 90 - CGFloat(percent) * 3.6, clockwise: true)
        arc.stroke()
    }
}
class PopoverButton: NSButton {
    override var acceptsFirstResponder: Bool { true }
    override func becomeFirstResponder() -> Bool { needsDisplay = true; return super.becomeFirstResponder() }
    override func resignFirstResponder() -> Bool { needsDisplay = true; return super.resignFirstResponder() }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if window?.firstResponder === self {
            NSColor.keyboardFocusIndicatorColor.setStroke()
            let focus = NSBezierPath(roundedRect: bounds.insetBy(dx: 3, dy: 3), xRadius: 5, yRadius: 5)
            focus.lineWidth = 2; focus.stroke()
        }
    }
}
final class MenuProjectRow: PopoverButton {
    let identity: String
    private var hoverArea: NSTrackingArea?
    init(project: MenuProject, subtitle: String, french: Bool, selected: Bool, width: CGFloat) {
        identity = project.id
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 66))
        title = ""; isBordered = false; setButtonType(.momentaryChange)
        wantsLayer = true; layer?.cornerRadius = 7; focusRingType = .exterior
        let ring = ProgressRing(frame: NSRect(x: 12, y: 17, width: 32, height: 32))
        let percent = project.overall.flatMap { $0.total > 0 && (project.tracking == nil || project.tracking?.mode == "measured") ? $0.percent : nil }
        ring.percent = percent; ring.setAccessibilityElement(false); addSubview(ring)
        let name = PassiveLabel(labelWithString: project.name)
        name.frame = NSRect(x: 56, y: 13, width: width - 140, height: 19)
        name.font = .systemFont(ofSize: 13, weight: selected ? .semibold : .medium)
        name.textColor = .labelColor; name.lineBreakMode = .byTruncatingTail
        let detail = PassiveLabel(labelWithString: subtitle)
        detail.frame = NSRect(x: 56, y: 35, width: width - 140, height: 16)
        detail.font = .systemFont(ofSize: 11); detail.textColor = .secondaryLabelColor
        detail.lineBreakMode = .byTruncatingTail
        let value = PassiveLabel(labelWithString: percent.map { "\($0)\(french ? " %" : "%")" } ?? "—")
        value.frame = NSRect(x: width - 76, y: 23, width: 62, height: 25)
        value.font = .monospacedDigitSystemFont(ofSize: 19, weight: .regular)
        value.textColor = percent == nil ? .secondaryLabelColor : .labelColor; value.alignment = .right
        for label in [name, detail, value] { label.setAccessibilityElement(false); addSubview(label) }
        toolTip = "\(project.name) · \(subtitle)"
        setAccessibilityLabel("\(project.name), \(value.stringValue), \(subtitle)")
        setAccessibilityIdentifier("project-overview-\(project.id)")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var acceptsFirstResponder: Bool { true }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area = hoverArea { removeTrackingArea(area) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area); hoverArea = area
    }
    override func mouseEntered(with event: NSEvent) { layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.055).cgColor }
    override func mouseExited(with event: NSEvent) { layer?.backgroundColor = NSColor.clear.cgColor }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 76 { performClick(nil) } else { super.keyDown(with: event) }
    }
}
final class FlippedProjectList: NSView { override var isFlipped: Bool { true } }
final class ProjectPopoverView: NSView {
    override var isFlipped: Bool { true }
    let settingsButton = PopoverButton()
    let addButton = PopoverButton()
    let refreshButton = PopoverButton()
    let quitButton = PopoverButton()
    let widgetButton = PopoverButton()
    let titleLabel = PassiveLabel(labelWithString: "Questlog")
    let message = PassiveLabel(wrappingLabelWithString: "")
    let scroll = NSScrollView()
    let list = FlippedProjectList()
    private let divider = NSBox()
    override init(frame: NSRect) {
        super.init(frame: frame)
        let surface = NSVisualEffectView(frame: bounds)
        surface.material = .popover; surface.blendingMode = .behindWindow; surface.state = .active
        surface.autoresizingMask = [.width, .height]; addSubview(surface)
        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold); titleLabel.alignment = .center
        titleLabel.textColor = .labelColor; addSubview(titleLabel)
        message.font = .systemFont(ofSize: 12); message.textColor = .secondaryLabelColor
        message.alignment = .center; addSubview(message)
        scroll.drawsBackground = false; scroll.borderType = .noBorder
        scroll.documentView = list; scroll.autohidesScrollers = true; addSubview(scroll)
        divider.boxType = .separator; addSubview(divider)
        for (button, symbol) in [(settingsButton, "gearshape"), (addButton, "plus"),
                                  (refreshButton, "arrow.clockwise"), (quitButton, "power")] {
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            button.imagePosition = .imageOnly; button.isBordered = false; button.bezelStyle = .inline
            button.contentTintColor = .secondaryLabelColor; addSubview(button)
        }
        widgetButton.isBordered = false; widgetButton.bezelStyle = .inline
        widgetButton.font = .systemFont(ofSize: 11); widgetButton.contentTintColor = .secondaryLabelColor
        addSubview(widgetButton)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layout() {
        super.layout()
        let width = bounds.width
        settingsButton.frame = NSRect(x: 12, y: 12, width: 28, height: 26)
        addButton.frame = NSRect(x: width - 40, y: 12, width: 28, height: 26)
        titleLabel.frame = NSRect(x: 52, y: 15, width: width - 104, height: 21)
        scroll.frame = NSRect(x: 6, y: 49, width: width - 12, height: bounds.height - 96)
        message.frame = NSRect(x: 30, y: 66, width: width - 60, height: 62)
        divider.frame = NSRect(x: 16, y: bounds.height - 43, width: width - 32, height: 1)
        widgetButton.frame = NSRect(x: 14, y: bounds.height - 34, width: width - 110, height: 24)
        refreshButton.frame = NSRect(x: width - 82, y: bounds.height - 34, width: 28, height: 24)
        quitButton.frame = NSRect(x: width - 40, y: bounds.height - 34, width: 28, height: 24)
    }
    func replaceRows(_ rows: [MenuProjectRow], message text: String = "") {
        list.subviews.forEach { $0.removeFromSuperview() }
        for (index, row) in rows.enumerated() { row.frame.origin.y = CGFloat(index) * 66; list.addSubview(row) }
        list.frame = NSRect(x: 0, y: 0, width: 348, height: CGFloat(rows.count) * 66)
        scroll.hasVerticalScroller = rows.count > 6; scroll.isHidden = rows.isEmpty
        message.stringValue = text; message.isHidden = !rows.isEmpty
        frame.size.height = 96 + (rows.isEmpty ? 108 : CGFloat(min(rows.count, 6)) * 66)
        needsLayout = true
    }
}

final class CompanionApp: NSObject, NSApplicationDelegate, NSWindowDelegate, WKScriptMessageHandler, NSPopoverDelegate {
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
    var statusItem: NSStatusItem?
    let projectPopover = NSPopover()
    let projectPopoverView = ProjectPopoverView(frame: NSRect(x: 0, y: 0, width: 360, height: 204))
    var overviewTimer: Timer?
    var overviewReading = false
    var overviewSnapshot: Data?
    var overviewSelection: String?
    var overviewKeyMonitor: Any?
    var detailsReady = false
    var pendingDetailsRoute: [String]?
    #if APP_STORE
    var storeRuntime: StoreRuntime?
    #endif
    var languagePreference = "auto"
    var appearancePreference = "auto"
    func applyAppearance(_ preference: String) {
        let value = ["auto", "light", "dark"].contains(preference) ? preference : "auto"
        appearancePreference = value
        let appearance = value == "auto" ? nil : NSAppearance(named: value == "dark" ? .darkAqua : .aqua)
        NSApp.appearance = appearance
        window?.appearance = appearance
        detailsWindow?.appearance = appearance
        projectPopover.appearance = appearance
    }
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
        for (button, label) in [(widget.expand, localized("打开详情", "Open details", "Ouvrir les détails")), (widget.quit, localized("隐藏小窗", "Hide widget", "Masquer la mini-fenêtre"))] {
            button.toolTip = label; button.setAccessibilityLabel(label)
        }
        window?.title = localized("Questlog · 项目进度", "Questlog · Project progress", "Questlog · Avancement du projet")
        detailsWindow?.title = localized("Questlog · 项目详情", "Questlog · Project details", "Questlog · Détails du projet")
        statusItem?.button?.toolTip = localized("Questlog · 所有项目进度", "Questlog · All project progress", "Questlog · Avancement des projets")
        statusItem?.button?.setAccessibilityLabel(localized("Questlog 项目进度", "Questlog project progress", "Avancement des projets Questlog"))
        for (button, label) in [(projectPopoverView.settingsButton, localized("设置", "Settings", "Réglages")),
                                (projectPopoverView.addButton, localized("连接项目", "Connect project", "Connecter un projet")),
                                (projectPopoverView.refreshButton, localized("刷新进度", "Refresh progress", "Actualiser l’avancement")),
                                (projectPopoverView.quitButton, localized("退出 Questlog", "Quit Questlog", "Quitter Questlog"))] {
            button.toolTip = label; button.setAccessibilityLabel(label)
        }
        projectPopoverView.widgetButton.title = window?.isVisible == true
            ? localized("隐藏小窗", "Hide widget", "Masquer la mini-fenêtre")
            : localized("显示小窗", "Show widget", "Afficher la mini-fenêtre")
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
                applyAppearance(config["appearance"] as? String ?? "auto")
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
        for (button, action) in [(widget.pin, #selector(togglePin)), (widget.expand, #selector(openDetails)), (widget.quit, #selector(hideWidget))] {
            button.target = self; button.action = action
        }
        if let area = NSScreen.main?.visibleFrame {
            window.setFrameOrigin(NSPoint(x: area.maxX - 324, y: area.minY + 30))
        }
        updateNativeLabels()
        widget.stage.stringValue = localized("正在读取任务…", "Reading tasks…", "Lecture des tâches…")
        reveal(window)
        setupStatusItem()
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
        appMenu.addItem(withTitle: localized("所有项目进度", "All project progress", "Avancement des projets"), action: #selector(toggleProjectPopover), keyEquivalent: "1")
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
    @objc func forceRefresh() { refreshSummary(force: true); if projectPopover.isShown { refreshProjectOverview() } }
    func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            // The app mark in template form: a three-quarter ring around a check.
            let track = NSBezierPath(ovalIn: NSRect(x: 2.5, y: 2.5, width: 13, height: 13)); track.lineWidth = 1.6
            NSColor.black.withAlphaComponent(0.3).setStroke(); track.stroke()
            let arc = NSBezierPath(); arc.lineWidth = 1.6; arc.lineCapStyle = .round
            arc.appendArc(withCenter: NSPoint(x: 9, y: 9), radius: 6.5, startAngle: 90, endAngle: -180, clockwise: true)
            NSColor.black.setStroke(); arc.stroke()
            let check = NSBezierPath(); check.lineWidth = 1.6; check.lineCapStyle = .round; check.lineJoinStyle = .round
            check.move(to: NSPoint(x: 6.7, y: 9.1)); check.line(to: NSPoint(x: 8.3, y: 7.5)); check.line(to: NSPoint(x: 11.4, y: 10.6))
            check.stroke()
            return true
        }
        image.isTemplate = true
        item.button?.image = image; item.button?.target = self; item.button?.action = #selector(toggleProjectPopover)
        statusItem = item
        let controller = NSViewController(); controller.view = projectPopoverView
        projectPopover.contentViewController = controller; projectPopover.behavior = .transient; projectPopover.delegate = self
        for (button, action) in [(projectPopoverView.settingsButton, #selector(openSettingsFromPopover)),
                                  (projectPopoverView.addButton, #selector(connectFromPopover)),
                                  (projectPopoverView.refreshButton, #selector(forceRefresh)),
                                  (projectPopoverView.quitButton, #selector(quit)),
                                  (projectPopoverView.widgetButton, #selector(toggleWidgetFromPopover))] {
            button.target = self; button.action = action
        }
        updateNativeLabels()
    }
    @objc func toggleProjectPopover() {
        guard let button = statusItem?.button else { return }
        if projectPopover.isShown { projectPopover.performClose(nil); return }
        updateNativeLabels()
        overviewSnapshot = nil
        projectPopoverView.replaceRows([], message: localized("正在读取项目进度…", "Reading project progress…", "Lecture de l’avancement…"))
        projectPopover.contentSize = projectPopoverView.frame.size
        projectPopover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        NSApp.activate(ignoringOtherApps: true)
        projectPopover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        projectPopover.contentViewController?.view.window?.makeKey()
        overviewKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, self.projectPopover.isShown,
                  event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return event }
            if event.keyCode == 53 { self.projectPopover.performClose(nil); return nil }
            let view = self.projectPopoverView
            let controls: [NSButton] = [view.settingsButton] + view.list.subviews.compactMap { $0 as? MenuProjectRow } +
                [view.addButton, view.widgetButton, view.refreshButton, view.quitButton]
            guard let window = view.window else { return event }
            if [48, 125, 126].contains(event.keyCode) {
                let backwards = event.keyCode == 126 || (event.keyCode == 48 && event.modifierFlags.contains(.shift))
                let current = controls.firstIndex { $0 === window.firstResponder }
                let next = current.map { ($0 + (backwards ? controls.count - 1 : 1)) % controls.count } ?? (backwards ? controls.count - 1 : 0)
                window.makeFirstResponder(controls[next]); controls[next].scrollToVisible(controls[next].bounds)
                return nil
            }
            if [36, 49, 76].contains(event.keyCode), let control = window.firstResponder as? NSButton {
                control.performClick(nil); return nil
            }
            return event
        }
        refreshProjectOverview()
        overviewTimer?.invalidate()
        overviewTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.refreshProjectOverview() }
        overviewTimer?.tolerance = 1
    }
    func popoverDidClose(_ notification: Notification) {
        overviewTimer?.invalidate(); overviewTimer = nil
        if let monitor = overviewKeyMonitor { NSEvent.removeMonitor(monitor); overviewKeyMonitor = nil }
    }
    func refreshProjectOverview() {
        guard projectPopover.isShown, !overviewReading, !exiting else { return }
        overviewReading = true
        let finish: (Result<Data, Error>) -> Void = { [weak self] result in
            guard let self = self else { return }; self.overviewReading = false
            guard self.projectPopover.isShown else { return }
            do {
                let bytes = try result.get()
                let overview = try JSONDecoder().decode(ProjectOverview.self, from: bytes)
                self.applyAppearance(overview.appearance ?? "auto")
                let preference = overview.language ?? "auto"
                if preference != self.languagePreference { self.languagePreference = preference; self.setupMenu() }
                self.updateNativeLabels()
                if self.overviewSnapshot == bytes && self.overviewSelection == self.selectedID { return }
                self.overviewSnapshot = bytes; self.overviewSelection = self.selectedID
                let rows = overview.projects.map { project -> MenuProjectRow in
                    let subtitle: String
                    if project.state == "permission" { subtitle = self.localized("需要重新授权目录", "Folder access required", "Autorisation du dossier requise") }
                    else if project.state == "unavailable" { subtitle = self.localized("暂时无法读取", "Unable to read", "Lecture impossible") }
                    else if let tracking = project.tracking, tracking.mode != "measured" {
                        subtitle = self.trackingSubtitle(tracking)
                    } else if let progress = project.overall, progress.total > 0 {
                        let scope = project.tracking?.title.isEmpty == false ? project.tracking!.title : self.localized("主清单", "Main list", "Liste principale")
                        subtitle = "\(scope) · \(progress.done)/\(progress.total)"
                    } else { subtitle = self.localized("尚无清单", "No checklist", "Aucune liste") }
                    let row = MenuProjectRow(project: project, subtitle: subtitle, french: self.language == .fr,
                                             selected: project.id == self.selectedID, width: overview.projects.count > 6 ? 332 : 348)
                    row.target = self; row.action = #selector(self.openOverviewProject(_:)); return row
                }
                self.projectPopoverView.replaceRows(rows, message: self.localized("尚未连接项目\n点击 + 连接本地项目", "No projects connected\nChoose + to connect a local project", "Aucun projet connecté\nChoisissez + pour connecter un dossier"))
            } catch {
                self.overviewSnapshot = nil
                self.projectPopoverView.replaceRows([], message: self.localized("暂时无法读取\n点击刷新重试", "Unable to read\nRefresh to try again", "Lecture impossible\nActualisez pour réessayer"))
            }
            self.projectPopover.contentSize = self.projectPopoverView.frame.size
        }
        #if APP_STORE
        storeRuntime?.projectOverview(completion: finish)
        #else
        runSummaryBridge(["--overview"], completion: finish)
        #endif
    }
    @objc func openOverviewProject(_ sender: MenuProjectRow) {
        selectedID = sender.identity; refreshSummary(force: true)
        openDetailsRoute(["project", sender.identity])
    }
    @objc func openSettingsFromPopover() { openDetailsRoute(["settings", ""]) }
    @objc func connectFromPopover() { openDetailsRoute(["connect", ""]) }
    func openDetailsRoute(_ route: [String]) {
        pendingDetailsRoute = route; projectPopover.performClose(nil); openDetails(); deliverDetailsRoute()
    }
    func deliverDetailsRoute() {
        guard detailsReady, let route = pendingDetailsRoute, let web = webView,
              let data = try? JSONSerialization.data(withJSONObject: route), let arguments = String(data: data, encoding: .utf8) else { return }
        pendingDetailsRoute = nil
        web.evaluateJavaScript("window.questlogNavigate?.(...\(arguments)); undefined;")
    }
    @objc func hideWidget() { window.orderOut(nil); updateNativeLabels() }
    @objc func toggleWidgetFromPopover() {
        if window.isVisible { hideWidget() } else { projectPopover.performClose(nil); showWidget() }
    }
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
            let appearance = config["appearance"] as? String ?? "auto"
            if appearancePreference != appearance { applyAppearance(appearance) }
            if languagePreference != preference { languagePreference = preference; setupMenu(); updateNativeLabels() }
            for project in projects where selectedID == nil || project["id"] as? String == selectedID {
                #if APP_STORE
                guard let root = project["root"] as? String, storeRuntime?.access.contains(root) == true else { stamp += "/ungranted"; continue }
                #endif
                if project["autoTasks"] as? Bool == true { autoPlanPolling = true }
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
        runSummaryBridge(project.map { ["--project", $0] } ?? [], completion: finish)
        #endif
    }
    #if !APP_STORE
    func runSummaryBridge(_ arguments: [String], completion: @escaping (Result<Data, Error>) -> Void) {
        guard let python = settings["python"], let config = settings["config"] else {
            completion(.failure(NSError(domain: "Questlog", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to read local configuration"]))); return
        }
        DispatchQueue.global(qos: .utility).async {
            let process = Process(); process.executableURL = URL(fileURLWithPath: python)
            process.arguments = [Bundle.main.resourceURL!.appendingPathComponent("read_summary.py").path, "--config", config] + arguments
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
                DispatchQueue.main.async { completion(.success(bytes)) }
            } catch { DispatchQueue.main.async { completion(.failure(error)) } }
        }
    }
    #endif
    func apply(_ response: SummaryResponse) {
        applyAppearance(response.appearance ?? "auto")
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
        if let tracking = project.tracking, tracking.mode != "measured" {
            applyUnmeasured(tracking)
            rebuildProjectMenu()
            return
        }
        widget.setProgressValue(project.overall.total > 0 ? project.overall.percent : nil, french: language == .fr)
        let scopeTitle = project.tracking?.title.isEmpty == false ? project.tracking!.title : localized("主清单", "Main list", "Liste")
        widget.scope.stringValue = project.overall.total > 0 ? "\(scopeTitle) \(project.overall.done)/\(project.overall.total)" : localized("尚无清单", "No checklist", "Aucune liste")
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
    func trackingSubtitle(_ tracking: TrackingState) -> String {
        if !tracking.conflicts.isEmpty { return localized("来源状态待核对", "Check source states", "Vérifier les états des sources") }
        if tracking.mode == "tasks" {
            return localized("识别 \(tracking.counts.total) 项 · 完成 \(tracking.counts.done) · 范围未知", "\(tracking.counts.done)/\(tracking.counts.total) detected · coverage unknown", "\(tracking.counts.done)/\(tracking.counts.total) détectées · périmètre inconnu")
        }
        if let signal = tracking.signals.first { return signal.text }
        return localized("资料不足 · 可定义目标", "More information needed · define goals", "Informations insuffisantes · définir des objectifs")
    }
    func applyUnmeasured(_ tracking: TrackingState) {
        widget.value.font = .systemFont(ofSize: 22, weight: .medium)
        widget.value.stringValue = tracking.mode == "tasks" ? "\(tracking.counts.done)/\(tracking.counts.total)" : !tracking.conflicts.isEmpty ? localized("待核对", "Check sources", "À vérifier") : tracking.signals.contains(where: { $0.kind == "blocker" }) ? localized("有阻塞", "Blocked", "Bloqué") : tracking.mode == "status" ? localized("项目近况", "Project state", "État du projet") : localized("待补充", "Unknown", "À préciser")
        widget.scope.stringValue = tracking.mode == "tasks" ? localized("已识别任务", "Detected tasks", "Tâches détectées") : tracking.signals.first?.file ?? ""
        let evidence = tracking.signals.first(where: { $0.kind == "blocker" }) ?? tracking.signals.first(where: { $0.kind == "current" }) ?? tracking.signals.first
        widget.stage.stringValue = tracking.mode == "tasks" ? localized("进行中 \(tracking.counts.active) · 阻塞 \(tracking.counts.blocked)", "\(tracking.counts.active) active · \(tracking.counts.blocked) blocked", "\(tracking.counts.active) en cours · \(tracking.counts.blocked) bloquées") : evidence?.text ?? localized("展开查看资料或定义目标", "Open notes or define goals", "Consulter les notes ou définir des objectifs")
        widget.stage.toolTip = evidence.map { "\($0.text)\n\($0.file):\($0.line)" } ?? trackingSubtitle(tracking)
        widget.eta.stringValue = tracking.mode == "tasks" ? localized("范围未知", "Scope unknown", "Périmètre inconnu") : ""
        widget.eta.toolTip = trackingSubtitle(tracking)
        widget.track.isHidden = true; widget.track.setProgress(0, animated: false)
        widget.track.setAccessibilityElement(false)
        widget.value.toolTip = trackingSubtitle(tracking); widget.scope.toolTip = trackingSubtitle(tracking)
        widget.needsLayout = true
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
        projectPopover.performClose(nil)
        NSApp.activate(ignoringOtherApps: true)
        if let details = detailsWindow { details.makeKeyAndOrderFront(nil); return }
        detailsReady = false
        let config = WKWebViewConfiguration()
        let appearance = "window.questlogAppearancePreference = '\(appearancePreference)';"
        config.userContentController.addUserScript(WKUserScript(source: appearance, injectionTime: .atDocumentStart, forMainFrameOnly: true))
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
        web.loadHTMLString("<html style='color-scheme:light dark'><body style='font:12px -apple-system;background:Canvas;color:GrayText;padding:55px 25px'>\(localized("正在读取项目详情…", "Reading project details…", "Lecture des détails du projet…"))</body></html>", baseURL: nil)
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
        detailsReady = false; pendingDetailsRoute = nil
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
        else if action == "details-ready" { detailsReady = true; deliverDetailsRoute() }
        else if action == "compact" { showWidget() }
        else if action.hasPrefix("language:") { refreshSummary(force: true) }
        else if action.hasPrefix("appearance:") {
            let preference = String(action.dropFirst("appearance:".count))
            if ["auto", "light", "dark"].contains(preference) { applyAppearance(preference); refreshSummary(force: true) }
        }
        else if action == "projects-changed" { refreshSummary(force: true) }
        else if action.hasPrefix("project:") {
            if pendingDetailsRoute?.first == "project" { return }
            let value = String(action.dropFirst(8))
            let id: String? = value.isEmpty ? nil : value
            if selectedID != id { selectedID = id; refreshSummary(force: true) }
        }
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if sender === detailsWindow { showWidget(); return false }
        hideWidget(); return false
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showWidget() }; return true
    }
    @objc func quit() { NSApp.terminate(nil) }
    func applicationWillTerminate(_ notification: Notification) {
        exiting = true; timer?.invalidate(); overviewTimer?.invalidate(); projectPopover.performClose(nil); stopDetails()
        if let item = statusItem { NSStatusBar.system.removeStatusItem(item) }
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
