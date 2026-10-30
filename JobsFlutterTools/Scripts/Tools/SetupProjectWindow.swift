//
//  SetupProjectWindow.swift
//  JobsFlutterTools
//
//  Created by Jobs on 2026年10月28日，星期三.
//

import AppKit
import WebKit
import Darwin

struct SetupEvent: Decodable {
    let id: String
    let parent: String?
    let title: String
    let state: String
    let message: String?
    let version: String?

    init(id: String, parent: String?, title: String, state: String, message: String?, version: String? = nil) {
        self.id = id
        self.parent = parent
        self.title = title
        self.state = state
        self.message = message
        self.version = version
    }
}

private struct SetupVersion: Decodable {
    let version: String
    let build: String
}

private final class SetupHorizontalSplit: NSSplitView {
    override var dividerThickness: CGFloat { 14 }

    override func drawDivider(in rect: NSRect) {
        NSColor.separatorColor.setFill()
        rect.fill()
        NSColor.secondaryLabelColor.setFill()
        NSBezierPath(roundedRect: NSRect(x: rect.midX - 24, y: rect.midY - 2, width: 48, height: 4), xRadius: 2, yRadius: 2).fill()
    }
}

final class SetupProjectWindow: NSObject, NSApplicationDelegate, NSWindowDelegate, WKScriptMessageHandler, WKNavigationDelegate, NSSplitViewDelegate {
    private let project: String
    private let tools: URL
    private let session: URL
    private let toolVersion: SetupVersion
    private var window: NSWindow!
    private var web: WKWebView!
    private var split: SetupHorizontalSplit!
    private var summary: NSTextField!
    private var cancel: NSButton!
    private var columns: [String: NSStackView] = [:]
    private var labels: [String: NSTextField] = [:]
    private var versionLabels: [String: NSTextField] = [:]
    private var states: [String: String] = [:]
    private var master: Int32 = -1
    private var child: pid_t = 0
    private var reader: DispatchSourceRead?
    private var rawLog: FileHandle!
    private var eventsTimer: Timer?
    private var eventsOffset: UInt64 = 0
    private var eventsBuffer = Data()
    private var finished = false
    private var requestedClose = false
    private let phases = [("flutter", "Flutter SDK"), ("java", "Java SDK"), ("platforms", "平台工具链"), ("gradle", "Gradle分发"), ("pub", "依赖与插件"), ("readiness", "设备与运行条件")]

    init(project: String, tools: URL) throws {
        self.project = project
        self.tools = tools
        let versionData = try Data(contentsOf: tools.appendingPathComponent("SetupVersion.json"))
        toolVersion = try JSONDecoder().decode(SetupVersion.self, from: versionData)
        guard toolVersion.version.range(of: #"^[0-9]+\.[0-9]+\.[0-9]+$"#, options: .regularExpression) != nil,
              toolVersion.build.range(of: #"^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$"#, options: .regularExpression) != nil else {
            throw NSError(domain: "JobsFlutterSetup", code: 3, userInfo: [NSLocalizedDescriptionKey: "随包SetupVersion.json版本格式无效，请重新取得完整工具包。"])
        }
        var template = Array(FileManager.default.temporaryDirectory.appendingPathComponent("JobsFlutterSetup-XXXXXX").path.utf8CString)
        guard let path = mkdtemp(&template) else {
            throw NSError(domain: "JobsFlutterSetup", code: 1, userInfo: [NSLocalizedDescriptionKey: "无法创建私有会话目录。"])
        }
        session = URL(fileURLWithPath: String(cString: path), isDirectory: true)
        super.init()
        let log = session.appendingPathComponent("terminal.raw.log")
        guard FileManager.default.createFile(atPath: log.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
            throw NSError(domain: "JobsFlutterSetup", code: 2, userInfo: [NSLocalizedDescriptionKey: "无法创建终端日志。"])
        }
        rawLog = try FileHandle(forWritingTo: log)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildWindow()
        NSApp.activate(ignoringOtherApps: true)
        eventsTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in self?.readEvents() }
    }

