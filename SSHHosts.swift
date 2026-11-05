import Cocoa

struct Host {
    let name: String
    let alias: String
    let host: String
    let port: Int
    let user: String
    let password: String

    var address: String { "\(user)@\(host):\(port)" }
    var searchText: String { "\(name) \(alias) \(host) \(user) \(port)".lowercased() }
}

enum TerminalKind {
    case commandFile      // Terminal.app：开 .command 文件
    case appleScript      // iTerm2：AppleScript create window with command
    case cli              // WezTerm / kitty / Alacritty / Ghostty
}

struct TerminalDef {
    let id: String
    let name: String
    let bundleID: String
    let kind: TerminalKind
    let cliPath: String
}

/// 唯一入口：列表 + 表单（新增/编辑都在同一个窗口里弹 sheet）
final class AppDelegate: NSObject, NSApplicationDelegate, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    var window: NSWindow!
    let searchField = NSSearchField()
    let table = NSTableView()
    let statusLabel = NSTextField(labelWithString: "")
    let terminalPopup = NSPopUpButton()

    var allHosts: [Host] = []
    var hosts: [Host] = []
    var terminals: [TerminalDef] = []

    // 表单
    var formPanel: NSPanel?
    let aliasField = NSTextField()
    let nameField = NSTextField()
    let hostField = NSTextField()
    let portField = NSTextField()
    let userField = NSTextField()
    let passwordField = NSSecureTextField()
    let envPopup = NSPopUpButton()
    let tagsField = NSTextField()
    let formStatus = NSTextField(labelWithString: "")
    var editingAlias: String?
    var originalAlias = ""

    let envs: [(key: String, title: String)] = [
        ("prod", "生产"), ("pre", "预生产"), ("test", "测试"), ("other", "其他"),
    ]

    var wsshPath: String { NSHomeDirectory() + "/.local/bin/wssh" }
    var isAddBundle: Bool { Bundle.main.bundleIdentifier == "local.workinfo.addssh" }

    var toolDir: URL {
        if let p = ProcessInfo.processInfo.environment["WORK_SSH_TOOL_DIR"], !p.isEmpty {
            return URL(fileURLWithPath: p)
        }
        if let res = Bundle.main.resourceURL,
           let p = try? String(contentsOf: res.appendingPathComponent("tools.path"), encoding: .utf8) {
            let dir = p.trimmingCharacters(in: .whitespacesAndNewlines)
            if FileManager.default.fileExists(atPath: dir + "/hosts.json") {
                return URL(fileURLWithPath: dir)
            }
        }
        let support = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/SSHAssistant")
        if FileManager.default.fileExists(atPath: support.appendingPathComponent("hosts.json").path) {
            return support
        }
        let parent = Bundle.main.bundleURL.deletingLastPathComponent()
        if FileManager.default.fileExists(atPath: parent.appendingPathComponent("hosts.json").path) {
            return parent
        }
        return support   // 默认数据目录（不存在时表单会提示）
    }

    var shortcutsDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/WorkInfoSSH/Shortcuts")
    }

    // MARK: - 生命周期

    func argValue(_ key: String) -> String? {
        guard let i = CommandLine.arguments.firstIndex(of: key), i + 1 < CommandLine.arguments.count else { return nil }
        return CommandLine.arguments[i + 1]
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("--self-test") {
            loadHosts(); _ = loadTerminals()
            print("self-test ok: hosts=\(allHosts.count) terminals=\(terminals.map { $0.id }.joined(separator: ","))")
            exit(0)
        }
        if let i = CommandLine.arguments.firstIndex(of: "--snapshot"), i + 1 < CommandLine.arguments.count {
            let path = CommandLine.arguments[i + 1]
            let v = buildContentView()
            loadHosts(); _ = loadTerminals()
            v.frame = NSRect(origin: .zero, size: NSSize(width: 700, height: 470))
            v.layoutSubtreeIfNeeded()
            snapshot(v, to: path)
            exit(0)
        }
        if let i = CommandLine.arguments.firstIndex(of: "--form-snapshot"), i + 1 < CommandLine.arguments.count {
            let path = CommandLine.arguments[i + 1]
            loadHosts()
            if let a = argValue("--edit"), let h = allHosts.first(where: { $0.alias == a }) {
                prefillForm(h)
            } else {
                resetForm()
            }
            let v = buildFormView()
            v.frame = NSRect(origin: .zero, size: v.fittingSize)
            v.layoutSubtreeIfNeeded()
            snapshot(v, to: path)
            exit(0)
        }
        if let i = CommandLine.arguments.firstIndex(of: "--open"), i + 2 < CommandLine.arguments.count {
            loadHosts(); _ = loadTerminals()
            let tid = CommandLine.arguments[i + 1]
            let alias = CommandLine.arguments[i + 2]
            guard let h = allHosts.first(where: { $0.alias == alias }),
                  let t = terminals.first(where: { $0.id == tid }) else { print("not found"); exit(1) }
            print(launch(t, host: h) ? "ok" : "fail")
            exit(0)
        }
        if CommandLine.arguments.contains("--list-terminals") {
            _ = loadTerminals()
            for t in terminals { print("\(t.id)\t\(t.name)\t\(t.kind)") }
            exit(0)
        }
        if CommandLine.arguments.contains("--write-shortcuts") {
            loadHosts()
            var n = 0
            for h in allHosts where writeShortcut(h) { n += 1 }
            print("shortcuts written: \(n), pruned: \(pruneShortcuts()) at \(shortcutsDir.path)")
            exit(0)
        }
        if let i = CommandLine.arguments.firstIndex(of: "--print-open"), i + 2 < CommandLine.arguments.count {
            loadHosts(); _ = loadTerminals()
            let tid = CommandLine.arguments[i + 1]
            let alias = CommandLine.arguments[i + 2]
            guard let h = allHosts.first(where: { $0.alias == alias }),
                  let t = terminals.first(where: { $0.id == tid }) else { print("not found"); exit(1) }
            print(describeOpen(t, h))
            exit(0)
        }

        _ = loadTerminals()
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 470),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        window.title = "SSH 主机"
        window.contentView = buildContentView()
        loadHosts()
        placeWindow(window)
        window.collectionBehavior.insert(.moveToActiveSpace)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            NSApp.activate(ignoringOtherApps: true)
            self?.window.makeKeyAndOrderFront(nil)
        }
        window.makeFirstResponder(searchField)

        NotificationCenter.default.addObserver(
            self, selector: #selector(didActivate),
            name: NSApplication.didBecomeActiveNotification, object: nil)

        buildMenu()

        // 点哪个图标都先进列表；编辑/添加再用 sheet
        if let alias = argValue("--edit") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                guard let self = self, let h = self.allHosts.first(where: { $0.alias == alias }) else { return }
                self.openEditSheet(h)
            }
        } else if isAddBundle {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                self?.openAddSheet()
            }
        }

        if CommandLine.arguments.contains("--launch-check") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                print("visible=\(self.window.isVisible) rows=\(self.hosts.count) terminals=\(self.terminals.count) sheet=\(self.formPanel != nil)")
                NSApp.terminate(nil)
            }
        }
    }

    func buildMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        appItem.submenu = appMenu
        appMenu.addItem(withTitle: "关于 SSH 主机",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                        keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let fileItem = NSMenuItem()
        main.addItem(fileItem)
        let fileMenu = NSMenu(title: "文件")
        fileItem.submenu = fileMenu
        fileMenu.addItem(withTitle: "在 Finder 中显示数据目录",
                         action: #selector(revealDataDir), keyEquivalent: "")
        fileMenu.addItem(withTitle: "重新载入", action: #selector(reloadHosts), keyEquivalent: "r")
        NSApp.mainMenu = main
    }

    @objc func revealDataDir() {
        NSWorkspace.shared.activateFileViewerSelecting([toolDir])
    }

    @objc func reloadHosts() {
        loadHosts()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    @objc func didActivate() {
        loadHosts()
    }

    func screenForNewWindow() -> NSScreen {
        let mouse = NSEvent.mouseLocation
        if let s = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) { return s }
        return NSScreen.main ?? NSScreen.screens[0]
    }

    func placeWindow(_ w: NSWindow) {
        let vf = screenForNewWindow().visibleFrame
        var size = w.frame.size
        size.width = min(size.width, vf.width - 40)
        size.height = min(size.height, vf.height - 40)
        w.setFrame(NSRect(x: vf.midX - size.width / 2, y: vf.midY - size.height / 2,
                          width: size.width, height: size.height), display: true)
    }

    // 点 Dock 图标时：窗口若在别的屏幕，搬回来并置前
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if let w = window {
            if w.screen != screenForNewWindow() { placeWindow(w) }
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
        return true
    }

    // MARK: - 数据

    func loadHosts() {
        let url = toolDir.appendingPathComponent("hosts.json")
        guard let data = try? Data(contentsOf: url),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            allHosts = []; hosts = []
            return
        }
        allHosts = arr.compactMap { d in
            guard let alias = d["alias"] as? String,
                  let host = d["host"] as? String,
                  let user = d["user"] as? String else { return nil }
            return Host(name: (d["name"] as? String) ?? alias,
                        alias: alias,
                        host: host,
                        port: (d["port"] as? Int) ?? 22,
                        user: user,
                        password: (d["password"] as? String) ?? "")
        }
        applyFilter()
    }

    func loadTerminals() -> [TerminalDef] {
        var list: [TerminalDef] = []
        let fm = FileManager.default
        if fm.fileExists(atPath: "/System/Applications/Utilities/Terminal.app") {
            list.append(TerminalDef(id: "com.apple.Terminal", name: "系统终端 Terminal",
                                    bundleID: "com.apple.Terminal", kind: .commandFile, cliPath: ""))
        }
        if fm.fileExists(atPath: "/Applications/iTerm.app") {
            list.append(TerminalDef(id: "com.googlecode.iterm2", name: "iTerm2",
                                    bundleID: "com.googlecode.iterm2", kind: .appleScript, cliPath: ""))
        }
        let cliApps: [(String, String, String)] = [
            ("com.github.wez.wezterm", "WezTerm", "/Applications/WezTerm.app/Contents/MacOS/wezterm"),
            ("net.kovidgoyal.kitty", "kitty", "/Applications/kitty.app/Contents/MacOS/kitty"),
            ("org.alacritty", "Alacritty", "/Applications/Alacritty.app/Contents/MacOS/alacritty"),
            ("com.mitchellh.ghostty", "Ghostty", "/Applications/Ghostty.app/Contents/MacOS/ghostty"),
        ]
        for (id, name, path) in cliApps where fm.isExecutableFile(atPath: path) {
            list.append(TerminalDef(id: id, name: name, bundleID: id, kind: .cli, cliPath: path))
        }
        terminals = list
        if terminalPopup.numberOfItems == 0 {
            for t in list { terminalPopup.addItem(withTitle: t.name) }
        }
        let saved = UserDefaults.standard.string(forKey: "PreferredTerminal") ?? "com.apple.Terminal"
        if let idx = list.firstIndex(where: { $0.id == saved }) {
            terminalPopup.selectItem(at: idx)
        } else if !list.isEmpty {
            terminalPopup.selectItem(at: 0)
        }
        return list
    }

    func selectedTerminal() -> TerminalDef? {
        guard !terminals.isEmpty else { return nil }
        let idx = terminalPopup.indexOfSelectedItem
        guard idx >= 0, idx < terminals.count else { return terminals.first }
        return terminals[idx]
    }

    func applyFilter() {
        let q = searchField.stringValue.trimmingCharacters(in: .whitespaces).lowercased()
        hosts = q.isEmpty ? allHosts : allHosts.filter { $0.searchText.contains(q) }
        table.reloadData()
        if !hosts.isEmpty {
            table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
        updateStatus()
    }

    func updateStatus() {
        statusLabel.stringValue = "\(hosts.count)/\(allHosts.count) 台 · 双击打开 · ⌘E 编辑"
    }

    // MARK: - 列表 UI

    func buildContentView() -> NSView {
        searchField.placeholderString = "搜索：名称 / 别名 / IP / 用户"
        searchField.target = self
        searchField.action = #selector(searchChanged)
        searchField.sendsSearchStringImmediately = true
        searchField.delegate = self

        table.usesAlternatingRowBackgroundColors = true
        table.rowHeight = 24
        table.allowsEmptySelection = false
        table.target = self
        table.doubleAction = #selector(openSelected)
        table.dataSource = self
        table.delegate = self

        for (id, title, width) in [("name", "名称", 250.0), ("alias", "别名", 130.0), ("addr", "地址", 250.0)] {
            let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            col.title = title
            col.width = width
            table.addTableColumn(col)
        }

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder

        statusLabel.font = NSFont.systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor

        terminalPopup.target = self
        terminalPopup.action = #selector(terminalChanged)

        let openButton = NSButton(title: "打开", target: self, action: #selector(openSelected))
        openButton.bezelStyle = .rounded
        openButton.keyEquivalent = "\r"

        let editButton = NSButton(title: "编辑", target: self, action: #selector(editSelected))
        editButton.bezelStyle = .rounded
        editButton.keyEquivalent = "e"
        editButton.keyEquivalentModifierMask = [.command]

        let addButton = NSButton(title: "添加主机", target: self, action: #selector(addTapped))
        addButton.bezelStyle = .rounded
        addButton.keyEquivalent = "n"
        addButton.keyEquivalentModifierMask = [.command]

        let bottom = NSStackView(views: [statusLabel, NSView(), terminalPopup, editButton, addButton, openButton])
        bottom.orientation = .horizontal
        bottom.spacing = 8
        bottom.distribution = .fill

        let stack = NSStackView(views: [searchField, scroll, bottom])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let root = NSView()
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            stack.topAnchor.constraint(equalTo: root.topAnchor),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            searchField.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -28),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -28),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 240),
            bottom.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -28),
        ])
        return root
    }

    func numberOfRows(in tableView: NSTableView) -> Int { hosts.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let col = tableColumn, row < hosts.count else { return nil }
        let h = hosts[row]
        let text: String
        switch col.identifier.rawValue {
        case "name": text = h.name
        case "alias": text = h.alias
        default: text = h.address
        }
        let cell = NSTextField(labelWithString: text)
        cell.lineBreakMode = .byTruncatingTail
        cell.font = NSFont.systemFont(ofSize: 12)
        if col.identifier.rawValue == "addr" { cell.textColor = .secondaryLabelColor }
        return cell
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            openSelected(); return true
        case #selector(NSResponder.moveDown(_:)):
            moveSelection(1); return true
        case #selector(NSResponder.moveUp(_:)):
            moveSelection(-1); return true
        default:
            return false
        }
    }

    func moveSelection(_ delta: Int) {
        guard !hosts.isEmpty else { return }
        let current = table.selectedRow >= 0 ? table.selectedRow : 0
        let next = min(max(current + delta, 0), hosts.count - 1)
        table.selectRowIndexes(IndexSet(integer: next), byExtendingSelection: false)
        table.scrollRowToVisible(next)
    }

    // MARK: - 表单 UI

    func label(_ text: String) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.alignment = .right
        l.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        return l
    }

    func buildFormView() -> NSView {
        aliasField.placeholderString = "例如 jss-prod（字母数字 . _ -）"
        nameField.placeholderString = "留空则显示为 别名 (IP)"
        hostField.placeholderString = "IP 或域名"
        portField.placeholderString = "22"
        if portField.stringValue.isEmpty { portField.stringValue = "22" }
        userField.placeholderString = "root"
        passwordField.placeholderString = "仅本机保存（600 权限文件）"
        tagsField.placeholderString = "可选，逗号分隔，如 Zeil,数据库"

        if envPopup.numberOfItems == 0 {
            for (i, e) in envs.enumerated() {
                envPopup.addItem(withTitle: e.title)
                envPopup.item(at: i)?.tag = i
            }
        }

        for f in [aliasField, nameField, hostField, portField, userField, passwordField, tagsField] {
            f.font = NSFont.systemFont(ofSize: 13)
            f.translatesAutoresizingMaskIntoConstraints = false
            if f.constraints.isEmpty {
                f.widthAnchor.constraint(greaterThanOrEqualToConstant: 300).isActive = true
            }
        }

        let grid = NSGridView(views: [
            [label("别名"), aliasField],
            [label("显示名"), nameField],
            [label("主机/IP"), hostField],
            [label("端口"), portField],
            [label("用户名"), userField],
            [label("密码"), passwordField],
            [label("环境"), envPopup],
            [label("标签"), tagsField],
        ])
        grid.rowSpacing = 10
        grid.columnSpacing = 10
        grid.column(at: 0).xPlacement = .trailing

        let hint = NSTextField(labelWithString: "保存后立即写入 ~/.ssh 与 iTerm2，⌘⇧O 搜索别名即可连接。")
        hint.font = NSFont.systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor

        formStatus.font = NSFont.systemFont(ofSize: 11)
        formStatus.textColor = .secondaryLabelColor

        let save = NSButton(title: editingAlias == nil ? "保存并写入" : "保存修改",
                            target: self, action: #selector(saveForm))
        save.bezelStyle = .rounded
        save.keyEquivalent = "\r"

        let cancel = NSButton(title: "取消", target: self, action: #selector(cancelForm))
        cancel.bezelStyle = .rounded
        cancel.keyEquivalent = "\u{1b}"

        let buttons = NSStackView(views: [formStatus, NSView(), cancel, save])
        buttons.orientation = .horizontal
        buttons.spacing = 8
        buttons.distribution = .fill

        let stack = NSStackView(views: [grid, hint, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.edgeInsets = NSEdgeInsets(top: 18, left: 18, bottom: 18, right: 18)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let root = NSView()
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            stack.topAnchor.constraint(equalTo: root.topAnchor),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            buttons.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -36),
        ])
        return root
    }

    func resetForm() {
        aliasField.stringValue = ""
        nameField.stringValue = ""
        hostField.stringValue = ""
        portField.stringValue = "22"
        userField.stringValue = ""
        passwordField.stringValue = ""
        tagsField.stringValue = ""
        envPopup.selectItem(at: 0)
        formStatus.stringValue = ""
        editingAlias = nil
        originalAlias = ""
    }

    func prefillForm(_ h: Host) {
        editingAlias = h.alias
        originalAlias = h.alias
        aliasField.stringValue = h.alias
        nameField.stringValue = h.name
        hostField.stringValue = h.host
        portField.stringValue = String(h.port)
        userField.stringValue = h.user
        passwordField.stringValue = h.password

        let url = toolDir.appendingPathComponent("hosts.json")
        var tags: [String] = []
        var envKey = "prod"
        if let data = try? Data(contentsOf: url),
           let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
           let e = arr.first(where: { ($0["alias"] as? String) == h.alias }) {
            let allTags = (e["tags"] as? [String]) ?? []
            let tagEnv: [String: String] = ["生产": "prod", "预生产": "pre", "测试": "test", "其他": "other"]
            envKey = tagEnv[allTags.first ?? "生产"] ?? "prod"
            let envNames: Set<String> = ["生产", "预生产", "测试", "其他"]
            tags = allTags.filter { !envNames.contains($0) }
        }
        if let idx = envs.firstIndex(where: { $0.key == envKey }) { envPopup.selectItem(at: idx) }
        tagsField.stringValue = tags.joined(separator: ",")
    }

    func showForm(_ edit: Host?) {
        resetForm()
        if let h = edit { prefillForm(h) }
        formStatus.stringValue = edit.map { "编辑 \($0.alias)：改完点「保存修改」" } ?? ""

        let view = buildFormView()
        let size = view.fittingSize
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: max(520, size.width), height: max(420, size.height)),
                            styleMask: [.titled], backing: .buffered, defer: false)
        panel.title = edit == nil ? "新增 SSH 主机" : "编辑 SSH 主机"
        panel.contentView = view
        formPanel = panel
        window.beginSheet(panel) { [weak self] _ in self?.formPanel = nil }
        panel.makeFirstResponder(aliasField)
    }

    @objc func addTapped() { showForm(nil) }
    @objc func openAddSheet() { showForm(nil) }

    @objc func editSelected() {
        let row = table.selectedRow >= 0 ? table.selectedRow : 0
        guard row >= 0, row < hosts.count else { return }
        openEditSheet(hosts[row])
    }

    func openEditSheet(_ h: Host) { showForm(h) }

    @objc func cancelForm() {
        if let p = formPanel { window.endSheet(p) }
    }

    @objc func saveForm() {
        let alias = aliasField.stringValue.trimmingCharacters(in: .whitespaces)
        let host = hostField.stringValue.trimmingCharacters(in: .whitespaces)
        let user = userField.stringValue.trimmingCharacters(in: .whitespaces)
        let pass = passwordField.stringValue
        let port = Int(portField.stringValue.trimmingCharacters(in: .whitespaces)) ?? -1

        guard !alias.isEmpty, !host.isEmpty, !user.isEmpty, !pass.isEmpty else {
            formStatus.textColor = .systemRed
            formStatus.stringValue = "别名、主机、用户名、密码都必须填写"
            return
        }
        guard port >= 1, port <= 65535 else {
            formStatus.textColor = .systemRed
            formStatus.stringValue = "端口必须是 1-65535"
            return
        }

        if editingAlias == nil, allHosts.contains(where: { $0.alias == alias }) {
            let alert = NSAlert()
            alert.messageText = "别名 \(alias) 已存在"
            alert.informativeText = "继续会覆盖原有记录。"
            alert.addButton(withTitle: "覆盖")
            alert.addButton(withTitle: "取消")
            if alert.runModal() != .alertFirstButtonReturn { return }
        }

        formStatus.textColor = .secondaryLabelColor
        formStatus.stringValue = "正在写入…"

        let (status, output) = runAddHost(
            alias: alias, host: host, user: user, pass: pass, port: port,
            name: nameField.stringValue.trimmingCharacters(in: .whitespaces),
            tags: tagsField.stringValue.trimmingCharacters(in: .whitespaces),
            envKey: envs[envPopup.indexOfSelectedItem].key,
            original: editingAlias ?? "")

        let jsonLine = output.split(separator: "\n").last(where: { $0.hasPrefix("{") })
        let json = jsonLine.flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }

        guard status == 0, let j = json, (j["ok"] as? Bool) == true else {
            formStatus.textColor = .systemRed
            formStatus.stringValue = (json?["error"] as? String) ?? "写入失败（exit \(status)）"
            return
        }

        let action = (j["action"] as? String) == "updated" ? "已更新" : "已添加"
        if let p = formPanel { window.endSheet(p) }
        loadHosts()
        statusLabel.stringValue = "\(action) \(alias) — 可在 ⌘⇧O 或列表里打开"
    }

    func runAddHost(alias: String, host: String, user: String, pass: String, port: Int,
                    name: String, tags: String, envKey: String, original: String) -> (Int32, String) {
        let script = toolDir.appendingPathComponent("add_host.py").path
        guard FileManager.default.fileExists(atPath: script) else {
            return (-1, "{\"ok\": false, \"error\": \"找不到 add_host.py\"}")
        }
        var args = [script, "--alias", alias, "--host", host, "--port", String(port),
                    "--user", user, "--password-stdin", "--env", envKey, "--yes", "--json"]
        if !name.isEmpty { args += ["--name", name] }
        if !tags.isEmpty { args += ["--tags", tags] }
        if !original.isEmpty { args += ["--original", original] }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        p.arguments = args
        p.currentDirectoryURL = toolDir
        let outPipe = Pipe(), inPipe = Pipe()
        p.standardOutput = outPipe
        p.standardError = outPipe
        p.standardInput = inPipe
        do { try p.run() } catch {
            return (-1, "{\"ok\": false, \"error\": \"启动脚本失败\"}")
        }
        if let d = (pass + "\n").data(using: .utf8) { inPipe.fileHandleForWriting.write(d) }
        inPipe.fileHandleForWriting.closeFile()
        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }

    // MARK: - 打开终端

    @objc func searchChanged() { applyFilter() }

    @objc func terminalChanged() {
        if let t = selectedTerminal() {
            UserDefaults.standard.set(t.id, forKey: "PreferredTerminal")
        }
    }

    @objc func openSelected() {
        let row = table.selectedRow >= 0 ? table.selectedRow : 0
        guard row >= 0, row < hosts.count, let term = selectedTerminal() else { return }
        let h = hosts[row]
        let ok = launch(term, host: h)
        statusLabel.stringValue = ok
            ? "已在 \(term.name) 打开 \(h.alias)"
            : "打开失败：\(term.name)（iTerm2 需在 系统设置 → 隐私与安全性 → 自动化 中允许）"
    }

    // 有窗口就开新标签，没有才开新窗口
    func appleScript(for term: TerminalDef, host h: Host) -> String {
        let cmd = "\(wsshPath) \(h.alias)"
        if term.id == "com.googlecode.iterm2" {
            return """
            tell application "iTerm2"
                activate
                if (count of windows) > 0 then
                    tell current window to create tab with default profile
                    delay 0.6
                    tell current session of current window to write text "\(cmd)"
                else
                    create window with default profile command "\(cmd)"
                end if
            end tell
            """
        }
        return """
        tell application "Terminal"
            activate
            if (count of windows) > 0 then
                do script "\(cmd)" in front window
            else
                do script "\(cmd)"
            end if
        end tell
        """
    }

    func describeOpen(_ term: TerminalDef, _ h: Host) -> String {
        switch term.kind {
        case .commandFile:
            return "open -b \(term.bundleID) \(shortcutsDir.path)/\(h.alias).command"
        case .appleScript:
            return appleScript(for: term, host: h).replacingOccurrences(of: "\n", with: " ")
        case .cli:
            return ([term.cliPath] + cliArguments(term, h)).joined(separator: " ")
        }
    }

    func cliArguments(_ term: TerminalDef, _ h: Host) -> [String] {
        switch term.id {
        case "com.github.wez.wezterm": return ["start", "--", wsshPath, h.alias]
        case "org.alacritty", "com.mitchellh.ghostty": return ["-e", wsshPath, h.alias]
        default: return [wsshPath, h.alias]
        }
    }

    @discardableResult
    func launch(_ term: TerminalDef, host h: Host) -> Bool {
        switch term.kind {
        case .commandFile:
            guard writeShortcut(h) else { return false }
            return run("/usr/bin/open", ["-b", term.bundleID,
                                         shortcutsDir.appendingPathComponent("\(h.alias).command").path])
        case .appleScript:
            if run("/usr/bin/osascript", ["-e", appleScript(for: term, host: h)]) { return true }
            // 自动化被拒 / 脚本失败时，退回开窗口的方式
            if term.id == "com.apple.Terminal" {
                guard writeShortcut(h) else { return false }
                return run("/usr/bin/open", ["-b", term.bundleID,
                                             shortcutsDir.appendingPathComponent("\(h.alias).command").path])
            }
            return false
        case .cli:
            return run(term.cliPath, cliArguments(term, h))
        }
    }

    func run(_ path: String, _ args: [String]) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        do { try p.run() } catch { return false }
        p.waitUntilExit()
        return p.terminationStatus == 0
    }

    @discardableResult
    func writeShortcut(_ h: Host) -> Bool {
        do {
            try FileManager.default.createDirectory(at: shortcutsDir, withIntermediateDirectories: true)
            let file = shortcutsDir.appendingPathComponent("\(h.alias).command")
            let body = """
            #!/bin/zsh
            # \(h.name)  \(h.user)@\(h.host):\(h.port)
            exec "$HOME/.local/bin/wssh" \(h.alias)

            """
            try body.write(to: file, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
            return true
        } catch { return false }
    }

    func pruneShortcuts() -> Int {
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: shortcutsDir.path) else { return 0 }
        let alive = Set(allHosts.map { $0.alias + ".command" })
        var n = 0
        for f in files where f.hasSuffix(".command") && !alive.contains(f) {
            try? FileManager.default.removeItem(at: shortcutsDir.appendingPathComponent(f))
            n += 1
        }
        return n
    }

    func snapshot(_ v: NSView, to path: String) {
        if let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) {
            v.cacheDisplay(in: v.bounds, to: rep)
            if let data = rep.representation(using: .png, properties: [:]) {
                try? data.write(to: URL(fileURLWithPath: path))
                print("snapshot: \(path) \(Int(v.bounds.width))x\(Int(v.bounds.height))")
                return
            }
        }
        print("snapshot failed")
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
