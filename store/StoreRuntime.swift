#if APP_STORE
import AppKit
import WebKit
import UniformTypeIdentifiers

struct StoreFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

final class StoreAccess {
    let file: URL
    private(set) var folders: [String: URL] = [:]
    private(set) var registries: [String: URL] = [:]
    private var bookmarks: [String: Data] = [:]

    init(directory: URL) throws {
        file = directory.appendingPathComponent("access.json")
        if let data = try? Data(contentsOf: file) {
            bookmarks = (try? JSONDecoder().decode([String: Data].self, from: data)) ?? [:]
        }
        var refreshed = false
        for (key, bookmark) in bookmarks {
            var stale = false
            guard let url = try? URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope], bookmarkDataIsStale: &stale),
                  url.startAccessingSecurityScopedResource() else { continue }
            if key.hasPrefix("registry:") { registries[String(key.dropFirst(9))] = url }
            else { folders[url.resolvingSymlinksInPath().path] = url }
            if stale, let data = try? url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess]) {
                bookmarks[key] = data; refreshed = true
            }
        }
        if refreshed { try persist() }
    }
    deinit {
        for url in folders.values { url.stopAccessingSecurityScopedResource() }
        for url in registries.values { url.stopAccessingSecurityScopedResource() }
    }
    func persist() throws { try JSONEncoder().encode(bookmarks).write(to: file, options: .atomic) }
    func reset() throws {
        try JSONEncoder().encode([String: Data]()).write(to: file, options: .atomic)
        for url in folders.values { url.stopAccessingSecurityScopedResource() }
        for url in registries.values { url.stopAccessingSecurityScopedResource() }
        folders.removeAll(); registries.removeAll(); bookmarks.removeAll()
    }
    func contains(_ path: String) -> Bool {
        let root = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        return folders.keys.contains { root == $0 || root.hasPrefix($0 + "/") }
    }
    func remember(_ url: URL, provider: String? = nil) throws {
        let resolved = url.resolvingSymlinksInPath()
        let data = try resolved.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess])
        guard resolved.startAccessingSecurityScopedResource() else { throw StoreFailure(message: "无法读取文件，请检查文件权限") }
        let key = provider.map { "registry:\($0)" } ?? "folder:\(resolved.path)"
        let old = bookmarks[key]
        bookmarks[key] = data
        do { try persist() }
        catch { bookmarks[key] = old; resolved.stopAccessingSecurityScopedResource(); throw error }
        if let provider = provider {
            registries[provider]?.stopAccessingSecurityScopedResource(); registries[provider] = resolved
        } else if folders[resolved.path] == nil { folders[resolved.path] = resolved }
        else { resolved.stopAccessingSecurityScopedResource() }
    }
    func chooseFolder(expected: String? = nil, title: String, completion: @escaping (Result<String?, Error>) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.allowsMultipleSelection = false; panel.canCreateDirectories = false
        panel.title = title
        if let expected = expected { panel.directoryURL = URL(fileURLWithPath: expected) }
        panel.begin { response in
            guard response == .OK, let url = panel.url else { completion(.success(nil)); return }
            do {
                let path = url.resolvingSymlinksInPath().path
                if let expected = expected, path != URL(fileURLWithPath: expected).resolvingSymlinksInPath().path {
                    throw StoreFailure(message: "请选择对应的项目目录")
                }
                try self.remember(url)
                completion(.success(path))
            } catch { completion(.failure(error)) }
        }
    }
    func chooseRegistry(provider: String, title: String, completion: @escaping (Result<Bool, Error>) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true; panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false; panel.allowedContentTypes = [.json]
        panel.showsHiddenFiles = true; panel.title = title
        panel.message = provider == "codex" ? "~/.codex/.codex-global-state.json" : "~/.claude.json"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { completion(.success(false)); return }
            do {
                let resource = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
                guard resource.isRegularFile == true, (resource.fileSize ?? Int.max) <= 15_000_000 else {
                    throw StoreFailure(message: "本地项目索引过大，请使用手动连接")
                }
                try self.remember(url, provider: provider)
                completion(.success(true))
            } catch { completion(.failure(error)) }
        }
    }
}

final class StoreRuntime: NSObject, WKScriptMessageHandlerWithReply, WKNavigationDelegate {
    let directory: URL
    let configuration: URL
    let resources: URL
    let access: StoreAccess
    let queue = DispatchQueue(label: "local.questlog.adapter", qos: .utility)
    weak var owner: CompanionApp?
    private var initialized = false