    private func buildWindow() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1180, height: 800), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.minSize = NSSize(width: 800, height: 560)
        window.title = "Flutter 项目配置 v\(toolVersion.version) · 构建 \(toolVersion.build) · \(URL(fileURLWithPath: project).lastPathComponent)"
        window.delegate = self
        let content = NSView()
        window.contentView = content
        let title = NSTextField(labelWithString: "SDK >>>>> 平台 >>>>> Gradle >>>>> 依赖与插件 >>>>> 运行条件")
        title.font = .boldSystemFont(ofSize: 18)
        summary = NSTextField(wrappingLabelWithString: "请在下方终端阅读自述并确认。fzf、方向键、返回及 Ctrl+C 均保留。")
        summary.textColor = .secondaryLabelColor
        let milestoneScroll = NSScrollView()
        milestoneScroll.hasHorizontalScroller = true
        milestoneScroll.hasVerticalScroller = true
        milestoneScroll.borderType = .bezelBorder
        let line = NSStackView()
        line.orientation = .horizontal
        line.alignment = .top
        line.spacing = 0
        line.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        for (index, phase) in phases.enumerated() {
            let (id, name) = phase
            let column = NSStackView()
            column.orientation = .vertical
            column.alignment = .leading
            column.spacing = 7
            column.distribution = .fill
            column.setHuggingPriority(.required, for: .vertical)
            column.widthAnchor.constraint(equalToConstant: 146).isActive = true
            line.addArrangedSubview(column)
            columns[id] = column
            update(SetupEvent(id: id, parent: nil, title: name, state: "pending", message: nil))
            if index < phases.count - 1 {
                let arrow = NSTextField(labelWithString: ">>>>>")
                arrow.font = .monospacedSystemFont(ofSize: 13, weight: .medium)
                arrow.widthAnchor.constraint(equalToConstant: 48).isActive = true
                arrow.textColor = .tertiaryLabelColor
                line.addArrangedSubview(arrow)
            }
        }
        milestoneScroll.documentView = line
        line.translatesAutoresizingMaskIntoConstraints = false
        line.heightAnchor.constraint(greaterThanOrEqualTo: milestoneScroll.contentView.heightAnchor).isActive = true
        line.widthAnchor.constraint(greaterThanOrEqualTo: milestoneScroll.contentView.widthAnchor).isActive = true
        let config = WKWebViewConfiguration()
        config.userContentController.add(self, name: "pty")
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = self
        web.loadFileURL(tools.appendingPathComponent("SetupGUIAssets/terminal.html"), allowingReadAccessTo: tools.appendingPathComponent("SetupGUIAssets", isDirectory: true))
        let hint = NSTextField(labelWithString: "原始输出完整保存在本机会话目录，可能包含敏感信息；复制或分享前请核对。")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        let open = NSButton(title: "打开日志目录", target: self, action: #selector(openLogs))
        cancel = NSButton(title: "取消任务（Ctrl+C）", target: self, action: #selector(cancelTask))
        split = SetupHorizontalSplit()
        split.isVertical = false
        split.dividerStyle = .thick
        split.delegate = self
        split.toolTip = "上下拖动此分隔条，调整任务线与终端高度；终端内容仍可独立滚动。"
        split.addArrangedSubview(milestoneScroll)
        split.addArrangedSubview(web)
        let footer = NSStackView(views: [hint, open, cancel])
        footer.orientation = .horizontal
        footer.spacing = 12
        for view in [title, summary!, split!, footer] {
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
            view.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16).isActive = true
            view.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16).isActive = true
        }
        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            summary.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 8),
            split.topAnchor.constraint(equalTo: summary.bottomAnchor, constant: 12),
            split.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -12),
            footer.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12)
        ])
        content.layoutSubtreeIfNeeded()
        split.adjustSubviews()
        split.setPosition(212, ofDividerAt: 0)
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        144
    }

    func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        max(144, splitView.bounds.height - splitView.dividerThickness - 180)
    }

    func splitView(_ splitView: NSSplitView, canCollapseSubview subview: NSView) -> Bool {
        false
    }

    private func update(_ event: SetupEvent) {
        let category = event.id.split(separator: ".").first.map(String.init) ?? ""
        let dependencyStep = event.id == "gradle.plugins" || event.id.contains(".native-dependencies") || event.id.hasSuffix(".pod-install")
        let root = dependencyStep ? "pub" : category
        guard let column = columns[root], ["pending", "running", "succeeded", "failed", "attention"].contains(event.state), event.id.count < 128, event.title.count < 300 else { return }
        if event.id != root, event.state == "running", states[root] == "pending", let name = phases.first(where: { $0.0 == root })?.1 {
            update(SetupEvent(id: root, parent: nil, title: name, state: "running", message: nil))
        }
        let field: NSTextField
        if let existing = labels[event.id] {
            field = existing
        } else {
            field = NSTextField(wrappingLabelWithString: "")
            field.font = event.id == root ? .boldSystemFont(ofSize: 13) : .systemFont(ofSize: 11)
            field.preferredMaxLayoutWidth = 140
            let node = NSStackView()
            node.orientation = .vertical
            node.alignment = .leading
            node.spacing = 2
            node.distribution = .fill
            node.setHuggingPriority(.required, for: .vertical)
            node.addArrangedSubview(field)
            let version = NSTextField(wrappingLabelWithString: "")
            version.font = .systemFont(ofSize: 10)
            version.textColor = .secondaryLabelColor
            version.preferredMaxLayoutWidth = 140
            version.maximumNumberOfLines = 2
            version.isHidden = true
            node.addArrangedSubview(version)
            column.addArrangedSubview(node)
            labels[event.id] = field
            versionLabels[event.id] = version
        }
        states[event.id] = event.state
        let symbols = ["pending": "○", "running": "◉", "succeeded": "✓", "failed": "✕", "attention": "!"]
        let names = ["pending": "等待", "running": "进行中", "succeeded": "成功", "failed": "失败", "attention": "需用户处理"]
        let indent = String(repeating: "  ", count: min(3, event.id.filter { $0 == "." }.count))
        let name = event.id == root ? (phases.first(where: { $0.0 == root })?.1 ?? event.title) : event.title
        field.stringValue = "\(indent)\(symbols[event.state]!) \(name) · \(names[event.state]!)"
        field.toolTip = event.message
        if let version = event.version?.trimmingCharacters(in: .whitespacesAndNewlines), !version.isEmpty, let label = versionLabels[event.id] {
            label.stringValue = "\(indent)版本 \(version)"
            label.toolTip = [version, event.message].compactMap { $0 }.joined(separator: "\n")
            label.isHidden = false
        }
        switch event.state {
        case "running": field.textColor = .systemBlue
        case "succeeded": field.textColor = .systemGreen
        case "failed": field.textColor = .systemRed
        case "attention": field.textColor = .systemOrange
        default: field.textColor = .secondaryLabelColor
        }
        if event.state == "running" || event.state == "attention" {
            summary?.stringValue = event.message?.isEmpty == false ? event.message! : "\(event.title)：\(names[event.state]!)；在下方终端继续操作。"
        }
    }

    private func readEvents() {
        let url = session.appendingPathComponent("events.jsonl")
        guard let input = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? input.close() }
        do {
            try input.seek(toOffset: eventsOffset)
            let data = try input.read(upToCount: 262144) ?? Data()
            eventsOffset += UInt64(data.count)
            eventsBuffer.append(data)
            while let newline = eventsBuffer.firstIndex(of: 10) {
                let line = eventsBuffer.prefix(upTo: newline)
                eventsBuffer.removeSubrange(...newline)
                if line.count <= 65536, let event = try? JSONDecoder().decode(SetupEvent.self, from: line) { update(event) }
            }
            if eventsBuffer.count > 65536 { eventsBuffer.removeAll() }
        } catch { summary.stringValue = "事件读取失败；任务状态请以下方原始终端与日志为准。" }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, let body = message.body as? [String: Any], let kind = body["type"] as? String else { return }
        if kind == "ready", child == 0 {
            do { try startPTY(cols: body["cols"] as? Int ?? 100, rows: body["rows"] as? Int ?? 30) }
            catch { finish(code: 1, error: error.localizedDescription) }
        } else if kind == "resize" {
            resize(cols: body["cols"] as? Int ?? 100, rows: body["rows"] as? Int ?? 30)
        } else if (kind == "input" || kind == "binary"), let value = body["data"] as? String, master >= 0, !finished {
            let data = kind == "binary" ? Data(value.unicodeScalars.map { UInt8(truncatingIfNeeded: $0.value) }) : Data(value.utf8)
            data.withUnsafeBytes { bytes in if let pointer = bytes.baseAddress { _ = Darwin.write(master, pointer, bytes.count) } }
        }
    }

    private func startPTY(cols: Int, rows: Int) throws {
        var size = winsize(ws_row: UInt16(clamping: rows), ws_col: UInt16(clamping: cols), ws_xpixel: 0, ws_ypixel: 0)
        var environment = ProcessInfo.processInfo.environment
        environment["TERM"] = "xterm-256color"
        environment["COLORTERM"] = "truecolor"
        environment["JOBS_FLUTTER_SETUP_EVENTS"] = session.appendingPathComponent("events.jsonl").path
        let arguments = ["/bin/zsh", "-l", tools.appendingPathComponent("SetupFlutterProject.zsh").path, "--project", project]
        var argv = arguments.map { strdup($0) } + [nil]
        var envp = environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer { argv.forEach { free($0) }; envp.forEach { free($0) } }
        child = argv.withUnsafeMutableBufferPointer { args in
            envp.withUnsafeMutableBufferPointer { env in
                let pid = forkpty(&master, nil, nil, &size)
                if pid == 0 {
                    execve("/bin/zsh", args.baseAddress!, env.baseAddress!)
                    _exit(127)
                }
                return pid
            }
        }
        guard child > 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        let fd = master
        reader = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .main)
        reader?.setEventHandler { [weak self] in
            guard let self else { return }
            var buffer = [UInt8](repeating: 0, count: 65536)
            let count = Darwin.read(fd, &buffer, buffer.count)
            if count > 0 {
                self.acceptOutput(Data(buffer.prefix(count)))
            } else if count == 0 || (count < 0 && errno != EINTR && errno != EAGAIN) {
                self.reader?.cancel()
            }
        }
        reader?.resume()
        let pid = child
        DispatchQueue.global().async { [weak self] in
            var status: Int32 = 0
            while waitpid(pid, &status, 0) < 0 && errno == EINTR {}
            let code = (status & 0x7f) == 0 ? (status >> 8) & 0xff : 128 + (status & 0x7f)
            DispatchQueue.main.async { self?.finish(code: Int(code), error: nil) }
        }
    }

    private func acceptOutput(_ data: Data) {
        do { try rawLog.write(contentsOf: data) }
        catch { summary.stringValue = "原始日志写入失败：\(error.localizedDescription)" }
        web.evaluateJavaScript("window.feedPTY('\(data.base64EncodedString())')", completionHandler: nil)
    }

    private func drainRemainingOutput() {
        guard master >= 0 else { return }
        let original = fcntl(master, F_GETFL)
        _ = fcntl(master, F_SETFL, original | O_NONBLOCK)
        var buffer = [UInt8](repeating: 0, count: 65536)
        while true {
            let count = Darwin.read(master, &buffer, buffer.count)
            if count <= 0 { break }
            acceptOutput(Data(buffer.prefix(count)))
        }
    }

    private func resize(cols: Int, rows: Int) {
        guard master >= 0 else { return }
        var size = winsize(ws_row: UInt16(clamping: max(2, min(500, rows))), ws_col: UInt16(clamping: max(10, min(1000, cols))), ws_xpixel: 0, ws_ypixel: 0)
        _ = ioctl(master, TIOCSWINSZ, &size)
        if child > 0 { _ = kill(-child, SIGWINCH) }
    }

    private func finish(code: Int, error: String?) {
        guard !finished else { return }
        finished = true
        drainRemainingOutput()
        readEvents()
        eventsTimer?.invalidate()
        cancel.isEnabled = false
        summary.stringValue = error ?? (code == 0 ? "流程已完成；具体构建、安装和启动结果请核对对应子节点。" : "流程结束（退出码\(code)）；已完成阶段保留，请查看需处理节点与下方日志。")
        for (id, state) in states where state == "running" {
            if let label = labels[id] {
                label.stringValue = label.stringValue.replacingOccurrences(of: "◉", with: "!").replacingOccurrences(of: "进行中", with: code == 0 ? "需确认状态" : "流程中断")
                label.textColor = .systemOrange
                states[id] = "attention"
            }
        }
        try? rawLog.synchronize()
        if requestedClose { window.close() }
    }

    @objc private func openLogs() { NSWorkspace.shared.open(session) }
    @objc private func cancelTask() {
        guard master >= 0 && !finished else { return }
        var interrupt: UInt8 = 3
        _ = Darwin.write(master, &interrupt, 1)
        summary.stringValue = "已向当前终端任务发送 Ctrl+C；等待后端退出，已完成安装不会自动撤销。"
        let pid = child
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self, !self.finished, pid > 0, self.child == pid else { return }
            _ = kill(-pid, SIGTERM)
            self.summary.stringValue = "任务未及时响应，正在停止本次终端进程组；保留原始日志。"
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            guard let self, !self.finished, pid > 0, self.child == pid else { return }
            _ = kill(-pid, SIGKILL)
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if finished { return true }
        let alert = NSAlert()
        alert.messageText = "取消正在进行的项目配置？"
        alert.informativeText = "将向当前任务发送中断；已完成的安装和配置保留，原始日志也会保留。"
        alert.addButton(withTitle: "继续任务")
        alert.addButton(withTitle: "取消并关闭")
        if alert.runModal() == .alertSecondButtonReturn { requestedClose = true; cancelTask() }
        return false
    }

    func windowWillClose(_ notification: Notification) { NSApp.terminate(nil) }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if finished { return .terminateNow }
        window.performClose(nil)
        return .terminateCancel
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(code: 1, error: "内嵌终端加载失败：\(error.localizedDescription)")
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(code: 1, error: "本地终端资源无法加载：\(error.localizedDescription)")
    }
    func applicationWillTerminate(_ notification: Notification) {
        reader?.cancel()
        if master >= 0 { Darwin.close(master) }
        try? rawLog.close()
        let carrier = tools.deletingLastPathComponent()
        if carrier.lastPathComponent.hasPrefix("JobsFlutterTools-") { try? FileManager.default.removeItem(at: carrier) }
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        decisionHandler(navigationAction.request.url?.isFileURL == true ? .allow : .cancel)
    }
}

if CommandLine.arguments.count == 5, CommandLine.arguments[1] == "--project", CommandLine.arguments[3] == "--tools" {
    do {
        let delegate = try SetupProjectWindow(project: CommandLine.arguments[2], tools: URL(fileURLWithPath: CommandLine.arguments[4], isDirectory: true))
        let application = NSApplication.shared
        application.setActivationPolicy(.regular)
        application.delegate = delegate
        application.run()
    } catch { fputs("Flutter配置窗口启动失败：\(error)\n", stderr); exit(1) }
} else {
    fputs("用法：SetupProjectWindow --project <绝对路径> --tools <工具目录>\n", stderr)
    exit(2)
}