    init(applicationSupport: URL? = nil) throws {
        resources = Bundle.main.resourceURL!
        directory = applicationSupport ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("QuestlogStore", isDirectory: true)
        configuration = directory.appendingPathComponent("projects.json")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: configuration.path) {
                try Data("{\"version\":1,\"language\":\"auto\",\"projects\":[]}".utf8).write(to: configuration, options: .atomic)
            }
            access = try StoreAccess(directory: directory)
        } catch { throw error }
        super.init()
    }
    func trusted(_ message: WKScriptMessage) -> Bool {
        guard message.frameInfo.isMainFrame, let url = message.frameInfo.request.url, url.isFileURL else { return false }
        return url.resolvingSymlinksInPath().path == resources.appendingPathComponent("public/index.html").resolvingSymlinksInPath().path
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let url = navigationAction.request.url
        let allowed = url?.isFileURL == true && url!.resolvingSymlinksInPath().path == resources.appendingPathComponent("public/index.html").resolvingSymlinksInPath().path
        decisionHandler(allowed || url?.absoluteString == "about:blank" ? .allow : .cancel)
    }
    func request(_ path: String, body: [String: Any]? = nil, completion: @escaping (Result<[String: Any], Error>) -> Void) {
        let request: [String: Any] = ["method": body == nil ? "GET" : "POST", "path": path, "body": body ?? [:],
                                      "authorizedRoots": Array(access.folders.keys), "registries": access.registries.mapValues { $0.path }]
        queue.async {
            do {
                let data = try JSONSerialization.data(withJSONObject: request)
                let response = try self.perform(data)
                DispatchQueue.main.async { completion(.success(response)) }
            } catch { DispatchQueue.main.async { completion(.failure(error)) } }
        }
    }
    private func perform(_ data: Data) throws -> [String: Any] {
        if !initialized {
            let framework = Bundle.main.privateFrameworksURL!.appendingPathComponent("Python.framework/Versions/3.13")
            if let failure = QLPythonInitialize(resources.path, framework.path) {
                defer { QLPythonFree(failure) }
                throw StoreFailure(message: String(cString: failure))
            }
            initialized = true
        }
        guard let result = QLPythonDispatch(String(decoding: data, as: UTF8.self), configuration.path) else {
            throw StoreFailure(message: "Unable to read bundled runtime response")
        }
        defer { QLPythonFree(result) }
        guard let response = try JSONSerialization.jsonObject(with: Data(String(cString: result).utf8)) as? [String: Any] else {
            throw StoreFailure(message: "Invalid bundled runtime response")
        }
        return response
    }
    func summary(project: String?, completion: @escaping (Result<Data, Error>) -> Void) {
        let suffix = project.map { "?project=" + ($0.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "") } ?? ""
        request("/api/summary" + suffix) { result in
            completion(result.flatMap { response in
                do {
                    let body = response["body"] as? [String: Any] ?? [:]
                    guard response["status"] as? Int == 200 else { throw StoreFailure(message: body["error"] as? String ?? "读取失败") }
                    return .success(try JSONSerialization.data(withJSONObject: body))
                } catch { return .failure(error) }
            })
        }
    }
    func reply(_ result: Result<[String: Any], Error>, to handler: @escaping (Any?, String?) -> Void) {
        switch result {
        case .success(let response): handler(response, nil)
        case .failure(let error): handler(["status": 422, "body": ["error": error.localizedDescription]], nil)
        }
    }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage, replyHandler: @escaping (Any?, String?) -> Void) {
        guard trusted(message), let request = message.body as? [String: Any], let path = request["path"] as? String,
              path.hasPrefix("/api/"), path.utf8.count < 4096 else { replyHandler(nil, "Untrusted request"); return }
        let body = request["body"] as? [String: Any]
        let title = owner?.localized("选择项目目录以授权只读访问", "Choose a project folder for read-only access", "Choisir un dossier de projet pour un accès en lecture seule") ?? "Questlog"
        if path == "/api/privacy/open" {
            NSWorkspace.shared.open(URL(string: "https://github.com/jamezzh7/questlog/blob/main/docs/privacy.md")!)
            replyHandler(["status": 200, "body": [:]], nil); return
        }
        if path == "/api/permissions/reset" {
            let alert = NSAlert()
            alert.messageText = owner?.localized("重置文件访问权限？", "Reset file permissions?", "Réinitialiser les autorisations ?") ?? "Questlog"
            alert.informativeText = owner?.localized("将忘记已选择的目录和工具索引授权。项目连接及工时设置会保留；重新读取时需要再次选择目录。", "Questlog will forget selected folder and tool-index grants. Connections and estimates are kept; choose folders again to resume reading.", "Questlog oubliera les autorisations des dossiers et index. Les connexions et estimations sont conservées ; choisissez de nouveau les dossiers pour reprendre la lecture.") ?? ""
            alert.addButton(withTitle: owner?.localized("取消", "Cancel", "Annuler") ?? "Cancel")
            alert.addButton(withTitle: owner?.localized("重置权限", "Reset permissions", "Réinitialiser") ?? "Reset")
            guard alert.runModal() == .alertSecondButtonReturn else { replyHandler(["status": 200, "body": ["cancelled": true]], nil); return }
            // Finish older reads before releasing their security-scoped grants.
            queue.sync {}
            do { try access.reset(); owner?.refreshSummary(force: true); replyHandler(["status": 200, "body": ["cancelled": false]], nil) }
            catch { reply(.failure(error), to: replyHandler) }
            return
        }
        if path == "/api/permissions/folder" {
            access.chooseFolder(title: title) { result in
                self.reply(result.map { ["status": 200, "body": ["root": $0 ?? "", "cancelled": $0 == nil]] }, to: replyHandler)
            }
            return
        }
        if path == "/api/permissions/project", let project = body?["project"] as? String,
           let data = try? Data(contentsOf: configuration),
           let config = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let projects = config["projects"] as? [[String: Any]],
           let root = projects.first(where: { $0["id"] as? String == project })?["root"] as? String {
            access.chooseFolder(expected: root, title: title) { result in
                self.reply(result.map { ["status": 200, "body": ["root": $0 ?? "", "cancelled": $0 == nil]] }, to: replyHandler)
            }
            return
        }
        if path == "/api/permissions/registry", let provider = body?["provider"] as? String, ["codex", "claude"].contains(provider) {
            access.chooseRegistry(provider: provider, title: owner?.localized("选择工具的项目索引", "Choose the tool's project index", "Choisir l’index des projets de l’outil") ?? "Questlog") { result in
                self.reply(result.map { ["status": 200, "body": ["cancelled": !$0]] }, to: replyHandler)
            }
            return
        }
        if path == "/api/connections", let provider = body?["provider"] as? String, let project = body?["project"] as? String {
            var components = URLComponents(); components.path = "/api/native/connection-target"
            components.queryItems = [URLQueryItem(name: "provider", value: provider), URLQueryItem(name: "project", value: project)]
            self.request(components.string!) { result in
                guard case .success(let response) = result, response["status"] as? Int == 200,
                      let target = response["body"] as? [String: Any], let root = target["root"] as? String else { self.reply(result, to: replyHandler); return }
                if self.access.contains(root) { self.request(path, body: body) { self.reply($0, to: replyHandler) }; return }
                self.access.chooseFolder(expected: root, title: title) { grant in
                    switch grant {
                    case .success(.some(_)): self.request(path, body: body) { self.reply($0, to: replyHandler) }
                    case .success(.none): replyHandler(["status": 499, "body": ["error": "已取消操作"]], nil)
                    case .failure(let error): self.reply(.failure(error), to: replyHandler)
                    }
                }
            }
            return
        }
        self.request(path, body: body) { self.reply($0, to: replyHandler) }
    }
    static func smoke() -> Int32 {
        do {
            let runtime = try StoreRuntime()
            let sample = runtime.directory.appendingPathComponent("SmokeSample")
            if FileManager.default.fileExists(atPath: sample.path) { try FileManager.default.removeItem(at: sample) }
            try FileManager.default.copyItem(at: runtime.resources.appendingPathComponent("SampleProject"), to: sample)
            let original = try Data(contentsOf: runtime.configuration)
            defer { try? original.write(to: runtime.configuration, options: .atomic); try? FileManager.default.removeItem(at: sample) }
            let settings: [String: Any] = ["language": "en", "projects": [["id": "orbit", "name": "Orbit", "root": sample.path, "tasksFile": "tasks.md", "primaryIds": ["A1", "A2", "A3", "A4", "A5"]]]]
            try JSONSerialization.data(withJSONObject: settings).write(to: runtime.configuration, options: .atomic)
            func call(_ path: String, roots: [String]) throws -> [String: Any] {
                let request: [String: Any] = ["method": "GET", "path": path, "authorizedRoots": roots, "registries": [:]]
                return try runtime.perform(JSONSerialization.data(withJSONObject: request))
            }
            let summary = try call("/api/summary", roots: [sample.path])
            let denied = try call("/api/progress?project=orbit", roots: [])
            guard summary["status"] as? Int == 200, denied["status"] as? Int == 403,
                  let body = summary["body"] as? [String: Any], let project = body["project"] as? [String: Any],
                  let overall = project["overall"] as? [String: Any], overall["percent"] as? Int == 60 else { throw StoreFailure(message: "Smoke assertions failed: \(summary)") }
            try original.write(to: runtime.configuration, options: .atomic)
            guard try Data(contentsOf: runtime.configuration) == original else { throw StoreFailure(message: "Smoke configuration was not restored") }
            print(String(data: try JSONSerialization.data(withJSONObject: ["embeddedRuntime": true, "overall": overall, "ungrantedAccessRejected": true, "configurationRestored": true], options: [.sortedKeys]), encoding: .utf8)!)
            return 0
        } catch { fputs(error.localizedDescription + "\n", stderr); return 1 }
    }
}
#endif
