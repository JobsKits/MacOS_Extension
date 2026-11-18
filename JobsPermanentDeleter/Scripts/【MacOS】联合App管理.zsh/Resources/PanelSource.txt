//
//  SelectFinderExtensionFeatures.swift
//  MacOS@Extension
//
//  Created by Jobs on 2026年10月19日，星期一.
//

import AppKit

// MARK: - Entry point
// 标准输出只返回操作和功能 ID；错误写入标准错误，取消不产生业务计划。
do {
    let selectionController = try FeatureSelectionController.parseArguments(Array(CommandLine.arguments.dropFirst()))
    print(selectionController.runModal())
    exit(0)
} catch {
    FileHandle.standardError.write(Data("错误：\(error.localizedDescription)\n".utf8))
    exit(2)
}
// MARK: - Feature catalog

/// 共用功能清单；安装和卸载使用相同的叶子标识。
struct FeatureOption {
    let identifier: String
    let title: String

    static let independent: [FeatureOption] = [
        FeatureOption(identifier: "android_studio_opener", title: "用 Android Studio 打开项目"),
        FeatureOption(identifier: "vscode_opener", title: "用 VSCode 打开项目"),
        FeatureOption(identifier: "xcode_opener", title: "用 Xcode 打开项目"),
        FeatureOption(identifier: "git-pull", title: "拉取 Git 到最新"),
        FeatureOption(identifier: "git-rollback", title: "Git 提交回退"),
        FeatureOption(identifier: "git_remote", title: "打开 Git 远程地址"),
        FeatureOption(identifier: "git_remote_copier", title: "复制 Git 远程地址"),
        FeatureOption(identifier: "path_copier", title: "复制绝对路径"),
        FeatureOption(identifier: "command-shortcut-create", title: "创建脚本快捷入口"),
        FeatureOption(identifier: "file-create", title: "新建文件"),
        FeatureOption(identifier: "file-hash", title: "查看文件指纹 Hash（SHA-256）"),
        FeatureOption(identifier: "file-visibility", title: "隐藏 / 显示所选项目"),
        FeatureOption(identifier: "permanent-delete", title: "永久删除所选项目"),
        FeatureOption(identifier: "send-to", title: "发送到外部磁盘或网络卷"),
        FeatureOption(identifier: "disk-space-info", title: "磁盘空间总览"),
        FeatureOption(identifier: "environment-update", title: "更新开发环境（update）"),
        FeatureOption(identifier: "run-authorize", title: "授予执行权限（chmod +x）"),
        FeatureOption(identifier: "run-revoke", title: "移除执行权限（chmod -x）"),
        FeatureOption(identifier: "ipa-resign", title: "IPA 免编译重签"),
        FeatureOption(identifier: "hidden-files-toggle", title: "显示 / 隐藏文件"),
        FeatureOption(identifier: "ios-simulator-create", title: "新建 iOS 模拟器"),
        FeatureOption(identifier: "android-simulator-create", title: "新建 Android 模拟器"),
        FeatureOption(identifier: "harmony-simulator-create", title: "新建 Harmony 模拟器"),        FeatureOption(identifier: "android-simulator-repair", title: "Android 模拟器检测与修复"),
        FeatureOption(identifier: "harmony-simulator-repair", title: "Harmony 模拟器检测与修复"),
        FeatureOption(identifier: "git-proxy-configure", title: "配置 Git 动态代理")
    ]

    static let terminal: [FeatureOption] = [
        FeatureOption(identifier: "terminal_open", title: "用终端打开"),
        FeatureOption(identifier: "file_content", title: "用终端查看文件内容"),
        FeatureOption(identifier: "file_merge", title: "合并分卷"),
        FeatureOption(identifier: "file_split", title: "拆分文件"),
        FeatureOption(identifier: "pod_install", title: "Pod Install"),
        FeatureOption(identifier: "clean_build_artifacts", title: "清理 Android / OpenHarmony 构建产物"),
        FeatureOption(identifier: "codegraph_bootstrap", title: "更新代码地图（.codegraph）"),
        FeatureOption(identifier: "git_empty_commit_push", title: "在终端创建空白 Commit 并 Push")
    ]

    static let ios: [FeatureOption] = [
        FeatureOption(identifier: "ios-disable-sandbox", title: "禁用 CocoaPods 构建沙盒"),
        FeatureOption(identifier: "ios-install-cocoapods", title: "安装 CocoaPods"),
        FeatureOption(identifier: "ios-pods-source-github", title: "CocoaPods 源：CDN → GitHub"),
        FeatureOption(identifier: "ios-extract-pods", title: "提取项目所有 Pod 相关文件"),
        FeatureOption(identifier: "ios-pod-update", title: "Pod Update"),
        FeatureOption(identifier: "ios-xcode-dependencies", title: "查询 Xcode 工程依赖关系"),
        FeatureOption(identifier: "ios-pod-repo-update", title: "更新 CocoaPods 本地仓库"),
        FeatureOption(identifier: "ios-pod-build-check", title: "检查本地 Pod 能否编译（仅 .podspec 目录）"),
        FeatureOption(identifier: "ios-code-snippets", title: "安装 / 升级 JobsCodeSnippets"),
        FeatureOption(identifier: "ios-clean-build-artifacts", title: "清理 iOS/Xcode 构建产物")
    ]

    // 每个可执行子菜单独立选择，分组标题不参与安装计数。
    static let flutter: [FeatureOption] = [
        FeatureOption(identifier: "flutter-project-setup", title: "一键配置 Flutter 项目"),
        FeatureOption(identifier: "flutter-run", title: "从终端运行 Flutter 项目"),
        FeatureOption(identifier: "flutter-pub-get", title: "拉取 Flutter Pub 依赖"),
        FeatureOption(identifier: "flutter-android-dependencies", title: "拉取 Android 原生依赖"),
        FeatureOption(identifier: "flutter-pods-dependencies", title: "拉取 CocoaPods 依赖"),
        FeatureOption(identifier: "flutter-spm-dependencies", title: "拉取 Swift Package 依赖"),
        FeatureOption(identifier: "flutter-ohos-dependencies", title: "拉取 OpenHarmony 依赖"),
        FeatureOption(identifier: "flutter-native-dependencies", title: "准备原生库与构建依赖（组合操作）"),
        FeatureOption(identifier: "flutter-flutter-precache", title: "下载Flutter平台资源"),
        FeatureOption(identifier: "flutter-web-dependencies", title: "拉取 Web 工程依赖"),
        FeatureOption(identifier: "flutter-export-all-dependencies", title: "🧳 一键提取 Flutter 依赖"),
        FeatureOption(identifier: "flutter-extract", title: "提取 Flutter Pub 依赖"),
        FeatureOption(identifier: "flutter-export-private-dependencies", title: "🔐 提取Flutter项目工程私库依赖"),
        FeatureOption(identifier: "flutter-import-all-dependencies", title: "📥 一键导入 Flutter 依赖"),
        FeatureOption(identifier: "flutter-import-dependencies", title: "导入 Flutter Pub 依赖"),
        FeatureOption(identifier: "flutter-import-private-dependencies", title: "📥 导入Flutter项目工程私库依赖"),
        FeatureOption(identifier: "flutter-export-gradle-dependencies", title: "提取 Gradle 分发与依赖缓存"),
        FeatureOption(identifier: "flutter-import-gradle-dependencies", title: "导入 Gradle 分发与依赖缓存"),
        FeatureOption(identifier: "flutter-export-pods-dependencies", title: "提取 CocoaPods 依赖"),
        FeatureOption(identifier: "flutter-import-pods-dependencies", title: "导入 CocoaPods 依赖"),
        FeatureOption(identifier: "flutter-export-spm-dependencies", title: "提取 Swift Package 依赖"),
        FeatureOption(identifier: "flutter-import-spm-dependencies", title: "导入 Swift Package 依赖"),
        FeatureOption(identifier: "flutter-export-ohos-dependencies", title: "提取 OpenHarmony 依赖"),
        FeatureOption(identifier: "flutter-import-ohos-dependencies", title: "导入 OpenHarmony 依赖"),
        FeatureOption(identifier: "flutter-export-native-dependencies", title: "提取 原生构建缓存"),
        FeatureOption(identifier: "flutter-import-native-dependencies", title: "导入 原生构建缓存"),
        FeatureOption(identifier: "flutter-export-precache-dependencies", title: "提取 Flutter 平台资源"),
        FeatureOption(identifier: "flutter-import-precache-dependencies", title: "导入 Flutter 平台资源"),
        FeatureOption(identifier: "flutter-export-web-dependencies", title: "提取 Web 依赖"),
        FeatureOption(identifier: "flutter-import-web-dependencies", title: "导入 Web 依赖"),
        FeatureOption(identifier: "flutter-sdk-version", title: "查看当前Flutter项目工程的SDK版本"),
        FeatureOption(identifier: "flutter-sdk-manage", title: "安装/切换Flutter SDK"),
        FeatureOption(identifier: "flutter-ohos-sdk-manage", title: "安装/切换Flutter@OpenHarmony SDK"),
        FeatureOption(identifier: "flutter-java-manage", title: "安装/切换Java SDK"),
        FeatureOption(identifier: "flutter-gradle-download", title: "下载Gradled分发与构建插件"),
        FeatureOption(identifier: "flutter-codegen", title: "Flutter 自动化生产代码"),
        FeatureOption(identifier: "flutter-package-ios", title: "打包 iOS"),
        FeatureOption(identifier: "flutter-package-android", title: "打包 Android"),
        FeatureOption(identifier: "flutter-package-ohos", title: "打包鸿蒙（HAP + APP）"),
        FeatureOption(identifier: "flutter-native-doctor", title: "原生 Flutter 项目体检"),
        FeatureOption(identifier: "flutter-harmony-doctor", title: "OpenHarmony Flutter 环境体检"),
        FeatureOption(identifier: "flutter-repair-android", title: "修复 Android SDK / platforms 缺失"),
        FeatureOption(identifier: "flutter-repair-imports", title: "修复 Flutter 项目中文路径"),
        FeatureOption(identifier: "flutter-repair-namespace", title: "修复 Flutter 插件 namespace"),
        FeatureOption(identifier: "flutter-repair-package-imports", title: "修复 Dart 相对 import 为 package 引用"),
        FeatureOption(identifier: "flutter-clean-build-artifacts", title: "清理当前 Flutter 项目构建产物"),
        FeatureOption(identifier: "flutter-maintenance", title: "依赖与缓存维护")
    ]

    static let all: [FeatureOption] = independent + terminal + ios + flutter
}

/// 按用途组织选项；安装工程及输出标识的顺序仍由 FeatureOption.all 决定。
struct FeatureGroup {
    let identifier: String
    let title: String
    let identifiers: [String]

    var options: [FeatureOption] {
        identifiers.compactMap { identifier in
            FeatureOption.all.first { $0.identifier == identifier }
        }
    }

    static let all: [FeatureGroup] = [
        FeatureGroup(identifier: "ide", title: "IDE 项目打开", identifiers: [
            "android_studio_opener", "vscode_opener", "xcode_opener"
        ]),
        FeatureGroup(identifier: "git", title: "Git 工具", identifiers: [
            "git-pull", "git-rollback", "git_remote", "git_remote_copier", "git-proxy-configure", "git_empty_commit_push"
        ]),
        FeatureGroup(identifier: "general", title: "文件与通用工具", identifiers: [
            "path_copier", "command-shortcut-create", "file-create", "file-hash", "file-visibility", "permanent-delete", "send-to", "disk-space-info", "environment-update", "run-authorize", "run-revoke", "hidden-files-toggle", "terminal_open", "file_content", "file_merge", "file_split",
            "clean_build_artifacts", "codegraph_bootstrap"
        ]),
        FeatureGroup(identifier: "flutter", title: "Flutter 工具 · 子菜单功能", identifiers: FeatureOption.flutter.map { $0.identifier }),
        FeatureGroup(identifier: "ios", title: "iOS / CocoaPods 工具", identifiers:
            ["pod_install", "ios-pod-update", "ipa-resign"] + FeatureOption.ios
                .map { $0.identifier }
                .filter { $0 != "ios-pod-update" }
        ),
        FeatureGroup(identifier: "simulators", title: "模拟器工具", identifiers: [
            "ios-simulator-create", "android-simulator-create", "harmony-simulator-create", "android-simulator-repair", "harmony-simulator-repair"
        ])
    ]
}

/// 按字节分帧，避免 Pipe 在中文 UTF-8 字节中间切块导致乱码；兼容回车进度行。
final class ManagerOutputDecoder {
    private var pending = Data()

    var preview: String {
        for trailingBytes in 0...min(3, pending.count) {
            if let text = String(data: pending.dropLast(trailingBytes), encoding: .utf8) {
                return text
            }
        }
        return String(decoding: pending, as: UTF8.self)
    }

    func append(_ data: Data) -> [String] {
        pending.append(data)
        var lines: [String] = []
        while let end = pending.firstIndex(where: { $0 == 10 || $0 == 13 }) {
            let line = String(decoding: pending[..<end], as: UTF8.self)
            pending.removeSubrange(...end)
            if !line.isEmpty {
                lines.append(line)
            }
        }
        return lines
    }

    func finish() -> [String] {
        guard !pending.isEmpty else {
            return []
        }
        let line = String(decoding: pending, as: UTF8.self)
        pending.removeAll()
        return [line]
    }

    func drainOverflow() -> String {
        guard pending.count > 65_536 else {
            return ""
        }
        var length = pending.count - 4
        while length > 0, String(data: pending.prefix(length), encoding: .utf8) == nil, length > pending.count - 8 {
            length -= 1
        }
        let text = String(decoding: pending.prefix(length), as: UTF8.self)
        pending.removeFirst(length)
        return text
    }
}

/// 完整日志只作为 cat 的数据参数传入 Terminal，不解释日志正文。
enum ManagerLogTerminal {
    static func validate(_ url: URL) throws {
        let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
        guard url.isFileURL, values?.isRegularFile == true,
              FileManager.default.isReadableFile(atPath: url.path) else {
            throw NSError(domain: "JobsFinderManagerLog", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "日志不存在或不可读：\(url.path)"])
        }
    }

    static func arguments(for url: URL) throws -> [String] {
        try validate(url)
        let script = """
        on run argv
            tell application "Terminal"
                activate
                do script (item 1 of argv)
            end tell
        end run
        """
        return ["-e", script, "/bin/cat -- \(shellWord(url.path))"]
    }

    // 与 Flutter 启动器采用同一 ANSI-C 引用，控制符也不进入 Terminal 输入流。
    static func shellWord(_ value: String) -> String {
        var escaped = ""
        for scalar in value.unicodeScalars {
            switch scalar.value {
            case 0x5C:
                escaped += "\\\\"
            case 0x27:
                escaped += "\\'"
            case 0x00...0x1F, 0x7F:
                escaped += String(format: "\\x%02x", scalar.value)
            case 0x85, 0x2028, 0x2029:
                escaped += String(format: "\\u%04x", scalar.value)
            default:
                escaped += String(scalar)
            }
        }
        return "$'\(escaped)'"
    }

    static func open(_ url: URL) throws {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = try arguments(for: url)
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "JobsFinderManagerLog", code: Int(process.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: "无法打开日志终端：\(String(decoding: data, as: UTF8.self))"])
        }
    }
}

/// 加宽系统分隔条的拖动区域，保留原生鼠标拖动与无障碍行为。
private final class ManagerLogSplitView: NSSplitView {

    override var dividerThickness: CGFloat {
        return 12
    }

    override var isFlipped: Bool {
        return true
    }

    override func drawDivider(in rect: NSRect) {
        NSColor.separatorColor.setFill()
        rect.fill()
        NSColor.secondaryLabelColor.setFill()
        NSBezierPath(
            roundedRect: NSRect(x: rect.midX - 22, y: rect.midY - 1, width: 44, height: 2),
            xRadius: 1,
            yRadius: 1
        ).fill()
    }
}

/// 复选框保留原生事件；普通行区域只在一次未拖动的按下/抬起后转交勾选。
private final class ManagerFeatureColumn: NSView {

    struct Row {
        let button: NSButton
        let status: NSTextField
        let height: CGFloat
    }

    var rows: [Row] = []
    var rowSpacing: CGFloat = 0
    private weak var pressedButton: NSButton?
    private var pressOrigin = NSPoint.zero

    private func row(at point: NSPoint) -> Row? {
        return rows.first { row in
            let height = max(row.height, row.button.frame.height) + rowSpacing
            let rect = NSRect(x: bounds.minX,
                              y: row.button.frame.midY - height / 2,
                              width: bounds.width,
                              height: height)
            return rect.contains(point)
        }
    }

    private func isLogAction(_ row: Row, at point: NSPoint) -> Bool {
        return !row.status.isHiddenOrHasHiddenAncestor && row.status.frame.contains(point) &&
            row.status.gestureRecognizers.contains { gesture in
                return gesture.isEnabled
            }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else {
            return nil
        }
        guard let row = row(at: convert(point, from: superview)) else {
            return hit
        }
        let local = convert(point, from: superview)
        if hit === row.button || hit.isDescendant(of: row.button) || isLogAction(row, at: local) {
            return hit
        }
        return self
    }

    override func mouseDown(with event: NSEvent) {
        pressedButton = nil
        let point = convert(event.locationInWindow, from: nil)
        guard event.type == .leftMouseDown, bounds.contains(point), let row = row(at: point),
              row.button.isEnabled, !row.button.isHiddenOrHasHiddenAncestor,
              !isLogAction(row, at: point) else {
            return
        }
        pressedButton = row.button
        pressOrigin = event.locationInWindow
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if !bounds.contains(point) || row(at: point)?.button !== pressedButton ||
            hypot(event.locationInWindow.x - pressOrigin.x, event.locationInWindow.y - pressOrigin.y) >= 4 {
            pressedButton = nil
        }
    }

    func cancelPendingSelection() {
        pressedButton = nil
    }

    override func scrollWheel(with event: NSEvent) {
        pressedButton = nil
        super.scrollWheel(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            pressedButton = nil
        }
        let point = convert(event.locationInWindow, from: nil)
        guard event.type == .leftMouseUp, bounds.contains(point), let button = pressedButton,
              let row = row(at: point), row.button === button,
              button.isEnabled, !button.isHiddenOrHasHiddenAncestor,
              !isLogAction(row, at: point), event.window === window,
              hypot(event.locationInWindow.x - pressOrigin.x, event.locationInWindow.y - pressOrigin.y) < 4 else {
            return
        }
        window?.makeFirstResponder(button)
        button.performClick(nil)
    }
}

/// 卡片只从标题区启动原生拖动，复选框与状态链接仍使用各自的鼠标事件。
private final class ManagerFeatureBox: NSBox,
                                       NSDraggingSource {

    static let pasteboardType = NSPasteboard.PasteboardType("com.jobs.finderextensions.feature-group")
    var groupIdentifier = ""
    var groupToolbar: NSView?
    var groupToolbarFrame = NSRect.zero
    var canMove: () -> Bool = {
        return true
    }
    private var mouseDownEvent: NSEvent?

    private var dragTitleFrame: NSRect {
        return NSRect(x: 0, y: bounds.height - 24, width: bounds.width, height: 24)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let grip = "⋮⋮" as NSString
        grip.draw(at: NSPoint(x: bounds.width - 24, y: titleRect.minY),
                  withAttributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.secondaryLabelColor])
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(dragTitleFrame, cursor: canMove() ? .openHand : .arrow)
    }

    override func mouseDown(with event: NSEvent) {
        guard canMove(), dragTitleFrame.contains(convert(event.locationInWindow, from: nil)) else {
            super.mouseDown(with: event)
            return
        }
        mouseDownEvent = event
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownEvent, canMove(),
              hypot(event.locationInWindow.x - start.locationInWindow.x, event.locationInWindow.y - start.locationInWindow.y) >= 4 else {
            return
        }
        mouseDownEvent = nil
        beginGroupDragging(with: event, from: self)
    }

    func beginGroupDragging(with event: NSEvent, from view: NSView) {
        guard canMove() else {
            return
        }
        let item = NSPasteboardItem()
        item.setString(groupIdentifier, forType: Self.pasteboardType)
        let draggingItem = NSDraggingItem(pasteboardWriter: item)
        let previewFrame = NSRect(x: 0, y: view.bounds.height - 42, width: min(view.bounds.width, 380), height: 42)
        let image = NSImage(size: previewFrame.size)
        image.lockFocus()
        NSColor.controlBackgroundColor.setFill()
        NSRect(origin: .zero, size: previewFrame.size).fill()
        (title as NSString).draw(at: NSPoint(x: 12, y: 13),
                                withAttributes: [.font: titleFont, .foregroundColor: NSColor.labelColor])
        image.unlockFocus()
        draggingItem.setDraggingFrame(previewFrame, contents: image)
        view.beginDraggingSession(with: [draggingItem], event: event, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        mouseDownEvent = nil
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        return context == .withinApplication ? .move : []
    }
}

/// 滚过原始标题后保留当前分组上下文，拖动仍由原卡片承担。
private final class ManagerFeaturePinnedHeader: NSView {

    weak var sourceBox: ManagerFeatureBox? {
        didSet {
            if let previous = oldValue, previous !== sourceBox, let toolbar = previous.groupToolbar {
                previous.contentView?.addSubview(toolbar)
                toolbar.frame = previous.groupToolbarFrame
            }
            if let toolbar = sourceBox?.groupToolbar, toolbar.superview !== self {
                addSubview(toolbar)
            }
        }
    }
    let titleField = NSTextField(labelWithString: "")
    private var mouseDownEvent: NSEvent?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        titleField.textColor = .labelColor
        titleField.setAccessibilityElement(false)
        addSubview(titleField)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override var isOpaque: Bool {
        return true
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
        ("⋮⋮" as NSString).draw(at: NSPoint(x: bounds.width - 24, y: titleField.frame.minY),
                               withAttributes: [.font: titleField.font!, .foregroundColor: NSColor.secondaryLabelColor])
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else {
            return nil
        }
        return hit is NSButton ? hit : self
    }

    override func resetCursorRects() {
        let titleArea = NSRect(x: 0, y: bounds.height - 28, width: bounds.width, height: 28)
        addCursorRect(titleArea, cursor: sourceBox?.canMove() == true ? .openHand : .arrow)
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownEvent = sourceBox?.canMove() == true ? event : nil
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownEvent,
              hypot(event.locationInWindow.x - start.locationInWindow.x, event.locationInWindow.y - start.locationInWindow.y) >= 4 else {
            return
        }
        mouseDownEvent = nil
        sourceBox?.beginGroupDragging(with: event, from: self)
    }

    override func mouseUp(with event: NSEvent) {
        mouseDownEvent = nil
    }
}

/// 列表负责原生拖放和插入线；重排时复用已有卡片，不打断选择或后台状态。
private final class ManagerFeatureList: NSView {

    var proposeDrop: ((String, NSPoint) -> NSRect?)?
    var acceptDrop: ((String, NSPoint) -> Bool)?
    private(set) var pinnedHeaders: [ManagerFeaturePinnedHeader] = []
    private var clipObservation: NSObjectProtocol?
    private var insertionFrame: NSRect? {
        didSet {
            needsDisplay = true
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([ManagerFeatureBox.pasteboardType])
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes([ManagerFeatureBox.pasteboardType])
    }

    deinit {
        if let clipObservation {
            NotificationCenter.default.removeObserver(clipObservation)
        }
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        if let clipObservation {
            NotificationCenter.default.removeObserver(clipObservation)
        }
        clipObservation = nil
        guard let clip = superview as? NSClipView else {
            return
        }
        clip.postsBoundsChangedNotifications = true
        clipObservation = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification,
                                                               object: clip,
                                                               queue: nil) { [weak self] _ in
            self?.updatePinnedHeaders()
        }
        updatePinnedHeaders()
    }

    func updatePinnedHeaders() {
        let boxes = subviews.compactMap { view in
            return view as? ManagerFeatureBox
        }
        let columns = Dictionary(grouping: boxes) { box in
            return box.frame.minX
        }.sorted { lhs, rhs in
            return lhs.key < rhs.key
        }
        while pinnedHeaders.count < columns.count {
            let header = ManagerFeaturePinnedHeader(frame: .zero)
            addSubview(header)
            pinnedHeaders.append(header)
        }
        for header in pinnedHeaders {
            header.isHidden = true
            header.sourceBox = nil
        }
        let top = visibleRect.maxY
        for (index, column) in columns.enumerated() {
            guard let box = column.value.first(where: { box in
                return box.frame.minY < top && box.convert(box.titleRect, to: self).maxY > top
            }) else {
                continue
            }
            let header = pinnedHeaders[index]
            header.sourceBox = box
            header.titleField.stringValue = box.title
            header.titleField.font = box.titleFont
            header.titleField.sizeToFit()
            let titleHeight = max(28, header.titleField.frame.height + 8)
            let toolbarHeight = box.groupToolbar?.frame.height ?? 0
            let height = titleHeight + toolbarHeight + 4
            // 下一组自然推走当前标题，避免吸顶条压住后一个分组。
            let y = max(top - height, box.frame.minY)
            header.frame = NSRect(x: box.frame.minX, y: y, width: box.frame.width, height: height)
            header.titleField.setFrameOrigin(NSPoint(x: 7, y: toolbarHeight + 4 + (titleHeight - header.titleField.frame.height) / 2))
            box.groupToolbar?.setFrameOrigin(NSPoint(x: 5, y: 4))
            header.isHidden = false
            header.needsDisplay = true
        }
    }

    private func draggedIdentifier(_ sender: NSDraggingInfo) -> String? {
        guard let source = sender.draggingSource as? ManagerFeatureBox, source.superview === self, source.canMove() else {
            return nil
        }
        let identifier = sender.draggingPasteboard.string(forType: ManagerFeatureBox.pasteboardType)
        return identifier == source.groupIdentifier ? identifier : nil
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        return draggingUpdated(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard let identifier = draggedIdentifier(sender) else {
            insertionFrame = nil
            return []
        }
        if let event = NSApplication.shared.currentEvent {
            autoscroll(with: event)
        }
        insertionFrame = proposeDrop?(identifier, convert(sender.draggingLocation, from: nil))
        return insertionFrame == nil ? [] : .move
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        insertionFrame = nil
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let identifier = draggedIdentifier(sender) else {
            return false
        }
        return proposeDrop?(identifier, convert(sender.draggingLocation, from: nil)) != nil
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        insertionFrame = nil
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        defer {
            insertionFrame = nil
        }
        guard let identifier = draggedIdentifier(sender) else {
            return false
        }
        return acceptDrop?(identifier, convert(sender.draggingLocation, from: nil)) ?? false
    }

    override func concludeDragOperation(_ sender: NSDraggingInfo?) {
        insertionFrame = nil
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if let insertionFrame {
            NSColor.controlAccentColor.setFill()
            NSBezierPath(roundedRect: insertionFrame, xRadius: 2, yRadius: 2).fill()
        }
    }
}

/// 日志颜色按语义保存，换主题只换调色板，不改日志原文。
private enum ManagerLogKind: String {
    case normal, info, success, warning, error, heading

    static let attribute = NSAttributedString.Key("JobsManagerLogKind")

    static func classify(_ line: String) -> Self {
        let value = line.trimmingCharacters(in: .whitespacesAndNewlines)
        func matches(_ pattern: String) -> Bool {
            return value.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
        }
        if matches(#"(?:退出码|exit(?: code)?)\s*[:：]?\s*-?[1-9]\d*|失败\s*[:：]?\s*[1-9]\d*|\b[1-9]\d*\s+(?:errors?|failed)\b"#) ||
            matches(#"^(?:❌|✖|⛔|🚫|error\b|fatal\b|exception\b|traceback\b|任务失败|无法|错误|失败|应用修改被权限阻止)|\*\*\s*BUILD FAILED|^.+:\d+(?::\d+)?:\s*(?:fatal\s+)?error:"#) {
            return .error
        }
        if matches(#"^(?:⚠|警告|warning\b|warn\b|注意|已请求停止|已收到停止|跳过|未安装|无需卸载)|^.+:\d+(?::\d+)?:\s*warning:"#) {
            return .warning
        }
        if matches(#"^(?:✅|✔|成功|已完成|安装成功|卸载成功|已清理|PASS\b|SUCCESS\b)|\*\*\s*BUILD SUCCEEDED"#) {
            return .success
        }
        if matches(#"^(?:━|═|={3,}|💎|🔷|【|\[阶段|阶段[：:])"#) {
            return .heading
        }
        if matches(#"^(?:ℹ|➤|📦|📂|🔧|INFO\b|提示|正在|开始|安装|卸载|清除构建产物|联合 App|当前脚本)"#) {
            return .info
        }
        return .normal
    }
}

private struct ManagerLogPalette {
    let dark: Bool

    private func color(_ light: UInt32, _ night: UInt32) -> NSColor {
        let value = dark ? night : light
        return NSColor(srgbRed: CGFloat((value >> 16) & 255) / 255,
                       green: CGFloat((value >> 8) & 255) / 255,
                       blue: CGFloat(value & 255) / 255, alpha: 1)
    }

    var background: NSColor {
        return color(0xF5F7FA, 0x141922)
    }

    func foreground(_ kind: ManagerLogKind) -> NSColor {
        switch kind {
        case .normal:
            return color(0x182230, 0xE5EAF1)
        case .info:
            return color(0x1756A9, 0x8AC6FF)
        case .success:
            return color(0x146C37, 0x76D69C)
        case .warning:
            return color(0x8B5100, 0xFFD18A)
        case .error:
            return color(0xB42318, 0xFF9B91)
        case .heading:
            return color(0x6B3DA5, 0xD2B2FF)
        }
    }
}

private enum ManagerLogStyling {
    static func plainText(_ message: String) -> String {
        return message
            .replacingOccurrences(of: "\u{1B}\\][^\u{7}\u{1B}]*(?:\u{7}|\u{1B}\\\\)|\u{1B}\\[[0-?]*[ -/]*[@-~]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\u{1B}(?:\\[[0-?]*[ -/]*)?$", with: "", options: .regularExpression)
    }

    static func attributed(_ message: String, palette: ManagerLogPalette, kind: ManagerLogKind? = nil) -> NSAttributedString {
        let result = NSMutableAttributedString(string: message)
        message.enumerateSubstrings(in: message.startIndex..<message.endIndex, options: .byLines) { line, _, enclosing, _ in
            let level = kind ?? ManagerLogKind.classify(line ?? "")
            result.addAttributes([
                ManagerLogKind.attribute: level.rawValue,
                .foregroundColor: palette.foreground(level),
                .font: NSFont.monospacedSystemFont(ofSize: 11, weight: level == .heading ? .semibold : .regular)
            ], range: NSRange(enclosing, in: message))
        }
        return result
    }

    static func recolor(_ storage: NSTextStorage, palette: ManagerLogPalette) {
        var runs: [(NSRange, ManagerLogKind)] = []
        storage.enumerateAttribute(ManagerLogKind.attribute, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            runs.append((range, (value as? String).flatMap(ManagerLogKind.init(rawValue:)) ?? .normal))
        }
        for (range, kind) in runs {
            storage.addAttribute(.foregroundColor, value: palette.foreground(kind), range: range)
        }
    }
}

/// 保留AppKit的精确delta、动量和横向滚动；只在用户滚动时暂停追尾。
private final class ManagerLogScrollView: NSScrollView {
    var manualScroll: (() -> Void)?
    var appearanceChanged: (() -> Void)?

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        appearanceChanged?()
    }

    override func scrollWheel(with event: NSEvent) {
        if event.scrollingDeltaX != 0 || event.scrollingDeltaY != 0 || event.phase == .began {
            manualScroll?()
        }
        super.scrollWheel(with: event)
    }
}

/// 右键动作明确绑定日志自身，避免焦点仍在复选框时误选其它内容。
private final class ManagerLogTextView: NSTextView {

    var preferences: ManagerPanelPreferences = .shared
    var manualScroll: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if [115, 116, 119, 121, 123, 124, 125, 126].contains(event.keyCode) {
            manualScroll?()
        }
        super.keyDown(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        window?.makeFirstResponder(self)
        let menu = super.menu(for: event) ?? NSMenu()
        if !menu.items.contains(where: { $0.action == #selector(selectAll(_:)) }) {
            if !menu.items.isEmpty {
                menu.addItem(.separator())
            }
            let item = NSMenuItem(title: preferences.text("全选"), action: #selector(selectAll(_:)), keyEquivalent: "a")
            item.target = self
            menu.addItem(item)
        }
        for item in menu.items {
            if item.action == #selector(copy(_:)) {
                item.title = preferences.text("复制")
            } else if item.action == #selector(selectAll(_:)) {
                item.title = preferences.text("全选")
            }
        }
        return menu
    }
}

/// 面板持有后台任务；兼容未传管理器路径时只返回选择计划的调用方。
final class FeatureSelectionController: NSObject,
                                        NSWindowDelegate,
                                        NSSplitViewDelegate,
                                        NSApplicationDelegate {

    private enum CloseChoice {
        case background, quit, cancel
    }
    private enum Outcome {
        case selected(String, [String])
        case cancelled
    }

    private let preferences: ManagerPanelPreferences
    private var themeControl: NSPopUpButton?
    private var languageControl: NSPopUpButton?
    private var preferencesToolbar: NSView?
    private var headerView: NSView?
    private var headerTitleLabel: NSTextField?
    private var headerTitleFrame = NSRect.zero
    private var headerBaseHeight: CGFloat = 0
    private var headerTopInset: CGFloat = 0
    private var headerListGap: CGFloat = 0
    private var minimumWindowHeightWithoutWrap: CGFloat = 0
    private let installControlGap: CGFloat = 16
    private var deploymentRowBaseY: CGFloat = 0
    private var deploymentRowHeight: CGFloat = 0
    private var buttonRow: NSView?
    private var featureDocument: ManagerFeatureList?
    private var featureBoxes: [String: ManagerFeatureBox] = [:]
    private var featureBoxSizes: [String: NSSize] = [:]
    private var displayedGroupColumns: [[String]] = []
    private var groupColumnFrames: [NSRect] = []
    private var usesTwoFeatureColumns = false
    private var featureColumnWidth: CGFloat = 0
    private var textBindings: [String: ManagerTextBinding] = [:]
    private var originalPanelFonts: [ObjectIdentifier: NSFont] = [:]
    private var maximumTextWidth: CGFloat = 1100
    private var interfaceLanguage = "zh-Hans"
    private var outcome: Outcome = .cancelled
    private var checkboxes: [(option: FeatureOption, button: NSButton)] = []
    private var window: NSWindow?
    private var summaryLabel: NSTextField?
    private var installButton: NSButton?
    private var selectAllButton: NSButton?
    private var clearButton: NSButton?
    private var groupControls: [(group: FeatureGroup, select: NSButton, clear: NSButton, summary: NSTextField)] = []

    private var managementAction: String
    private let scopeIdentifiers: Set<String>
    private var actionControl: NSSegmentedControl?
    private var installLocation: String
    private var installLocationButton: NSButton?
    private var installLocationLabel: NSTextField?
    private var cleanupBuildProducts = false
    private var cleanupBuildProductsButton: NSButton?
    private var cleanupNowButton: NSButton?
    private var privacySettingsButton: NSButton?
    private var privacySettingsOpener: (() -> Void)?
    private var appManagementBlocked = false
    private var activeWorkerAction: String?
    private var lastWorkerAction: String?
    private var stopRequestURL: URL?
    private var stopRequested = false
    private var workerReportedStopped = false
    private var managerPath: String?
    private var worker: Process?
    private var runningIdentifiers: [String] = []
    private var featureStates: [String: String] = [:]
    private var statusLabels: [String: NSTextField] = [:]
    private var statusIcons: [String: NSImageView] = [:]
    private var activityIndicators: [String: NSProgressIndicator] = [:]
    private var progressIndicator: NSProgressIndicator?
    private var executionLabel: NSTextField?
    private var executionTimer: Timer?
    private struct ExecutionTiming {

        var hasStarted = false
        var startedAt: TimeInterval?
        var elapsed: TimeInterval = 0
    }
    private var installationTiming = ExecutionTiming()
    private var uninstallationTiming = ExecutionTiming()
    private var cleanupTiming = ExecutionTiming()

    // 刷新事件共用，安装与卸载的起点和最终耗时分别保存。
    private var executionAction: String {
        return activeWorkerAction ?? managementAction
    }

    private var executionTiming: ExecutionTiming {
        get {
            switch executionAction {
            case "uninstall":
                return uninstallationTiming
            case "cleanup":
                return cleanupTiming
            default:
                return installationTiming
            }
        }
        set {
            switch executionAction {
            case "uninstall":
                uninstallationTiming = newValue
            case "cleanup":
                cleanupTiming = newValue
            default:
                installationTiming = newValue
            }
        }
    }

    private var timingTitle: String {
        switch executionAction {
        case "uninstall":
            return "卸载"
        case "cleanup":
            return "清理"
        default:
            return "安装"
        }
    }

    private var executionActionTitle: String {
        return executionAction == "cleanup" ? "清除构建产物" : (executionAction == "uninstall" ? "卸载" : "安装 / 更新")
    }
    private var logTextView: NSTextView?
    private var logScrollView: ManagerLogScrollView?
    private var logSplitView: ManagerLogSplitView?
    private var featureScrollView: NSScrollView?
    private var minimumUpperPaneHeight: CGFloat = 220
    private var logURL: URL?
    private var logHandle: FileHandle?
    private var logErrorPresenter: ((String) -> Void)?
    private var liveOutputLength = 0
    private var closeButton: NSButton?
    private var followLogButton: NSButton?
    private(set) var lastExitStatus: Int32?
    private var backgroundStatusItem: NSStatusItem?
    private var backgroundStateItem: NSMenuItem?
    private var backgroundShowItem: NSMenuItem?
    private var backgroundQuitItem: NSMenuItem?
    private var closeChoiceAlert: NSAlert?
    private var closeChoicePending = false
    private var closeChoiceID: UUID?
    private var isExiting = false
    private var isBackgrounded = false
    private var closeChoicePresenter: ((@escaping (CloseChoice) -> Void) -> Void)?

    private var isRunning: Bool {
        worker != nil
    }

    init(action: String = "install",
         scope: [String]? = nil,
         installLocation: String = "build",
         preferences: ManagerPanelPreferences = .shared) {
        self.preferences = preferences
        managementAction = action
        self.installLocation = installLocation
        scopeIdentifiers = Set(scope ?? FeatureOption.all.map { $0.identifier })
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(systemPreferencesChanged), name: NSLocale.currentLocaleDidChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(systemPreferencesChanged), name: NSApplication.didBecomeActiveNotification, object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        if let backgroundStatusItem {
            NSStatusBar.system.removeStatusItem(backgroundStatusItem)
        }
    }

    static func parseArguments(_ arguments: [String]) throws -> FeatureSelectionController {
        var action = "install"
        var scope: [String]?
        var managerPath: String?
        var installLocation: String?
        var cleanupBuildProducts = true
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            if argument == "--cleanup-build-products" || argument == "--no-cleanup-build-products" {
                cleanupBuildProducts = argument == "--cleanup-build-products"
                index += 1
                continue
            }
            guard ["--action", "--scope", "--manager", "--install-location"].contains(argument), index + 1 < arguments.count else {
                throw NSError(domain: "JobsFinderFeatureSelection", code: 2,
                              userInfo: [NSLocalizedDescriptionKey: "未知参数或缺少值：\(argument)"])
            }
            index += 1
            let value = arguments[index]
            if argument == "--action" {
                guard ["install", "uninstall"].contains(value) else {
                    throw NSError(domain: "JobsFinderFeatureSelection", code: 2,
                                  userInfo: [NSLocalizedDescriptionKey: "未知操作：\(value)"])
                }
                action = value
            } else if argument == "--scope" {
                let identifiers = value.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
                let available = Set(FeatureOption.all.map { $0.identifier })
                guard !identifiers.isEmpty, identifiers.allSatisfy({ available.contains($0) }) else {
                    throw NSError(domain: "JobsFinderFeatureSelection", code: 2,
                                  userInfo: [NSLocalizedDescriptionKey: "功能范围含未知或空标识：\(value)"])
                }
                scope = identifiers
            } else if argument == "--install-location" {
                guard ["build", "applications"].contains(value) else {
                    throw NSError(domain: "JobsFinderFeatureSelection", code: 2,
                                  userInfo: [NSLocalizedDescriptionKey: "未知安装位置：\(value)"])
                }
                installLocation = value
            } else {
                guard value.hasPrefix("/"), FileManager.default.isReadableFile(atPath: value) else {
                    throw NSError(domain: "JobsFinderFeatureSelection", code: 2,
                                  userInfo: [NSLocalizedDescriptionKey: "管理脚本不可读取：\(value)"])
                }
                managerPath = value
            }
            index += 1
        }
        let location = installLocation ?? (managerPath == nil ? "build" : "applications")
        let controller = FeatureSelectionController(action: action,
                                                    scope: scope,
                                                    installLocation: location)
        controller.managerPath = managerPath
        controller.cleanupBuildProducts = cleanupBuildProducts && managerPath != nil && location == "applications"
        return controller
    }

    private var visibleGroups: [FeatureGroup] {
        FeatureGroup.all.compactMap { group in
            let identifiers = group.identifiers.filter { scopeIdentifiers.contains($0) }
            return identifiers.isEmpty ? nil : FeatureGroup(identifier: group.identifier, title: group.title, identifiers: identifiers)
        }
    }

    private var actionTitle: String {
        managementAction == "uninstall" ? "卸载" : "安装 / 更新"
    }

    func runModal() -> String {
        let application = NSApplication.shared
        let previousDelegate = application.delegate
        application.delegate = self
        // 管理会话始终保留 Dock 入口；只返回计划的内部选择器沿用辅助应用模式。
        application.setActivationPolicy(managerPath == nil ? .accessory : .regular)
        application.finishLaunching()
        installMenu(application: application)
        buildWindow()
        if let window {
            window.makeKeyAndOrderFront(nil)
            application.activate(ignoringOtherApps: true)
            // 使用普通应用事件循环，避免模态面板在其它应用窗口之上驻留。
            application.run()
            window.orderOut(nil)
        }
        removeBackgroundStatusItem()
        if application.delegate === self {
            application.delegate = previousDelegate
        }
        return formattedOutcome()
    }

    func installMenu(application: NSApplication) {
        let menu = NSMenu()
        let appItem = NSMenuItem(title: "Jobs Finder 扩展管理", action: nil, keyEquivalent: "")
        let appMenu = NSMenu(title: "Jobs Finder 扩展管理")
        let close = NSMenuItem(title: "关闭管理器", action: #selector(cancelClicked), keyEquivalent: "q")
        close.target = self
        appMenu.addItem(close)
        appItem.submenu = appMenu
        menu.addItem(appItem)
        let edit = NSMenuItem(title: "编辑", action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(withTitle: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        edit.submenu = editMenu
        menu.addItem(edit)
        application.mainMenu = menu
    }

    func formattedOutcome() -> String {
        switch outcome {
        case .selected(let action, let identifiers):
            return identifiers.isEmpty ? "__NONE__" : "\(action)|\(identifiers.joined(separator: ","))"
        case .cancelled:
            return "__CANCELLED__"
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        requestPanelClose()
        return false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        requestPanelClose()
        return .terminateCancel
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        restorePanelWindow()
        return false
    }

    func requestPanelClose() {
        guard !isExiting else {
            return
        }
        if isRunning {
            dismissCloseChoice()
            sendPanelToBackground()
            return
        }
        // 旧命令替换调用只等待选择结果，不能让纯选择器在后台挂住调用方。
        guard managerPath != nil else {
            finishClosingPanel()
            return
        }
        guard !closeChoicePending else {
            return
        }
        restorePanelWindow()
        closeChoicePending = true
        let choiceID = UUID()
        closeChoiceID = choiceID
        let completion: (CloseChoice) -> Void = { [weak self] choice in
            guard let self, self.closeChoicePending, self.closeChoiceID == choiceID else {
                return
            }
            self.closeChoicePending = false
            self.closeChoiceID = nil
            self.closeChoiceAlert = nil
            // 选择框显示后再核验一次，任务状态改变时仍以保全任务为先。
            if self.isRunning {
                self.sendPanelToBackground()
                return
            }
            switch choice {
            case .background:
                self.sendPanelToBackground()
            case .quit:
                self.finishClosingPanel()
            case .cancel:
                break
            }
        }
        if let closeChoicePresenter {
            closeChoicePresenter(completion)
            return
        }
        let alert = NSAlert()
        alert.window.appearance = window?.appearance
        alert.messageText = preferences.text("关闭管理面板")
        alert.informativeText = preferences.text("退到系统状态栏，还是完全退出安装／卸载面板？")
        alert.addButton(withTitle: preferences.text("退到后台"))
        alert.addButton(withTitle: preferences.text("完全退出"))
        alert.addButton(withTitle: preferences.text("取消")).keyEquivalent = "\u{1b}"
        for button in alert.buttons {
            button.font = ManagerPanelPreferences.scriptFont(button.font ?? .systemFont(ofSize: NSFont.systemFontSize),
                                                            language: preferences.resolvedLanguage)
        }
        closeChoiceAlert = alert
        if let window {
            alert.beginSheetModal(for: window) { response in
                completion(response == .alertFirstButtonReturn ? .background :
                    (response == .alertSecondButtonReturn ? .quit : .cancel))
            }
        } else {
            completion(.cancel)
        }
    }

    private func dismissCloseChoice() {
        closeChoicePending = false
        closeChoiceID = nil
        if let alert = closeChoiceAlert, let parent = alert.window.sheetParent {
            parent.endSheet(alert.window, returnCode: .cancel)
        }
        closeChoiceAlert = nil
    }

    private func ensureBackgroundStatusItem() -> Bool {
        if backgroundStatusItem != nil {
            return true
        }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = item.button else {
            NSStatusBar.system.removeStatusItem(item)
            return false
        }
        // 复用随包应用图标，保留已有透明底蓝色标识。
        if let icon = NSApplication.shared.applicationIconImage?.copy() as? NSImage {
            icon.size = NSSize(width: 18, height: 18)
            icon.isTemplate = false
            button.image = icon
        } else {
            button.title = "🧩"
        }
        button.setAccessibilityLabel(preferences.text("Jobs Finder 扩展管理"))
        let menu = NSMenu()
        menu.autoenablesItems = false
        let state = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        state.isEnabled = false
        menu.addItem(state)
        menu.addItem(.separator())
        let show = NSMenuItem(title: "", action: #selector(restorePanelWindow), keyEquivalent: "")
        show.target = self
        menu.addItem(show)
        let quit = NSMenuItem(title: "", action: #selector(quitFromStatusBar), keyEquivalent: "")
        quit.target = self
        menu.addItem(quit)
        item.menu = menu
        backgroundStatusItem = item
        backgroundStateItem = state
        backgroundShowItem = show
        backgroundQuitItem = quit
        updateBackgroundStatus()
        return true
    }

    func sendPanelToBackground() {
        cancelPendingFeatureSelections()
        guard ensureBackgroundStatusItem() else {
            appendLog("无法创建状态栏入口，保留管理窗口以便查看任务。\n", kind: .error)
            return
        }
        isBackgrounded = true
        updateBackgroundStatus()
        window?.orderOut(nil)
    }

    @objc func restorePanelWindow() {
        guard !isExiting else {
            return
        }
        isBackgrounded = false
        window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        updateBackgroundStatus()
    }

    @objc func quitFromStatusBar() {
        if isRunning {
            sendPanelToBackground()
        } else {
            finishClosingPanel()
        }
    }

    func updateBackgroundStatus() {
        guard let item = backgroundStatusItem else {
            return
        }
        let state = executionLabel?.stringValue ?? preferences.text("安装 / 更新就绪")
        backgroundStateItem?.title = preferences.text("状态：{0}").replacingOccurrences(of: "{0}", with: state)
        backgroundShowItem?.title = preferences.text("显示管理面板")
        backgroundQuitItem?.title = preferences.text("完全退出")
        backgroundQuitItem?.isEnabled = !isRunning
        backgroundQuitItem?.toolTip = isRunning ? preferences.text("任务进行中，完成后可完全退出。") : nil
        item.button?.setAccessibilityLabel(preferences.text("Jobs Finder 扩展管理"))
        item.button?.toolTip = preferences.text("Jobs Finder 扩展管理") + "\n" + state
    }

    private func removeBackgroundStatusItem() {
        if let backgroundStatusItem {
            NSStatusBar.system.removeStatusItem(backgroundStatusItem)
        }
        backgroundStatusItem = nil
        backgroundStateItem = nil
        backgroundShowItem = nil
        backgroundQuitItem = nil
    }

    private func finishClosingPanel() {
        guard !isRunning else {
            sendPanelToBackground()
            return
        }
        isExiting = true
        isBackgrounded = false
        dismissCloseChoice()
        removeBackgroundStatusItem()
        outcome = .cancelled
        NSApplication.shared.stop(nil)
        // stop 也可从异步选择框回调触发，补事件唤醒普通应用循环。
        if let event = NSEvent.otherEvent(with: .applicationDefined, location: .zero,
                                         modifierFlags: [], timestamp: 0, windowNumber: 0,
                                         context: nil, subtype: 0, data1: 0, data2: 0) {
            NSApplication.shared.postEvent(event, atStart: false)
        }
    }

    func windowDidResize(_ notification: Notification) {
        cancelPendingFeatureSelections()
        layoutPreferencesHeader()
    }

    func windowDidResignKey(_ notification: Notification) {
        cancelPendingFeatureSelections()
    }

    private func cancelPendingFeatureSelections() {
        for box in featureBoxes.values {
            (box.contentView as? ManagerFeatureColumn)?.cancelPendingSelection()
        }
    }

    func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        return minimumUpperPaneHeight
    }

    func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        return max(minimumUpperPaneHeight, splitView.bounds.height - splitView.dividerThickness - 112)
    }

    func splitView(_ splitView: NSSplitView, canCollapseSubview subview: NSView) -> Bool {
        return false
    }

    func splitView(_ splitView: NSSplitView, resizeSubviewsWithOldSize oldSize: NSSize) {
        guard splitView.arrangedSubviews.count == 2 else {
            return
        }
        let upper = splitView.arrangedSubviews[0]
        let lower = splitView.arrangedSubviews[1]
        let available = max(0, splitView.bounds.height - splitView.dividerThickness)
        // 拖动限制不会约束窗口缩放；缩窗时也要给列表与操作栏留足空间。
        let logHeight = min(max(112, lower.frame.height), max(112, available - minimumUpperPaneHeight))
        let upperHeight = max(0, available - logHeight)
        upper.frame = NSRect(x: 0, y: 0, width: splitView.bounds.width, height: upperHeight)
        lower.frame = NSRect(
            x: 0,
            y: upperHeight + splitView.dividerThickness,
            width: splitView.bounds.width,
            height: logHeight
        )
    }
}

private extension FeatureSelectionController {
    func buildWindow(screenSize: NSSize? = nil) {
        checkboxes.removeAll()
        groupControls.removeAll()
        featureBoxes.removeAll()
        featureBoxSizes.removeAll()
        featureDocument = nil
        statusLabels.removeAll()
        statusIcons.removeAll()
        activityIndicators.removeAll()
        let screenSize = screenSize ?? NSScreen.main?.visibleFrame.size ?? NSSize(width: 1280, height: 800)
        maximumTextWidth = max(600, screenSize.width - 52)
        featureColumnWidth = screenSize.width >= 1280 ? floor((screenSize.width - 122) / 2) : maximumTextWidth - 38
        let compact = screenSize.height < 700
        let header = NSView()
        textBindings.removeAll()
        originalPanelFonts.removeAll()
        let preferencesRow = makePreferencesRow()

        let titleLabel = NSTextField(labelWithString: "自定义Finder右键菜单")
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        headerTitleLabel = titleLabel
        preferencesToolbar = preferencesRow
        headerView = header

        let subtitleLabel = NSTextField(labelWithString:
            "卸载仅移除所选菜单，其它功能保留；组内选择只影响本组。"
        )
        subtitleLabel.font = .systemFont(ofSize: 12)
        subtitleLabel.textColor = .secondaryLabelColor

        let actionControl = NSSegmentedControl(labels: ["安装 / 更新", "卸载"], trackingMode: .selectOne,
                                                target: self, action: #selector(actionChanged))
        actionControl.selectedSegment = managementAction == "uninstall" ? 1 : 0
        actionControl.setAccessibilityLabel("操作：安装 / 更新或卸载")
        self.actionControl = actionControl

        let summaryLabel = NSTextField(labelWithString: "已选 0 / \(scopeIdentifiers.count) 项；空选不能执行，切换操作保留勾选。")
        summaryLabel.font = .systemFont(ofSize: 12, weight: .medium)
        summaryLabel.textColor = .secondaryLabelColor
        self.summaryLabel = summaryLabel

        installLocationButton = nil
        installLocationLabel = nil
        cleanupBuildProductsButton = nil
        cleanupNowButton = nil
        privacySettingsButton = nil
        var headerControls: [NSControl] = [summaryLabel]
        // 旧选择器只返回功能计划；真正管理面板才承担部署位置的选择与执行。
        if managerPath != nil {
            let locationButton = NSButton(checkboxWithTitle: "使用「应用程序」中的联合 App 安装 / 卸载",
                                          target: self,
                                          action: #selector(installLocationChanged))
            locationButton.state = installLocation == "applications" ? .on : .off
            locationButton.toolTip = "勾选：在 /Applications/Jobs自定义右键菜单.app 中统一管理所选功能；未勾选：沿用当前构建目录。"
            locationButton.setAccessibilityLabel("使用应用程序中的联合 App 安装或卸载")
            installLocationButton = locationButton
            let cleanupButton = NSButton(checkboxWithTitle: "安装成功后清除此轮构建产物",
                                         target: self,
                                         action: #selector(cleanupBuildProductsChanged))
            cleanupButton.state = cleanupBuildProducts ? .on : .off
            cleanupButton.toolTip = "仅在联合 App 成功安装到「应用程序」并完成核验后清除此轮构建产物；安装失败不清理。"
            cleanupButton.setAccessibilityLabel("安装成功后清除此轮构建产物")
            cleanupBuildProductsButton = cleanupButton
            let cleanupNow = NSButton(title: "🧹 清除构建产物",
                                      target: self,
                                      action: #selector(cleanupNowClicked))
            cleanupNow.bezelStyle = .rounded
            cleanupNow.isBordered = false
            cleanupNow.wantsLayer = true
            cleanupNow.layer?.cornerRadius = 5
            cleanupNow.layer?.backgroundColor = NSColor.systemRed.cgColor
            cleanupNow.contentTintColor = .white
            cleanupNow.attributedTitle = NSAttributedString(string: cleanupNow.title, attributes: [
                .foregroundColor: NSColor.white,
                .font: NSFont.systemFont(ofSize: 12, weight: .semibold)
            ])
            cleanupNow.toolTip = "只清理当前勾选功能的构建产物，不执行安装或卸载。"
            cleanupNow.setAccessibilityLabel("清除所选功能的构建产物")
            cleanupNowButton = cleanupNow
            let privacyButton = NSButton(title: "打开隐私与安全性设置",
                                         target: self,
                                         action: #selector(openPrivacySettingsClicked))
            privacyButton.bezelStyle = .rounded
            privacyButton.font = .systemFont(ofSize: 12)
            privacyButton.toolTip = "在“隐私与安全性 → App 管理”中添加并启用 Jobs右键菜单管理面板.app；此按钮只打开设置。"
            privacySettingsButton = privacyButton
            header.addSubview(privacyButton)
            let locationLabel = NSTextField(labelWithString: installLocationDescription)
            locationLabel.font = .systemFont(ofSize: 11)
            locationLabel.textColor = .secondaryLabelColor
            installLocationLabel = locationLabel
            headerControls += [locationLabel, locationButton]
        }
        headerControls += [subtitleLabel, actionControl, titleLabel]

        header.addSubview(preferencesRow)
        var headerHeight: CGFloat = 0
        var headerWidth: CGFloat = 0
        for label in headerControls {
            if label === summaryLabel {
                fitLabel(summaryLabel, reserving: (0...scopeIdentifiers.count).map { count in
                    "已选 \(count) / \(scopeIdentifiers.count) 项；空选不能执行，切换操作保留勾选。"
                })
            } else if label === installLocationLabel, let locationLabel = installLocationLabel {
                fitLabel(locationLabel, reserving: [
                    "当前目标：构建目录（原有方式；清理构建产物会影响功能）。",
                    "联合 App：Jobs自定义右键菜单.app；位置：/Applications/Jobs自定义右键菜单.app（安装成功后可清理构建产物）"
                ])
            } else {
                fitLocalizedControl(label)
            }
            if label === installLocationButton, let cleanup = cleanupBuildProductsButton {
                fitLocalizedControl(label, maximumWidth: floor(maximumTextWidth * 0.56))
                fitLocalizedControl(cleanup, maximumWidth: floor(maximumTextWidth * 0.44) - installControlGap)
                deploymentRowBaseY = headerHeight
                deploymentRowHeight = max(label.frame.height, cleanup.frame.height)
                label.setFrameOrigin(NSPoint(x: 0, y: headerHeight + (deploymentRowHeight - label.frame.height) / 2))
                cleanup.setFrameOrigin(NSPoint(x: label.frame.maxX + installControlGap,
                                               y: headerHeight + (deploymentRowHeight - cleanup.frame.height) / 2))
                header.addSubview(label)
                header.addSubview(cleanup)
                headerHeight += deploymentRowHeight + (compact ? 6 : 10)
                headerWidth = max(headerWidth, max(label.frame.width, min(maximumTextWidth, cleanup.frame.maxX)))
                continue
            }
            if label === titleLabel {
                label.setFrameSize(NSSize(width: label.frame.width,
                                          height: max(label.frame.height, preferencesRow.frame.height)))
            }
            var rowHeight = label.frame.height
            if label === actionControl, let privacyButton = privacySettingsButton {
                fitLocalizedControl(privacyButton)
                rowHeight = max(rowHeight, privacyButton.frame.height)
                privacyButton.setFrameOrigin(NSPoint(x: label.frame.width + 18,
                                                     y: headerHeight + (rowHeight - privacyButton.frame.height) / 2))
                headerWidth = max(headerWidth, privacyButton.frame.maxX)
            }
            label.setFrameOrigin(NSPoint(x: 0, y: headerHeight + (rowHeight - label.frame.height) / 2))
            header.addSubview(label)
            headerHeight += rowHeight + (compact ? 6 : 10)
            headerWidth = max(headerWidth, label.frame.width)
        }
        refreshCleanupBuildProductsOption()
        header.setFrameSize(NSSize(width: headerWidth, height: headerHeight - (compact ? 6 : 10)))
        headerBaseHeight = header.frame.height
        headerTitleFrame = titleLabel.frame
        preferencesRow.setFrameOrigin(NSPoint(x: headerWidth - preferencesRow.frame.width,
                                               y: titleLabel.frame.midY - preferencesRow.frame.height / 2))
        preferencesRow.autoresizingMask = [.minXMargin, .minYMargin]

        let boxes = visibleGroups.map { makeGroupBox(group: $0, spacing: compact ? 3 : 6) }
        let verticalPadding: CGFloat = compact ? 56 : 84
        let logHeight: CGFloat = compact ? 140 : 180
        let executionRow = makeExecutionRow(width: 0, height: 32)
        let executionHeight = executionRow.frame.height
        let featureList = makeFeatureList(
            boxes: boxes,
            screenSize: screenSize,
            reservedHeight: header.frame.height + 32 + verticalPadding + 32 + logHeight + executionHeight
        )
        let logPanel = makeLogPanel(width: 0, height: logHeight)
        let contentWidth = max(featureList.frame.width, headerWidth, logPanel.frame.width, executionRow.frame.width)
        logPanel.setFrameSize(NSSize(width: contentWidth, height: logHeight))
        executionRow.setFrameSize(NSSize(width: contentWidth, height: executionHeight))
        let buttonRow = makeButtonRow(width: contentWidth)
        self.buttonRow = buttonRow
        let headerSize = header.frame.size
        let buttonHeight = buttonRow.frame.height
        featureList.setFrameSize(NSSize(width: featureList.frame.width,
                                        height: max(80, featureList.frame.height - max(0, buttonHeight - 32) - 4)))
        let titlebarHeight = NSWindow.frameRect(forContentRect: .zero,
                                                styleMask: [.titled, .closable, .miniaturizable, .resizable]).height
        let contentSize = NSSize(
            width: contentWidth + 52,
            height: min(screenSize.height - titlebarHeight,
                        headerSize.height + featureList.frame.height + buttonHeight + verticalPadding + logHeight + executionHeight)
        )
        let container = NSView(frame: NSRect(origin: .zero, size: contentSize))
        let bottomInset: CGFloat = compact ? 10 : 14
        let topInset: CGFloat = compact ? 10 : 20
        let headerGap: CGFloat = compact ? 8 : 14
        let listGap: CGFloat = compact ? 8 : 16
        let split = ManagerLogSplitView(frame: NSRect(
            x: 26,
            y: bottomInset,
            width: contentWidth,
            height: contentSize.height - bottomInset - topInset - headerSize.height - headerGap
        ))
        split.isVertical = false
        split.dividerStyle = .thick
        split.autoresizingMask = [.width, .height]
        split.delegate = self
        split.toolTip = "上下拖动分隔条调整日志高度；功能列表和日志可分别滚动。"
        split.setAccessibilityLabel("功能列表与实时日志高度分隔条")
        logSplitView = split
        let upper = NSView(frame: NSRect(
            x: 0,
            y: 0,
            width: contentWidth,
            height: split.bounds.height - split.dividerThickness - logHeight
        ))
        minimumUpperPaneHeight = (compact ? 80 : 100) + executionHeight + buttonHeight + listGap + 4
        executionRow.setFrameOrigin(.zero)
        executionRow.autoresizingMask = [.width]
        buttonRow.frame = NSRect(x: 0, y: executionHeight + 4, width: contentWidth, height: buttonHeight)
        buttonRow.autoresizingMask = [.width]
        installButton?.autoresizingMask = [.minXMargin]
        closeButton?.autoresizingMask = [.minXMargin]
        cleanupNowButton?.autoresizingMask = [.minXMargin]
        featureList.frame = NSRect(
            x: 0,
            y: buttonRow.frame.maxY + listGap,
            width: contentWidth,
            height: upper.bounds.height - buttonRow.frame.maxY - listGap
        )
        featureList.autoresizingMask = [.width, .height]
        for view in [featureList, buttonRow, executionRow] {
            upper.addSubview(view)
        }
        split.addArrangedSubview(upper)
        split.addArrangedSubview(logPanel)
        container.addSubview(split)
        header.frame = NSRect(
            x: 26,
            y: split.frame.maxY + headerGap,
            width: contentWidth,
            height: headerSize.height
        )
        header.autoresizingMask = [.width, .minYMargin]
        container.addSubview(header)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Jobs Finder 扩展管理"
        window.level = .normal
        window.hidesOnDeactivate = false
        window.contentView = container
        window.contentMinSize = NSSize(
            width: contentSize.width,
            height: bottomInset + topInset + headerSize.height + headerGap + minimumUpperPaneHeight + split.dividerThickness + 112
        )
        window.delegate = self
        self.window = window
        headerTopInset = topInset
        headerListGap = headerGap
        minimumWindowHeightWithoutWrap = window.contentMinSize.height
        layoutPreferencesHeader()
        container.layoutSubtreeIfNeeded()
        split.adjustSubviews()
        split.setPosition(split.bounds.height - split.dividerThickness - logHeight, ofDividerAt: 0)
        window.center()
        refreshSelectionState()
        applyPanelPreferences()
    }

    /// 默认左侧收纳通用功能，右侧专放 Flutter；窄屏仅折叠显示，不改保存的双列布局。
    func makeFeatureList(boxes: [NSBox],
                         screenSize: NSSize,
                         reservedHeight: CGFloat) -> NSView {
        let gap: CGFloat = 14
        let visible = Set(featureBoxes.keys)
        let columns = preferences.featureGroupColumns.map { column in
            return column.filter { identifier in
                return visible.contains(identifier)
            }
        }
        let widest = featureBoxSizes.values.map { size in
            return size.width
        }.max() ?? 0
        let bothColumnsHaveContent = columns.allSatisfy { column in
            return !column.isEmpty
        }
        usesTwoFeatureColumns = boxes.count > 1 && (visible.count == FeatureGroup.all.count || bothColumnsHaveContent) && widest * 2 + gap + 68 <= screenSize.width - 40
        let width = usesTwoFeatureColumns ? widest * 2 + gap : widest
        let document = ManagerFeatureList(frame: NSRect(x: 0, y: 0, width: width, height: 0))
        featureDocument = document
        for box in boxes {
            document.addSubview(box)
        }
        document.proposeDrop = { [weak self] identifier, point in
            return self?.featureGroupDropProposal(identifier: identifier, point: point)?.indicator
        }
        document.acceptDrop = { [weak self] identifier, point in
            guard let self, let proposal = self.featureGroupDropProposal(identifier: identifier, point: point) else {
                return false
            }
            return self.moveFeatureGroup(identifier, toColumn: proposal.column, before: proposal.before)
        }
        layoutFeatureGroups()
        let availableHeight = max(80, screenSize.height - reservedHeight)
        let viewportHeight = min(document.frame.height, availableHeight)
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: width + 16, height: viewportHeight))
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = false
        scroll.drawsBackground = false
        scroll.documentView = document
        featureScrollView = scroll
        scroll.contentView.scroll(to: NSPoint(x: 0, y: max(0, document.frame.height - viewportHeight)))
        scroll.reflectScrolledClipView(scroll.contentView)
        return scroll
    }

    func layoutFeatureGroups() {
        cancelPendingFeatureSelections()
        guard let document = featureDocument else {
            return
        }
        let visible = Set(featureBoxes.keys)
        let logicalColumns = preferences.featureGroupColumns.map { column in
            return column.filter { identifier in
                return visible.contains(identifier)
            }
        }
        let nonempty = logicalColumns.filter { column in
            return !column.isEmpty
        }
        let collapsed = nonempty.flatMap { column in
            return column
        }
        displayedGroupColumns = usesTwoFeatureColumns ? logicalColumns : [collapsed]
        let gap: CGFloat = 14
        let minimumWidth = featureBoxSizes.values.map { size in
            return size.width
        }.max() ?? 0
        // 双列等宽保留空列落点，卡片跨列后也不会撑宽文档或挤掉状态列。
        let widths = displayedGroupColumns.map { _ in
            return minimumWidth
        }
        let heights = displayedGroupColumns.map { column in
            let cardHeight = column.reduce(CGFloat(0)) { total, identifier in
                return total + (featureBoxSizes[identifier]?.height ?? 0)
            }
            return cardHeight + CGFloat(max(0, column.count - 1)) * gap
        }
        let size = NSSize(width: widths.reduce(0, +) + CGFloat(max(0, widths.count - 1)) * gap,
                          height: max(heights.max() ?? 0, featureScrollView?.contentSize.height ?? 0))
        document.setFrameSize(size)
        groupColumnFrames.removeAll()
        var x: CGFloat = 0
        for (index, column) in displayedGroupColumns.enumerated() {
            let width = widths[index]
            groupColumnFrames.append(NSRect(x: x, y: 0, width: width, height: size.height))
            var y = size.height
            for identifier in column {
                guard let box = featureBoxes[identifier], let natural = featureBoxSizes[identifier] else {
                    continue
                }
                y -= natural.height
                box.frame = NSRect(x: x, y: y, width: width, height: natural.height)
                box.layoutSubtreeIfNeeded()
                if let content = box.contentView {
                    for (key, status) in statusLabels where status.superview === content {
                        status.setFrameOrigin(NSPoint(x: content.bounds.width - status.frame.width, y: status.frame.minY))
                        if let icon = statusIcons[key], let spinner = activityIndicators[key] {
                            let frame = NSRect(x: status.frame.minX - 24, y: icon.frame.minY, width: 16, height: 16)
                            icon.frame = frame
                            spinner.frame = frame
                        }
                    }
                }
                y -= gap
            }
            x += width + gap
        }
        document.updatePinnedHeaders()
    }

    func featureGroupDropProposal(identifier: String,
                                  point: NSPoint) -> (column: Int, before: String?, indicator: NSRect)? {
        guard featureBoxes[identifier] != nil, !groupColumnFrames.isEmpty else {
            return nil
        }
        let displayColumn = groupColumnFrames.indices.min { lhs, rhs in
            return abs(groupColumnFrames[lhs].midX - point.x) < abs(groupColumnFrames[rhs].midX - point.x)
        } ?? 0
        let candidates = displayedGroupColumns[displayColumn].filter { key in
            return key != identifier
        }
        let before = candidates.first { key in
            return point.y >= (featureBoxes[key]?.frame.midY ?? 0)
        }
        let logicalColumn: Int
        if usesTwoFeatureColumns {
            logicalColumn = displayColumn
        } else {
            let neighbor = before ?? candidates.last ?? identifier
            logicalColumn = preferences.featureGroupColumns.firstIndex { column in
                return column.contains(neighbor)
            } ?? 0
        }
        let frame = groupColumnFrames[displayColumn]
        let beforeY = before.flatMap { key in
            return featureBoxes[key]?.frame.maxY
        }.map { value in
            return value + 5
        }
        let afterY = candidates.last.flatMap { key in
            return featureBoxes[key]?.frame.minY
        }.map { value in
            return value - 9
        }
        let y = beforeY ?? afterY ?? frame.maxY - 4
        return (logicalColumn, before, NSRect(x: frame.minX + 4, y: min(max(0, y), frame.maxY - 4), width: frame.width - 8, height: 4))
    }

    @discardableResult
    func moveFeatureGroup(_ identifier: String,
                          toColumn column: Int,
                          before: String?) -> Bool {
        guard featureBoxes[identifier] != nil, (0...1).contains(column), before != identifier else {
            return false
        }
        var columns = preferences.featureGroupColumns
        columns = columns.map { current in
            return current.filter { key in
                return key != identifier
            }
        }
        let insertion = before.flatMap { key in
            return columns[column].firstIndex(of: key)
        } ?? columns[column].count
        columns[column].insert(identifier, at: insertion)
        let oldHeight = featureDocument?.frame.height ?? 0
        let oldY = featureScrollView?.contentView.bounds.minY ?? 0
        preferences.featureGroupColumns = columns
        layoutFeatureGroups()
        if let scroll = featureScrollView, let document = featureDocument {
            let y = max(0, min(document.frame.height - scroll.contentSize.height, oldY + document.frame.height - oldHeight))
            scroll.contentView.scroll(to: NSPoint(x: 0, y: y))
            scroll.reflectScrolledClipView(scroll.contentView)
        }
        return true
    }

    func makeGroupBox(group: FeatureGroup, spacing: CGFloat) -> NSBox {
        let box = ManagerFeatureBox()
        box.groupIdentifier = group.identifier
        box.title = group.title
        box.titleFont = .systemFont(ofSize: 13, weight: .semibold)

        let column = ManagerFeatureColumn()
        column.rowSpacing = spacing
        let controls = NSView()
        let select = NSButton(title: "全选", target: self, action: #selector(selectGroupClicked(_:)))
        let clear = NSButton(title: "全不选", target: self, action: #selector(clearGroupClicked(_:)))
        var controlsWidth: CGFloat = 0
        var controlsHeight: CGFloat = 0
        for button in [select, clear] {
            styleAuxiliaryButton(button)
            button.identifier = NSUserInterfaceItemIdentifier(group.identifier)
            button.setAccessibilityLabel("\(group.title)：\(button.title)")
            fitLocalizedControl(button)
            button.setFrameOrigin(NSPoint(x: controlsWidth, y: 0))
            controls.addSubview(button)
            controlsWidth += button.frame.width + 8
            controlsHeight = max(controlsHeight, button.frame.height)
        }
        let summary = NSTextField(labelWithString: "已选 0 / \(group.options.count)")
        summary.font = .systemFont(ofSize: 11)
        summary.textColor = .secondaryLabelColor
        fitLabel(summary, reserving: (0...group.options.count).map { count in
            "已选 \(count) / \(group.options.count)"
        })
        summary.setFrameOrigin(NSPoint(x: controlsWidth, y: (controlsHeight - summary.frame.height) / 2))
        controls.addSubview(summary)
        controlsWidth += summary.frame.width
        controls.setFrameSize(NSSize(width: controlsWidth, height: controlsHeight))
        groupControls.append((group, select, clear, summary))
        var optionButtons: [NSButton] = []
        var contentWidth = controlsWidth
        var contentHeight = controlsHeight + spacing
        let statusTexts = ["未选择", "已选择", "等待中", "清理中…", "卸载中…", "安装中…", "已清理", "已卸载", "安装成功", "未执行", "未安装，无需卸载", "失败，见日志"]
        let statusSample = NSTextField(labelWithString: "未选择")
        statusSample.font = .systemFont(ofSize: 11)
        fitLabel(statusSample, reserving: statusTexts, maximumWidth: min(260, maximumTextWidth * 0.3))
        let statusWidth = max(88, statusSample.frame.width)
        let statusHeight = max(20, statusSample.frame.height)
        for option in group.options {
            let checkbox = NSButton(
                title: option.title,
                target: self,
                action: #selector(selectionChanged)
            )
            checkbox.setButtonType(.switch)
            checkbox.font = .systemFont(ofSize: 13)
            checkbox.state = .off
            checkboxes.append((option, checkbox))
            // 分组外框、滚动条与窗口边距也计入屏宽，窄屏仍可退成完整的一列。
            fitLocalizedControl(checkbox, maximumWidth: max(200, featureColumnWidth - statusWidth - 46))
            optionButtons.append(checkbox)
            contentWidth = max(contentWidth, checkbox.frame.width + statusWidth + 32)
            contentHeight += max(statusHeight, checkbox.frame.height) + spacing
        }
        contentHeight -= spacing
        column.setFrameSize(NSSize(width: contentWidth, height: contentHeight))
        controls.setFrameOrigin(NSPoint(x: 0, y: contentHeight - controlsHeight))
        box.groupToolbar = controls
        box.groupToolbarFrame = controls.frame
        column.addSubview(controls)
        var y = controls.frame.minY - spacing
        for checkbox in optionButtons {
            let rowHeight = max(statusHeight, checkbox.frame.height)
            y -= rowHeight
            checkbox.setFrameOrigin(NSPoint(x: 0, y: y + (rowHeight - checkbox.frame.height) / 2))
            column.addSubview(checkbox)
            let identifier = checkboxes.first { $0.button === checkbox }!.option.identifier
            let status = NSTextField(labelWithString: "未选择")
            status.font = .systemFont(ofSize: 11)
            status.textColor = .secondaryLabelColor
            status.cell?.wraps = true
            status.cell?.isScrollable = false
            status.cell?.usesSingleLineMode = false
            status.maximumNumberOfLines = 0
            status.lineBreakMode = .byWordWrapping
            status.frame = NSRect(x: contentWidth - statusWidth, y: checkbox.frame.midY - statusHeight / 2, width: statusWidth, height: statusHeight)
            status.identifier = NSUserInterfaceItemIdentifier(identifier)
            let click = NSClickGestureRecognizer(target: self, action: #selector(failedStatusClicked(_:)))
            click.isEnabled = false
            status.addGestureRecognizer(click)
            column.addSubview(status)
            statusLabels[identifier] = status
            column.rows.append(ManagerFeatureColumn.Row(button: checkbox, status: status, height: rowHeight))
            // 图标与活动指示器共用固定列，状态文字不随图标显隐而移动。
            let iconFrame = NSRect(x: status.frame.minX - 24, y: checkbox.frame.midY - 8, width: 16, height: 16)
            let icon = NSImageView(frame: iconFrame)
            icon.imageScaling = .scaleProportionallyDown
            icon.setAccessibilityElement(false)
            column.addSubview(icon)
            statusIcons[identifier] = icon
            let activity = NSProgressIndicator(frame: iconFrame)
            activity.style = .spinning
            activity.controlSize = .small
            activity.isDisplayedWhenStopped = false
            column.addSubview(activity)
            activityIndicators[identifier] = activity
            y -= spacing
        }
        box.contentView = column
        box.setFrameFromContentFrame(NSRect(origin: .zero, size: NSSize(width: contentWidth, height: contentHeight)))
        featureBoxes[group.identifier] = box
        featureBoxSizes[group.identifier] = box.frame.size
        return box
    }

    func makeButtonRow(width: CGFloat) -> NSView {
        let row = NSView()

        let selectAllButton = NSButton(title: "全选", target: self, action: #selector(selectAllClicked))
        styleAuxiliaryButton(selectAllButton)
        let clearButton = NSButton(title: "全不选", target: self, action: #selector(clearAllClicked))
        styleAuxiliaryButton(clearButton)

        let cancelButton = NSButton(title: "关闭", target: self, action: #selector(cancelClicked))
        cancelButton.bezelStyle = .rounded
        cancelButton.keyEquivalent = "\u{1b}"

        // 预留较长的安装标题宽度，避免从卸载切回安装时裁掉文字。
        let installButton = NSButton(title: "安装 / 更新", target: self, action: #selector(installClicked))
        installButton.bezelStyle = .rounded
        installButton.keyEquivalent = "\r"

        var height: CGFloat = 0
        for button in [selectAllButton, clearButton, cancelButton, installButton] + [cleanupNowButton].compactMap({ $0 }) {
            let limit = button === cancelButton ? width * 0.11 : (button === cleanupNowButton ? width * 0.24 - 18 : width * 0.19)
            fitLocalizedControl(button, maximumWidth: max(60, floor(limit) - 10))
            row.addSubview(button)
            height = max(height, button.frame.height)
        }
        selectAllButton.setFrameOrigin(.zero)
        clearButton.setFrameOrigin(NSPoint(x: selectAllButton.frame.maxX + 10, y: 0))
        if let cleanup = cleanupNowButton {
            cleanup.setFrameSize(NSSize(width: cleanup.frame.width + 18, height: max(24, cleanup.frame.height)))
            cleanup.setFrameOrigin(NSPoint(x: width - cleanup.frame.width, y: 0))
        }
        let installRight = cleanupNowButton.map { $0.frame.minX - 10 } ?? width
        installButton.setFrameOrigin(NSPoint(x: installRight - installButton.frame.width, y: 0))
        cancelButton.setFrameOrigin(NSPoint(x: installButton.frame.minX - cancelButton.frame.width - 10, y: 0))
        row.setFrameSize(NSSize(width: width, height: max(height, cleanupNowButton?.frame.height ?? 0)))
        for control in row.subviews {
            control.setFrameOrigin(NSPoint(x: control.frame.minX, y: (row.frame.height - control.frame.height) / 2))
        }

        self.selectAllButton = selectAllButton
        self.clearButton = clearButton
        self.installButton = installButton
        self.closeButton = cancelButton
        return row
    }

    func styleAuxiliaryButton(_ button: NSButton) {
        button.bezelStyle = .rounded
        button.font = .systemFont(ofSize: 12, weight: .medium)
    }

    /// 按实际字体预留所有动态文案的最大尺寸，避免计数变长后裁字或推动邻近控件。
    func fitLabel(_ label: NSTextField, reserving values: [String], maximumWidth: CGFloat? = nil) {
        let original = label.stringValue
        let originalFont = label.font ?? NSFont.systemFont(ofSize: 12)
        let limit = maximumWidth ?? maximumTextWidth
        var size = NSSize.zero
        for value in values {
            for language in ManagerPanelPreferences.languages where language != "system" {
                label.font = ManagerPanelPreferences.scriptFont(originalFont, language: language)
                label.stringValue = preferences.text(value, language: language)
                label.sizeToFit()
                size.width = max(size.width, label.frame.width)
                size.height = max(size.height, label.frame.height)
            }
        }
        label.stringValue = original
        label.font = originalFont
        if size.width + 2 > limit {
            label.cell?.wraps = true
            label.cell?.isScrollable = false
            label.cell?.usesSingleLineMode = false
            label.maximumNumberOfLines = 0
            label.lineBreakMode = .byWordWrapping
            var height: CGFloat = 0
            for value in values {
                for language in ManagerPanelPreferences.languages where language != "system" {
                    let text = preferences.text(value, language: language)
                    let font = ManagerPanelPreferences.scriptFont(originalFont, language: language)
                    let bounds = (text as NSString).boundingRect(with: NSSize(width: limit - 4, height: .greatestFiniteMagnitude),
                        options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font])
                    height = max(height, ceil(bounds.height) + 4)
                }
            }
            size = NSSize(width: limit - 2, height: height)
        }
        label.setFrameSize(NSSize(width: ceil(size.width) + 2, height: ceil(size.height)))
    }

    func makeExecutionRow(width: CGFloat, height: CGFloat) -> NSView {
        let label = NSTextField(labelWithString: "就绪；选择功能后点击操作按钮。")
        label.font = .systemFont(ofSize: 12)
        let count = scopeIdentifiers.count
        var messages = [label.stringValue, "任务仍在执行，请等待结束后关闭，避免中断安装。"]
        for action in ["安装 / 更新", "卸载", "清除构建产物"] {
            let timing = action == "卸载" ? "卸载" : (action == "清除构建产物" ? "清理" : "安装")
            messages += (0...count).map { completed in
                "\(action)中；已处理 \(completed) / \(count) 项（\(completionPercentage(completed: completed, total: count))，按完成项计数）；\(timing)用时 9999:59:59"
            }
        }
        for failed in 0...count {
            messages.append("任务失败：成功 \(count - failed)，失败 \(failed)；退出码 \(Int32.min)；进度 100.0%；安装总用时 9999:59:59")
        }
        messages.append("已完成：成功 \(count)，失败 0；退出码 0；进度 100.0%；安装总用时 9999:59:59")
        messages.append("已完成：成功 \(count)，失败 \(count)，无需卸载 \(count)，未执行 \(count)；退出码 \(Int32.min)；进度 100.0%；卸载总用时 9999:59:59")
        messages.append("已停止：成功 \(count)，失败 \(count)，未执行 \(count)；退出码 \(Int32.min)；进度 100.0%；安装总用时 9999:59:59")
        messages.append("正在完成当前功能，随后停止；安装用时 9999:59:59")
        messages.append("需要权限检查：成功 \(count)，失败 \(count)，无需卸载 \(count)，未执行 \(count)；退出码 77；进度 100.0%；卸载总用时 9999:59:59")
        fitLabel(label, reserving: messages, maximumWidth: maximumTextWidth - 152)
        let rowWidth = max(width, 152 + label.frame.width)
        let rowHeight = max(height, label.frame.height + 12)
        let row = NSView(frame: NSRect(x: 0, y: 0, width: rowWidth, height: rowHeight))
        let progress = NSProgressIndicator(frame: NSRect(x: 0, y: (rowHeight - 14) / 2, width: 140, height: 14))
        progress.isIndeterminate = false
        progress.minValue = 0
        progress.maxValue = 1
        row.addSubview(progress)
        progressIndicator = progress
        label.frame = NSRect(x: 152, y: 6, width: rowWidth - 152, height: rowHeight - 12)
        label.autoresizingMask = [.width]
        row.addSubview(label)
        executionLabel = label
        return row
    }

    func makeLogPanel(width: CGFloat, height: CGFloat) -> NSView {
        let label = NSTextField(labelWithString: "实时日志（可选择文字并复制）")
        label.font = .systemFont(ofSize: 12, weight: .medium)
        fitLocalizedControl(label)
        let copy = NSButton(title: "复制日志", target: self, action: #selector(copyLogClicked))
        let reveal = NSButton(title: "日志文件", target: self, action: #selector(revealLogClicked))
        let follow = NSButton(checkboxWithTitle: "自动滚动", target: self, action: #selector(followLogChanged))
        follow.state = .on
        followLogButton = follow
        let buttons = [copy, reveal, follow]
        for button in buttons {
            button.font = .systemFont(ofSize: 11)
            fitLocalizedControl(button)
        }
        let buttonsWidth = buttons.reduce(CGFloat(0)) { $0 + $1.frame.width } + 16
        fitLocalizedControl(label, maximumWidth: maximumTextWidth - buttonsWidth - 12)
        let minimumWidth = ceil(label.frame.width) + 12 + buttons.reduce(CGFloat(0)) { $0 + $1.frame.width } + 16
        let panelWidth = max(width, minimumWidth)
        let panel = NSView(frame: NSRect(x: 0, y: 0, width: panelWidth, height: height))
        let toolbarHeight = max(32, label.frame.height + 8, (buttons.map { $0.frame.height }.max() ?? 0) + 8)
        label.frame = NSRect(x: 0, y: height - 4 - label.frame.height, width: ceil(label.frame.width), height: label.frame.height)
        label.autoresizingMask = [.minYMargin]
        panel.addSubview(label)
        var right = panelWidth
        for button in buttons {
            right -= button.frame.width
            button.setFrameOrigin(NSPoint(x: right, y: height - 4 - button.frame.height))
            button.autoresizingMask = [.minXMargin, .minYMargin]
            panel.addSubview(button)
            right -= 8
        }
        if let previous = logScrollView {
            NotificationCenter.default.removeObserver(self, name: NSScrollView.willStartLiveScrollNotification, object: previous)
        }
        let scroll = ManagerLogScrollView(frame: NSRect(x: 0, y: 0, width: panelWidth, height: height - toolbarHeight))
        scroll.manualScroll = { [weak self] in
            self?.pauseLogFollowing()
        }
        scroll.appearanceChanged = { [weak self] in
            guard let self, self.preferences.theme == "system" else {
                return
            }
            self.applyLogPalette()
        }
        scroll.usesPredominantAxisScrolling = false
        scroll.drawsBackground = true
        scroll.backgroundColor = logPalette.background
        NotificationCenter.default.addObserver(self, selector: #selector(logWillStartLiveScroll(_:)),
                                               name: NSScrollView.willStartLiveScrollNotification, object: scroll)
        logScrollView = scroll
        scroll.autoresizingMask = [.width, .height]
        scroll.borderType = .bezelBorder
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        let text = ManagerLogTextView(frame: scroll.contentView.bounds)
        text.preferences = preferences
        text.manualScroll = { [weak self] in
            self?.pauseLogFollowing()
        }
        text.isEditable = false
        text.isSelectable = true
        text.isRichText = false
        text.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        text.textColor = logPalette.foreground(.normal)
        text.backgroundColor = logPalette.background
        text.isVerticallyResizable = true
        text.isHorizontallyResizable = true
        text.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        text.textContainer?.widthTracksTextView = false
        text.minSize = NSSize(width: scroll.contentSize.width, height: scroll.contentSize.height)
        text.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        scroll.documentView = text
        logTextView = text
        panel.addSubview(scroll)
        return panel
    }

    private var logPalette: ManagerLogPalette {
        let dark: Bool
        switch preferences.theme {
        case "dark":
            dark = true
        case "light":
            dark = false
        default:
            dark = (window?.effectiveAppearance ?? NSApplication.shared.effectiveAppearance).bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        }
        return ManagerLogPalette(dark: dark)
    }

    func pauseLogFollowing() {
        followLogButton?.state = .off
    }

    @objc func logWillStartLiveScroll(_ notification: Notification) {
        guard notification.object as? NSScrollView === logScrollView else {
            return
        }
        pauseLogFollowing()
    }

    @objc func followLogChanged() {
        if followLogButton?.state == .on {
            logTextView?.scrollToEndOfDocument(nil)
        }
    }

    @objc func copyLogClicked() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(logTextView?.string ?? "", forType: .string)
    }

    @objc func revealLogClicked() {
        if let logURL {
            NSWorkspace.shared.activateFileViewerSelecting([logURL])
        }
    }

    @objc func failedStatusClicked(_ gesture: NSClickGestureRecognizer) {
        guard gesture.isEnabled, let label = gesture.view as? NSTextField,
              !label.isHiddenOrHasHiddenAncestor,
              let identifier = label.identifier?.rawValue,
              statusLabels[identifier] === label, featureStates[identifier] == "failed",
              let url = logURL else {
            return
        }
        do {
            try logHandle?.synchronize()
            try ManagerLogTerminal.validate(url)
        } catch {
            presentLogError(error.localizedDescription)
            return
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                try ManagerLogTerminal.open(url)
            } catch {
                DispatchQueue.main.async { [weak self] in
                    self?.presentLogError(error.localizedDescription)
                }
            }
        }
    }

    func presentLogError(_ message: String) {
        if let logErrorPresenter {
            logErrorPresenter(message)
            return
        }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = preferences.text("无法查看本次日志")
        alert.informativeText = preferences.text(message)
        alert.addButton(withTitle: preferences.text("确定"))
        if let window, window.isVisible {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }

    func appendLog(_ message: String, kind: ManagerLogKind? = nil) {
        removeLiveOutput()
        let clean = ManagerLogStyling.plainText(message)
        if let data = clean.data(using: .utf8) {
            logHandle?.write(data)
        }
        guard let text = logTextView, let storage = text.textStorage else {
            return
        }
        storage.append(ManagerLogStyling.attributed(clean, palette: logPalette, kind: kind))
        // 保留完整磁盘日志，限制窗口文本量以免长编译日志拖慢交互。
        if storage.length > 600_000 {
            storage.deleteCharacters(in: NSRange(location: 0, length: storage.length - 500_000))
        }
        if followLogButton?.state == .on {
            text.scrollToEndOfDocument(nil)
        }
    }

    func removeLiveOutput() {
        if liveOutputLength > 0, let storage = logTextView?.textStorage {
            storage.deleteCharacters(in: NSRange(location: storage.length - liveOutputLength, length: liveOutputLength))
        }
        liveOutputLength = 0
    }

    func showLiveOutput(_ text: String) {
        removeLiveOutput()
        guard !text.isEmpty, !text.hasPrefix("JOBS_MANAGER_EVENT"), !"JOBS_MANAGER_EVENT".hasPrefix(text),
              !text.hasPrefix("JOBS_MANAGER_STOPPED"), !"JOBS_MANAGER_STOPPED".hasPrefix(text),
              !text.hasPrefix("JOBS_MANAGER_BLOCKED"), !"JOBS_MANAGER_BLOCKED".hasPrefix(text),
              let storage = logTextView?.textStorage else {
            return
        }
        let clean = ManagerLogStyling.plainText(text)
        let visible = String(clean.suffix(100_000))
        storage.append(ManagerLogStyling.attributed(visible, palette: logPalette))
        liveOutputLength = (visible as NSString).length
        if followLogButton?.state == .on {
            logTextView?.scrollToEndOfDocument(nil)
        }
    }

    func consumeOutputLine(_ line: String) {
        let parts = line.split(separator: "\t", maxSplits: 3, omittingEmptySubsequences: false).map(String.init)
        if parts.count >= 2, parts[0] == "JOBS_MANAGER_BLOCKED", parts[1] == "app-management" {
            appManagementBlocked = true
            let responsibleApp = ProcessInfo.processInfo.environment["JOBS_FINDER_RESPONSIBLE_APP"] ?? "Jobs右键菜单管理面板.app"
            appendLog("应用修改被权限阻止：请检查“隐私与安全性 → App 管理”授权及目标目录权限；负责应用：\(responsibleApp)。处理后重新执行，面板不会自动更改授权。\n")
            refreshSelectionState()
        } else if parts.first == "JOBS_MANAGER_STOPPED", activeWorkerAction == "install" {
            workerReportedStopped = true
            appendLog("已收到停止确认；当前安装单元已经完成。\n")
            refreshExecutionState()
        } else if parts.count >= 3, parts[0] == "JOBS_MANAGER_EVENT", runningIdentifiers.contains(parts[1]),
           ["running", "succeeded", "failed", "skipped", "not-installed"].contains(parts[2]),
           parts[2] != "not-installed" || activeWorkerAction == "uninstall" {
            featureStates[parts[1]] = parts[2]
            if parts.count == 4, !parts[3].isEmpty {
                let kind: ManagerLogKind = parts[2] == "failed" ? .error :
                    (parts[2] == "succeeded" ? .success : (parts[2] == "running" ? .info : .warning))
                appendLog(parts[3] + "\n", kind: kind)
            }
            refreshExecutionState()
        } else {
            appendLog(line + "\n")
        }
    }

    func startWorker(identifiers: [String], path: String, action: String? = nil) {
        guard !isRunning else {
            return
        }
        activeWorkerAction = action ?? managementAction
        lastWorkerAction = activeWorkerAction
        stopRequested = false
        workerReportedStopped = false
        appManagementBlocked = false
        stopRequestURL = nil
        executionTimer?.invalidate()
        executionTiming.hasStarted = true
        executionTiming.startedAt = ProcessInfo.processInfo.systemUptime
        executionTiming.elapsed = 0
        runningIdentifiers = identifiers
        featureStates = Dictionary(uniqueKeysWithValues: identifiers.map { ($0, "waiting") })
        lastExitStatus = nil
        logTextView?.string = ""
        liveOutputLength = 0
        try? logHandle?.close()
        let session = FileManager.default.temporaryDirectory.appendingPathComponent("JobsFinderManager-\(UUID().uuidString)", isDirectory: true)
        let url = session.appendingPathComponent("manager.log")
        do {
            try FileManager.default.createDirectory(at: session, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            guard FileManager.default.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
                throw NSError(domain: "JobsFinderManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "无法创建本次会话日志。"])
            }
            logURL = url
            logHandle = try FileHandle(forWritingTo: url)
            if activeWorkerAction == "install" {
                stopRequestURL = session.appendingPathComponent("stop-request")
            }
        } catch {
            appendLog("无法准备管理会话：\(error.localizedDescription)\n")
            finishWorker(exitStatus: 2)
            return
        }
        appendLog("\(executionActionTitle) \(identifiers.count) 项；日志文件：\(url.path)\n")
        appendLog("\(installLocationDescription)\n")
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        var arguments = [path, "--non-interactive", "--action", executionAction,
                         "--features", identifiers.joined(separator: ","),
                         "--install-location", installLocation]
        if let stopRequestURL {
            arguments += ["--stop-request-file", stopRequestURL.path]
        }
        let requestCleanup = activeWorkerAction == "install" && isCleanupOptionAvailable && cleanupBuildProducts
        if requestCleanup {
            arguments.append("--cleanup-build-products")
            appendLog("安装成功后清除此轮构建产物：已勾选。\n")
        }
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice
        var environment = ProcessInfo.processInfo.environment
        environment["NO_COLOR"] = "1"
        environment["CLICOLOR"] = "0"
        environment["TERM"] = "dumb"
        environment["NSUnbufferedIO"] = "YES"
        environment["JOBS_FINDER_CLEANUP_BUILD_PRODUCTS"] = requestCleanup ? "1" : "0"
        process.environment = environment
        worker = process
        refreshSelectionState()
        refreshExecutionState()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.refreshExecutionSummary()
        }
        executionTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        do {
            try process.run()
        } catch {
            appendLog("无法启动任务：\(error.localizedDescription)\n")
            finishWorker(exitStatus: 2)
            return
        }
        // 阻塞读和等待均留在后台；同一队列投递的输出先于结束状态处理。
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let decoder = ManagerOutputDecoder()
            while true {
                let data = pipe.fileHandleForReading.availableData
                if data.isEmpty {
                    break
                }
                let lines = decoder.append(data)
                let overflow = decoder.drainOverflow()
                let preview = decoder.preview
                DispatchQueue.main.async { [weak self] in
                    for line in lines {
                        self?.consumeOutputLine(line)
                    }
                    if !overflow.isEmpty {
                        self?.appendLog(overflow)
                    }
                    self?.showLiveOutput(preview)
                }
            }
            let tail = decoder.finish()
            process.waitUntilExit()
            DispatchQueue.main.async { [weak self] in
                for line in tail {
                    self?.consumeOutputLine(line)
                }
                self?.finishWorker(exitStatus: process.terminationStatus)
            }
        }
    }

    func finishWorker(exitStatus: Int32) {
        defer {
            localizeInterface()
        }
        let completedAction = executionAction
        let completedTimingTitle = timingTitle
        if let startedAt = executionTiming.startedAt {
            executionTiming.elapsed = max(0, ProcessInfo.processInfo.systemUptime - startedAt)
        }
        executionTiming.startedAt = nil
        let completedElapsed = executionTiming.elapsed
        executionTimer?.invalidate()
        executionTimer = nil
        lastExitStatus = exitStatus
        appManagementBlocked = appManagementBlocked || exitStatus == 77
        for identifier in runningIdentifiers where !["succeeded", "failed", "skipped", "not-installed"].contains(featureStates[identifier] ?? "") {
            featureStates[identifier] = workerReportedStopped || appManagementBlocked ? "skipped" : "failed"
        }
        worker = nil
        activeWorkerAction = nil
        lastWorkerAction = completedAction
        refreshSelectionState()
        refreshExecutionState()
        let succeeded = runningIdentifiers.filter { featureStates[$0] == "succeeded" }.count
        let failed = runningIdentifiers.filter { featureStates[$0] == "failed" }.count
        let skipped = runningIdentifiers.filter { featureStates[$0] == "skipped" }.count
        let notInstalled = runningIdentifiers.filter { featureStates[$0] == "not-installed" }.count
        let result = appManagementBlocked ? "需要权限检查" : (workerReportedStopped ? "已停止" : (exitStatus == 0 && failed == 0 ? "已完成" : "任务失败"))
        let percentage = completionPercentage(completed: succeeded + failed + notInstalled, total: runningIdentifiers.count)
        let notInstalledDescription = notInstalled > 0 ? "，无需卸载 \(notInstalled)" : ""
        let skippedDescription = skipped > 0 ? "，未执行 \(skipped)" : ""
        executionLabel?.stringValue = "\(result)：成功 \(succeeded)，失败 \(failed)\(notInstalledDescription)\(skippedDescription)；退出码 \(exitStatus)；进度 \(percentage)；\(completedTimingTitle)总用时 \(formattedElapsedTime(completedElapsed))"
        let summaryKind: ManagerLogKind
        if appManagementBlocked {
            summaryKind = .error
        } else if workerReportedStopped {
            summaryKind = .warning
        } else {
            summaryKind = exitStatus == 0 && failed == 0 ? .success : .error
        }
        appendLog("\n\(executionLabel?.stringValue ?? "")\n", kind: summaryKind)
        try? logHandle?.synchronize()
        try? logHandle?.close()
        logHandle = nil
    }

    func refreshExecutionState() {
        for checkbox in checkboxes {
            let identifier = checkbox.option.identifier
            let state = featureStates[identifier] ?? (checkbox.button.state == .on ? "selected" : "idle")
            let text: String
            let color: NSColor
            switch state {
            /// 尚未轮到当前菜单所属的安装单元。
            case "waiting":
                text = "等待中"
                color = .secondaryLabelColor
            /// 按本次操作展示正在处理的状态。
            case "running":
                let action = activeWorkerAction ?? lastWorkerAction ?? managementAction
                text = action == "cleanup" ? "清理中…" : (action == "uninstall" ? "卸载中…" : "安装中…")
                color = .systemBlue
            /// 业务明确完成后才展示绿色成功。
            case "succeeded":
                let action = activeWorkerAction ?? lastWorkerAction ?? managementAction
                text = action == "cleanup" ? "已清理" : (action == "uninstall" ? "已卸载" : "安装成功")
                color = .systemGreen
            /// 所选位置没有安装已完成核查，单独显示，不冒充删除成功。
            case "not-installed":
                text = "未安装，无需卸载"
                color = .secondaryLabelColor
            /// 用户停止或权限阻断后未开始的菜单。
            case "skipped":
                text = "未执行"
                color = .secondaryLabelColor
            /// 真实失败保留日志入口。
            case "failed":
                text = "失败，见日志"
                color = .systemRed
            /// 未开始执行时仅反映当前勾选状态。
            default:
                text = state == "selected" ? "已选择" : "未选择"
                color = .secondaryLabelColor
            }
            if let label = statusLabels[identifier] {
                let canOpenLog = state == "failed" && logURL != nil
                label.stringValue = text
                label.textColor = color
                label.attributedStringValue = NSAttributedString(string: text, attributes: [
                    .font: label.font ?? NSFont.systemFont(ofSize: 11),
                    .foregroundColor: color,
                    .underlineStyle: canOpenLog ? NSUnderlineStyle.single.rawValue : 0
                ])
                label.toolTip = canOpenLog ? logURL.map { "点击在新终端显示本次完整日志：\($0.path)" } : nil
                label.gestureRecognizers.forEach { $0.isEnabled = canOpenLog }
            }
            if let icon = statusIcons[identifier] {
                let symbol: String
                switch state {
                case "waiting":
                    symbol = "clock"
                case "succeeded":
                    symbol = "checkmark.circle.fill"
                case "failed":
                    symbol = "xmark.circle.fill"
                case "not-installed":
                    symbol = "minus.circle"
                case "skipped":
                    symbol = "pause.circle"
                case "selected":
                    symbol = "checkmark.circle"
                default:
                    symbol = "circle"
                }
                icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
                icon.contentTintColor = color
                icon.isHidden = state == "running"
            }
            if state == "running" {
                activityIndicators[identifier]?.startAnimation(nil)
            } else {
                activityIndicators[identifier]?.stopAnimation(nil)
            }
        }
        let completed = runningIdentifiers.filter { ["succeeded", "failed", "not-installed"].contains(featureStates[$0] ?? "") }.count
        progressIndicator?.maxValue = Double(max(1, runningIdentifiers.count))
        progressIndicator?.doubleValue = Double(completed)
        refreshExecutionSummary()
    }

    /// 计时独立于日志输出刷新，长时间编译无输出时仍显示实际等待时间。
    func refreshExecutionSummary() {
        defer {
            localizeInterface()
        }
        if isRunning {
            let completed = runningIdentifiers.filter { ["succeeded", "failed", "not-installed"].contains(featureStates[$0] ?? "") }.count
            let elapsed = executionTiming.startedAt.map { max(0, ProcessInfo.processInfo.systemUptime - $0) } ?? executionTiming.elapsed
            let percentage = completionPercentage(completed: completed, total: runningIdentifiers.count)
            if stopRequested && activeWorkerAction == "install" {
                executionLabel?.stringValue = "正在完成当前功能，随后停止；安装用时 \(formattedElapsedTime(elapsed))"
                return
            }
            executionLabel?.stringValue = "\(executionActionTitle)中；已处理 \(completed) / \(runningIdentifiers.count) 项（\(percentage)，按完成项计数）；\(timingTitle)用时 \(formattedElapsedTime(elapsed))"
        } else if lastExitStatus == nil {
            executionLabel?.stringValue = executionTiming.hasStarted
                ? "\(actionTitle)就绪；\(timingTitle)用时 \(formattedElapsedTime(executionTiming.elapsed))"
                : "\(actionTitle)就绪"
        }
    }

    func completionPercentage(completed: Int, total: Int) -> String {
        let percentage = total > 0 ? Double(min(max(0, completed), total)) / Double(total) * 100 : 0
        return String(format: "%.1f%%", locale: Locale(identifier: "en_US_POSIX"), percentage)
    }

    /// 小时持续累加，超过一天也不会回到零。
    func formattedElapsedTime(_ elapsed: TimeInterval) -> String {
        let seconds = Int(max(0, elapsed))
        return String(format: "%02d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
    }

    @objc func actionChanged() {
        guard !isRunning else {
            return
        }
        let nextAction = actionControl?.selectedSegment == 1 ? "uninstall" : "install"
        guard nextAction != managementAction else {
            return
        }
        managementAction = nextAction
        runningIdentifiers.removeAll()
        featureStates.removeAll()
        lastExitStatus = nil
        lastWorkerAction = nil
        refreshSelectionState()
    }

    private var installLocationDescription: String {
        return installLocation == "applications"
            ? "联合 App：Jobs自定义右键菜单.app；位置：/Applications/Jobs自定义右键菜单.app（安装成功后可清理构建产物）"
            : "当前目标：构建目录（原有方式；清理构建产物会影响功能）。"
    }

    private var isCleanupOptionAvailable: Bool {
        return managerPath != nil && installLocation == "applications" && managementAction == "install"
    }

    /// 卸载仅隐藏自动清理，保留本次选择供返回安装时恢复；构建目录仍撤回清理。
    func refreshCleanupBuildProductsOption() {
        if managerPath == nil || installLocation != "applications" {
            cleanupBuildProducts = false
        }
        cleanupBuildProductsButton?.state = cleanupBuildProducts ? .on : .off
        cleanupBuildProductsButton?.isHidden = !isCleanupOptionAvailable
        cleanupBuildProductsButton?.isEnabled = isCleanupOptionAvailable && !isRunning
        let standaloneAvailable = managerPath != nil && installLocation == "applications"
        // 保留入口可发现性；构建目录仍执行原有禁用保护。
        cleanupNowButton?.isHidden = managerPath == nil
        cleanupNowButton?.isEnabled = standaloneAvailable && !isRunning && !checkedIdentifiers().isEmpty
        cleanupNowButton?.toolTip = standaloneAvailable
            ? "只清理当前勾选功能的构建产物，不执行安装或卸载。"
            : installLocationDescription
        cleanupNowButton?.layer?.opacity = cleanupNowButton?.isEnabled == true ? 1 : 0.55
        privacySettingsButton?.isHidden = !appManagementBlocked
        privacySettingsButton?.isEnabled = appManagementBlocked && !isRunning
        if let row = buttonRow {
            layoutButtonRow(row)
        }
    }

    @objc func cleanupBuildProductsChanged() {
        guard isCleanupOptionAvailable && !isRunning else {
            refreshCleanupBuildProductsOption()
            return
        }
        cleanupBuildProducts = cleanupBuildProductsButton?.state == .on
    }

    /// 更换位置只清除上一目标的执行结果，保留本次勾选与独立操作计时。
    @objc func installLocationChanged() {
        guard !isRunning else {
            installLocationButton?.state = installLocation == "applications" ? .on : .off
            return
        }
        installLocation = installLocationButton?.state == .on ? "applications" : "build"
        installLocationLabel?.stringValue = installLocationDescription
        runningIdentifiers.removeAll()
        featureStates.removeAll()
        lastExitStatus = nil
        lastWorkerAction = nil
        refreshSelectionState()
    }

    @objc func selectionChanged() {
        refreshSelectionState()
    }

    @objc func selectAllClicked() {
        checkboxes.forEach {
            $0.button.state = .on
        }
        refreshSelectionState()
    }

    @objc func clearAllClicked() {
        checkboxes.forEach {
            $0.button.state = .off
        }
        refreshSelectionState()
    }

    @objc func selectGroupClicked(_ sender: NSButton) {
        setGroupSelection(sender, state: .on)
    }

    @objc func clearGroupClicked(_ sender: NSButton) {
        setGroupSelection(sender, state: .off)
    }

    func setGroupSelection(_ sender: NSButton, state: NSControl.StateValue) {
        guard let group = visibleGroups.first(where: { $0.identifier == sender.identifier?.rawValue }) else {
            return
        }
        let identifiers = Set(group.identifiers)
        for checkbox in checkboxes where identifiers.contains(checkbox.option.identifier) {
            checkbox.button.state = state
        }
        refreshSelectionState()
    }

    /// 只打开系统设置；添加与启用授权必须由用户在系统界面完成。
    @objc func openPrivacySettingsClicked() {
        guard appManagementBlocked, !isRunning else {
            return
        }
        if let privacySettingsOpener {
            privacySettingsOpener()
            return
        }
        if !NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app")) {
            appendLog("无法打开系统设置，请手动进入“隐私与安全性 → App 管理”。\n")
        }
    }

    /// 独立清理只使用当前功能选择，不改变安装 / 卸载页签及其计时。
    @objc func cleanupNowClicked() {
        guard !isRunning, installLocation == "applications", let managerPath else {
            return
        }
        let identifiers = checkedIdentifiers()
        guard !identifiers.isEmpty else {
            return
        }
        startWorker(identifiers: identifiers, path: managerPath, action: "cleanup")
    }

    /// 停止仅提交合作式请求；当前构建或登记单元可以正常收尾。
    func requestInstallationStop() {
        guard isRunning, activeWorkerAction == "install", !stopRequested, let stopRequestURL else {
            return
        }
        do {
            try Data("stop\n".utf8).write(to: stopRequestURL, options: .withoutOverwriting)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: stopRequestURL.path)
            stopRequested = true
            appendLog("已请求停止安装；正在完成当前功能，随后停止。\n")
            refreshSelectionState()
        } catch {
            appendLog("无法提交停止请求：\(error.localizedDescription)\n")
        }
    }

    @objc func installClicked() {
        if isRunning {
            requestInstallationStop()
            return
        }
        let identifiers = checkedIdentifiers()
        guard !identifiers.isEmpty else {
            return
        }
        if let managerPath {
            startWorker(identifiers: identifiers, path: managerPath)
            return
        }
        outcome = .selected(managementAction, identifiers)
        NSApplication.shared.stop(nil)
    }

    @objc func cancelClicked() {
        requestPanelClose()
    }

    func checkedIdentifiers() -> [String] {
        let selected = Set(checkboxes
            .filter { $0.button.state == .on }
            .map { $0.option.identifier })
        return FeatureOption.all.map { $0.identifier }.filter { selected.contains($0) }
    }

    func refreshSelectionState() {
        let checkedCount = checkboxes.filter { $0.button.state == .on }.count
        let canStop = isRunning && activeWorkerAction == "install"
        installButton?.title = canStop ? (stopRequested ? "停止中…" : "停止安装") : actionTitle
        installButton?.isEnabled = canStop ? !stopRequested : (checkedCount > 0 && !isRunning)
        clearButton?.isEnabled = checkedCount > 0 && !isRunning
        selectAllButton?.isEnabled = checkedCount < checkboxes.count && !isRunning
        actionControl?.isEnabled = !isRunning
        installLocationButton?.isEnabled = !isRunning
        refreshCleanupBuildProductsOption()
        closeButton?.isEnabled = true
        for checkbox in checkboxes {
            checkbox.button.isEnabled = !isRunning
        }
        summaryLabel?.stringValue = "已选 \(checkedCount) / \(checkboxes.count) 项；空选不能执行，切换操作保留勾选。"
        for controls in groupControls {
            let identifiers = Set(controls.group.identifiers)
            let count = checkboxes.filter { identifiers.contains($0.option.identifier) && $0.button.state == .on }.count
            controls.select.isEnabled = count < identifiers.count && !isRunning
            controls.clear.isEnabled = count > 0 && !isRunning
            controls.summary.stringValue = "已选 \(count) / \(identifiers.count)"
        }
        refreshExecutionState()
    }
}
// MARK: - Panel preferences

/// 总面板与独立包共用偏好；测试可注入独立 suite，不改用户设置。
final class ManagerPanelPreferences {

    static let shared = ManagerPanelPreferences()
    static let domain = "com.jobs.finderextensions.managementpanel.preferences"
    static let themes = ["system", "dark", "light"]
    static let languages = ["system", "zh-Hans", "zh-Hant", "bo", "en", "ja", "fr", "es", "de", "ru", "ko"]
    static let languageNames = ["跟随系统", "简体中文", "繁體中文", "བོད་ཡིག", "English", "日本語", "Français", "Español", "Deutsch", "Русский", "한국어"]
    let defaults: UserDefaults
    var systemLanguages: () -> [String]
    private var translationCache: [String: String] = [:]

    init(defaults: UserDefaults = UserDefaults(suiteName: ManagerPanelPreferences.domain)!,
         systemLanguages: @escaping () -> [String] = {
             return UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?["AppleLanguages"] as? [String] ?? Locale.preferredLanguages
         }) {
        self.defaults = defaults
        self.systemLanguages = systemLanguages
    }

    var theme: String {
        get {
            let value = defaults.string(forKey: "theme") ?? "system"
            return Self.themes.contains(value) ? value : "system"
        }
        set {
            defaults.set(Self.themes.contains(newValue) ? newValue : "system", forKey: "theme")
        }
    }

    var language: String {
        get {
            let value = defaults.string(forKey: "language") ?? "system"
            return Self.languages.contains(value) ? value : "system"
        }
        set {
            defaults.set(Self.languages.contains(newValue) ? newValue : "system", forKey: "language")
        }
    }

    /// 稳定分组 ID 跨语言、模式和独立包共用；损坏／旧值只过滤失效 ID 并补齐新增组。
    static let defaultFeatureGroupColumns = [["ide", "git", "general", "ios", "simulators"], ["flutter"]]

    var featureGroupColumns: [[String]] {
        get {
            let stored = defaults.array(forKey: "featureGroupColumns.v1") as? [[String]]
            return Self.normalizedFeatureGroupColumns(stored ?? Self.defaultFeatureGroupColumns)
        }
        set {
            defaults.set(Self.normalizedFeatureGroupColumns(newValue), forKey: "featureGroupColumns.v1")
        }
    }

    static func normalizedFeatureGroupColumns(_ input: [[String]]) -> [[String]] {
        let allowed = Set(FeatureGroup.all.map { group in
            return group.identifier
        })
        var seen = Set<String>()
        var result = [Array<String>(), Array<String>()]
        for column in 0..<2 {
            for identifier in input.indices.contains(column) ? input[column] : [] {
                if allowed.contains(identifier), seen.insert(identifier).inserted {
                    result[column].append(identifier)
                }
            }
        }
        for (column, identifiers) in defaultFeatureGroupColumns.enumerated() {
            for identifier in identifiers where seen.insert(identifier).inserted {
                result[column].append(identifier)
            }
        }
        return result
    }

    var resolvedLanguage: String {
        return language == "system" ? Self.resolveLanguage(systemLanguages().first ?? "en") : language
    }

    static func resolveLanguage(_ identifier: String) -> String {
        let parts = identifier.lowercased().replacingOccurrences(of: "_", with: "-").split(separator: "-").map(String.init)
        guard parts.first == "zh" else {
            let base = parts.first ?? "en"
            return Self.languages.contains(base) ? base : "en"
        }
        if parts.contains("hant") {
            return "zh-Hant"
        }
        if parts.contains("hans") {
            return "zh-Hans"
        }
        return parts.contains(where: { ["tw", "hk", "mo"].contains($0) }) ? "zh-Hant" : "zh-Hans"
    }

    /// 固定产品名也是磁盘名称，繁体界面不改写其路径。
    static func traditional(_ source: String) -> String {
        let names = ["Jobs自定义右键菜单.app", "Jobs右键菜单管理面板.app", "简体中文", "繁體中文"]
        var text = source
        for (index, name) in names.enumerated() {
            text = text.replacingOccurrences(of: name, with: "__JOBS_NAME_\(index)__")
        }
        text = text.applyingTransform(StringTransform("Hans-Hant"), reverse: false) ?? text
        for (index, name) in names.enumerated() {
            text = text.replacingOccurrences(of: "__JOBS_NAME_\(index)__", with: name)
        }
        return text
    }

    private struct Translation {
        let source: String
        let english: String
        let expression: NSRegularExpression?
        let tokens: [String]
    }

    private static let translations: [Translation] = translationTable.split(separator: "\n").compactMap { line in
        let pair = line.split(separator: "|", maxSplits: 1).map(String.init)
        guard pair.count == 2 else {
            return nil
        }
        let tokenExpression = try! NSRegularExpression(pattern: #"\{\d+\}"#)
        let matches = tokenExpression.matches(in: pair[0], range: NSRange(pair[0].startIndex..., in: pair[0]))
        let tokens = matches.map { (pair[0] as NSString).substring(with: $0.range) }
        var pattern = NSRegularExpression.escapedPattern(for: pair[0])
        for token in tokens {
            pattern = pattern.replacingOccurrences(of: NSRegularExpression.escapedPattern(for: token), with: "(.*?)")
        }
        return Translation(source: pair[0], english: pair[1], expression: tokens.isEmpty ? nil : try! NSRegularExpression(pattern: "^" + pattern + "$", options: .dotMatchesLineSeparators), tokens: tokens)
    }

    func text(_ source: String, language: String? = nil) -> String {
        let language = language ?? resolvedLanguage
        guard language != "zh-Hans" else {
            return source
        }
        let key = language + "\u{0}" + source
        if let cached = translationCache[key] {
            return cached
        }
        let translated = translate(source, language: language)
        translationCache[key] = translated
        return translated
    }

    private func translate(_ source: String, language: String) -> String {
        if let entry = Self.translations.first(where: { $0.source == source }) {
            return translatedEntry(entry, language: language)
        }
        for entry in Self.translations where entry.expression != nil {
            guard let match = entry.expression?.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)) else {
                continue
            }
            var result = translatedEntry(entry, language: language)
            for (index, token) in entry.tokens.enumerated() {
                let argument = (source as NSString).substring(with: match.range(at: index + 1))
                // 插值默认当数据；只有固定动作名可作为界面短语翻译，路径原样保留。
                let value = Self.translations.first(where: { $0.tokens.isEmpty && $0.source == argument }).map {
                    translatedEntry($0, language: language)
                } ?? argument
                result = result.replacingOccurrences(of: token, with: value)
            }
            return result
        }
        return language == "zh-Hant" ? Self.traditional(source) : source
    }

    func variants(_ source: String) -> [String] {
        return Self.languages.filter { $0 != "system" }.map { text(source, language: $0) }
    }

    private func translatedEntry(_ entry: Translation, language: String) -> String {
        if language == "zh-Hant" {
            return Self.traditional(entry.source)
        }
        if language == "en" {
            return entry.english
        }
        return Self.additionalTranslations[language]?[entry.english] ?? entry.english
    }

    static func scriptFont(_ font: NSFont, language: String) -> NSFont {
        guard language == "bo" else {
            return font
        }
        let size = max(13, font.pointSize)
        return NSFont(name: "Kailasa", size: size) ?? NSFont(name: "Kokonor", size: size) ?? font
    }

    // 标准目录在构建时嵌入；运行中的独立面板不读取源码路径或外部翻译文件。
    private static let additionalTranslations: [String: [String: String]] = {
        return (try? JSONSerialization.jsonObject(with: Data(additionalTranslationsJSON.utf8))) as? [String: [String: String]] ?? [:]
    }()
    // JOBS_MANAGER_TRANSLATIONS_BEGIN
    private static let additionalTranslationsJSON = #"""
    {
      "bo": {
        "Update development environment (update)": "གསར་སྤེལ་ཁོར་ཡུག་གསར་བཅོས། (update)",
        "Total disk space": "གསོག་སྡུད་སྡེར་མའི་བར་སྟོང་བསྡོམས།",
        "Create script launcher": "སྒྲིག་ཡིག་འཕྲལ་འཇུག་བཟོ།",
        "Theme": "མངོན་ཚུལ།",
        "Language": "སྐད་ཡིག",
        "🎨 Theme": "🎨 མངོན་ཚུལ།",
        "🌐 Language": "🌐 སྐད་ཡིག",
        "Follow system": "མ་ལག་དང་བསྟུན་པ།",
        "Dark": "མཚན་མོ།",
        "Light": "ཉིན་མོ།",
        "Jobs Finder Extension Manager": "Jobs Finder རྒྱ་སྐྱེད་དོ་དམ་ཆས།",
        "Customize Finder Context Menu": "Finder གཡས་མཐེབ་འདེམས་ཐོ་སྒྲིག་འགོད།",
        "Close Manager": "དོ་དམ་ཆས་ཁ་རྒྱག",
        "Edit": "རྩོམ་སྒྲིག",
        "Copy": "འདྲ་བཤུས།",
        "Select all": "ཚང་མ་འདེམས།",
        "Clear all": "ཚང་མའི་འདེམས་རྟགས་སེལ།",
        "Close": "ཁ་རྒྱག",
        "OK": "གཏན་འཁེལ།",
        "Install": "སྒྲིག་འཇུག",
        "Install / Update": "སྒྲིག་འཇུག / གསར་བཅོས།",
        "Uninstall": "སྒྲིག་འཇུག་སུབ།",
        "Cleanup": "གཙང་སེལ།",
        "Clean build products": "བཟོ་སྐྲུན་ཐོན་རྫས་སུབ།",
        "🧹 Clean build products": "🧹 བཟོ་སྐྲུན་ཐོན་རྫས་སུབ།",
        "Stop installation": "སྒྲིག་འཇུག་མཚམས་འཇོག",
        "Stopping…": "མཚམས་འཇོག་བཞིན་པ།…",
        "Action: install / update or uninstall": "བྱ་བ། སྒྲིག་འཇུག / གསར་བཅོས་སམ་སྒྲིག་འཇུག་སུབ་པ།",
        "Uninstall removes selected menus only. Group selection affects its own group.": "འདེམས་པའི་འདེམས་ཐོ་ཁོ་ན་སུབ་ཀྱི་ཡོད། ཚོགས་པའི་ནང་གི་འདེམས་ཀས་ཚོགས་པ་དེ་ཁོ་ནར་ཕན་ནུས་ཐོན།",
        "Install / uninstall with the combined App in Applications": "ཉེར་སྤྱོད་དཀར་ཆག་ནང་གི་མཉམ་སྡེབ་ཉེར་སྤྱོད་བརྒྱུད་སྒྲིག་འཇུག / སུབ་པ།",
        "Install or uninstall the combined App in Applications": "ཉེར་སྤྱོད་དཀར་ཆག་ནང་གི་མཉམ་སྡེབ་ཉེར་སྤྱོད་བརྒྱུད་སྒྲིག་འཇུག་གམ་སུབ་པ།",
        "Selected: manage features in /Applications/Jobs自定义右键菜单.app. Otherwise use the build directory.": "འདེམས་རྟགས་ཡོད་ན། /Applications/Jobs自定义右键菜单.app ནང་འདེམས་པའི་བྱེད་ནུས་དོ་དམ་བྱེད། མེད་ན་བཟོ་སྐྲུན་དཀར་ཆག་སྤྱོད།",
        "Clean this build after successful installation": "སྒྲིག་འཇུག་ལེགས་འགྲུབ་རྗེས་ཐེངས་འདིའི་བཟོ་སྐྲུན་ཐོན་རྫས་སུབ།",
        "Clean this build only after the combined App is installed and verified in Applications. Keep failed builds.": "མཉམ་སྡེབ་ཉེར་སྤྱོད་དེ་ཉེར་སྤྱོད་དཀར་ཆག་ནང་སྒྲིག་འཇུག་དང་ར་སྤྲོད་ལེགས་འགྲུབ་རྗེས་ཁོ་ན་ཐེངས་འདིའི་ཐོན་རྫས་སུབ། ཕམ་པའི་བཟོ་སྐྲུན་ཉར།",
        "Clean build products of selected features without installing or uninstalling.": "འདེམས་པའི་བྱེད་ནུས་ཀྱི་བཟོ་སྐྲུན་ཐོན་རྫས་ཁོ་ན་གཙང་སེལ་བྱེད། སྒྲིག་འཇུག་གམ་སུབ་པ་མི་བྱེད།",
        "Clean selected features' build products": "འདེམས་པའི་བྱེད་ནུས་ཀྱི་བཟོ་སྐྲུན་ཐོན་རྫས་གཙང་སེལ།",
        "Open Privacy & Security": "སྒེར་གསང་དང་བདེ་འཇགས་སྒྲིག་འགོད་ཁ་ཕྱེ།",
        "Add and enable Jobs右键菜单管理面板.app in Privacy & Security → App Management. This only opens Settings.": "སྒེར་གསང་དང་བདེ་འཇགས་ → ཉེར་སྤྱོད་དོ་དམ་ནང་ Jobs右键菜单管理面板.app སྣོན་ནས་སྤྱོད་སྒོ་ཕྱེ། མཐེབ་འདིས་སྒྲིག་འགོད་ཁོ་ན་ཁ་ཕྱེ་བ་ཡིན།",
        "Target: build directory. Cleaning these products affects installed features.": "མིག་སྔའི་དམིགས་ཡུལ། བཟོ་སྐྲུན་དཀར་ཆག ཐོན་རྫས་དེ་དག་སུབ་ན་སྒྲིག་འཇུག་ཟིན་པའི་བྱེད་ནུས་ལ་གནོད་སྲིད།",
        "App: Jobs自定义右键菜单.app at /Applications/Jobs自定义右键菜单.app (build products can be cleaned after installation)": "མཉམ་སྡེབ་ཉེར་སྤྱོད། Jobs自定义右键菜单.app། གནས་ཡུལ། /Applications/Jobs自定义右键菜单.app (སྒྲིག་འཇུག་རྗེས་བཟོ་སྐྲུན་ཐོན་རྫས་སུབ་ཆོག)",
        "Drag the divider to resize the log. Features and logs scroll separately.": "མཚམས་འབྱེད་ཐིག་གོང་འོག་ཏུ་འདྲུད་ནས་ཟིན་ཐོའི་མཐོ་ཚད་སྒྱུར། བྱེད་ནུས་ཐོ་དང་ཟིན་ཐོ་སོ་སོར་འདྲིལ་ཆོག",
        "Feature list and live log divider": "བྱེད་ནུས་ཐོ་དང་དུས་ཐོག་ཟིན་ཐོའི་མཚམས་འབྱེད་ཐིག",
        "Live log (select and copy text)": "དུས་ཐོག་ཟིན་ཐོ། (ཡིག་གེ་འདེམས་ནས་འདྲ་བཤུས་བྱེད་ཆོག)",
        "Copy log": "ཟིན་ཐོ་འདྲ་བཤུས།",
        "Log file": "ཟིན་ཐོའི་ཡིག་ཆ།",
        "Auto-scroll": "རང་འགུལ་འདྲིལ་བ།",
        "Ready. Select features and choose an action.": "གྲ་སྒྲིག་ཚར། བྱེད་ནུས་འདེམས་ནས་བྱ་བའི་མཐེབ་གནོན།",
        "A task is running. Wait for it to finish before closing.": "ལས་འགན་འགྲོ་བཞིན་ཡོད། སྒྲིག་འཇུག་མི་ཆད་པའི་ཆེད་དུ་ལས་འགན་ཚར་རྗེས་ཁ་རྒྱག་རོགས།",
        "Unable to view this log": "ཐེངས་འདིའི་ཟིན་ཐོ་ལྟ་མི་ཐུབ།",
        "Log is missing or unreadable: {0}": "ཟིན་ཐོ་མེད་པའམ་ཀློག་མི་ཐུབ། {0}",
        "Unable to open log terminal: {0}": "ཟིན་ཐོའི་མཐའ་སྣེ་ཁ་ཕྱེ་མི་ཐུབ། {0}",
        "Click to show this session's full log in a new terminal: {0}": "ཐེངས་འདིའི་ཟིན་ཐོ་ཆ་ཚང་མཐའ་སྣེ་གསར་པར་སྟོན་པར་མནན། {0}",
        "Selected {0} / {1}. Select at least one. Changing action keeps selection.": "{0} / {1} འདེམས་ཟིན། ཉུང་མཐར་གཅིག་འདེམས་དགོས། བྱ་བ་བརྗེ་སྐབས་འདེམས་ཀ་ཉར།",
        "Selected {0} / {1}": "{0} / {1} འདེམས་ཟིན།",
        "{0}: select all": "{0}། ཚང་མ་འདེམས།",
        "{0}: clear all": "{0}། ཚང་མའི་འདེམས་རྟགས་སེལ།",
        "Waiting": "སྒུག་བཞིན་པ།",
        "Cleaning…": "གཙང་སེལ་བྱེད་བཞིན་པ།…",
        "Uninstalling…": "སྒྲིག་འཇུག་སུབ་བཞིན་པ།…",
        "Installing…": "སྒྲིག་འཇུག་བྱེད་བཞིན་པ།…",
        "Cleaned": "གཙང་སེལ་བྱས་ཟིན།",
        "Uninstalled": "སྒྲིག་འཇུག་སུབ་ཟིན།",
        "Installed": "སྒྲིག་འཇུག་ལེགས་འགྲུབ།",
        "Skipped": "ལག་བསྟར་མ་བྱས།",
        "Not installed; nothing to remove": "སྒྲིག་འཇུག་མ་བྱས་པས་སུབ་དགོས་མེད།",
        "Failed: see log": "ཕམ་པ། ཟིན་ཐོ་ལ་གཟིགས།",
        "Selected": "འདེམས་ཟིན།",
        "Not selected": "འདེམས་མེད།",
        "App Management permission required": "ཉེར་སྤྱོད་དོ་དམ་གྱི་ཆོག་མཆན་དགོས།",
        "Permission check required": "ཆོག་མཆན་ཞིབ་བཤེར་དགོས།",
        "Stopped": "མཚམས་བཞག་ཟིན།",
        "Completed": "ལེགས་འགྲུབ་ཟིན།",
        "Task failed": "ལས་འགན་ཕམ་པ།",
        "{0}: processed {1} / {2} ({3}, completed items); {4} time {5}": "{0} བྱེད་བཞིན་པ། {1} / {2} སྒྲུབ་ཟིན། ({3}། ཚར་བའི་གྲངས་ལྟར།) {4} ཡི་དུས་ཡུན། {5}",
        "{0} ready": "{0} གྲ་སྒྲིག་ཚར།",
        "{0} ready; {1} time {2}": "{0} གྲ་སྒྲིག་ཚར། {1} ཡི་དུས་ཡུན། {2}",
        "Finishing the current feature, then stopping; install time {0}": "མིག་སྔའི་བྱེད་ནུས་ཚར་རྗེས་མཚམས་འཇོག་རྒྱུ་ཡིན། སྒྲིག་འཇུག་དུས་ཡུན། {0}",
        "{0}: {1} succeeded, {2} failed, {3} skipped; exit {4}; {5}; {6} time {7}": "{0}། ལེགས་འགྲུབ་ {1}། ཕམ་པ་ {2}། ལག་བསྟར་མ་བྱས་ {3}། ཕྱིར་ཐོན་ཨང་ {4}། {5}། {6} ཡི་དུས་ཡུན་བསྡོམས་ {7}",
        "{0}: {1} succeeded, {2} failed, {3} not installed, {4} skipped; exit {5}; {6}; {7} time {8}": "{0}། ལེགས་འགྲུབ་ {1}། ཕམ་པ་ {2}། སྒྲིག་འཇུག་མ་བྱས་ {3}། ལག་བསྟར་མ་བྱས་ {4}། ཕྱིར་ཐོན་ཨང་ {5}། {6}། {7} ཡི་དུས་ཡུན་བསྡོམས་ {8}",
        "{0}: {1} succeeded, {2} failed, {3} not installed; exit {4}; {5}; {6} time {7}": "{0}། ལེགས་འགྲུབ་ {1}། ཕམ་པ་ {2}། སྒྲིག་འཇུག་མ་བྱས་ {3}། ཕྱིར་ཐོན་ཨང་ {4}། {5}། {6} ཡི་དུས་ཡུན་བསྡོམས་ {7}",
        "{0}: {1} succeeded, {2} failed; exit {3}; {4}; {5} time {6}": "{0}། ལེགས་འགྲུབ་ {1}། ཕམ་པ་ {2}། ཕྱིར་ཐོན་ཨང་ {3}། {4}། {5} ཡི་དུས་ཡུན་བསྡོམས་ {6}",
        "Open projects in IDEs": "IDE ནང་ལས་གཞི་ཁ་ཕྱེ་བ།",
        "Git tools": "Git ལག་ཆ།",
        "Files and general tools": "ཡིག་ཆ་དང་སྤྱི་སྤྱོད་ལག་ཆ།",
        "Flutter tools · submenu actions": "Flutter ལག་ཆ། · ཡན་ལག་འདེམས་ཐོའི་བྱ་བ།",
        "iOS / CocoaPods tools": "iOS / CocoaPods ལག་ཆ།",
        "Simulator tools": "ལད་ཟློས་ཆས་ཀྱི་ལག་ཆ།",
        "Open project in Android Studio": "Android Studio ནང་ལས་གཞི་ཁ་ཕྱེ།",
        "Open project in VSCode": "VSCode ནང་ལས་གཞི་ཁ་ཕྱེ།",
        "Open project in Xcode": "Xcode ནང་ལས་གཞི་ཁ་ཕྱེ།",
        "Pull latest Git changes": "Git གི་གསར་ཤོས་འགྱུར་བ་ལེན།",
        "Roll back Git commit": "Git འབུལ་བ་ཕྱིར་ལོག",
        "Open Git remote URL": "Git ཐག་རིང་མཛོད་ཀྱི་དྲ་གནས་ཁ་ཕྱེ།",
        "Copy Git remote URL": "Git ཐག་རིང་མཛོད་ཀྱི་དྲ་གནས་འདྲ་བཤུས།",
        "Copy absolute path": "ལྟོས་མེད་ལམ་བུ་འདྲ་བཤུས།",
        "Create file": "ཡིག་ཆ་གསར་བཟོ།",
        "View file fingerprint Hash (SHA-256)": "ཡིག་ཆའི་མཛུབ་རྗེས་ཨང་ (SHA-256) སྟོན།",
        "Hide / show selected items": "བདམས་པའི་རྣམ་གྲངས་སྦེད / སྟོན།",
        "Send to external disk or network volume": "ཕྱིའི་སྡེར་མའམ་དྲ་རྒྱའི་གསོག་སྡུད་སྡེ་ཚན་ལ་གཏོང་།",
        "Grant execute permission (chmod +x)": "ལག་བསྟར་ཆོག་མཆན་སྤྲོད། (chmod +x)",
        "Remove execute permission (chmod -x)": "ལག་བསྟར་ཆོག་མཆན་ཕྱིར་འཐེན། (chmod -x)",
        "Re-sign IPA without building": "སྒྲིག་སྒྱུར་མ་བྱས་པར་ IPA ལ་སླར་མིང་རྟགས་འགོད།",
        "Show / hide files": "ཡིག་ཆ་མངོན་པ་ / སྦེད་པ།",
        "Create iOS simulator": "iOS ལད་ཟློས་ཆས་གསར་བཟོ།",
        "Create Android simulator": "Android ལད་ཟློས་ཆས་གསར་བཟོ།",
        "Create Harmony simulator": "Harmony ལད་ཟློས་ཆས་གསར་བཟོ།",
        "Check / repair Android simulator": "Android ལད་ཟློས་ཆས་ཞིབ་བཤེར་ / ཉམས་གསོ།",
        "Check / repair Harmony simulator": "Harmony ལད་ཟློས་ཆས་ཞིབ་བཤེར་ / ཉམས་གསོ།",
        "Configure Git proxy": "Git གི་འགུལ་རྣམ་ལས་ཚབ་སྒྲིག་འགོད།",
        "Open in terminal": "མཐའ་སྣེ་ནང་ཁ་ཕྱེ།",
        "View file contents in terminal": "མཐའ་སྣེ་ནང་ཡིག་ཆའི་ནང་དོན་ལྟ།",
        "Merge file parts": "ཡིག་ཆའི་ཆ་ཤས་མཉམ་སྡེབ།",
        "Split file": "ཡིག་ཆ་ཁ་གྱེས།",
        "Clean Android / OpenHarmony builds": "Android / OpenHarmony བཟོ་སྐྲུན་ཐོན་རྫས་གཙང་སེལ།",
        "Update code map (.codegraph)": "ཚབ་ཨང་ས་ཁྲ་ (.codegraph) གསར་བཅོས།",
        "Create empty commit and push in terminal": "མཐའ་སྣེ་ནང་འབུལ་བ་སྟོང་པ་བཟོས་ནས་ཡར་སྐྱེལ།",
        "Disable CocoaPods build sandbox": "CocoaPods བཟོ་སྐྲུན་གྱི་ལོགས་འཇོག་ཁོར་ཡུག་སྒོ་རྒྱག",
        "Install CocoaPods": "CocoaPods སྒྲིག་འཇུག",
        "CocoaPods source: CDN → GitHub": "CocoaPods ཁུངས། CDN → GitHub",
        "Export all project Pod files": "ལས་གཞིའི་ Pod འབྲེལ་ཡོད་ཡིག་ཆ་ཚང་མ་ཕྱིར་འདྲེན།",
        "Inspect Xcode project dependencies": "Xcode ལས་གཞིའི་བརྟེན་འབྲེལ་ཞིབ་བཤེར།",
        "Update local CocoaPods repositories": "CocoaPods ཀྱི་རང་གནས་མཛོད་གསར་བཅོས།",
        "Check local Pod builds (.podspec folder)": "རང་གནས་ Pod སྒྲིག་སྒྱུར་ཐུབ་མིན་ཞིབ་བཤེར། (.podspec དཀར་ཆག་ཁོ་ན།)",
        "Install / update JobsCodeSnippets": "JobsCodeSnippets སྒྲིག་འཇུག / གསར་བཅོས།",
        "Clean iOS / Xcode builds": "iOS / Xcode བཟོ་སྐྲུན་ཐོན་རྫས་གཙང་སེལ།",
        "Set up Flutter project": "Flutter ལས་གཞི་སྒྲིག་འགོད།",
        "Run Flutter project in terminal": "མཐའ་སྣེ་ནང་ Flutter ལས་གཞི་ལག་བསྟར།",
        "Fetch Flutter Pub dependencies": "Flutter Pub བརྟེན་འབྲེལ་ལེན།",
        "Fetch native Android dependencies": "Android གི་ཐད་ཀའི་བརྟེན་འབྲེལ་ལེན།",
        "Fetch CocoaPods dependencies": "CocoaPods བརྟེན་འབྲེལ་ལེན།",
        "Fetch Swift Package dependencies": "Swift Package བརྟེན་འབྲེལ་ལེན།",
        "Fetch OpenHarmony dependencies": "OpenHarmony བརྟེན་འབྲེལ་ལེན།",
        "Prepare native libraries and build dependencies": "མ་ལག་ཐད་ཀའི་བྱ་རིམ་མཛོད་དང་བཟོ་སྐྲུན་བརྟེན་འབྲེལ་གྲ་སྒྲིག",
        "Download Flutter platform resources": "Flutter ལས་སྟེགས་ཐོན་ཁུངས་ཕབ་ལེན།",
        "Fetch Web project dependencies": "དྲ་ངོས་ལས་གཞིའི་བརྟེན་འབྲེལ་ལེན།",
        "🧳 Export Flutter dependencies": "🧳 Flutter བརྟེན་འབྲེལ་ཚང་མ་ཕྱིར་འདྲེན།",
        "Export Flutter Pub dependencies": "Flutter Pub བརྟེན་འབྲེལ་ཕྱིར་འདྲེན།",
        "🔐 Export private Flutter dependencies": "🔐 Flutter སྒེར་གྱི་མཛོད་བརྟེན་འབྲེལ་ཕྱིར་འདྲེན།",
        "📥 Import Flutter dependencies": "📥 Flutter བརྟེན་འབྲེལ་ཚང་མ་ནང་འདྲེན།",
        "Import Flutter Pub dependencies": "Flutter Pub བརྟེན་འབྲེལ་ནང་འདྲེན།",
        "📥 Import private Flutter dependencies": "📥 Flutter སྒེར་གྱི་མཛོད་བརྟེན་འབྲེལ་ནང་འདྲེན།",
        "Export Gradle distributions and cache": "Gradle འགྲེམས་སྤེལ་ཐུམ་བུ་དང་གནས་སྐབས་གསོག་འཇོག་ཕྱིར་འདྲེན།",
        "Import Gradle distributions and cache": "Gradle འགྲེམས་སྤེལ་ཐུམ་བུ་དང་གནས་སྐབས་གསོག་འཇོག་ནང་འདྲེན།",
        "Export CocoaPods dependencies": "CocoaPods བརྟེན་འབྲེལ་ཕྱིར་འདྲེན།",
        "Import CocoaPods dependencies": "CocoaPods བརྟེན་འབྲེལ་ནང་འདྲེན།",
        "Export Swift Package dependencies": "Swift Package བརྟེན་འབྲེལ་ཕྱིར་འདྲེན།",
        "Import Swift Package dependencies": "Swift Package བརྟེན་འབྲེལ་ནང་འདྲེན།",
        "Export OpenHarmony dependencies": "OpenHarmony བརྟེན་འབྲེལ་ཕྱིར་འདྲེན།",
        "Import OpenHarmony dependencies": "OpenHarmony བརྟེན་འབྲེལ་ནང་འདྲེན།",
        "Export native build cache": "མ་ལག་ཐད་ཀའི་བཟོ་སྐྲུན་གནས་སྐབས་གསོག་འཇོག་ཕྱིར་འདྲེན།",
        "Import native build cache": "མ་ལག་ཐད་ཀའི་བཟོ་སྐྲུན་གནས་སྐབས་གསོག་འཇོག་ནང་འདྲེན།",
        "Export Flutter platform resources": "Flutter ལས་སྟེགས་ཐོན་ཁུངས་ཕྱིར་འདྲེན།",
        "Import Flutter platform resources": "Flutter ལས་སྟེགས་ཐོན་ཁུངས་ནང་འདྲེན།",
        "Export Web dependencies": "དྲ་ངོས་བརྟེན་འབྲེལ་ཕྱིར་འདྲེན།",
        "Import Web dependencies": "དྲ་ངོས་བརྟེན་འབྲེལ་ནང་འདྲེན།",
        "Show Flutter project SDK version": "Flutter ལས་གཞིའི་ SDK པར་གཞི་སྟོན།",
        "Install / switch Flutter SDK": "Flutter SDK སྒྲིག་འཇུག / བརྗེ་བ།",
        "Install / switch Flutter@OpenHarmony SDK": "Flutter@OpenHarmony SDK སྒྲིག་འཇུག / བརྗེ་བ།",
        "Install / switch Java SDK": "Java SDK སྒྲིག་འཇུག / བརྗེ་བ།",
        "Download Gradle distributions and plugins": "Gradle འགྲེམས་སྤེལ་ཐུམ་བུ་དང་བཟོ་སྐྲུན་བསྒར་ལྷུ་ཕབ་ལེན།",
        "Generate Flutter code": "Flutter ཚབ་ཨང་རང་འགུལ་གསར་བཟོ།",
        "Package iOS": "iOS ཐུམ་བུ་བཟོ།",
        "Package Android": "Android ཐུམ་བུ་བཟོ།",
        "Package Harmony (HAP + APP)": "Harmony ཐུམ་བུ་བཟོ། (HAP + APP)",
        "Check native Flutter project": "ཐད་ཀའི་ Flutter ལས་གཞིའི་བདེ་ཐང་ཞིབ་བཤེར།",
        "Check OpenHarmony Flutter environment": "OpenHarmony Flutter ཁོར་ཡུག་གི་བདེ་ཐང་ཞིབ་བཤེར།",
        "Repair missing Android SDK / platforms": "ཆད་པའི་ Android SDK / ལས་སྟེགས་ཉམས་གསོ།",
        "Repair Chinese Flutter project paths": "Flutter ལས་གཞིའི་རྒྱ་ཡིག་ལམ་བུ་ཉམས་གསོ།",
        "Repair Flutter plugin namespaces": "Flutter བསྒར་ལྷུའི་ namespace ཉམས་གསོ།",
        "Convert relative Dart imports to packages": "Dart འབྲེལ་ལྟོས་ནང་འདྲེན་ package འདྲེན་སྟངས་སུ་སྒྱུར།",
        "Clean current Flutter project builds": "ད་ལྟའི་ Flutter ལས་གཞིའི་བཟོ་སྐྲུན་ཐོན་རྫས་གཙང་སེལ།",
        "Dependency and cache maintenance": "བརྟེན་འབྲེལ་དང་གནས་སྐབས་གསོག་འཇོག་ཉམས་གསོ།",
        "Custom Explorer context menu": "Explorer གཡས་མཐེབ་འདེམས་ཐོ་རང་སྒྲིག",
        "Jobs Windows · Custom Explorer context menu": "Jobs Windows · Explorer གཡས་མཐེབ་འདེམས་ཐོ་རང་སྒྲིག",
        "Show a regular file's SHA-256 in a new terminal and copy the digest; do not modify or execute the file.": "མཐའ་སྣེ་གསར་པའི་ནང་རྒྱུན་ལྡན་ཡིག་ཆ་གཅིག་གི་ SHA-256 སྟོན་ཞིང་དེའི་གནས་ཐང་འདྲ་བཤུས་བྱེད། ཡིག་ཆ་བཟོ་བཅོས་དང་ལག་བསྟར་མི་བྱེད།",
        " (preview)": "（སྔོན་ལྟ་ཙམ）",
        "⏪ Roll back Git commits": "⏪ Git འབུལ་བ་ཕྱིར་ལོག",
        "▶️ Run Flutter project in terminal": "▶️ མཐའ་སྣེ་ནང་ Flutter ལས་གཞི་ལག་བསྟར།",
        "☕ Install / switch Java SDK": "☕ Java SDK སྒྲིག་འཇུག / བརྗེ་བ།",
        "♻️ Flutter cleanup and maintenance": "♻️ Flutter གཙང་སེལ་དང་ཉམས་གསོ།",
        "⚙️ Generate Flutter code": "⚙️ Flutter ཚབ་ཨང་རང་འགུལ་གསར་བཟོ།",
        "✅ Installed": "✅ སྒྲིག་འཇུག་ལེགས་འགྲུབ།",
        "⬇️ Pull latest Git changes": "⬇️ Git གསར་ཤོས་ཀྱི་འགྱུར་བ་ལེན།",
        "🌈 Create Harmony emulator": "🌈 Harmony ལད་མོའི་འཕྲུལ་ཆས་གསར་བཟོ།",
        "🌐 Open Git remote URL": "🌐 Git རྒྱང་སྦྲེལ་དྲ་གནས་ཁ་ཕྱེ།",
        "🌐 Fetch Web project dependencies": "🌐 དྲ་ངོས་ལས་གཞིའི་བརྟེན་འབྲེལ་ལེན།",
        "🌳 Open in Sourcetree": "🌳 Sourcetree ནང་ཁ་ཕྱེ།",
        "🏥 Flutter project diagnostics": "🏥 Flutter ལས་གཞིའི་བདེ་ཐང་ཞིབ་བཤེར།",
        "🏥 Flutter diagnostics": "🏥 Flutter བདེ་ཐང་ཞིབ་བཤེར།",
        "🏷️ Repair Flutter plugin namespaces": "🏷️ Flutter བསྒར་ལྷུའི་ namespace ཉམས་གསོ།",
        "👁️ Show / hide hidden files": "👁️ སྦས་པའི་ཡིག་ཆ་སྟོན / སྦེད།",
        "💓 OpenHarmony Flutter diagnostics": "💓 OpenHarmony Flutter ཁོར་ཡུག་གི་བདེ་ཐང་ཞིབ་བཤེར།",
        "💠 Open project in Visual Studio": "💠 Visual Studio ནང་ལས་གཞི་ཁ་ཕྱེ།",
        "💻 Open in terminal": "💻 མཐའ་སྣེ་ནང་ཁ་ཕྱེ།",
        "📄 View file in terminal": "📄 མཐའ་སྣེ་ནང་ཡིག་ཆ་ལྟ་བ།",
        "📋 Copy absolute path": "📋 ངེས་གཏན་ལམ་བུ་འདྲ་བཤུས།",
        "📚 Download Gradle distributions and build plugins": "📚 Gradle འགྲེམས་སྤེལ་ཐུམ་བུ་དང་བཟོ་སྐྲུན་བསྒར་ལྷུ་ཕབ་ལེན།",
        "📝 Open project in VSCode": "📝 VSCode ནང་ལས་གཞི་ཁ་ཕྱེ།",
        "📡 Configure Git dynamic proxy": "📡 Git འགུལ་རྣམ་ཚབ་སྦྲེལ་སྒྲིག་འགོད།",
        "📤 Import Flutter Pub dependencies": "📤 Flutter Pub བརྟེན་འབྲེལ་ནང་འདྲེན།",
        "📤 Import Flutter platform assets": "📤 Flutter ལས་སྟེགས་ཐོན་ཁུངས་ནང་འདྲེན།",
        "📤 Import Gradle distributions and dependency caches": "📤 Gradle འགྲེམས་སྤེལ་ཐུམ་བུ་དང་བརྟེན་འབྲེལ་གནས་སྐབས་གསོག་འཇོག་ནང་འདྲེན།",
        "📤 Import OpenHarmony dependencies": "📤 OpenHarmony བརྟེན་འབྲེལ་ནང་འདྲེན།",
        "📤 Import Web dependencies": "📤 དྲ་ངོས་བརྟེན་འབྲེལ་ནང་འདྲེན།",
        "📤 Import native build caches": "📤 མ་ལག་ཐད་ཀའི་བཟོ་སྐྲུན་གནས་སྐབས་གསོག་འཇོག་ནང་འདྲེན།",
        "📤 Import Flutter project dependencies": "📤 Flutter ལས་གཞིའི་བརྟེན་འབྲེལ་ནང་འདྲེན།",
        "📤 Create empty commit and push": "📤 ནང་དོན་མེད་པའི་འབུལ་བ་བཟོས་ཏེ་ཕར་སྐྱེལ།",
        "📥 Install Flutter dependencies (pub get)": "📥 Flutter བརྟེན་འབྲེལ་སྒྲིག་འཇུག (pub get)",
        "📥 Import private Flutter project dependencies": "📥 Flutter ལས་གཞིའི་སྒེར་གྱི་མཛོད་བརྟེན་འབྲེལ་ནང་འདྲེན།",
        "📥 Fetch Flutter Pub dependencies": "📥 Flutter Pub བརྟེན་འབྲེལ་ལེན།",
        "📥 Fetch Flutter project dependencies": "📥 Flutter ལས་གཞིའི་བརྟེན་འབྲེལ་ལེན།",
        "📦 Package Flutter project": "📦 Flutter ལས་གཞི་ཐུམ་བུ་བཟོ།",
        "📦 Package HarmonyOS (HAP + APP)": "📦 HarmonyOS ཐུམ་བུ་བཟོ། (HAP + APP)",
        "📱 Create Android emulator": "📱 Android ལད་མོའི་འཕྲུལ་ཆས་གསར་བཟོ།",
        "🔀 Install / switch Flutter SDK (FVM)": "🔀 Flutter SDK སྒྲིག་འཇུག / བརྗེ་བ། (FVM)",
        "🔀 Install / switch Flutter SDK": "🔀 Flutter SDK སྒྲིག་འཇུག / བརྗེ་བ།",
        "🔀 Install / switch Flutter environments": "🔀 Flutter ལག་བསྟར་ཁོར་ཡུག་སྒྲིག་འཇུག / བརྗེ་བ།",
        "🔎 Show current Flutter SDK version": "🔎 ད་ལྟའི་ Flutter SDK པར་གཞི་སྟོན།",
        "🔎 Show current Flutter project's SDK version": "🔎 ད་ལྟའི་ Flutter ལས་གཞིའི་ SDK པར་གཞི་སྟོན།",
        "🔐 Export private Flutter project dependencies": "🔐 Flutter ལས་གཞིའི་སྒེར་གྱི་མཛོད་བརྟེན་འབྲེལ་ཕྱིར་འདྲེན།",
        "🔎 Show file fingerprint Hash (SHA-256)": "🔎 ཡིག་ཆའི་མཛུབ་རྗེས་ Hash སྟོན། (SHA-256)",
        "➕ Grant execute permission": "➕ ལག་བསྟར་ཆོག་མཆན་སྤྲོད།",
        "➖ Remove execute permission": "➖ ལག་བསྟར་ཆོག་མཆན་སེལ།",
        "🔒 Grant execute permission": "🔒 ལག་བསྟར་ཆོག་མཆན་སྤྲོད།",
        "🔓 Remove execute permission": "🔓 ལག་བསྟར་ཆོག་མཆན་སེལ།",
        "🔗 Copy Git remote URL": "🔗 Git རྒྱང་སྦྲེལ་དྲ་གནས་འདྲ་བཤུས།",
        "🔧 Flutter repairs": "🔧 Flutter ལས་གཞི་ཉམས་གསོ།",
        "🕊️ Install / switch Flutter@OpenHarmony SDK": "🕊️ Flutter@OpenHarmony SDK སྒྲིག་འཇུག / བརྗེ་བ།",
        "🕊️ Fetch OpenHarmony dependencies": "🕊️ OpenHarmony བརྟེན་འབྲེལ་ལེན།",
        "🗃️ Download Flutter platform assets": "🗃️ Flutter ལས་སྟེགས་ཐོན་ཁུངས་ཕབ་ལེན།",
        "🗺️ Update code map (.codegraph)": "🗺️ ཚབ་ཨང་ས་ཁྲ་གསར་སྒྱུར། (.codegraph)",
        "🤖 Fetch Android native dependencies": "🤖 Android གི་ཐད་ཀའི་བརྟེན་འབྲེལ་ལེན།",
        "🦋 Flutter development": "🦋 Flutter འཕེལ་བཟོའི་རམ་འདེགས།",
        "🦋 Flutter development tools": "🦋 Flutter འཕེལ་བཟོའི་རམ་འདེགས་ལག་ཆ།",
        "🧑‍⚕️ Native Flutter diagnostics": "🧑‍⚕️ ཐད་ཀའི་ Flutter ལས་གཞིའི་བདེ་ཐང་ཞིབ་བཤེར།",
        "🧩 Export Flutter Pub dependencies": "🧩 Flutter Pub བརྟེན་འབྲེལ་ཕྱིར་འདྲེན།",
        "🧩 Export Flutter platform assets": "🧩 Flutter ལས་སྟེགས་ཐོན་ཁུངས་ཕྱིར་འདྲེན།",
        "🧩 Export Flutter third-party dependencies": "🧩 Flutter ཕྱི་ཕྱོགས་བརྟེན་འབྲེལ་ཕྱིར་འདྲེན།",
        "🧩 Export Gradle distributions and dependency caches": "🧩 Gradle འགྲེམས་སྤེལ་ཐུམ་བུ་དང་བརྟེན་འབྲེལ་གནས་སྐབས་གསོག་འཇོག་ཕྱིར་འདྲེན།",
        "🧩 Export OpenHarmony dependencies": "🧩 OpenHarmony བརྟེན་འབྲེལ་ཕྱིར་འདྲེན།",
        "🧩 Export Web dependencies": "🧩 དྲ་ངོས་བརྟེན་འབྲེལ་ཕྱིར་འདྲེན།",
        "🧩 Export native build caches": "🧩 མ་ལག་ཐད་ཀའི་བཟོ་སྐྲུན་གནས་སྐབས་གསོག་འཇོག་ཕྱིར་འདྲེན།",
        "🧩 Export Flutter project dependencies": "🧩 Flutter ལས་གཞིའི་བརྟེན་འབྲེལ་ཕྱིར་འདྲེན།",
        "🧩 Merge file volumes / ✂️ Split file": "🧩 ཡིག་ཆའི་ཆ་ཤས་ཟླ་སྒྲིལ / ✂️ ཡིག་ཆ་དབྱེ་བ།",
        "🧭 Open project in Android Studio": "🧭 Android Studio ནང་ལས་གཞི་ཁ་ཕྱེ།",
        "🧯 Clean build output": "🧯 བཟོ་སྐྲུན་ཐོན་རྫས་གཙང་སེལ།",
        "🧰 Diagnose and repair Harmony emulator": "🧰 Harmony ལད་མོའི་འཕྲུལ་ཆས་བརྟག་དཔྱད་དང་ཉམས་གསོ།",
        "🧱 Flutter assets and build dependencies": "🧱 Flutter རྒྱུ་ཆ་དང་བཟོ་སྐྲུན་བརྟེན་འབྲེལ།",
        "🧱 Prepare native libraries and build dependencies (combined)": "🧱 གདོད་མའི་དཔེ་མཛོད་དང་བཟོ་སྐྲུན་བརྟེན་འབྲེལ་གྲ་སྒྲིག（མཉམ་སྒྲུབ）།",
        "🧹 Clean build output": "🧹 བཟོ་སྐྲུན་ཐོན་རྫས་གཙང་སེལ།",
        "🩹 Repair missing Android SDK / platforms": "🩹 ཆད་པའི Android SDK / སྟེགས་བུ་ཉམས་གསོ།",
        "🩺 Diagnose and repair Android emulator": "🩺 Android ལད་མོའི་འཕྲུལ་ཆས་བརྟག་དཔྱད་དང་ཉམས་གསོ།",
        "🚀 Set up Flutter project": "🚀 Flutter ལས་གཞི་སྒྲིག་འགོད།",
        "🚚 Import all Flutter dependencies": "🚚 Flutter བརྟེན་འབྲེལ་ཚང་མ་ནང་འདྲེན།",
        "🚚 Export all Flutter dependencies": "🚚 Flutter བརྟེན་འབྲེལ་ཚང་མ་ཕྱིར་འདྲེན།",
        "Jobs Windows · Uninstall Explorer extensions": "Jobs Windows · Explorer རྒྱ་སྐྱེད་སྒྲིག་འཇུག་སུབ།",
        "Jobs Windows · Install Explorer extensions": "Jobs Windows · Explorer རྒྱ་སྐྱེད་སྒྲིག་འཇུག",
        "Jobs Windows · Manage Explorer extensions": "Jobs Windows · Explorer རྒྱ་སྐྱེད་དོ་དམ།",
        "Jobs Windows · Configure Explorer extensions": "Jobs Windows · Explorer རྒྱ་སྐྱེད་སྒྲིག་འགོད།",
        "Drag the divider vertically to resize the log": "དབྱེ་ཐིག་སྟེང་འོག་ཏུ་འདྲུད་ནས་ཟིན་ཐོའི་མཐོ་ཚད་སྒྱུར།",
        "Drag vertically to resize the log": "སྟེང་འོག་ཏུ་འདྲུད་ནས་ཟིན་ཐོའི་མཐོ་ཚད་སྒྱུར།",
        "Validate the Flutter project, diagnose the toolchain in terminal, and choose a Flutter SDK version with fzf.": "Flutter ལས་གཞི་བདེན་དཔང་བྱས་རྗེས་མཐའ་སྣེར་ལག་ཆའི་སྦྲེལ་ཐག་བརྟག་དཔྱད་བྱས་ནས fzf ཡིས Flutter SDK པར་གཞི་འདེམས།",
        "Validate the Flutter project, then show the active SDK version (project FVM or system SDK) in terminal and compare it with .fvmrc and pubspec constraints.": "Flutter ལས་གཞི་བདེན་དཔང་བྱས་རྗེས་མཐའ་སྣེར་ད་ལྟའི SDK པར་གཞི（ལས་གཞིའི FVM ཡང་ན་མ་ལག་གི SDK）མངོན་ནས .fvmrc དང pubspec ཡི་ཚད་བཀག་དང་བསྡུར།",
        "Flutter roots only. Choose Android / iOS / HarmonyOS with fzf in CMD. Supports APK / AAB and HAP / APP. iOS requires MacOS and Xcode.": "Flutter ལས་གཞིའི་རྩ་བའི་དཀར་ཆག་ཁོ་ན། CMD ནང fzf ཡིས Android / iOS / HarmonyOS འདེམས། APK / AAB དང HAP / APP རྒྱབ་སྐྱོར་བྱེད། iOS ལ MacOS དང Xcode དགོས།",
        "Flutter roots only. Choose a device and view logs in CMD; the app continues in the background after the window closes.": "Flutter ལས་གཞིའི་རྩ་བའི་དཀར་ཆག་ཁོ་ན། CMD ནང་སྒྲིག་ཆས་འདེམས་ནས་ཟིན་ཐོ་ལྟ། སྒེའུ་ཁུང་བཀག་རྗེས་ཀྱང་ཉེར་སྤྱོད་རྒྱབ་ལྗོངས་སུ་མུ་མཐུད་ལག་བསྟར་བྱེད།",
        "Flutter roots only. Read-only version and doctor diagnostics in terminal; no dependency fetching, cleanup, or tool upgrades.": "Flutter ལས་གཞིའི་རྩ་བའི་དཀར་ཆག་ཁོ་ན། མཐའ་སྣེར་པར་གཞི་དང doctor ཀློག་ཙམ་གྱི་བརྟག་དཔྱད་བྱེད། བརྟེན་འབྲེལ་ལེན་པ་དང་གཙང་སེལ་དང་ལག་ཆ་རིམ་སྤར་མི་བྱེད།",
        "Flutter roots only. Preview configured generators, then fetch dependencies and generate code after confirmation. Deleting conflicts requires separate opt-in.": "Flutter ལས་གཞིའི་རྩ་བའི་དཀར་ཆག་ཁོ་ན། སྒྲིག་ཟིན་པའི་སྐྱེད་ཆས་སྔོན་ལྟ་བྱས་ནས་གཏན་འཁེལ་རྗེས་བརྟེན་འབྲེལ་ལེན་ཞིང་ཚབ་ཨང་སྐྱེད། འགལ་ཟླའི་ཡིག་ཆ་སུབ་ན་ལོགས་སུ་ཆོག་མཆན་དགོས།",
        "Git worktree folders only. Detect nested repositories. Soft mode preserves the index and worktree; hard mode requires exact YES confirmation.": "Git ལས་ཀའི་སྡོང་པོའི་དཀར་ཆག་ཁོ་ན། ནང་བཅུག་མཛོད་ཁང་འཚོལ། soft ཐབས་ཀྱིས་གནས་སྐབས་ས་ཁུལ་དང་ལས་ཀའི་སྡོང་པོ་ཉར། hard ཐབས་ལ YES ཏག་ཏག་བྲིས་ནས་གཏན་འཁེལ་དགོས།",
        "Desktop background on x64 Windows only. Missing tools come from the SDL mirror; missing system images come from the official Emulator. Enter selects a stable phone image; confirm its license to create and start a unique instance.": "x64 Windows ཡི་ཅོག་ངོས་རྒྱབ་ལྗོངས་ཁོ་ན། ཆད་པའི་ལག་ཆ SDL མེ་ལོང་ནས་ལེན། ཆད་པའི་མ་ལག་གཟུགས་བརྙན་གཞུང་ཕྱོགས Emulator ནས་ལེན། Enter ཡིས་བརྟན་པའི་ཁ་པར་གཟུགས་བརྙན་འདེམས། ཆོག་མཆན་གཏན་འཁེལ་ནས་མིང་མི་འདྲ་བའི་དཔེ་གསར་བཟོ་ཞིང་འགོ་སློང་།",
        "Manage only this package's actions. Unselected actions remain when uninstalling.": "ཐུམ་སྒྲིལ་འདིའི་བྱ་བ་ཁོ་ན་དོ་དམ། སྒྲིག་འཇུག་སུབ་སྐབས་མ་འདེམས་པའི་བྱ་བ་ཉར།",
        "Desktop background only. Configure user-level Git to prefer the system proxy and fall back to a direct connection.": "ཅོག་ངོས་རྒྱབ་ལྗོངས་ཁོ་ན། སྤྱོད་མཁན་རིམ་པའི Git ལ་མ་ལག་གི་ཚབ་སྦྲེལ་སྔོན་འདེམས་བྱས་ནས་མི་འགྲུབ་ཚེ་ཐད་སྦྲེལ་ལ་ཕྱིར་ལོག་པར་སྒྲིག",
        "Desktop background only. Diagnose the SDK in CMD, choose a device and system image, then create or start an Android AVD.": "ཅོག་ངོས་རྒྱབ་ལྗོངས་ཁོ་ན། CMD ནང SDK བརྟག་དཔྱད་བྱས་ནས་སྒྲིག་ཆས་དང་མ་ལག་གཟུགས་བརྙན་འདེམས། དེ་ནས Android AVD གསར་བཟོ་ཡང་ན་འགོ་སློང་།",
        "Desktop background only. Check existing DevEco Emulator instances, then start one or confirm a nondestructive restart. Data is preserved.": "ཅོག་ངོས་རྒྱབ་ལྗོངས་ཁོ་ན། ཡོད་ཟིན་པའི DevEco Emulator དཔེ་བཤེར་ནས་གཅིག་འགོ་སློང་ཡང་ན་གནོད་མེད་བསྐྱར་འགོ་སློང་གཏན་འཁེལ། གཞི་གྲངས་ཉར།",
        "Desktop background only. Check emulator location and /data; optionally reset caches, precisely uninstall, back up the AVD, and retest with a cold boot.": "ཅོག་ངོས་རྒྱབ་ལྗོངས་ཁོ་ན། ལད་མོའི་འཕྲུལ་ཆས་ཀྱི་གནས་ཡུལ་དང /data བཤེར། གདམ་ཀ་ལྟར་གནས་སྐབས་གསོག་འཇོག་བསྐྱར་སྒྲིག་དང་གནད་འཕིགས་སྒྲིག་འཇུག་སུབ་པ་དང AVD གྲབས་ཉར་བྱས་ནས་འཁྱག་འགོ་སློང་གིས་བསྐྱར་ཚོད་བྱེད།",
        "Show the next action on the desktop background. Toggle hidden files for the current user's Explorer without changing protected-system-file settings.": "ཅོག་ངོས་རྒྱབ་ལྗོངས་སུ་རྗེས་མའི་བྱ་བ་མངོན། ད་ལྟའི་སྤྱོད་མཁན་གྱི Explorer ནང་སྦས་པའི་ཡིག་ཆ་མངོན་སྦས་བརྗེ། སྲུང་སྐྱོབ་མ་ལག་ཡིག་ཆའི་སྒྲིག་འགོད་མི་སྒྱུར།",
        "Visible only for nonempty native Android or valid Flutter (official / HarmonyOS) project roots. Validated again before opening.": "ནང་དོན་སྟོང་མིན་པའི་གདོད་མའི Android ཡང་ན་ནུས་ལྡན Flutter（གཞུང་ཕྱོགས / HarmonyOS）ལས་གཞིའི་རྩ་བའི་དཀར་ཆག་ཁོ་ནར་མངོན། ཁ་མ་ཕྱེ་གོང་བསྐྱར་དུ་བདེན་དཔང་བྱེད།",
        "Preview: the selection is shown in the log. No installation or uninstallation was performed.": "སྔོན་ལྟ། འདེམས་པ་ཟིན་ཐོར་མངོན། སྒྲིག་འཇུག་དང་སྒྲིག་འཇུག་སུབ་པ་གང་ཡང་མ་བྱས།",
        "Preview only. Confirming displays the selection in the log without installing, uninstalling, or writing state or registry entries.": "སྔོན་ལྟ་ཁོ་ན། གཏན་འཁེལ་ན་འདེམས་པ་ཟིན་ཐོར་མངོན། སྒྲིག་འཇུག་དང་སྒྲིག་འཇུག་སུབ་པ་མི་བྱེད། གནས་བབ་དང་ཐོ་འགོད་མཛོད་ལའང་མི་འབྲི།",
        "Deployed copies use their bound location. To change it, open the manager from the source directory. Default installations run in the current user's LocalAppData; local builds run under this package's work directory and stop working if it moves.": "བཀྲམ་ཟིན་པའི་འདྲ་བཤུས་ཀྱིས་བསྡམས་པའི་གནས་ཡུལ་སྤྱོད། བརྗེ་ན་འབྱུང་ཁུངས་དཀར་ཆག་ནས་དོ་དམ་ཆས་ཁ་ཕྱེ། སོར་བཞག་སྒྲིག་འཇུག་ད་ལྟའི་སྤྱོད་མཁན་གྱི LocalAppData ནང་ལག་བསྟར། རང་སའི་བཟོ་སྐྲུན་ཐུམ་སྒྲིལ་འདིའི་ལས་ཀའི་དཀར་ཆག་འོག་ལག་བསྟར་ཞིང་དཀར་ཆག་སྤོས་ན་ནུས་པ་ཤོར།",
        "Prefer Windows Terminal; otherwise use system PowerShell.": "Windows Terminal སྔོན་འདེམས་བྱེད། མེད་ན་མ་ལག་གི PowerShell སྤྱོད།",
        "Could not save preferences: ": "འདེམས་སྒྲིག་ཉར་མ་ཐུབ། ",
        "Save settings": "སྒྲིག་འགོད་ཉར།",
        "Protect local changes. On conflict, choose to restore, discard changes, or commit and retry.": "རང་སའི་བསྒྱུར་བཅོས་སྲུང་། འགལ་ཟླ་བྱུང་ན་སླར་གསོ་དང་བསྒྱུར་བཅོས་དོར་བ་ཡང་ན commit བྱས་རྗེས་བསྐྱར་ཚོད་འདེམས།",
        "All operations completed. Copy the log or close the panel.": "བྱ་བ་ཚང་མ་གྲུབ་ཟིན། ཟིན་ཐོ་འདྲ་བཤུས་བྱེད་ཡང་ན་འདེམས་ངོས་ཁ་རྒྱག",
        "Other context-menu features": "གཡས་མཐེབ་འདེམས་ཐོའི་བྱེད་ནུས་གཞན།",
        "Create or synchronize the code map for the current directory.": "ད་ལྟའི་དཀར་ཆག་གི་ཚབ་ཨང་ས་ཁྲ་གསར་བཟོ་ཡང་ན་མཉམ་བགྲོད།",
        "Feature and log divider": "བྱེད་ནུས་དང་ཟིན་ཐོའི་དབྱེ་ཐིག",
        "Select features, then confirm. Unselected features remain. Hover for installation details.": "བྱེད་ནུས་འདེམས་ནས་གཏན་འཁེལ། མ་འདེམས་པའི་བྱེད་ནུས་ཉར། སྟོན་མདའ་སྟེང་དུ་བཞག་ན་སྒྲིག་འཇུག་གི་ཞིབ་ཆ་མངོན།",
        "Checked features are installed; unchecked ones are uninstalled. Saving an empty selection disables all installed features.": "བདམས་པའི་བྱེད་ནུས་སྒྲིག་འཇུག་བྱེད། མ་བདམས་པ་སྒྲིག་འཇུག་སུབ། འདེམས་ཐོ་སྟོང་པ་ཉར་ན་སྒྲིག་འཇུག་ཟིན་པའི་བྱེད་ནུས་ཚང་མ་འགོག",
        "Select features to install. Enabled sibling actions and other unselected features remain.": "སྒྲིག་འཇུག་བྱ་རྒྱུའི་བྱེད་ནུས་འདེམས། མཉམ་རིམ་གྱི་སྤྱོད་འགོ་ཚུགས་པའི་བྱ་བ་དང་མ་འདེམས་པའི་བྱེད་ནུས་གཞན་ཉར།",
        "Total uninstall time": "སྒྲིག་འཇུག་སུབ་པའི་སྤྱིའི་དུས་ཚོད།",
        "Uninstall selected": "བདམས་པ་སྒྲིག་འཇུག་སུབ།",
        "Uninstall selected features": "བདམས་པའི་བྱེད་ནུས་སྒྲིག་འཇུག་སུབ།",
        "Uninstall time": "སྒྲིག་འཇུག་སུབ་པའི་དུས་ཚོད།",
        "Cancel": "མེད་པར་བཟོ།",
        "Uninstall only selected installed features. Other features, logs, backups and tools remain.": "བདམས་པའི་སྒྲིག་འཇུག་ཟིན་པའི་བྱེད་ནུས་ཁོ་ན་སུབ། བྱེད་ནུས་གཞན་དང་ཟིན་ཐོ་དང་གྲབས་ཉར་དང་ལག་ཆ་ཉར།",
        "Change only the current user's ExecuteFile ACL for a single regular NTFS file after confirmation. Does not launch the file or change global policy.": "གཏན་འཁེལ་རྗེས་རྒྱུན་ལྡན NTFS ཡིག་ཆ་གཅིག་ལ་ད་ལྟའི་སྤྱོད་མཁན་གྱི ExecuteFile ACL ཁོ་ན་སྒྱུར། ཡིག་ཆ་མི་འགོ་སློང་ཞིང་སྤྱི་ཡོངས་སྲིད་ཇུས་མི་སྒྱུར།",
        "View a single regular file. Files over 1 MiB or suspected binary files require YES in the terminal.": "རྒྱུན་ལྡན་ཡིག་ཆ་གཅིག་ལྟ། 1 MiB ལས་ཆེ་བ་ཡང་ན་གཉིས་གོང་ཡིག་ཆ་ཡིན་སྙམ་པ་ལ་མཐའ་སྣེར YES འབྲི་དགོས།",
        "Clean only the selected packages' build workspaces. Installed DLLs, scripts, settings and registry entries remain.": "བདམས་པའི་ཐུམ་སྒྲིལ་གྱི་བཟོ་སྐྲུན་ལས་ཁུལ་ཁོ་ན་གཙང་སེལ། སྒྲིག་འཇུག་ཟིན་པའི DLL དང་འཁྲབ་གཞུང་དང་སྒྲིག་འགོད་དང་ཐོ་འགོད་མཛོད་ཀྱི་ཚན་པ་ཉར།",
        "Copy full log": "ཟིན་ཐོ་ཆ་ཚང་འདྲ་བཤུས།",
        "Copy the original remote URL for the current branch.": "ད་ལྟའི་ཡལ་གའི་ཐོག་མའི་རྒྱང་འབྲེལ URL འདྲ་བཤུས།",
        "Copy the absolute path of a file or folder.": "ཡིག་ཆ་ཡང་ན་དཀར་ཆག་གི་ལྟོས་མེད་འགྲོ་ལམ་འདྲ་བཤུས།",
        "Could not copy the log: ": "ཟིན་ཐོ་འདྲ་བཤུས་མ་ཐུབ། ",
        "Failed — open log": "ཕམ་སོང་། — ཟིན་ཐོ་ཁ་ཕྱེ།",
        "Install / update": "སྒྲིག་འཇུག / གསར་སྒྱུར།",
        "Install / update selected features": "བདམས་པའི་བྱེད་ནུས་སྒྲིག་འཇུག / གསར་སྒྱུར།",
        "Total install time": "སྒྲིག་འཇུག་གི་སྤྱིའི་དུས་ཚོད།",
        "Install time": "སྒྲིག་འཇུག་གི་དུས་ཚོད།",
        "Merge appears for a complete selected volume set; split appears for one regular file. Originals are always preserved.": "ཡོངས་ཚང་གི་ཆ་ཤས་ཚང་མ་བདམས་ན་མཉམ་སྒྲིལ་མངོན། རྒྱུན་ལྡན་ཡིག་ཆ་གཅིག་བདམས་ན་ཁ་བྲལ་མངོན། མ་ཡིག་རྟག་ཏུ་ཉར།",
        "Live log (drag the divider to resize)": "དུས་ཐོག་ཟིན་ཐོ（དབྱེ་ཐིག་འདྲུད་ནས་མཐོ་ཚད་སྒྱུར）།",
        "Installation stopped after the current package transaction. Unstarted items are marked Not run.": "ད་ལྟའི་ཐུམ་སྒྲིལ་གྱི་བྱ་ཚན་གྲུབ་རྗེས་སྒྲིག་འཇུག་བཀག་ཟིན། འགོ་མ་ཚུགས་པའི་ཚན་པར་ལག་བསྟར་མ་བྱས་ཞེས་རྟགས་བཀོད།",
        "Stop requested. Waiting for the current package transaction; later items will not run.": "བཀག་འགོག་རེ་ཞུ་བྱས་ཟིན། ད་ལྟའི་ཐུམ་སྒྲིལ་བྱ་ཚན་གྲུབ་པར་སྒུག རྗེས་མའི་ཚན་པ་ལག་བསྟར་མི་བྱེད།",
        "Selected {0} / {1}. Closing or cancelling makes no changes.": "བདམས་པ {0} / {1}། ཁ་རྒྱག་པ་ཡང་ན་མེད་པར་བཟོས་ན་བསྒྱུར་བཅོས་མི་བྱེད།",
        "Hover for feature details. Windows 11: right-click → Show more options.": "སྟོན་མདའ་སྟེང་དུ་བཞག་ན་བྱེད་ནུས་ཀྱི་ཞིབ་ཆ་མངོན། Windows 11: གཡས་མཐེབ → གདམ་ཀ་མང་བ་མངོན།",
        "Could not open the full log: ": "ཟིན་ཐོ་ཆ་ཚང་ཁ་ཕྱེ་མ་ཐུབ། ",
        "Open the repository website for the current Git worktree.": "ད་ལྟའི Git ལས་ཀའི་སྡོང་པོའི་མཛོད་ཁང་དྲ་ཚིགས་ཁ་ཕྱེ།",
        "Open the solution or project at the current directory level.": "ད་ལྟའི་དཀར་ཆག་རིམ་པའི་སྤྱི་ལས་གཞི་ཡང་ན་ལས་གཞི་ཁ་ཕྱེ།",
        "Export resolved third-party Pub sources and licenses from the project lockfile. Press Enter to use the desktop as output.": "ལས་གཞིའི་ཟྭ་ཡིག་ནས་ཐག་ཆོད་ཟིན་པའི་ཕྱོགས་གསུམ་པའི Pub འབྱུང་ཁུངས་དང་ཆོག་མཆན་ཕྱིར་འདྲེན། Enter མནན་ན་ཅོག་ངོས་ཕྱིར་འདོན་གནས་སུ་སྤྱོད།",
        "An operation is running. Wait for the transaction to finish before closing. Logs can be copied at any time.": "བྱ་བ་ཞིག་ལག་བསྟར་བཞིན་ཡོད། བྱ་ཚན་གྲུབ་རྗེས་ད་གཟོད་ཁ་རྒྱག ཟིན་ཐོ་དུས་ནམ་ཡང་འདྲ་བཤུས་བྱས་ཆོག",
        "Could not build the operation plan: ": "བྱ་བའི་འཆར་གཞི་བཟོ་མ་ཐུབ། ",
        "Could not start the operation: ": "བྱ་བ་འགོ་སློང་མ་ཐུབ། ",
        "Log: ": "ཟིན་ཐོ། ",
        "🈶 Repair Chinese paths in Flutter project": "🈶 Flutter ལས་གཞིའི་རྒྱ་ཡིག་འགྲོ་ལམ་ཉམས་གསོ།",
        "Not installed; nothing to uninstall": "སྒྲིག་འཇུག་མ་བྱས། སུབ་རྒྱུ་མེད།",
        "Not installed": "སྒྲིག་འཇུག་མ་བྱས།",
        "Not run": "ལག་བསྟར་མ་བྱས།",
        "This feature": "བྱེད་ནུས་འདི།",
        "Local build directory (moving or cleaning it disables the menu)": "རང་སའི་བཟོ་སྐྲུན་དཀར་ཆག（སྤོ་བ་ཡང་ན་གཙང་སེལ་བྱས་ན་འདེམས་ཐོ་ནུས་མེད་འགྱུར）།",
        "Validate the branch, staging area and upstream, then confirm the push.": "ཡལ་ག་དང་གནས་སྐབས་ས་ཁུལ་དང་གོང་རིམ་བདེན་དཔང་བྱས་རྗེས་སྐྱེལ་འབུལ་གཏན་འཁེལ།",
        "Validate the Flutter project, then fetch dependencies.": "Flutter ལས་གཞི་བདེན་དཔང་བྱས་རྗེས་བརྟེན་འབྲེལ་ལེན།",
        "Installing / updating…": "སྒྲིག་འཇུག / གསར་སྒྱུར་བཞིན…",
        "This entry has been removed. Existing installations can be uninstalled but cannot be reinstalled.": "འཇུག་སྒོ་འདི་བསུབས་ཟིན། ཡོད་ཟིན་པའི་སྒྲིག་འཇུག་སུབ་ཆོག་ཀྱང་བསྐྱར་དུ་སྒྲིག་འཇུག་མི་ཐུབ།",
        "No features require processing; ": "ཐག་གཅོད་དགོས་པའི་བྱེད་ནུས་མེད། ",
        "No features require processing. No settings were changed.": "ཐག་གཅོད་དགོས་པའི་བྱེད་ནུས་མེད། སྒྲིག་འགོད་གང་ཡང་མ་བསྒྱུར།",
        "Total cleanup time": "གཙང་སེལ་གྱི་སྤྱིའི་དུས་ཚོད།",
        "Cleanup time": "གཙང་སེལ་གྱི་དུས་ཚོད།",
        "Click to read the full session log in a new PowerShell window. The current task continues.": "མནན་ནས PowerShell སྒེའུ་ཁུང་གསར་པར་ཐེངས་འདིའི་ཟིན་ཐོ་ཆ་ཚང་ཀློག ད་ལྟའི་ལས་འགན་མུ་མཐུད་ལག་བསྟར་བྱེད།",
        "Pending": "ཐག་གཅོད་ལ་སྒུག་བཞིན།",
        "Waiting to stop…": "བཀག་འགོག་ལ་སྒུག་བཞིན…",
        "Ordered Flutter development, diagnostics, repair and maintenance tools. Regular actions use project FVM; environment setup supports FVM / system Flutter and jEnv / system Java.": "གོ་རིམ་ལྡན་པའི Flutter གསར་སྤེལ་དང་བརྟག་དཔྱད་དང་ཉམས་གསོ་དང་བདག་སྐྱོང་ལག་ཆ། རྒྱུན་ལྡན་བྱ་བར་ལས་གཞིའི FVM སྤྱོད། ཁོར་ཡུག་སྒྲིག་འགོད་ལ FVM / མ་ལག་གི Flutter དང jEnv / མ་ལག་གི Java རྒྱབ་སྐྱོར་བྱེད།",
        "Detect the Flutter / Android project and preview cleanup scope. iOS cleanup is unavailable on Windows.": "Flutter / Android ལས་གཞི་འཚོལ་ནས་གཙང་སེལ་ཁྱབ་ཁོངས་སྔོན་ལྟ། Windows ནང iOS གཙང་སེལ་མི་ཐུབ།",
        "Could not read preferences: ": "འདེམས་སྒྲིག་ཀློག་མ་ཐུབ། ",
        "Could not read the log: ": "ཟིན་ཐོ་ཀློག་མ་ཐུབ། ",
        "Explorer context-menu extensions · ": "Explorer གཡས་མཐེབ་འདེམས་ཐོའི་རྒྱ་སྐྱེད · ",
        "Explorer extensions · Manage": "Explorer རྒྱ་སྐྱེད · དོ་དམ།",
        "Return selection": "འདེམས་པ་ཕྱིར་སྤྲོད།",
        "Exit code: ": "ཕྱིར་ཐོན་ཨང་། ",
        "Choose an operation and select features. Unselected features remain; only installed features can be uninstalled.": "བྱ་བ་དང་བྱེད་ནུས་འདེམས། མ་འདེམས་པའི་བྱེད་ནུས་ཉར། སྒྲིག་འཇུག་ཟིན་པའི་བྱེད་ནུས་ཁོ་ན་སྒྲིག་འཇུག་སུབ་ཆོག",
        "Some features failed; other selected features were still processed. Click a failed status to open the full session log.": "བྱེད་ནུས་ཁ་ཤས་ཕམ་སོང་ཡང་བདམས་པའི་བྱེད་ནུས་གཞན་མུ་མཐུད་ཐག་གཅོད་བྱས། ཕམ་པའི་གནས་བབ་མནན་ནས་ཐེངས་འདིའི་ཟིན་ཐོ་ཆ་ཚང་ཁ་ཕྱེ།",
        "Available for nonempty regular directories outside iOS projects, including Flutter roots. Validated again before opening.": "iOS ལས་གཞི་མིན་པའི་ནང་དོན་སྟོང་མིན་རྒྱུན་ལྡན་དཀར་ཆག་ལ་སྤྱོད་ཆོག Flutter རྩ་བའི་དཀར་ཆག་ཀྱང་ཚུད། ཁ་མ་ཕྱེ་གོང་བསྐྱར་དུ་བདེན་དཔང་བྱེད།",
        "Default installation location (recommended)": "སོར་བཞག་སྒྲིག་འཇུག་གནས་ཡུལ（འོས་སྦྱོར）།",
        "{0}; Results: succeeded {1}; nothing to uninstall {2}; failed {3}; not run {4}": "{0}། འབྲས་བུ། ལེགས་གྲུབ {1}། སུབ་རྒྱུ་མེད {2}། ཕམ་པ {3}། ལག་བསྟར་མ་བྱས {4}",
        "{0} Exit code: {1}.": "{0} ཕྱིར་ཐོན་ཨང་། {1}།",
        "{0} {1}": "{0} {1}",
        "{0}{1} {2}": "{0}{1} {2}",
        "{0} in progress; completed {1} / {2} ({3}% by completed items); {4} {5}": "{0} བྱེད་བཞིན། གྲུབ་པ {1} / {2}（གྲུབ་པའི་ཚན་པ་ལྟར {3}%）། {4} {5}",
        "{0} Completed {1} / {2} ({3}% by completed items); {4} {5}": "{0} གྲུབ་པ {1} / {2}（གྲུབ་པའི་ཚན་པ་ལྟར {3}%）། {4} {5}",
        "Close management panel": "དོ་དམ་པང་ལེབ་ཁ་རྒྱག",
        "Run in the menu bar, or quit the installation / uninstallation panel?": "མ་ལག་གི་གནས་ཚུལ་ཐོ་བྱང་ནང་རྒྱབ་ལྗོངས་སུ་འཁོར་སྐྱོད་བྱེད་དམ། ཡང་ན་སྒྲིག་འཇུག / སུབ་པའི་པང་ལེབ་ནས་རྦད་དེ་ཕྱིར་འདོན་བྱེད།",
        "Run in background": "རྒྱབ་ལྗོངས་སུ་འཁོར་སྐྱོད།",
        "Quit completely": "རྦད་དེ་ཕྱིར་འདོན།",
        "Show management panel": "དོ་དམ་པང་ལེབ་སྟོན།",
        "Status: {0}": "གནས་ཚུལ། {0}",
        "A task is running. You can quit after it finishes.": "ལས་ཀ་འཁོར་སྐྱོད་བཞིན་ཡོད། ལེགས་འགྲུབ་རྗེས་རྦད་དེ་ཕྱིར་འདོན་བྱེད་ཆོག"
      },
      "ja": {
        "Update development environment (update)": "開発環境を更新（update）",
        "Total disk space": "ディスク空き容量の合計",
        "Create script launcher": "スクリプト起動ファイルを作成",
        "Theme": "テーマ",
        "Language": "言語",
        "🎨 Theme": "🎨 テーマ",
        "🌐 Language": "🌐 言語",
        "Follow system": "システムに従う",
        "Dark": "ダーク",
        "Light": "ライト",
        "Jobs Finder Extension Manager": "Jobs Finder 拡張機能マネージャー",
        "Customize Finder Context Menu": "Finder コンテキストメニューをカスタマイズ",
        "Close Manager": "マネージャーを閉じる",
        "Edit": "編集",
        "Copy": "コピー",
        "Select all": "すべて選択",
        "Clear all": "選択をすべて解除",
        "Close": "閉じる",
        "OK": "OK",
        "Install": "インストール",
        "Install / Update": "インストール / 更新",
        "Uninstall": "アンインストール",
        "Cleanup": "クリーンアップ",
        "Clean build products": "ビルド生成物を削除",
        "🧹 Clean build products": "🧹 ビルド生成物を削除",
        "Stop installation": "インストールを停止",
        "Stopping…": "停止中…",
        "Action: install / update or uninstall": "操作：インストール / 更新またはアンインストール",
        "Uninstall removes selected menus only. Group selection affects its own group.": "選択したメニューのみを削除します。グループ内の選択はそのグループのみに適用されます。",
        "Install / uninstall with the combined App in Applications": "アプリケーション内の統合 App でインストール / アンインストール",
        "Install or uninstall the combined App in Applications": "アプリケーション内の統合 App をインストールまたはアンインストール",
        "Selected: manage features in /Applications/Jobs自定义右键菜单.app. Otherwise use the build directory.": "選択時は /Applications/Jobs自定义右键菜单.app 内の機能を管理します。未選択時はビルドディレクトリを使用します。",
        "Clean this build after successful installation": "インストール成功後に今回のビルドを削除",
        "Clean this build only after the combined App is installed and verified in Applications. Keep failed builds.": "統合 App をアプリケーションにインストールして検証した後のみ、今回のビルドを削除します。失敗したビルドは保持します。",
        "Clean build products of selected features without installing or uninstalling.": "選択した機能のビルド生成物のみを削除します。インストールやアンインストールは行いません。",
        "Clean selected features' build products": "選択した機能のビルド生成物を削除",
        "Open Privacy & Security": "プライバシーとセキュリティを開く",
        "Add and enable Jobs右键菜单管理面板.app in Privacy & Security → App Management. This only opens Settings.": "「プライバシーとセキュリティ → App 管理」で Jobs右键菜单管理面板.app を追加して有効にしてください。このボタンは設定のみを開きます。",
        "Target: build directory. Cleaning these products affects installed features.": "対象：ビルドディレクトリ。生成物を削除すると、インストール済み機能に影響します。",
        "App: Jobs自定义右键菜单.app at /Applications/Jobs自定义右键菜单.app (build products can be cleaned after installation)": "App：/Applications/Jobs自定义右键菜单.app（インストール後にビルド生成物を削除可能）",
        "Drag the divider to resize the log. Features and logs scroll separately.": "区切り線を上下にドラッグしてログの高さを調整します。機能とログは個別にスクロールできます。",
        "Feature list and live log divider": "機能一覧とリアルタイムログの区切り線",
        "Live log (select and copy text)": "リアルタイムログ（文字を選択してコピー可能）",
        "Copy log": "ログをコピー",
        "Log file": "ログファイル",
        "Auto-scroll": "自動スクロール",
        "Ready. Select features and choose an action.": "準備完了。機能を選択して操作ボタンを押してください。",
        "A task is running. Wait for it to finish before closing.": "タスクを実行中です。完了してから閉じてください。",
        "Unable to view this log": "このログを表示できません",
        "Log is missing or unreadable: {0}": "ログが存在しないか、読み取れません：{0}",
        "Unable to open log terminal: {0}": "ログ用ターミナルを開けません：{0}",
        "Click to show this session's full log in a new terminal: {0}": "クリックすると、このセッションの完全なログを新しいターミナルに表示します：{0}",
        "Selected {0} / {1}. Select at least one. Changing action keeps selection.": "{0} / {1} 件を選択。1 件以上選択してください。操作を切り替えても選択は保持されます。",
        "Selected {0} / {1}": "{0} / {1} 件を選択",
        "{0}: select all": "{0}：すべて選択",
        "{0}: clear all": "{0}：選択をすべて解除",
        "Waiting": "待機中",
        "Cleaning…": "クリーンアップ中…",
        "Uninstalling…": "アンインストール中…",
        "Installing…": "インストール中…",
        "Cleaned": "削除済み",
        "Uninstalled": "アンインストール済み",
        "Installed": "インストール済み",
        "Skipped": "未実行",
        "Not installed; nothing to remove": "未インストール：削除不要",
        "Failed: see log": "失敗：ログを確認",
        "Selected": "選択済み",
        "Not selected": "未選択",
        "App Management permission required": "App 管理権限が必要です",
        "Permission check required": "権限の確認が必要です",
        "Stopped": "停止済み",
        "Completed": "完了",
        "Task failed": "タスク失敗",
        "{0}: processed {1} / {2} ({3}, completed items); {4} time {5}": "{0}：処理済み {1} / {2}（{3}、完了項目基準）；{4}時間 {5}",
        "{0} ready": "{0}の準備完了",
        "{0} ready; {1} time {2}": "{0}の準備完了；{1}時間 {2}",
        "Finishing the current feature, then stopping; install time {0}": "現在の機能を完了してから停止します；インストール時間 {0}",
        "{0}: {1} succeeded, {2} failed, {3} skipped; exit {4}; {5}; {6} time {7}": "{0}：成功 {1}、失敗 {2}、未実行 {3}；終了 {4}；{5}；{6}時間 {7}",
        "{0}: {1} succeeded, {2} failed, {3} not installed, {4} skipped; exit {5}; {6}; {7} time {8}": "{0}：成功 {1}、失敗 {2}、削除不要 {3}、未実行 {4}；終了 {5}；{6}；{7}時間 {8}",
        "{0}: {1} succeeded, {2} failed, {3} not installed; exit {4}; {5}; {6} time {7}": "{0}：成功 {1}、失敗 {2}、削除不要 {3}；終了 {4}；{5}；{6}時間 {7}",
        "{0}: {1} succeeded, {2} failed; exit {3}; {4}; {5} time {6}": "{0}：成功 {1}、失敗 {2}；終了 {3}；{4}；{5}時間 {6}",
        "Open projects in IDEs": "IDE でプロジェクトを開く",
        "Git tools": "Git ツール",
        "Files and general tools": "ファイルと共通ツール",
        "Flutter tools · submenu actions": "Flutter ツール・サブメニュー操作",
        "iOS / CocoaPods tools": "iOS / CocoaPods ツール",
        "Simulator tools": "シミュレーターツール",
        "Open project in Android Studio": "Android Studio でプロジェクトを開く",
        "Open project in VSCode": "VSCode でプロジェクトを開く",
        "Open project in Xcode": "Xcode でプロジェクトを開く",
        "Pull latest Git changes": "Git の最新変更を取得",
        "Roll back Git commit": "Git コミットを巻き戻す",
        "Open Git remote URL": "Git リモート URL を開く",
        "Copy Git remote URL": "Git リモート URL をコピー",
        "Copy absolute path": "絶対パスをコピー",
        "Create file": "ファイルを作成",
        "View file fingerprint Hash (SHA-256)": "ファイルのハッシュを表示（SHA-256）",
        "Hide / show selected items": "選択した項目を非表示 / 表示",
        "Send to external disk or network volume": "外部ディスクまたはネットワークボリュームに送る",
        "Grant execute permission (chmod +x)": "実行権限を付与（chmod +x）",
        "Remove execute permission (chmod -x)": "実行権限を削除（chmod -x）",
        "Re-sign IPA without building": "ビルドせずに IPA を再署名",
        "Show / hide files": "ファイルを表示 / 非表示",
        "Create iOS simulator": "iOS シミュレーターを作成",
        "Create Android simulator": "Android シミュレーターを作成",
        "Create Harmony simulator": "Harmony シミュレーターを作成",
        "Check / repair Android simulator": "Android シミュレーターを診断 / 修復",
        "Check / repair Harmony simulator": "Harmony シミュレーターを診断 / 修復",
        "Configure Git proxy": "Git プロキシを設定",
        "Open in terminal": "ターミナルで開く",
        "View file contents in terminal": "ターミナルでファイルの内容を表示",
        "Merge file parts": "分割ファイルを結合",
        "Split file": "ファイルを分割",
        "Clean Android / OpenHarmony builds": "Android / OpenHarmony ビルドを削除",
        "Update code map (.codegraph)": "コードマップを更新（.codegraph）",
        "Create empty commit and push in terminal": "ターミナルで空のコミットを作成して Push",
        "Disable CocoaPods build sandbox": "CocoaPods のビルドサンドボックスを無効化",
        "Install CocoaPods": "CocoaPods をインストール",
        "CocoaPods source: CDN → GitHub": "CocoaPods ソース：CDN → GitHub",
        "Export all project Pod files": "プロジェクトの全 Pod ファイルをエクスポート",
        "Inspect Xcode project dependencies": "Xcode プロジェクトの依存関係を確認",
        "Update local CocoaPods repositories": "ローカル CocoaPods リポジトリを更新",
        "Check local Pod builds (.podspec folder)": "ローカル Pod のビルドを確認（.podspec フォルダ）",
        "Install / update JobsCodeSnippets": "JobsCodeSnippets をインストール / 更新",
        "Clean iOS / Xcode builds": "iOS / Xcode ビルドを削除",
        "Set up Flutter project": "Flutter プロジェクトをセットアップ",
        "Run Flutter project in terminal": "Flutter プロジェクトをターミナルで実行",
        "Fetch Flutter Pub dependencies": "Flutter Pub の依存関係を取得",
        "Fetch native Android dependencies": "Android ネイティブの依存関係を取得",
        "Fetch CocoaPods dependencies": "CocoaPods の依存関係を取得",
        "Fetch Swift Package dependencies": "Swift Package の依存関係を取得",
        "Fetch OpenHarmony dependencies": "OpenHarmony の依存関係を取得",
        "Prepare native libraries and build dependencies": "ネイティブライブラリとビルド依存関係を準備",
        "Download Flutter platform resources": "Flutter プラットフォームリソースをダウンロード",
        "Fetch Web project dependencies": "Web プロジェクトの依存関係を取得",
        "🧳 Export Flutter dependencies": "🧳 Flutter の依存関係をエクスポート",
        "Export Flutter Pub dependencies": "Flutter Pub の依存関係をエクスポート",
        "🔐 Export private Flutter dependencies": "🔐 Flutter の非公開依存関係をエクスポート",
        "📥 Import Flutter dependencies": "📥 Flutter の依存関係をインポート",
        "Import Flutter Pub dependencies": "Flutter Pub の依存関係をインポート",
        "📥 Import private Flutter dependencies": "📥 Flutter の非公開依存関係をインポート",
        "Export Gradle distributions and cache": "Gradle 配布物とキャッシュをエクスポート",
        "Import Gradle distributions and cache": "Gradle 配布物とキャッシュをインポート",
        "Export CocoaPods dependencies": "CocoaPods の依存関係をエクスポート",
        "Import CocoaPods dependencies": "CocoaPods の依存関係をインポート",
        "Export Swift Package dependencies": "Swift Package の依存関係をエクスポート",
        "Import Swift Package dependencies": "Swift Package の依存関係をインポート",
        "Export OpenHarmony dependencies": "OpenHarmony の依存関係をエクスポート",
        "Import OpenHarmony dependencies": "OpenHarmony の依存関係をインポート",
        "Export native build cache": "ネイティブビルドキャッシュをエクスポート",
        "Import native build cache": "ネイティブビルドキャッシュをインポート",
        "Export Flutter platform resources": "Flutter プラットフォームリソースをエクスポート",
        "Import Flutter platform resources": "Flutter プラットフォームリソースをインポート",
        "Export Web dependencies": "Web の依存関係をエクスポート",
        "Import Web dependencies": "Web の依存関係をインポート",
        "Show Flutter project SDK version": "Flutter プロジェクトの SDK バージョンを表示",
        "Install / switch Flutter SDK": "Flutter SDK をインストール / 切り替え",
        "Install / switch Flutter@OpenHarmony SDK": "Flutter@OpenHarmony SDK をインストール / 切り替え",
        "Install / switch Java SDK": "Java SDK をインストール / 切り替え",
        "Download Gradle distributions and plugins": "Gradle 配布物とプラグインをダウンロード",
        "Generate Flutter code": "Flutter コードを生成",
        "Package iOS": "iOS をパッケージ化",
        "Package Android": "Android をパッケージ化",
        "Package Harmony (HAP + APP)": "Harmony をパッケージ化（HAP + APP）",
        "Check native Flutter project": "ネイティブ Flutter プロジェクトを診断",
        "Check OpenHarmony Flutter environment": "OpenHarmony Flutter 環境を診断",
        "Repair missing Android SDK / platforms": "不足している Android SDK / platforms を修復",
        "Repair Chinese Flutter project paths": "Flutter プロジェクトの中国語パスを修復",
        "Repair Flutter plugin namespaces": "Flutter プラグインの namespace を修復",
        "Convert relative Dart imports to packages": "Dart の相対 import を package 参照に変換",
        "Clean current Flutter project builds": "現在の Flutter プロジェクトのビルドを削除",
        "Dependency and cache maintenance": "依存関係とキャッシュのメンテナンス",
        "Custom Explorer context menu": "Explorer コンテキストメニューをカスタマイズ",
        "Jobs Windows · Custom Explorer context menu": "Jobs Windows · Explorer コンテキストメニューをカスタマイズ",
        "Show a regular file's SHA-256 in a new terminal and copy the digest; do not modify or execute the file.": "通常ファイルの SHA-256 を新しいターミナルに表示し、ハッシュ値をコピーします。ファイルの変更や実行は行いません。",
        " (preview)": "（プレビューのみ）",
        "⏪ Roll back Git commits": "⏪ Git コミットを巻き戻す",
        "▶️ Run Flutter project in terminal": "▶️ Flutter プロジェクトをターミナルで実行",
        "☕ Install / switch Java SDK": "☕ Java SDK をインストール / 切り替え",
        "♻️ Flutter cleanup and maintenance": "♻️ Flutter のクリーンアップと保守",
        "⚙️ Generate Flutter code": "⚙️ Flutter コードを生成",
        "✅ Installed": "✅ インストール済み",
        "⬇️ Pull latest Git changes": "⬇️ Git の最新変更を取得",
        "🌈 Create Harmony emulator": "🌈 Harmony エミュレーターを作成",
        "🌐 Open Git remote URL": "🌐 Git リモート URL を開く",
        "🌐 Fetch Web project dependencies": "🌐 Web プロジェクトの依存関係を取得",
        "🌳 Open in Sourcetree": "🌳 Sourcetree で開く",
        "🏥 Flutter project diagnostics": "🏥 Flutter プロジェクトの診断",
        "🏥 Flutter diagnostics": "🏥 Flutter 診断",
        "🏷️ Repair Flutter plugin namespaces": "🏷️ Flutter プラグインの namespace を修復",
        "👁️ Show / hide hidden files": "👁️ 隠しファイルを表示 / 非表示",
        "💓 OpenHarmony Flutter diagnostics": "💓 OpenHarmony Flutter の環境診断",
        "💠 Open project in Visual Studio": "💠 Visual Studio でプロジェクトを開く",
        "💻 Open in terminal": "💻 ターミナルで開く",
        "📄 View file in terminal": "📄 ターミナルでファイルを表示",
        "📋 Copy absolute path": "📋 絶対パスをコピー",
        "📚 Download Gradle distributions and build plugins": "📚 Gradle 配布物とビルドプラグインをダウンロード",
        "📝 Open project in VSCode": "📝 VSCode でプロジェクトを開く",
        "📡 Configure Git dynamic proxy": "📡 Git 動的プロキシを設定",
        "📤 Import Flutter Pub dependencies": "📤 Flutter Pub の依存関係をインポート",
        "📤 Import Flutter platform assets": "📤 Flutter プラットフォームアセットをインポート",
        "📤 Import Gradle distributions and dependency caches": "📤 Gradle 配布物と依存関係キャッシュをインポート",
        "📤 Import OpenHarmony dependencies": "📤 OpenHarmony の依存関係をインポート",
        "📤 Import Web dependencies": "📤 Web の依存関係をインポート",
        "📤 Import native build caches": "📤 ネイティブビルドキャッシュをインポート",
        "📤 Import Flutter project dependencies": "📤 Flutter プロジェクトの依存関係をインポート",
        "📤 Create empty commit and push": "📤 空のコミットを作成して Push",
        "📥 Install Flutter dependencies (pub get)": "📥 Flutter の依存関係をインストール（pub get）",
        "📥 Import private Flutter project dependencies": "📥 Flutter プロジェクトの非公開依存関係をインポート",
        "📥 Fetch Flutter Pub dependencies": "📥 Flutter Pub の依存関係を取得",
        "📥 Fetch Flutter project dependencies": "📥 Flutter プロジェクトの依存関係を取得",
        "📦 Package Flutter project": "📦 Flutter プロジェクトをパッケージ化",
        "📦 Package HarmonyOS (HAP + APP)": "📦 HarmonyOS をパッケージ化（HAP + APP）",
        "📱 Create Android emulator": "📱 Android エミュレーターを作成",
        "🔀 Install / switch Flutter SDK (FVM)": "🔀 Flutter SDK をインストール / 切り替え（FVM）",
        "🔀 Install / switch Flutter SDK": "🔀 Flutter SDK をインストール / 切り替え",
        "🔀 Install / switch Flutter environments": "🔀 Flutter 実行環境をインストール / 切り替え",
        "🔎 Show current Flutter SDK version": "🔎 現在の Flutter SDK バージョンを表示",
        "🔎 Show current Flutter project's SDK version": "🔎 現在の Flutter プロジェクトの SDK バージョンを表示",
        "🔐 Export private Flutter project dependencies": "🔐 Flutter プロジェクトの非公開依存関係をエクスポート",
        "🔎 Show file fingerprint Hash (SHA-256)": "🔎 ファイルのハッシュを表示（SHA-256）",
        "➕ Grant execute permission": "➕ 実行権限を付与",
        "➖ Remove execute permission": "➖ 実行権限を削除",
        "🔒 Grant execute permission": "🔒 実行権限を付与",
        "🔓 Remove execute permission": "🔓 実行権限を削除",
        "🔗 Copy Git remote URL": "🔗 Git リモート URL をコピー",
        "🔧 Flutter repairs": "🔧 Flutter の修復",
        "🕊️ Install / switch Flutter@OpenHarmony SDK": "🕊️ Flutter@OpenHarmony SDK をインストール / 切り替え",
        "🕊️ Fetch OpenHarmony dependencies": "🕊️ OpenHarmony の依存関係を取得",
        "🗃️ Download Flutter platform assets": "🗃️ Flutter プラットフォームアセットをダウンロード",
        "🗺️ Update code map (.codegraph)": "🗺️ コードマップを更新（.codegraph）",
        "🤖 Fetch Android native dependencies": "🤖 Android ネイティブの依存関係を取得",
        "🦋 Flutter development": "🦋 Flutter 開発",
        "🦋 Flutter development tools": "🦋 Flutter 開発ツール",
        "🧑‍⚕️ Native Flutter diagnostics": "🧑‍⚕️ ネイティブ Flutter の診断",
        "🧩 Export Flutter Pub dependencies": "🧩 Flutter Pub の依存関係をエクスポート",
        "🧩 Export Flutter platform assets": "🧩 Flutter プラットフォームアセットをエクスポート",
        "🧩 Export Flutter third-party dependencies": "🧩 Flutter のサードパーティ依存関係をエクスポート",
        "🧩 Export Gradle distributions and dependency caches": "🧩 Gradle 配布物と依存関係キャッシュをエクスポート",
        "🧩 Export OpenHarmony dependencies": "🧩 OpenHarmony の依存関係をエクスポート",
        "🧩 Export Web dependencies": "🧩 Web の依存関係をエクスポート",
        "🧩 Export native build caches": "🧩 ネイティブビルドキャッシュをエクスポート",
        "🧩 Export Flutter project dependencies": "🧩 Flutter プロジェクトの依存関係をエクスポート",
        "🧩 Merge file volumes / ✂️ Split file": "🧩 分割ファイルを結合 / ✂️ ファイルを分割",
        "🧭 Open project in Android Studio": "🧭 Android Studio でプロジェクトを開く",
        "🧯 Clean build output": "🧯 ビルド出力を削除",
        "🧰 Diagnose and repair Harmony emulator": "🧰 Harmony エミュレーターを診断して修復",
        "🧱 Flutter assets and build dependencies": "🧱 Flutter のアセットとビルド依存関係",
        "🧱 Prepare native libraries and build dependencies (combined)": "🧱 ネイティブライブラリとビルド依存関係を準備（組み合わせ）",
        "🧹 Clean build output": "🧹 ビルド出力を削除",
        "🩹 Repair missing Android SDK / platforms": "🩹 不足している Android SDK / platforms を修復",
        "🩺 Diagnose and repair Android emulator": "🩺 Android エミュレーターを診断して修復",
        "🚀 Set up Flutter project": "🚀 Flutter プロジェクトをセットアップ",
        "🚚 Import all Flutter dependencies": "🚚 Flutter の依存関係をすべてインポート",
        "🚚 Export all Flutter dependencies": "🚚 Flutter の依存関係をすべてエクスポート",
        "Jobs Windows · Uninstall Explorer extensions": "Jobs Windows · Explorer 拡張機能をアンインストール",
        "Jobs Windows · Install Explorer extensions": "Jobs Windows · Explorer 拡張機能をインストール",
        "Jobs Windows · Manage Explorer extensions": "Jobs Windows · Explorer 拡張機能を管理",
        "Jobs Windows · Configure Explorer extensions": "Jobs Windows · Explorer 拡張機能を設定",
        "Drag the divider vertically to resize the log": "区切り線を上下にドラッグしてログの高さを調整",
        "Drag vertically to resize the log": "上下にドラッグしてログの高さを調整",
        "Validate the Flutter project, diagnose the toolchain in terminal, and choose a Flutter SDK version with fzf.": "Flutter プロジェクトを検証し、ターミナルでツールチェーンを診断して、fzf で Flutter SDK バージョンを選択します。",
        "Validate the Flutter project, then show the active SDK version (project FVM or system SDK) in terminal and compare it with .fvmrc and pubspec constraints.": "Flutter プロジェクトを検証し、実際に使用中の SDK バージョン（プロジェクト FVM またはシステム SDK）をターミナルに読み取り専用で表示して、.fvmrc と pubspec の制約を確認します。",
        "Flutter roots only. Choose Android / iOS / HarmonyOS with fzf in CMD. Supports APK / AAB and HAP / APP. iOS requires MacOS and Xcode.": "Flutter ルートのみ表示します。CMD の fzf で Android / iOS / HarmonyOS を選択します。APK / AAB と HAP / APP に対応します。iOS には MacOS と Xcode が必要です。",
        "Flutter roots only. Choose a device and view logs in CMD; the app continues in the background after the window closes.": "Flutter ルートのみ表示します。CMD でデバイスを選択してログを表示します。ウィンドウを閉じても App はバックグラウンドで動作します。",
        "Flutter roots only. Read-only version and doctor diagnostics in terminal; no dependency fetching, cleanup, or tool upgrades.": "Flutter ルートのみ表示します。ターミナルでバージョンと doctor 診断を読み取り専用で実行します。依存関係の取得、削除、ツールの更新は行いません。",
        "Flutter roots only. Preview configured generators, then fetch dependencies and generate code after confirmation. Deleting conflicts requires separate opt-in.": "Flutter ルートのみ表示します。設定済みジェネレーターをプレビューし、確認後に依存関係の取得とコード生成を行います。競合ファイルの削除には個別の同意が必要です。",
        "Git worktree folders only. Detect nested repositories. Soft mode preserves the index and worktree; hard mode requires exact YES confirmation.": "Git ワークツリーフォルダのみ表示します。入れ子のリポジトリを認識します。soft はインデックスと作業内容を保持し、hard には正確な YES の確認が必要です。",
        "Desktop background on x64 Windows only. Missing tools come from the SDL mirror; missing system images come from the official Emulator. Enter selects a stable phone image; confirm its license to create and start a unique instance.": "x64 Windows のデスクトップ背景のみ表示します。不足するツールは SDL ミラーから、システムイメージは公式 Emulator から取得します。Enter で安定版の電話イメージを選び、ライセンスを確認して一意のインスタンスを作成・起動します。",
        "Manage only this package's actions. Unselected actions remain when uninstalling.": "このパッケージの操作のみを管理します。アンインストール時も未選択の操作は保持します。",
        "Desktop background only. Configure user-level Git to prefer the system proxy and fall back to a direct connection.": "デスクトップ背景のみ表示します。ユーザーレベルの Git を設定し、システムプロキシを優先して、失敗時は直接接続に切り替えます。",
        "Desktop background only. Diagnose the SDK in CMD, choose a device and system image, then create or start an Android AVD.": "デスクトップ背景のみ表示します。CMD で SDK を診断し、機種とシステムイメージを選択して Android AVD を作成または起動します。",
        "Desktop background only. Check existing DevEco Emulator instances, then start one or confirm a nondestructive restart. Data is preserved.": "デスクトップ背景のみ表示します。既存の DevEco Emulator とインスタンスを確認し、選択したものを起動するか、確認後にデータを保持して再起動します。",
        "Desktop background only. Check emulator location and /data; optionally reset caches, precisely uninstall, back up the AVD, and retest with a cold boot.": "デスクトップ背景のみ表示します。エミュレーターの場所と /data を確認します。任意でキャッシュのリセット、正確なアンインストール、AVD 全体のバックアップとコールドブートでの再テストを行えます。",
        "Show the next action on the desktop background. Toggle hidden files for the current user's Explorer without changing protected-system-file settings.": "デスクトップ背景に次の操作を表示します。現在のユーザーの Explorer で隠しファイルを切り替え、保護されたシステムファイルの設定は変更しません。",
        "Visible only for nonempty native Android or valid Flutter (official / HarmonyOS) project roots. Validated again before opening.": "空でないネイティブ Android または有効な Flutter（公式 / HarmonyOS）のプロジェクトルートのみ表示し、開く前にも検証します。",
        "Preview: the selection is shown in the log. No installation or uninstallation was performed.": "プレビューのみ：選択内容をログに表示しました。インストールやアンインストールは行っていません。",
        "Preview only. Confirming displays the selection in the log without installing, uninstalling, or writing state or registry entries.": "機能選択のプレビューのみです。確認すると下部ログに選択内容を表示します。インストール、アンインストール、状態やレジストリへの書き込みは行いません。",
        "Deployed copies use their bound location. To change it, open the manager from the source directory. Default installations run in the current user's LocalAppData; local builds run under this package's work directory and stop working if it moves.": "配布済みコピーは現在の配置先を使用します。変更するにはソースディレクトリからマネージャーを開いてください。既定では現在のユーザーの LocalAppData で単独実行し、ローカルビルドはパッケージの work 内で動作するため、移動すると機能しなくなります。",
        "Prefer Windows Terminal; otherwise use system PowerShell.": "Windows Terminal を優先し、利用できなければシステム PowerShell を使用します。",
        "Could not save preferences: ": "設定を保存できませんでした： ",
        "Save settings": "設定を保存",
        "Protect local changes. On conflict, choose to restore, discard changes, or commit and retry.": "ローカルの変更を保護します。競合時は復元、変更の破棄、またはコミット後に再試行を選択してください。",
        "All operations completed. Copy the log or close the panel.": "すべての処理が完了しました。ログをコピーするか、パネルを閉じてください。",
        "Other context-menu features": "その他のコンテキストメニュー機能",
        "Create or synchronize the code map for the current directory.": "現在のディレクトリのコードマップを作成または同期します。",
        "Feature and log divider": "機能とログの区切り線",
        "Select features, then confirm. Unselected features remain. Hover for installation details.": "機能を選択して確認してください。未選択の機能は保持されます。インストール状況はポインターを重ねると確認できます。",
        "Checked features are installed; unchecked ones are uninstalled. Saving an empty selection disables all installed features.": "選択した機能はインストールし、未選択の機能はアンインストールします。選択をすべて解除して保存すると、インストール済み機能をすべて無効にします。",
        "Select features to install. Enabled sibling actions and other unselected features remain.": "インストールする機能を選択してください。有効な同梱の操作とその他の未選択機能は保持されます。",
        "Total uninstall time": "アンインストール総時間",
        "Uninstall selected": "選択項目をアンインストール",
        "Uninstall selected features": "選択した機能をアンインストール",
        "Uninstall time": "アンインストール時間",
        "Cancel": "キャンセル",
        "Uninstall only selected installed features. Other features, logs, backups and tools remain.": "選択したインストール済み機能のみを削除します。その他の機能、ログ、バックアップ、ツールは保持します。",
        "Change only the current user's ExecuteFile ACL for a single regular NTFS file after confirmation. Does not launch the file or change global policy.": "確認後、通常の NTFS ファイル 1 個について、現在のユーザーの ExecuteFile ACL のみを変更します。ファイルの起動やグローバルポリシーの変更は行いません。",
        "View a single regular file. Files over 1 MiB or suspected binary files require YES in the terminal.": "通常ファイルを 1 個だけ表示します。1 MiB 超またはバイナリの疑いがある場合、ターミナルで YES の入力が必要です。",
        "Clean only the selected packages' build workspaces. Installed DLLs, scripts, settings and registry entries remain.": "選択したパッケージ専用のビルド作業領域のみを削除します。インストール済み DLL、スクリプト、設定、レジストリエントリは保持します。",
        "Copy full log": "ログ全体をコピー",
        "Copy the original remote URL for the current branch.": "現在のブランチの元のリモート URL をコピーします。",
        "Copy the absolute path of a file or folder.": "ファイルまたはフォルダの絶対パスをコピーします。",
        "Could not copy the log: ": "ログをコピーできませんでした： ",
        "Failed — open log": "失敗 — ログを開く",
        "Install / update": "インストール / 更新",
        "Install / update selected features": "選択した機能をインストール / 更新",
        "Total install time": "インストール総時間",
        "Install time": "インストール時間",
        "Merge appears for a complete selected volume set; split appears for one regular file. Originals are always preserved.": "同じ組の分割ファイルをすべて選択すると結合を表示し、通常ファイル 1 個を選択すると分割を表示します。元のファイルは常に保持します。",
        "Live log (drag the divider to resize)": "リアルタイムログ（上の区切り線で高さを調整）",
        "Installation stopped after the current package transaction. Unstarted items are marked Not run.": "現在のパッケージのトランザクション完了後にインストールを停止しました。未開始の項目は「未実行」と表示します。",
        "Stop requested. Waiting for the current package transaction; later items will not run.": "停止を要求しました。現在のパッケージのトランザクション終了を待っています。以降の項目は実行しません。",
        "Selected {0} / {1}. Closing or cancelling makes no changes.": "{0} / {1} 件を選択。閉じるかキャンセルすると変更は行われません。",
        "Hover for feature details. Windows 11: right-click → Show more options.": "ポインターを重ねると機能の説明を表示します。Windows 11：右クリック → その他のオプションを表示。",
        "Could not open the full log: ": "完全なログを開けませんでした： ",
        "Open the repository website for the current Git worktree.": "現在の Git ワークツリーのリポジトリ Web サイトを開きます。",
        "Open the solution or project at the current directory level.": "現在の階層のソリューションまたはプロジェクトを開きます。",
        "Export resolved third-party Pub sources and licenses from the project lockfile. Press Enter to use the desktop as output.": "プロジェクトのロックファイルに従い、解決済みサードパーティ Pub ソースとライセンスをエクスポートします。出力先は Enter でデスクトップを選べます。",
        "An operation is running. Wait for the transaction to finish before closing. Logs can be copied at any time.": "操作を実行中です。トランザクション完了後に閉じてください。ログはいつでもコピーできます。",
        "Could not build the operation plan: ": "操作計画を作成できませんでした： ",
        "Could not start the operation: ": "操作を開始できませんでした： ",
        "Log: ": "ログ： ",
        "🈶 Repair Chinese paths in Flutter project": "🈶 Flutter プロジェクトの中国語パスを修復",
        "Not installed; nothing to uninstall": "未インストール：削除不要",
        "Not installed": "未インストール",
        "Not run": "未実行",
        "This feature": "この機能",
        "Local build directory (moving or cleaning it disables the menu)": "ローカルビルドディレクトリ（移動や削除でメニューが無効）",
        "Validate the branch, staging area and upstream, then confirm the push.": "ブランチ、ステージング領域、上流を検証してから Push を確認します。",
        "Validate the Flutter project, then fetch dependencies.": "Flutter プロジェクトを検証してから依存関係を取得します。",
        "Installing / updating…": "インストール / 更新中…",
        "This entry has been removed. Existing installations can be uninstalled but cannot be reinstalled.": "この項目は削除済みです。既存のインストールは削除できますが、再インストールはできません。",
        "No features require processing; ": "処理が必要な機能はありません； ",
        "No features require processing. No settings were changed.": "処理が必要な機能はありません。設定は変更されていません。",
        "Total cleanup time": "クリーンアップ総時間",
        "Cleanup time": "クリーンアップ時間",
        "Click to read the full session log in a new PowerShell window. The current task continues.": "クリックすると、新しい PowerShell ウィンドウに今回の完全なセッションログを表示します。現在のタスクは継続します。",
        "Pending": "保留中",
        "Waiting to stop…": "停止を待機中…",
        "Ordered Flutter development, diagnostics, repair and maintenance tools. Regular actions use project FVM; environment setup supports FVM / system Flutter and jEnv / system Java.": "Flutter の開発、診断、修復、保守ツールを固定順で表示します。通常の操作はプロジェクト FVM を使用し、環境設定は FVM / システム Flutter と jEnv / システム Java に対応します。",
        "Detect the Flutter / Android project and preview cleanup scope. iOS cleanup is unavailable on Windows.": "Flutter / Android プロジェクトを検出して削除範囲をプレビューします。Windows では iOS のクリーンアップは利用できません。",
        "Could not read preferences: ": "設定を読み取れませんでした： ",
        "Could not read the log: ": "ログを読み取れませんでした： ",
        "Explorer context-menu extensions · ": "Explorer コンテキストメニュー拡張機能 · ",
        "Explorer extensions · Manage": "Explorer 拡張機能 · 管理",
        "Return selection": "選択内容を返す",
        "Exit code: ": "終了コード： ",
        "Choose an operation and select features. Unselected features remain; only installed features can be uninstalled.": "操作を選び、機能を選択してください。未選択の機能は保持されます。アンインストールはインストール済みの機能のみが対象です。",
        "Some features failed; other selected features were still processed. Click a failed status to open the full session log.": "一部の機能が失敗しましたが、その他の選択した機能は処理しました。失敗状態をクリックすると、完全なセッションログを表示します。",
        "Available for nonempty regular directories outside iOS projects, including Flutter roots. Validated again before opening.": "空ではない、iOS プロジェクト以外の通常ディレクトリで利用できます。Flutter ルートにも対応し、開く前に再検証します。",
        "Default installation location (recommended)": "既定のインストール先（推奨）",
        "{0}; Results: succeeded {1}; nothing to uninstall {2}; failed {3}; not run {4}": "{0}；結果：成功 {1}；削除不要 {2}；失敗 {3}；未実行 {4}",
        "{0} Exit code: {1}.": "{0} 終了コード：{1}。",
        "{0} {1}": "{0} {1}",
        "{0}{1} {2}": "{0}{1} {2}",
        "{0} in progress; completed {1} / {2} ({3}% by completed items); {4} {5}": "{0}を実行中；完了 {1} / {2}（{3}%、完了項目基準）；{4} {5}",
        "{0} Completed {1} / {2} ({3}% by completed items); {4} {5}": "{0} 完了 {1} / {2}（{3}%、完了項目基準）；{4} {5}",
        "Close management panel": "管理パネルを閉じる",
        "Run in the menu bar, or quit the installation / uninstallation panel?": "メニューバーで実行を続けますか？ それともインストール／アンインストールパネルを完全に終了しますか？",
        "Run in background": "バックグラウンドで実行",
        "Quit completely": "完全に終了",
        "Show management panel": "管理パネルを表示",
        "Status: {0}": "状態：{0}",
        "A task is running. You can quit after it finishes.": "タスクを実行中です。完了後に完全に終了できます。"
      },
      "fr": {
        "Update development environment (update)": "Mettre à jour l’environnement de développement (update)",
        "Total disk space": "Espace disque total disponible",
        "Create script launcher": "Créer un lanceur de script",
        "Theme": "Thème",
        "Language": "Langue",
        "🎨 Theme": "🎨 Thème",
        "🌐 Language": "🌐 Langue",
        "Follow system": "Suivre le système",
        "Dark": "Sombre",
        "Light": "Clair",
        "Jobs Finder Extension Manager": "Gestionnaire d’extensions Finder Jobs",
        "Customize Finder Context Menu": "Personnaliser le menu contextuel du Finder",
        "Close Manager": "Fermer le gestionnaire",
        "Edit": "Modifier",
        "Copy": "Copier",
        "Select all": "Tout sélectionner",
        "Clear all": "Tout désélectionner",
        "Close": "Fermer",
        "OK": "Valider",
        "Install": "Installer",
        "Install / Update": "Installer / Mettre à jour",
        "Uninstall": "Désinstaller",
        "Cleanup": "Nettoyage",
        "Clean build products": "Nettoyer les produits de compilation",
        "🧹 Clean build products": "🧹 Nettoyer les produits de compilation",
        "Stop installation": "Arrêter l’installation",
        "Stopping…": "Arrêt en cours…",
        "Action: install / update or uninstall": "Action : installer / mettre à jour ou désinstaller",
        "Uninstall removes selected menus only. Group selection affects its own group.": "La désinstallation ne supprime que les menus sélectionnés. La sélection par groupe ne concerne que ce groupe.",
        "Install / uninstall with the combined App in Applications": "Installer / désinstaller avec l’app combinée dans Applications",
        "Install or uninstall the combined App in Applications": "Installer ou désinstaller l’app combinée dans Applications",
        "Selected: manage features in /Applications/Jobs自定义右键菜单.app. Otherwise use the build directory.": "Coché : gérer les fonctions dans /Applications/Jobs自定义右键菜单.app. Sinon, utiliser le dossier de compilation.",
        "Clean this build after successful installation": "Nettoyer cette compilation après une installation réussie",
        "Clean this build only after the combined App is installed and verified in Applications. Keep failed builds.": "Nettoyer cette compilation uniquement après installation et vérification de l’app combinée dans Applications. Conserver les compilations échouées.",
        "Clean build products of selected features without installing or uninstalling.": "Nettoyer les produits de compilation des fonctions sélectionnées, sans installation ni désinstallation.",
        "Clean selected features' build products": "Nettoyer les produits de compilation des fonctions sélectionnées",
        "Open Privacy & Security": "Ouvrir Confidentialité et sécurité",
        "Add and enable Jobs右键菜单管理面板.app in Privacy & Security → App Management. This only opens Settings.": "Ajouter et activer Jobs右键菜单管理面板.app dans Confidentialité et sécurité → Gestion des apps. Ce bouton ouvre uniquement les réglages.",
        "Target: build directory. Cleaning these products affects installed features.": "Cible : dossier de compilation. Nettoyer ces produits affecte les fonctions installées.",
        "App: Jobs自定义右键菜单.app at /Applications/Jobs自定义右键菜单.app (build products can be cleaned after installation)": "App : Jobs自定义右键菜单.app dans /Applications/Jobs自定义右键菜单.app (les produits de compilation peuvent être nettoyés après l’installation)",
        "Drag the divider to resize the log. Features and logs scroll separately.": "Faire glisser le séparateur pour redimensionner le journal. Les fonctions et le journal défilent séparément.",
        "Feature list and live log divider": "Séparateur entre la liste des fonctions et le journal en direct",
        "Live log (select and copy text)": "Journal en direct (texte sélectionnable et copiable)",
        "Copy log": "Copier le journal",
        "Log file": "Fichier journal",
        "Auto-scroll": "Défilement automatique",
        "Ready. Select features and choose an action.": "Prêt. Sélectionner des fonctions et une action.",
        "A task is running. Wait for it to finish before closing.": "Une tâche est en cours. Attendre sa fin avant de fermer.",
        "Unable to view this log": "Impossible d’afficher ce journal",
        "Log is missing or unreadable: {0}": "Journal absent ou illisible : {0}",
        "Unable to open log terminal: {0}": "Impossible d’ouvrir le terminal du journal : {0}",
        "Click to show this session's full log in a new terminal: {0}": "Cliquer pour afficher le journal complet de cette session dans un nouveau terminal : {0}",
        "Selected {0} / {1}. Select at least one. Changing action keeps selection.": "Sélection : {0} / {1}. Sélectionner au moins un élément. Changer d’action conserve la sélection.",
        "Selected {0} / {1}": "Sélection : {0} / {1}",
        "{0}: select all": "{0} : tout sélectionner",
        "{0}: clear all": "{0} : tout désélectionner",
        "Waiting": "En attente",
        "Cleaning…": "Nettoyage…",
        "Uninstalling…": "Désinstallation…",
        "Installing…": "Installation…",
        "Cleaned": "Nettoyé",
        "Uninstalled": "Désinstallé",
        "Installed": "Installé",
        "Skipped": "Ignoré",
        "Not installed; nothing to remove": "Non installé ; rien à supprimer",
        "Failed: see log": "Échec : voir le journal",
        "Selected": "Sélectionné",
        "Not selected": "Non sélectionné",
        "App Management permission required": "Autorisation de gestion des apps requise",
        "Permission check required": "Vérification des autorisations requise",
        "Stopped": "Arrêté",
        "Completed": "Terminé",
        "Task failed": "Échec de la tâche",
        "{0}: processed {1} / {2} ({3}, completed items); {4} time {5}": "{0} : traité {1} / {2} ({3}, éléments terminés) ; durée de {4} : {5}",
        "{0} ready": "{0} prêt",
        "{0} ready; {1} time {2}": "{0} prêt ; durée de {1} : {2}",
        "Finishing the current feature, then stopping; install time {0}": "Fin de la fonction en cours, puis arrêt ; durée d’installation : {0}",
        "{0}: {1} succeeded, {2} failed, {3} skipped; exit {4}; {5}; {6} time {7}": "{0} : {1} réussis, {2} échoués, {3} ignorés ; code {4} ; {5} ; durée de {6} : {7}",
        "{0}: {1} succeeded, {2} failed, {3} not installed, {4} skipped; exit {5}; {6}; {7} time {8}": "{0} : {1} réussis, {2} échoués, {3} non installés, {4} ignorés ; code {5} ; {6} ; durée de {7} : {8}",
        "{0}: {1} succeeded, {2} failed, {3} not installed; exit {4}; {5}; {6} time {7}": "{0} : {1} réussis, {2} échoués, {3} non installés ; code {4} ; {5} ; durée de {6} : {7}",
        "{0}: {1} succeeded, {2} failed; exit {3}; {4}; {5} time {6}": "{0} : {1} réussis, {2} échoués ; code {3} ; {4} ; durée de {5} : {6}",
        "Open projects in IDEs": "Ouvrir les projets dans les IDE",
        "Git tools": "Outils Git",
        "Files and general tools": "Fichiers et outils généraux",
        "Flutter tools · submenu actions": "Outils Flutter · actions du sous-menu",
        "iOS / CocoaPods tools": "Outils iOS / CocoaPods",
        "Simulator tools": "Outils de simulateur",
        "Open project in Android Studio": "Ouvrir le projet dans Android Studio",
        "Open project in VSCode": "Ouvrir le projet dans VSCode",
        "Open project in Xcode": "Ouvrir le projet dans Xcode",
        "Pull latest Git changes": "Récupérer les dernières modifications Git",
        "Roll back Git commit": "Revenir à un commit Git",
        "Open Git remote URL": "Ouvrir l’URL distante Git",
        "Copy Git remote URL": "Copier l’URL distante Git",
        "Copy absolute path": "Copier le chemin absolu",
        "Create file": "Créer un fichier",
        "View file fingerprint Hash (SHA-256)": "Afficher l’empreinte du fichier (SHA-256)",
        "Hide / show selected items": "Masquer / afficher les éléments sélectionnés",
        "Send to external disk or network volume": "Envoyer vers un disque externe ou un volume réseau",
        "Grant execute permission (chmod +x)": "Accorder le droit d’exécution (chmod +x)",
        "Remove execute permission (chmod -x)": "Retirer le droit d’exécution (chmod -x)",
        "Re-sign IPA without building": "Signer à nouveau l’IPA sans compiler",
        "Show / hide files": "Afficher / masquer les fichiers",
        "Create iOS simulator": "Créer un simulateur iOS",
        "Create Android simulator": "Créer un simulateur Android",
        "Create Harmony simulator": "Créer un simulateur Harmony",
        "Check / repair Android simulator": "Vérifier / réparer le simulateur Android",
        "Check / repair Harmony simulator": "Vérifier / réparer le simulateur Harmony",
        "Configure Git proxy": "Configurer le proxy Git",
        "Open in terminal": "Ouvrir dans le terminal",
        "View file contents in terminal": "Afficher le contenu du fichier dans le terminal",
        "Merge file parts": "Fusionner les parties du fichier",
        "Split file": "Scinder le fichier",
        "Clean Android / OpenHarmony builds": "Nettoyer les compilations Android / OpenHarmony",
        "Update code map (.codegraph)": "Mettre à jour la carte du code (.codegraph)",
        "Create empty commit and push in terminal": "Créer un commit vide et pousser dans le terminal",
        "Disable CocoaPods build sandbox": "Désactiver le bac à sable de compilation CocoaPods",
        "Install CocoaPods": "Installer CocoaPods",
        "CocoaPods source: CDN → GitHub": "Source CocoaPods : CDN → GitHub",
        "Export all project Pod files": "Exporter tous les fichiers Pod du projet",
        "Inspect Xcode project dependencies": "Inspecter les dépendances du projet Xcode",
        "Update local CocoaPods repositories": "Mettre à jour les dépôts CocoaPods locaux",
        "Check local Pod builds (.podspec folder)": "Vérifier les compilations Pod locales (dossier .podspec)",
        "Install / update JobsCodeSnippets": "Installer / mettre à jour JobsCodeSnippets",
        "Clean iOS / Xcode builds": "Nettoyer les compilations iOS / Xcode",
        "Set up Flutter project": "Configurer le projet Flutter",
        "Run Flutter project in terminal": "Exécuter le projet Flutter dans le terminal",
        "Fetch Flutter Pub dependencies": "Récupérer les dépendances Flutter Pub",
        "Fetch native Android dependencies": "Récupérer les dépendances Android natives",
        "Fetch CocoaPods dependencies": "Récupérer les dépendances CocoaPods",
        "Fetch Swift Package dependencies": "Récupérer les dépendances Swift Package",
        "Fetch OpenHarmony dependencies": "Récupérer les dépendances OpenHarmony",
        "Prepare native libraries and build dependencies": "Préparer les bibliothèques natives et les dépendances de compilation",
        "Download Flutter platform resources": "Télécharger les ressources de plateforme Flutter",
        "Fetch Web project dependencies": "Récupérer les dépendances du projet Web",
        "🧳 Export Flutter dependencies": "🧳 Exporter les dépendances Flutter",
        "Export Flutter Pub dependencies": "Exporter les dépendances Flutter Pub",
        "🔐 Export private Flutter dependencies": "🔐 Exporter les dépendances Flutter privées",
        "📥 Import Flutter dependencies": "📥 Importer les dépendances Flutter",
        "Import Flutter Pub dependencies": "Importer les dépendances Flutter Pub",
        "📥 Import private Flutter dependencies": "📥 Importer les dépendances Flutter privées",
        "Export Gradle distributions and cache": "Exporter les distributions et le cache Gradle",
        "Import Gradle distributions and cache": "Importer les distributions et le cache Gradle",
        "Export CocoaPods dependencies": "Exporter les dépendances CocoaPods",
        "Import CocoaPods dependencies": "Importer les dépendances CocoaPods",
        "Export Swift Package dependencies": "Exporter les dépendances Swift Package",
        "Import Swift Package dependencies": "Importer les dépendances Swift Package",
        "Export OpenHarmony dependencies": "Exporter les dépendances OpenHarmony",
        "Import OpenHarmony dependencies": "Importer les dépendances OpenHarmony",
        "Export native build cache": "Exporter le cache de compilation natif",
        "Import native build cache": "Importer le cache de compilation natif",
        "Export Flutter platform resources": "Exporter les ressources de plateforme Flutter",
        "Import Flutter platform resources": "Importer les ressources de plateforme Flutter",
        "Export Web dependencies": "Exporter les dépendances Web",
        "Import Web dependencies": "Importer les dépendances Web",
        "Show Flutter project SDK version": "Afficher la version du SDK du projet Flutter",
        "Install / switch Flutter SDK": "Installer / changer de SDK Flutter",
        "Install / switch Flutter@OpenHarmony SDK": "Installer / changer de SDK Flutter@OpenHarmony",
        "Install / switch Java SDK": "Installer / changer de SDK Java",
        "Download Gradle distributions and plugins": "Télécharger les distributions et plugins Gradle",
        "Generate Flutter code": "Générer le code Flutter",
        "Package iOS": "Créer le paquet iOS",
        "Package Android": "Créer le paquet Android",
        "Package Harmony (HAP + APP)": "Créer le paquet Harmony (HAP + APP)",
        "Check native Flutter project": "Vérifier le projet Flutter natif",
        "Check OpenHarmony Flutter environment": "Vérifier l’environnement Flutter OpenHarmony",
        "Repair missing Android SDK / platforms": "Réparer les SDK / plateformes Android manquants",
        "Repair Chinese Flutter project paths": "Réparer les chemins chinois du projet Flutter",
        "Repair Flutter plugin namespaces": "Réparer les espaces de noms des plugins Flutter",
        "Convert relative Dart imports to packages": "Convertir les imports Dart relatifs en imports de paquets",
        "Clean current Flutter project builds": "Nettoyer les compilations du projet Flutter actuel",
        "Dependency and cache maintenance": "Maintenance des dépendances et des caches",
        "Custom Explorer context menu": "Menu contextuel Explorer personnalisé",
        "Jobs Windows · Custom Explorer context menu": "Jobs Windows · Menu contextuel Explorer personnalisé",
        "Show a regular file's SHA-256 in a new terminal and copy the digest; do not modify or execute the file.": "Afficher le SHA-256 d’un fichier ordinaire dans un nouveau terminal et copier son empreinte ; ne pas modifier ni exécuter le fichier.",
        " (preview)": " (aperçu)",
        "⏪ Roll back Git commits": "⏪ Revenir à des commits Git",
        "▶️ Run Flutter project in terminal": "▶️ Exécuter le projet Flutter dans le terminal",
        "☕ Install / switch Java SDK": "☕ Installer / changer de SDK Java",
        "♻️ Flutter cleanup and maintenance": "♻️ Nettoyage et maintenance Flutter",
        "⚙️ Generate Flutter code": "⚙️ Générer le code Flutter",
        "✅ Installed": "✅ Installé",
        "⬇️ Pull latest Git changes": "⬇️ Récupérer les dernières modifications Git",
        "🌈 Create Harmony emulator": "🌈 Créer un émulateur Harmony",
        "🌐 Open Git remote URL": "🌐 Ouvrir l’URL distante Git",
        "🌐 Fetch Web project dependencies": "🌐 Récupérer les dépendances du projet Web",
        "🌳 Open in Sourcetree": "🌳 Ouvrir dans Sourcetree",
        "🏥 Flutter project diagnostics": "🏥 Diagnostic du projet Flutter",
        "🏥 Flutter diagnostics": "🏥 Diagnostic Flutter",
        "🏷️ Repair Flutter plugin namespaces": "🏷️ Réparer les espaces de noms des plugins Flutter",
        "👁️ Show / hide hidden files": "👁️ Afficher / masquer les fichiers cachés",
        "💓 OpenHarmony Flutter diagnostics": "💓 Diagnostic Flutter OpenHarmony",
        "💠 Open project in Visual Studio": "💠 Ouvrir le projet dans Visual Studio",
        "💻 Open in terminal": "💻 Ouvrir dans le terminal",
        "📄 View file in terminal": "📄 Afficher le fichier dans le terminal",
        "📋 Copy absolute path": "📋 Copier le chemin absolu",
        "📚 Download Gradle distributions and build plugins": "📚 Télécharger les distributions et plugins de compilation Gradle",
        "📝 Open project in VSCode": "📝 Ouvrir le projet dans VSCode",
        "📡 Configure Git dynamic proxy": "📡 Configurer le proxy dynamique Git",
        "📤 Import Flutter Pub dependencies": "📤 Importer les dépendances Flutter Pub",
        "📤 Import Flutter platform assets": "📤 Importer les ressources de plateforme Flutter",
        "📤 Import Gradle distributions and dependency caches": "📤 Importer les distributions et caches de dépendances Gradle",
        "📤 Import OpenHarmony dependencies": "📤 Importer les dépendances OpenHarmony",
        "📤 Import Web dependencies": "📤 Importer les dépendances Web",
        "📤 Import native build caches": "📤 Importer les caches de compilation natifs",
        "📤 Import Flutter project dependencies": "📤 Importer les dépendances du projet Flutter",
        "📤 Create empty commit and push": "📤 Créer un commit vide et pousser",
        "📥 Install Flutter dependencies (pub get)": "📥 Installer les dépendances Flutter (pub get)",
        "📥 Import private Flutter project dependencies": "📥 Importer les dépendances privées du projet Flutter",
        "📥 Fetch Flutter Pub dependencies": "📥 Récupérer les dépendances Flutter Pub",
        "📥 Fetch Flutter project dependencies": "📥 Récupérer les dépendances du projet Flutter",
        "📦 Package Flutter project": "📦 Créer le paquet du projet Flutter",
        "📦 Package HarmonyOS (HAP + APP)": "📦 Créer le paquet HarmonyOS (HAP + APP)",
        "📱 Create Android emulator": "📱 Créer un émulateur Android",
        "🔀 Install / switch Flutter SDK (FVM)": "🔀 Installer / changer de SDK Flutter (FVM)",
        "🔀 Install / switch Flutter SDK": "🔀 Installer / changer de SDK Flutter",
        "🔀 Install / switch Flutter environments": "🔀 Installer / changer d’environnement Flutter",
        "🔎 Show current Flutter SDK version": "🔎 Afficher la version du SDK Flutter actuel",
        "🔎 Show current Flutter project's SDK version": "🔎 Afficher la version du SDK du projet Flutter actuel",
        "🔐 Export private Flutter project dependencies": "🔐 Exporter les dépendances privées du projet Flutter",
        "🔎 Show file fingerprint Hash (SHA-256)": "🔎 Afficher l’empreinte du fichier (SHA-256)",
        "➕ Grant execute permission": "➕ Accorder le droit d’exécution",
        "➖ Remove execute permission": "➖ Retirer le droit d’exécution",
        "🔒 Grant execute permission": "🔒 Accorder le droit d’exécution",
        "🔓 Remove execute permission": "🔓 Retirer le droit d’exécution",
        "🔗 Copy Git remote URL": "🔗 Copier l’URL distante Git",
        "🔧 Flutter repairs": "🔧 Réparations Flutter",
        "🕊️ Install / switch Flutter@OpenHarmony SDK": "🕊️ Installer / changer de SDK Flutter@OpenHarmony",
        "🕊️ Fetch OpenHarmony dependencies": "🕊️ Récupérer les dépendances OpenHarmony",
        "🗃️ Download Flutter platform assets": "🗃️ Télécharger les ressources de plateforme Flutter",
        "🗺️ Update code map (.codegraph)": "🗺️ Mettre à jour la carte du code (.codegraph)",
        "🤖 Fetch Android native dependencies": "🤖 Récupérer les dépendances Android natives",
        "🦋 Flutter development": "🦋 Développement Flutter",
        "🦋 Flutter development tools": "🦋 Outils de développement Flutter",
        "🧑‍⚕️ Native Flutter diagnostics": "🧑‍⚕️ Diagnostic Flutter natif",
        "🧩 Export Flutter Pub dependencies": "🧩 Exporter les dépendances Flutter Pub",
        "🧩 Export Flutter platform assets": "🧩 Exporter les ressources de plateforme Flutter",
        "🧩 Export Flutter third-party dependencies": "🧩 Exporter les dépendances tierces Flutter",
        "🧩 Export Gradle distributions and dependency caches": "🧩 Exporter les distributions et caches de dépendances Gradle",
        "🧩 Export OpenHarmony dependencies": "🧩 Exporter les dépendances OpenHarmony",
        "🧩 Export Web dependencies": "🧩 Exporter les dépendances Web",
        "🧩 Export native build caches": "🧩 Exporter les caches de compilation natifs",
        "🧩 Export Flutter project dependencies": "🧩 Exporter les dépendances du projet Flutter",
        "🧩 Merge file volumes / ✂️ Split file": "🧩 Fusionner les volumes / ✂️ Scinder le fichier",
        "🧭 Open project in Android Studio": "🧭 Ouvrir le projet dans Android Studio",
        "🧯 Clean build output": "🧯 Nettoyer les sorties de compilation",
        "🧰 Diagnose and repair Harmony emulator": "🧰 Diagnostiquer et réparer l’émulateur Harmony",
        "🧱 Flutter assets and build dependencies": "🧱 Ressources Flutter et dépendances de compilation",
        "🧱 Prepare native libraries and build dependencies (combined)": "🧱 Préparer les bibliothèques natives et les dépendances de compilation (combiné)",
        "🧹 Clean build output": "🧹 Nettoyer les sorties de compilation",
        "🩹 Repair missing Android SDK / platforms": "🩹 Réparer les SDK / plateformes Android manquants",
        "🩺 Diagnose and repair Android emulator": "🩺 Diagnostiquer et réparer l’émulateur Android",
        "🚀 Set up Flutter project": "🚀 Configurer le projet Flutter",
        "🚚 Import all Flutter dependencies": "🚚 Importer toutes les dépendances Flutter",
        "🚚 Export all Flutter dependencies": "🚚 Exporter toutes les dépendances Flutter",
        "Jobs Windows · Uninstall Explorer extensions": "Jobs Windows · Désinstaller les extensions Explorer",
        "Jobs Windows · Install Explorer extensions": "Jobs Windows · Installer les extensions Explorer",
        "Jobs Windows · Manage Explorer extensions": "Jobs Windows · Gérer les extensions Explorer",
        "Jobs Windows · Configure Explorer extensions": "Jobs Windows · Configurer les extensions Explorer",
        "Drag the divider vertically to resize the log": "Faire glisser le séparateur verticalement pour redimensionner le journal",
        "Drag vertically to resize the log": "Faire glisser verticalement pour redimensionner le journal",
        "Validate the Flutter project, diagnose the toolchain in terminal, and choose a Flutter SDK version with fzf.": "Valider le projet Flutter, diagnostiquer la chaîne d’outils dans le terminal et choisir une version du SDK Flutter avec fzf.",
        "Validate the Flutter project, then show the active SDK version (project FVM or system SDK) in terminal and compare it with .fvmrc and pubspec constraints.": "Valider le projet Flutter, puis afficher la version du SDK actif (FVM du projet ou SDK système) dans le terminal et la comparer à .fvmrc et aux contraintes du pubspec.",
        "Flutter roots only. Choose Android / iOS / HarmonyOS with fzf in CMD. Supports APK / AAB and HAP / APP. iOS requires MacOS and Xcode.": "Racines de projets Flutter uniquement. Choisir Android / iOS / HarmonyOS avec fzf dans CMD. Prend en charge APK / AAB et HAP / APP. iOS nécessite MacOS et Xcode.",
        "Flutter roots only. Choose a device and view logs in CMD; the app continues in the background after the window closes.": "Racines de projets Flutter uniquement. Choisir un appareil et consulter les journaux dans CMD ; l’app continue en arrière-plan après la fermeture de la fenêtre.",
        "Flutter roots only. Read-only version and doctor diagnostics in terminal; no dependency fetching, cleanup, or tool upgrades.": "Racines de projets Flutter uniquement. Diagnostic en lecture seule de la version et de doctor dans le terminal ; sans récupération de dépendances, nettoyage ni mise à niveau d’outils.",
        "Flutter roots only. Preview configured generators, then fetch dependencies and generate code after confirmation. Deleting conflicts requires separate opt-in.": "Racines de projets Flutter uniquement. Prévisualiser les générateurs configurés, puis récupérer les dépendances et générer le code après confirmation. La suppression des conflits exige un accord distinct.",
        "Git worktree folders only. Detect nested repositories. Soft mode preserves the index and worktree; hard mode requires exact YES confirmation.": "Dossiers d’arbres de travail Git uniquement. Détecter les dépôts imbriqués. Le mode soft préserve l’index et l’arbre de travail ; le mode hard exige la saisie exacte de YES.",
        "Desktop background on x64 Windows only. Missing tools come from the SDL mirror; missing system images come from the official Emulator. Enter selects a stable phone image; confirm its license to create and start a unique instance.": "Arrière-plan du bureau sur Windows x64 uniquement. Les outils manquants proviennent du miroir SDL ; les images système manquantes proviennent de l’Emulator officiel. Entrée choisit une image de téléphone stable ; confirmer sa licence pour créer et démarrer une instance unique.",
        "Manage only this package's actions. Unselected actions remain when uninstalling.": "Gérer uniquement les actions de ce paquet. Les actions non sélectionnées sont conservées lors de la désinstallation.",
        "Desktop background only. Configure user-level Git to prefer the system proxy and fall back to a direct connection.": "Arrière-plan du bureau uniquement. Configurer Git au niveau utilisateur pour privilégier le proxy système et utiliser une connexion directe en repli.",
        "Desktop background only. Diagnose the SDK in CMD, choose a device and system image, then create or start an Android AVD.": "Arrière-plan du bureau uniquement. Diagnostiquer le SDK dans CMD, choisir un appareil et une image système, puis créer ou démarrer un AVD Android.",
        "Desktop background only. Check existing DevEco Emulator instances, then start one or confirm a nondestructive restart. Data is preserved.": "Arrière-plan du bureau uniquement. Vérifier les instances DevEco Emulator existantes, puis en démarrer une ou confirmer un redémarrage sans destruction. Les données sont préservées.",
        "Desktop background only. Check emulator location and /data; optionally reset caches, precisely uninstall, back up the AVD, and retest with a cold boot.": "Arrière-plan du bureau uniquement. Vérifier l’emplacement de l’émulateur et /data ; proposer la réinitialisation des caches, une désinstallation ciblée, la sauvegarde de l’AVD et un nouveau test avec démarrage à froid.",
        "Show the next action on the desktop background. Toggle hidden files for the current user's Explorer without changing protected-system-file settings.": "Afficher l’action suivante sur l’arrière-plan du bureau. Basculer l’affichage des fichiers cachés dans l’Explorer de l’utilisateur actuel sans changer les paramètres des fichiers système protégés.",
        "Visible only for nonempty native Android or valid Flutter (official / HarmonyOS) project roots. Validated again before opening.": "Visible uniquement pour les racines non vides de projets Android natifs ou Flutter valides (officiel / HarmonyOS). Nouvelle validation avant ouverture.",
        "Preview: the selection is shown in the log. No installation or uninstallation was performed.": "Aperçu : la sélection apparaît dans le journal. Aucune installation ni désinstallation n’a été effectuée.",
        "Preview only. Confirming displays the selection in the log without installing, uninstalling, or writing state or registry entries.": "Aperçu uniquement. La confirmation affiche la sélection dans le journal sans installation, désinstallation ni écriture d’état ou du registre.",
        "Deployed copies use their bound location. To change it, open the manager from the source directory. Default installations run in the current user's LocalAppData; local builds run under this package's work directory and stop working if it moves.": "Les copies déployées utilisent leur emplacement lié. Pour le modifier, ouvrir le gestionnaire depuis le dossier source. Les installations par défaut s’exécutent dans LocalAppData de l’utilisateur actuel ; les compilations locales s’exécutent dans le dossier de travail du paquet et cessent de fonctionner s’il est déplacé.",
        "Prefer Windows Terminal; otherwise use system PowerShell.": "Privilégier Windows Terminal ; sinon, utiliser PowerShell système.",
        "Could not save preferences: ": "Impossible d’enregistrer les préférences : ",
        "Save settings": "Enregistrer les paramètres",
        "Protect local changes. On conflict, choose to restore, discard changes, or commit and retry.": "Protéger les modifications locales. En cas de conflit, choisir de restaurer, d’abandonner les modifications ou de créer un commit puis réessayer.",
        "All operations completed. Copy the log or close the panel.": "Toutes les opérations sont terminées. Copier le journal ou fermer le panneau.",
        "Other context-menu features": "Autres fonctions du menu contextuel",
        "Create or synchronize the code map for the current directory.": "Créer ou synchroniser la carte du code du dossier actuel.",
        "Feature and log divider": "Séparateur entre fonctions et journal",
        "Select features, then confirm. Unselected features remain. Hover for installation details.": "Sélectionner des fonctions, puis confirmer. Les fonctions non sélectionnées sont conservées. Survoler pour voir les détails d’installation.",
        "Checked features are installed; unchecked ones are uninstalled. Saving an empty selection disables all installed features.": "Les fonctions cochées sont installées ; celles décochées sont désinstallées. Enregistrer une sélection vide désactive toutes les fonctions installées.",
        "Select features to install. Enabled sibling actions and other unselected features remain.": "Sélectionner les fonctions à installer. Les actions voisines activées et les autres fonctions non sélectionnées sont conservées.",
        "Total uninstall time": "Durée totale de désinstallation",
        "Uninstall selected": "Désinstaller la sélection",
        "Uninstall selected features": "Désinstaller les fonctions sélectionnées",
        "Uninstall time": "Durée de désinstallation",
        "Cancel": "Annuler",
        "Uninstall only selected installed features. Other features, logs, backups and tools remain.": "Désinstaller uniquement les fonctions installées sélectionnées. Les autres fonctions, journaux, sauvegardes et outils sont conservés.",
        "Change only the current user's ExecuteFile ACL for a single regular NTFS file after confirmation. Does not launch the file or change global policy.": "Après confirmation, modifier uniquement l’ACL ExecuteFile de l’utilisateur actuel pour un seul fichier NTFS ordinaire. Ne lance pas le fichier et ne modifie pas la stratégie globale.",
        "View a single regular file. Files over 1 MiB or suspected binary files require YES in the terminal.": "Afficher un seul fichier ordinaire. Les fichiers de plus de 1 Mio ou potentiellement binaires exigent YES dans le terminal.",
        "Clean only the selected packages' build workspaces. Installed DLLs, scripts, settings and registry entries remain.": "Nettoyer uniquement les espaces de compilation des paquets sélectionnés. Les DLL, scripts, paramètres et entrées de registre installés sont conservés.",
        "Copy full log": "Copier le journal complet",
        "Copy the original remote URL for the current branch.": "Copier l’URL distante d’origine de la branche actuelle.",
        "Copy the absolute path of a file or folder.": "Copier le chemin absolu d’un fichier ou dossier.",
        "Could not copy the log: ": "Impossible de copier le journal : ",
        "Failed — open log": "Échec — ouvrir le journal",
        "Install / update": "Installer / mettre à jour",
        "Install / update selected features": "Installer / mettre à jour les fonctions sélectionnées",
        "Total install time": "Durée totale d’installation",
        "Install time": "Durée d’installation",
        "Merge appears for a complete selected volume set; split appears for one regular file. Originals are always preserved.": "La fusion apparaît pour un ensemble complet de volumes sélectionnés ; la scission apparaît pour un seul fichier ordinaire. Les originaux sont toujours conservés.",
        "Live log (drag the divider to resize)": "Journal en direct (faire glisser le séparateur pour redimensionner)",
        "Installation stopped after the current package transaction. Unstarted items are marked Not run.": "Installation arrêtée après la transaction du paquet actuel. Les éléments non commencés sont marqués Non exécuté.",
        "Stop requested. Waiting for the current package transaction; later items will not run.": "Arrêt demandé. Attente de la transaction du paquet actuel ; les éléments suivants ne seront pas exécutés.",
        "Selected {0} / {1}. Closing or cancelling makes no changes.": "Sélection : {0} / {1}. Fermer ou annuler n’apporte aucune modification.",
        "Hover for feature details. Windows 11: right-click → Show more options.": "Survoler pour voir les détails. Windows 11 : clic droit → Afficher plus d’options.",
        "Could not open the full log: ": "Impossible d’ouvrir le journal complet : ",
        "Open the repository website for the current Git worktree.": "Ouvrir le site web du dépôt de l’arbre de travail Git actuel.",
        "Open the solution or project at the current directory level.": "Ouvrir la solution ou le projet au niveau du dossier actuel.",
        "Export resolved third-party Pub sources and licenses from the project lockfile. Press Enter to use the desktop as output.": "Exporter les sources Pub tierces résolues et leurs licences depuis le verrou du projet. Appuyer sur Entrée pour utiliser le bureau comme destination.",
        "An operation is running. Wait for the transaction to finish before closing. Logs can be copied at any time.": "Une opération est en cours. Attendre la fin de la transaction avant de fermer. Les journaux peuvent être copiés à tout moment.",
        "Could not build the operation plan: ": "Impossible de créer le plan d’opération : ",
        "Could not start the operation: ": "Impossible de démarrer l’opération : ",
        "Log: ": "Journal : ",
        "🈶 Repair Chinese paths in Flutter project": "🈶 Réparer les chemins chinois du projet Flutter",
        "Not installed; nothing to uninstall": "Non installé ; rien à désinstaller",
        "Not installed": "Non installé",
        "Not run": "Non exécuté",
        "This feature": "Cette fonction",
        "Local build directory (moving or cleaning it disables the menu)": "Dossier de compilation local (déplacer ou nettoyer ce dossier désactive le menu)",
        "Validate the branch, staging area and upstream, then confirm the push.": "Valider la branche, l’index et le dépôt amont, puis confirmer le push.",
        "Validate the Flutter project, then fetch dependencies.": "Valider le projet Flutter, puis récupérer les dépendances.",
        "Installing / updating…": "Installation / mise à jour…",
        "This entry has been removed. Existing installations can be uninstalled but cannot be reinstalled.": "Cette entrée a été supprimée. Les installations existantes peuvent être désinstallées, mais pas réinstallées.",
        "No features require processing; ": "Aucune fonction à traiter ; ",
        "No features require processing. No settings were changed.": "Aucune fonction à traiter. Aucun paramètre n’a été modifié.",
        "Total cleanup time": "Durée totale de nettoyage",
        "Cleanup time": "Durée de nettoyage",
        "Click to read the full session log in a new PowerShell window. The current task continues.": "Cliquer pour lire le journal complet de la session dans une nouvelle fenêtre PowerShell. La tâche actuelle continue.",
        "Pending": "En attente de traitement",
        "Waiting to stop…": "Attente de l’arrêt…",
        "Ordered Flutter development, diagnostics, repair and maintenance tools. Regular actions use project FVM; environment setup supports FVM / system Flutter and jEnv / system Java.": "Outils Flutter ordonnés de développement, diagnostic, réparation et maintenance. Les actions courantes utilisent le FVM du projet ; la configuration prend en charge FVM / Flutter système et jEnv / Java système.",
        "Detect the Flutter / Android project and preview cleanup scope. iOS cleanup is unavailable on Windows.": "Détecter le projet Flutter / Android et prévisualiser le périmètre de nettoyage. Le nettoyage iOS est indisponible sous Windows.",
        "Could not read preferences: ": "Impossible de lire les préférences : ",
        "Could not read the log: ": "Impossible de lire le journal : ",
        "Explorer context-menu extensions · ": "Extensions du menu contextuel Explorer · ",
        "Explorer extensions · Manage": "Extensions Explorer · Gestion",
        "Return selection": "Renvoyer la sélection",
        "Exit code: ": "Code de sortie : ",
        "Choose an operation and select features. Unselected features remain; only installed features can be uninstalled.": "Choisir une opération et sélectionner des fonctions. Les fonctions non sélectionnées sont conservées ; seules les fonctions installées peuvent être désinstallées.",
        "Some features failed; other selected features were still processed. Click a failed status to open the full session log.": "Certaines fonctions ont échoué ; les autres fonctions sélectionnées ont tout de même été traitées. Cliquer sur un état d’échec pour ouvrir le journal complet de la session.",
        "Available for nonempty regular directories outside iOS projects, including Flutter roots. Validated again before opening.": "Disponible pour les dossiers ordinaires non vides hors projets iOS, y compris les racines Flutter. Nouvelle validation avant ouverture.",
        "Default installation location (recommended)": "Emplacement d’installation par défaut (recommandé)",
        "{0}; Results: succeeded {1}; nothing to uninstall {2}; failed {3}; not run {4}": "{0} ; résultats : réussis {1} ; rien à désinstaller {2} ; échoués {3} ; non exécutés {4}",
        "{0} Exit code: {1}.": "{0} Code de sortie : {1}.",
        "{0} {1}": "{0} {1}",
        "{0}{1} {2}": "{0}{1} {2}",
        "{0} in progress; completed {1} / {2} ({3}% by completed items); {4} {5}": "{0} en cours ; terminés {1} / {2} ({3}% par éléments terminés) ; {4} {5}",
        "{0} Completed {1} / {2} ({3}% by completed items); {4} {5}": "{0} Terminés {1} / {2} ({3}% par éléments terminés) ; {4} {5}",
        "Close management panel": "Fermer le panneau de gestion",
        "Run in the menu bar, or quit the installation / uninstallation panel?": "Continuer dans la barre des menus ou quitter complètement le panneau d’installation / désinstallation ?",
        "Run in background": "Exécuter en arrière-plan",
        "Quit completely": "Quitter complètement",
        "Show management panel": "Afficher le panneau de gestion",
        "Status: {0}": "État : {0}",
        "A task is running. You can quit after it finishes.": "Une tâche est en cours. Vous pourrez quitter une fois celle-ci terminée."
      },
      "es": {
        "Update development environment (update)": "Actualizar el entorno de desarrollo (update)",
        "Total disk space": "Espacio libre total en discos",
        "Create script launcher": "Crear acceso al script",
        "Theme": "Tema",
        "Language": "Idioma",
        "🎨 Theme": "🎨 Tema",
        "🌐 Language": "🌐 Idioma",
        "Follow system": "Seguir el sistema",
        "Dark": "Oscuro",
        "Light": "Claro",
        "Jobs Finder Extension Manager": "Gestor de extensiones de Finder de Jobs",
        "Customize Finder Context Menu": "Personalizar el menú contextual de Finder",
        "Close Manager": "Cerrar el gestor",
        "Edit": "Editar",
        "Copy": "Copiar",
        "Select all": "Seleccionar todo",
        "Clear all": "Desmarcar todo",
        "Close": "Cerrar",
        "OK": "Aceptar",
        "Install": "Instalar",
        "Install / Update": "Instalar / Actualizar",
        "Uninstall": "Desinstalar",
        "Cleanup": "Limpieza",
        "Clean build products": "Limpiar los productos de compilación",
        "🧹 Clean build products": "🧹 Limpiar los productos de compilación",
        "Stop installation": "Detener la instalación",
        "Stopping…": "Deteniendo…",
        "Action: install / update or uninstall": "Operación: instalar / actualizar o desinstalar",
        "Uninstall removes selected menus only. Group selection affects its own group.": "La desinstalación solo elimina los menús seleccionados. La selección de un grupo solo afecta a ese grupo.",
        "Install / uninstall with the combined App in Applications": "Instalar / desinstalar con la app unificada en Aplicaciones",
        "Install or uninstall the combined App in Applications": "Instalar o desinstalar la app unificada en Aplicaciones",
        "Selected: manage features in /Applications/Jobs自定义右键菜单.app. Otherwise use the build directory.": "Marcado: gestionar funciones en /Applications/Jobs自定义右键菜单.app. En caso contrario, usar el directorio de compilación.",
        "Clean this build after successful installation": "Limpiar esta compilación tras una instalación correcta",
        "Clean this build only after the combined App is installed and verified in Applications. Keep failed builds.": "Limpiar esta compilación solo después de instalar y verificar la app unificada en Aplicaciones. Conservar las compilaciones fallidas.",
        "Clean build products of selected features without installing or uninstalling.": "Limpiar los productos de compilación de las funciones seleccionadas sin instalar ni desinstalar.",
        "Clean selected features' build products": "Limpiar los productos de compilación de las funciones seleccionadas",
        "Open Privacy & Security": "Abrir Privacidad y seguridad",
        "Add and enable Jobs右键菜单管理面板.app in Privacy & Security → App Management. This only opens Settings.": "Añadir y activar Jobs右键菜单管理面板.app en Privacidad y seguridad → Gestión de apps. Esto solo abre Ajustes.",
        "Target: build directory. Cleaning these products affects installed features.": "Destino: directorio de compilación. Limpiar estos productos afecta a las funciones instaladas.",
        "App: Jobs自定义右键菜单.app at /Applications/Jobs自定义右键菜单.app (build products can be cleaned after installation)": "App: Jobs自定义右键菜单.app en /Applications/Jobs自定义右键菜单.app (los productos de compilación se pueden limpiar tras la instalación)",
        "Drag the divider to resize the log. Features and logs scroll separately.": "Arrastrar el separador para cambiar la altura del registro. Las funciones y el registro se desplazan por separado.",
        "Feature list and live log divider": "Separador entre la lista de funciones y el registro en directo",
        "Live log (select and copy text)": "Registro en directo (seleccionar y copiar texto)",
        "Copy log": "Copiar el registro",
        "Log file": "Archivo de registro",
        "Auto-scroll": "Desplazamiento automático",
        "Ready. Select features and choose an action.": "Listo. Seleccionar funciones y una operación.",
        "A task is running. Wait for it to finish before closing.": "Hay una tarea en curso. Esperar a que termine antes de cerrar.",
        "Unable to view this log": "No se puede ver este registro",
        "Log is missing or unreadable: {0}": "El registro no existe o no se puede leer: {0}",
        "Unable to open log terminal: {0}": "No se puede abrir el terminal del registro: {0}",
        "Click to show this session's full log in a new terminal: {0}": "Pulsar para mostrar el registro completo de esta sesión en un nuevo terminal: {0}",
        "Selected {0} / {1}. Select at least one. Changing action keeps selection.": "Seleccionados {0} / {1}. Seleccionar al menos uno. Cambiar de operación conserva la selección.",
        "Selected {0} / {1}": "Seleccionados {0} / {1}",
        "{0}: select all": "{0}: seleccionar todo",
        "{0}: clear all": "{0}: desmarcar todo",
        "Waiting": "En espera",
        "Cleaning…": "Limpiando…",
        "Uninstalling…": "Desinstalando…",
        "Installing…": "Instalando…",
        "Cleaned": "Limpiado",
        "Uninstalled": "Desinstalado",
        "Installed": "Instalado",
        "Skipped": "Omitido",
        "Not installed; nothing to remove": "No instalado; nada que eliminar",
        "Failed: see log": "Error: ver el registro",
        "Selected": "Seleccionado",
        "Not selected": "No seleccionado",
        "App Management permission required": "Se requiere permiso de gestión de apps",
        "Permission check required": "Se requiere comprobar los permisos",
        "Stopped": "Detenido",
        "Completed": "Completado",
        "Task failed": "La tarea ha fallado",
        "{0}: processed {1} / {2} ({3}, completed items); {4} time {5}": "{0}: procesados {1} / {2} ({3}, elementos completados); tiempo de {4}: {5}",
        "{0} ready": "{0} listo",
        "{0} ready; {1} time {2}": "{0} listo; tiempo de {1}: {2}",
        "Finishing the current feature, then stopping; install time {0}": "Terminando la función actual antes de detenerse; tiempo de instalación: {0}",
        "{0}: {1} succeeded, {2} failed, {3} skipped; exit {4}; {5}; {6} time {7}": "{0}: {1} correctos, {2} fallidos, {3} omitidos; código {4}; {5}; tiempo de {6}: {7}",
        "{0}: {1} succeeded, {2} failed, {3} not installed, {4} skipped; exit {5}; {6}; {7} time {8}": "{0}: {1} correctos, {2} fallidos, {3} no instalados, {4} omitidos; código {5}; {6}; tiempo de {7}: {8}",
        "{0}: {1} succeeded, {2} failed, {3} not installed; exit {4}; {5}; {6} time {7}": "{0}: {1} correctos, {2} fallidos, {3} no instalados; código {4}; {5}; tiempo de {6}: {7}",
        "{0}: {1} succeeded, {2} failed; exit {3}; {4}; {5} time {6}": "{0}: {1} correctos, {2} fallidos; código {3}; {4}; tiempo de {5}: {6}",
        "Open projects in IDEs": "Abrir proyectos en los IDE",
        "Git tools": "Herramientas Git",
        "Files and general tools": "Archivos y herramientas generales",
        "Flutter tools · submenu actions": "Herramientas Flutter · acciones del submenú",
        "iOS / CocoaPods tools": "Herramientas iOS / CocoaPods",
        "Simulator tools": "Herramientas de simuladores",
        "Open project in Android Studio": "Abrir proyecto en Android Studio",
        "Open project in VSCode": "Abrir proyecto en VSCode",
        "Open project in Xcode": "Abrir proyecto en Xcode",
        "Pull latest Git changes": "Obtener los últimos cambios de Git",
        "Roll back Git commit": "Revertir a un commit de Git",
        "Open Git remote URL": "Abrir URL remota de Git",
        "Copy Git remote URL": "Copiar URL remota de Git",
        "Copy absolute path": "Copiar ruta absoluta",
        "Create file": "Crear archivo",
        "View file fingerprint Hash (SHA-256)": "Ver la huella del archivo (SHA-256)",
        "Hide / show selected items": "Ocultar / mostrar los elementos seleccionados",
        "Send to external disk or network volume": "Enviar a un disco externo o volumen de red",
        "Grant execute permission (chmod +x)": "Conceder permiso de ejecución (chmod +x)",
        "Remove execute permission (chmod -x)": "Quitar permiso de ejecución (chmod -x)",
        "Re-sign IPA without building": "Volver a firmar el IPA sin compilar",
        "Show / hide files": "Mostrar / ocultar archivos",
        "Create iOS simulator": "Crear simulador iOS",
        "Create Android simulator": "Crear simulador Android",
        "Create Harmony simulator": "Crear simulador Harmony",
        "Check / repair Android simulator": "Comprobar / reparar simulador Android",
        "Check / repair Harmony simulator": "Comprobar / reparar simulador Harmony",
        "Configure Git proxy": "Configurar proxy de Git",
        "Open in terminal": "Abrir en el terminal",
        "View file contents in terminal": "Ver contenido del archivo en el terminal",
        "Merge file parts": "Unir partes del archivo",
        "Split file": "Dividir archivo",
        "Clean Android / OpenHarmony builds": "Limpiar compilaciones de Android / OpenHarmony",
        "Update code map (.codegraph)": "Actualizar mapa del código (.codegraph)",
        "Create empty commit and push in terminal": "Crear commit vacío y enviar desde el terminal",
        "Disable CocoaPods build sandbox": "Desactivar el aislamiento de compilación de CocoaPods",
        "Install CocoaPods": "Instalar CocoaPods",
        "CocoaPods source: CDN → GitHub": "Fuente de CocoaPods: CDN → GitHub",
        "Export all project Pod files": "Exportar todos los archivos Pod del proyecto",
        "Inspect Xcode project dependencies": "Inspeccionar dependencias del proyecto Xcode",
        "Update local CocoaPods repositories": "Actualizar repositorios locales de CocoaPods",
        "Check local Pod builds (.podspec folder)": "Comprobar compilaciones de Pods locales (carpeta .podspec)",
        "Install / update JobsCodeSnippets": "Instalar / actualizar JobsCodeSnippets",
        "Clean iOS / Xcode builds": "Limpiar compilaciones de iOS / Xcode",
        "Set up Flutter project": "Configurar proyecto Flutter",
        "Run Flutter project in terminal": "Ejecutar proyecto Flutter en el terminal",
        "Fetch Flutter Pub dependencies": "Obtener dependencias de Flutter Pub",
        "Fetch native Android dependencies": "Obtener dependencias nativas de Android",
        "Fetch CocoaPods dependencies": "Obtener dependencias de CocoaPods",
        "Fetch Swift Package dependencies": "Obtener dependencias de Swift Package",
        "Fetch OpenHarmony dependencies": "Obtener dependencias de OpenHarmony",
        "Prepare native libraries and build dependencies": "Preparar bibliotecas nativas y dependencias de compilación",
        "Download Flutter platform resources": "Descargar recursos de plataformas Flutter",
        "Fetch Web project dependencies": "Obtener dependencias del proyecto Web",
        "🧳 Export Flutter dependencies": "🧳 Exportar dependencias de Flutter",
        "Export Flutter Pub dependencies": "Exportar dependencias de Flutter Pub",
        "🔐 Export private Flutter dependencies": "🔐 Exportar dependencias privadas de Flutter",
        "📥 Import Flutter dependencies": "📥 Importar dependencias de Flutter",
        "Import Flutter Pub dependencies": "Importar dependencias de Flutter Pub",
        "📥 Import private Flutter dependencies": "📥 Importar dependencias privadas de Flutter",
        "Export Gradle distributions and cache": "Exportar distribuciones y caché de Gradle",
        "Import Gradle distributions and cache": "Importar distribuciones y caché de Gradle",
        "Export CocoaPods dependencies": "Exportar dependencias de CocoaPods",
        "Import CocoaPods dependencies": "Importar dependencias de CocoaPods",
        "Export Swift Package dependencies": "Exportar dependencias de Swift Package",
        "Import Swift Package dependencies": "Importar dependencias de Swift Package",
        "Export OpenHarmony dependencies": "Exportar dependencias de OpenHarmony",
        "Import OpenHarmony dependencies": "Importar dependencias de OpenHarmony",
        "Export native build cache": "Exportar caché de compilación nativa",
        "Import native build cache": "Importar caché de compilación nativa",
        "Export Flutter platform resources": "Exportar recursos de plataformas Flutter",
        "Import Flutter platform resources": "Importar recursos de plataformas Flutter",
        "Export Web dependencies": "Exportar dependencias Web",
        "Import Web dependencies": "Importar dependencias Web",
        "Show Flutter project SDK version": "Mostrar versión del SDK del proyecto Flutter",
        "Install / switch Flutter SDK": "Instalar / cambiar SDK de Flutter",
        "Install / switch Flutter@OpenHarmony SDK": "Instalar / cambiar SDK de Flutter@OpenHarmony",
        "Install / switch Java SDK": "Instalar / cambiar SDK de Java",
        "Download Gradle distributions and plugins": "Descargar distribuciones y complementos de Gradle",
        "Generate Flutter code": "Generar código Flutter",
        "Package iOS": "Empaquetar iOS",
        "Package Android": "Empaquetar Android",
        "Package Harmony (HAP + APP)": "Empaquetar Harmony (HAP + APP)",
        "Check native Flutter project": "Comprobar proyecto Flutter nativo",
        "Check OpenHarmony Flutter environment": "Comprobar entorno Flutter de OpenHarmony",
        "Repair missing Android SDK / platforms": "Reparar SDK / plataformas Android que faltan",
        "Repair Chinese Flutter project paths": "Reparar rutas chinas del proyecto Flutter",
        "Repair Flutter plugin namespaces": "Reparar espacios de nombres de complementos Flutter",
        "Convert relative Dart imports to packages": "Convertir imports relativos de Dart en imports de paquetes",
        "Clean current Flutter project builds": "Limpiar compilaciones del proyecto Flutter actual",
        "Dependency and cache maintenance": "Mantenimiento de dependencias y cachés",
        "Custom Explorer context menu": "Menú contextual de Explorer personalizado",
        "Jobs Windows · Custom Explorer context menu": "Jobs Windows · Menú contextual de Explorer personalizado",
        "Show a regular file's SHA-256 in a new terminal and copy the digest; do not modify or execute the file.": "Mostrar el SHA-256 de un archivo normal en un nuevo terminal y copiar su huella; no modificar ni ejecutar el archivo.",
        " (preview)": " (vista previa)",
        "⏪ Roll back Git commits": "⏪ Revertir a commits de Git",
        "▶️ Run Flutter project in terminal": "▶️ Ejecutar proyecto Flutter en el terminal",
        "☕ Install / switch Java SDK": "☕ Instalar / cambiar SDK de Java",
        "♻️ Flutter cleanup and maintenance": "♻️ Limpieza y mantenimiento de Flutter",
        "⚙️ Generate Flutter code": "⚙️ Generar código Flutter",
        "✅ Installed": "✅ Instalado",
        "⬇️ Pull latest Git changes": "⬇️ Obtener los últimos cambios de Git",
        "🌈 Create Harmony emulator": "🌈 Crear emulador Harmony",
        "🌐 Open Git remote URL": "🌐 Abrir URL remota de Git",
        "🌐 Fetch Web project dependencies": "🌐 Obtener dependencias del proyecto Web",
        "🌳 Open in Sourcetree": "🌳 Abrir en Sourcetree",
        "🏥 Flutter project diagnostics": "🏥 Diagnóstico del proyecto Flutter",
        "🏥 Flutter diagnostics": "🏥 Diagnóstico de Flutter",
        "🏷️ Repair Flutter plugin namespaces": "🏷️ Reparar espacios de nombres de complementos Flutter",
        "👁️ Show / hide hidden files": "👁️ Mostrar / ocultar archivos ocultos",
        "💓 OpenHarmony Flutter diagnostics": "💓 Diagnóstico Flutter de OpenHarmony",
        "💠 Open project in Visual Studio": "💠 Abrir proyecto en Visual Studio",
        "💻 Open in terminal": "💻 Abrir en el terminal",
        "📄 View file in terminal": "📄 Ver archivo en el terminal",
        "📋 Copy absolute path": "📋 Copiar ruta absoluta",
        "📚 Download Gradle distributions and build plugins": "📚 Descargar distribuciones y complementos de compilación de Gradle",
        "📝 Open project in VSCode": "📝 Abrir proyecto en VSCode",
        "📡 Configure Git dynamic proxy": "📡 Configurar proxy dinámico de Git",
        "📤 Import Flutter Pub dependencies": "📤 Importar dependencias de Flutter Pub",
        "📤 Import Flutter platform assets": "📤 Importar recursos de plataformas Flutter",
        "📤 Import Gradle distributions and dependency caches": "📤 Importar distribuciones y cachés de dependencias de Gradle",
        "📤 Import OpenHarmony dependencies": "📤 Importar dependencias de OpenHarmony",
        "📤 Import Web dependencies": "📤 Importar dependencias Web",
        "📤 Import native build caches": "📤 Importar cachés de compilación nativa",
        "📤 Import Flutter project dependencies": "📤 Importar dependencias del proyecto Flutter",
        "📤 Create empty commit and push": "📤 Crear commit vacío y enviar",
        "📥 Install Flutter dependencies (pub get)": "📥 Instalar dependencias de Flutter (pub get)",
        "📥 Import private Flutter project dependencies": "📥 Importar dependencias privadas del proyecto Flutter",
        "📥 Fetch Flutter Pub dependencies": "📥 Obtener dependencias de Flutter Pub",
        "📥 Fetch Flutter project dependencies": "📥 Obtener dependencias del proyecto Flutter",
        "📦 Package Flutter project": "📦 Empaquetar proyecto Flutter",
        "📦 Package HarmonyOS (HAP + APP)": "📦 Empaquetar HarmonyOS (HAP + APP)",
        "📱 Create Android emulator": "📱 Crear emulador Android",
        "🔀 Install / switch Flutter SDK (FVM)": "🔀 Instalar / cambiar SDK de Flutter (FVM)",
        "🔀 Install / switch Flutter SDK": "🔀 Instalar / cambiar SDK de Flutter",
        "🔀 Install / switch Flutter environments": "🔀 Instalar / cambiar entornos de Flutter",
        "🔎 Show current Flutter SDK version": "🔎 Mostrar versión del SDK de Flutter actual",
        "🔎 Show current Flutter project's SDK version": "🔎 Mostrar versión del SDK del proyecto Flutter actual",
        "🔐 Export private Flutter project dependencies": "🔐 Exportar dependencias privadas del proyecto Flutter",
        "🔎 Show file fingerprint Hash (SHA-256)": "🔎 Mostrar huella del archivo (SHA-256)",
        "➕ Grant execute permission": "➕ Conceder permiso de ejecución",
        "➖ Remove execute permission": "➖ Quitar permiso de ejecución",
        "🔒 Grant execute permission": "🔒 Conceder permiso de ejecución",
        "🔓 Remove execute permission": "🔓 Quitar permiso de ejecución",
        "🔗 Copy Git remote URL": "🔗 Copiar URL remota de Git",
        "🔧 Flutter repairs": "🔧 Reparaciones de Flutter",
        "🕊️ Install / switch Flutter@OpenHarmony SDK": "🕊️ Instalar / cambiar SDK de Flutter@OpenHarmony",
        "🕊️ Fetch OpenHarmony dependencies": "🕊️ Obtener dependencias de OpenHarmony",
        "🗃️ Download Flutter platform assets": "🗃️ Descargar recursos de plataformas Flutter",
        "🗺️ Update code map (.codegraph)": "🗺️ Actualizar mapa del código (.codegraph)",
        "🤖 Fetch Android native dependencies": "🤖 Obtener dependencias nativas de Android",
        "🦋 Flutter development": "🦋 Desarrollo Flutter",
        "🦋 Flutter development tools": "🦋 Herramientas de desarrollo Flutter",
        "🧑‍⚕️ Native Flutter diagnostics": "🧑‍⚕️ Diagnóstico de Flutter nativo",
        "🧩 Export Flutter Pub dependencies": "🧩 Exportar dependencias de Flutter Pub",
        "🧩 Export Flutter platform assets": "🧩 Exportar recursos de plataformas Flutter",
        "🧩 Export Flutter third-party dependencies": "🧩 Exportar dependencias de terceros de Flutter",
        "🧩 Export Gradle distributions and dependency caches": "🧩 Exportar distribuciones y cachés de dependencias de Gradle",
        "🧩 Export OpenHarmony dependencies": "🧩 Exportar dependencias de OpenHarmony",
        "🧩 Export Web dependencies": "🧩 Exportar dependencias Web",
        "🧩 Export native build caches": "🧩 Exportar cachés de compilación nativa",
        "🧩 Export Flutter project dependencies": "🧩 Exportar dependencias del proyecto Flutter",
        "🧩 Merge file volumes / ✂️ Split file": "🧩 Unir volúmenes / ✂️ Dividir archivo",
        "🧭 Open project in Android Studio": "🧭 Abrir proyecto en Android Studio",
        "🧯 Clean build output": "🧯 Limpiar resultados de compilación",
        "🧰 Diagnose and repair Harmony emulator": "🧰 Diagnosticar y reparar emulador Harmony",
        "🧱 Flutter assets and build dependencies": "🧱 Recursos de Flutter y dependencias de compilación",
        "🧱 Prepare native libraries and build dependencies (combined)": "🧱 Preparar bibliotecas nativas y dependencias de compilación (combinado)",
        "🧹 Clean build output": "🧹 Limpiar resultados de compilación",
        "🩹 Repair missing Android SDK / platforms": "🩹 Reparar SDK / plataformas Android que faltan",
        "🩺 Diagnose and repair Android emulator": "🩺 Diagnosticar y reparar emulador Android",
        "🚀 Set up Flutter project": "🚀 Configurar proyecto Flutter",
        "🚚 Import all Flutter dependencies": "🚚 Importar todas las dependencias de Flutter",
        "🚚 Export all Flutter dependencies": "🚚 Exportar todas las dependencias de Flutter",
        "Jobs Windows · Uninstall Explorer extensions": "Jobs Windows · Desinstalar extensiones de Explorer",
        "Jobs Windows · Install Explorer extensions": "Jobs Windows · Instalar extensiones de Explorer",
        "Jobs Windows · Manage Explorer extensions": "Jobs Windows · Gestionar extensiones de Explorer",
        "Jobs Windows · Configure Explorer extensions": "Jobs Windows · Configurar extensiones de Explorer",
        "Drag the divider vertically to resize the log": "Arrastrar el separador verticalmente para cambiar la altura del registro",
        "Drag vertically to resize the log": "Arrastrar verticalmente para cambiar la altura del registro",
        "Validate the Flutter project, diagnose the toolchain in terminal, and choose a Flutter SDK version with fzf.": "Validar el proyecto Flutter, diagnosticar la cadena de herramientas en el terminal y elegir una versión del SDK de Flutter con fzf.",
        "Validate the Flutter project, then show the active SDK version (project FVM or system SDK) in terminal and compare it with .fvmrc and pubspec constraints.": "Validar el proyecto Flutter y mostrar en el terminal la versión del SDK activo (FVM del proyecto o SDK del sistema) para compararla con .fvmrc y las restricciones de pubspec.",
        "Flutter roots only. Choose Android / iOS / HarmonyOS with fzf in CMD. Supports APK / AAB and HAP / APP. iOS requires MacOS and Xcode.": "Solo raíces de proyectos Flutter. Elegir Android / iOS / HarmonyOS con fzf en CMD. Admite APK / AAB y HAP / APP. iOS requiere MacOS y Xcode.",
        "Flutter roots only. Choose a device and view logs in CMD; the app continues in the background after the window closes.": "Solo raíces de proyectos Flutter. Elegir un dispositivo y ver los registros en CMD; la app sigue en segundo plano al cerrar la ventana.",
        "Flutter roots only. Read-only version and doctor diagnostics in terminal; no dependency fetching, cleanup, or tool upgrades.": "Solo raíces de proyectos Flutter. Diagnóstico de versión y doctor de solo lectura en el terminal; sin obtener dependencias, limpiar ni actualizar herramientas.",
        "Flutter roots only. Preview configured generators, then fetch dependencies and generate code after confirmation. Deleting conflicts requires separate opt-in.": "Solo raíces de proyectos Flutter. Previsualizar los generadores configurados y, tras confirmar, obtener dependencias y generar código. Eliminar conflictos requiere autorización adicional.",
        "Git worktree folders only. Detect nested repositories. Soft mode preserves the index and worktree; hard mode requires exact YES confirmation.": "Solo carpetas de árboles de trabajo Git. Detectar repositorios anidados. El modo soft conserva el índice y el árbol de trabajo; el modo hard exige confirmar exactamente con YES.",
        "Desktop background on x64 Windows only. Missing tools come from the SDL mirror; missing system images come from the official Emulator. Enter selects a stable phone image; confirm its license to create and start a unique instance.": "Solo fondo del escritorio en Windows x64. Las herramientas que faltan se obtienen del espejo SDL; las imágenes del sistema que faltan, del Emulator oficial. Intro selecciona una imagen estable de teléfono; confirmar su licencia para crear e iniciar una instancia única.",
        "Manage only this package's actions. Unselected actions remain when uninstalling.": "Gestionar solo las acciones de este paquete. Las acciones no seleccionadas se conservan al desinstalar.",
        "Desktop background only. Configure user-level Git to prefer the system proxy and fall back to a direct connection.": "Solo fondo del escritorio. Configurar Git para el usuario de modo que prefiera el proxy del sistema y use conexión directa como alternativa.",
        "Desktop background only. Diagnose the SDK in CMD, choose a device and system image, then create or start an Android AVD.": "Solo fondo del escritorio. Diagnosticar el SDK en CMD, elegir un dispositivo y una imagen del sistema y crear o iniciar un AVD Android.",
        "Desktop background only. Check existing DevEco Emulator instances, then start one or confirm a nondestructive restart. Data is preserved.": "Solo fondo del escritorio. Comprobar las instancias existentes de DevEco Emulator y luego iniciar una o confirmar un reinicio no destructivo. Se conservan los datos.",
        "Desktop background only. Check emulator location and /data; optionally reset caches, precisely uninstall, back up the AVD, and retest with a cold boot.": "Solo fondo del escritorio. Comprobar la ubicación del emulador y /data; opcionalmente restablecer cachés, desinstalar de forma precisa, respaldar el AVD y repetir la prueba con arranque en frío.",
        "Show the next action on the desktop background. Toggle hidden files for the current user's Explorer without changing protected-system-file settings.": "Mostrar la siguiente acción en el fondo del escritorio. Alternar los archivos ocultos del Explorer del usuario actual sin cambiar la configuración de archivos protegidos del sistema.",
        "Visible only for nonempty native Android or valid Flutter (official / HarmonyOS) project roots. Validated again before opening.": "Visible solo para raíces no vacías de proyectos Android nativos o Flutter válidos (oficial / HarmonyOS). Se valida otra vez antes de abrir.",
        "Preview: the selection is shown in the log. No installation or uninstallation was performed.": "Vista previa: la selección aparece en el registro. No se ha instalado ni desinstalado nada.",
        "Preview only. Confirming displays the selection in the log without installing, uninstalling, or writing state or registry entries.": "Solo vista previa. Confirmar muestra la selección en el registro sin instalar, desinstalar ni escribir el estado o el registro del sistema.",
        "Deployed copies use their bound location. To change it, open the manager from the source directory. Default installations run in the current user's LocalAppData; local builds run under this package's work directory and stop working if it moves.": "Las copias desplegadas usan su ubicación vinculada. Para cambiarla, abrir el gestor desde el directorio de fuentes. Las instalaciones predeterminadas se ejecutan en LocalAppData del usuario actual; las compilaciones locales, en el directorio de trabajo del paquete, y dejan de funcionar si se mueve.",
        "Prefer Windows Terminal; otherwise use system PowerShell.": "Preferir Windows Terminal; si no está disponible, usar PowerShell del sistema.",
        "Could not save preferences: ": "No se han podido guardar las preferencias: ",
        "Save settings": "Guardar configuración",
        "Protect local changes. On conflict, choose to restore, discard changes, or commit and retry.": "Proteger los cambios locales. En caso de conflicto, elegir restaurar, descartar los cambios o crear un commit y reintentar.",
        "All operations completed. Copy the log or close the panel.": "Todas las operaciones han terminado. Copiar el registro o cerrar el panel.",
        "Other context-menu features": "Otras funciones del menú contextual",
        "Create or synchronize the code map for the current directory.": "Crear o sincronizar el mapa del código del directorio actual.",
        "Feature and log divider": "Separador entre funciones y registro",
        "Select features, then confirm. Unselected features remain. Hover for installation details.": "Seleccionar funciones y confirmar. Las no seleccionadas se conservan. Pasar el cursor para ver detalles de instalación.",
        "Checked features are installed; unchecked ones are uninstalled. Saving an empty selection disables all installed features.": "Las funciones marcadas se instalan; las desmarcadas se desinstalan. Guardar una selección vacía desactiva todas las funciones instaladas.",
        "Select features to install. Enabled sibling actions and other unselected features remain.": "Seleccionar las funciones que se van a instalar. Las acciones relacionadas habilitadas y las demás funciones no seleccionadas se conservan.",
        "Total uninstall time": "Tiempo total de desinstalación",
        "Uninstall selected": "Desinstalar selección",
        "Uninstall selected features": "Desinstalar funciones seleccionadas",
        "Uninstall time": "Tiempo de desinstalación",
        "Cancel": "Cancelar",
        "Uninstall only selected installed features. Other features, logs, backups and tools remain.": "Desinstalar solo las funciones instaladas seleccionadas. Las demás funciones, registros, copias de seguridad y herramientas se conservan.",
        "Change only the current user's ExecuteFile ACL for a single regular NTFS file after confirmation. Does not launch the file or change global policy.": "Tras confirmar, cambiar solo la ACL ExecuteFile del usuario actual para un único archivo normal NTFS. No ejecuta el archivo ni cambia la directiva global.",
        "View a single regular file. Files over 1 MiB or suspected binary files require YES in the terminal.": "Ver un único archivo normal. Los archivos de más de 1 MiB o sospechosos de ser binarios requieren YES en el terminal.",
        "Clean only the selected packages' build workspaces. Installed DLLs, scripts, settings and registry entries remain.": "Limpiar solo los espacios de compilación de los paquetes seleccionados. Se conservan las DLL, scripts, configuraciones y entradas del registro instalados.",
        "Copy full log": "Copiar registro completo",
        "Copy the original remote URL for the current branch.": "Copiar la URL remota original de la rama actual.",
        "Copy the absolute path of a file or folder.": "Copiar la ruta absoluta de un archivo o carpeta.",
        "Could not copy the log: ": "No se ha podido copiar el registro: ",
        "Failed — open log": "Error — abrir registro",
        "Install / update": "Instalar / actualizar",
        "Install / update selected features": "Instalar / actualizar funciones seleccionadas",
        "Total install time": "Tiempo total de instalación",
        "Install time": "Tiempo de instalación",
        "Merge appears for a complete selected volume set; split appears for one regular file. Originals are always preserved.": "Unir aparece al seleccionar un conjunto completo de volúmenes; dividir aparece para un único archivo normal. Los originales siempre se conservan.",
        "Live log (drag the divider to resize)": "Registro en directo (arrastrar el separador para cambiar su altura)",
        "Installation stopped after the current package transaction. Unstarted items are marked Not run.": "Instalación detenida tras la transacción del paquete actual. Los elementos no iniciados se marcan como No ejecutado.",
        "Stop requested. Waiting for the current package transaction; later items will not run.": "Se ha solicitado detener. Esperando la transacción del paquete actual; los elementos siguientes no se ejecutarán.",
        "Selected {0} / {1}. Closing or cancelling makes no changes.": "Seleccionados {0} / {1}. Cerrar o cancelar no realiza cambios.",
        "Hover for feature details. Windows 11: right-click → Show more options.": "Pasar el cursor para ver detalles. Windows 11: clic derecho → Mostrar más opciones.",
        "Could not open the full log: ": "No se ha podido abrir el registro completo: ",
        "Open the repository website for the current Git worktree.": "Abrir el sitio web del repositorio del árbol de trabajo Git actual.",
        "Open the solution or project at the current directory level.": "Abrir la solución o el proyecto del nivel de directorio actual.",
        "Export resolved third-party Pub sources and licenses from the project lockfile. Press Enter to use the desktop as output.": "Exportar fuentes de terceros de Pub resueltas y sus licencias desde el archivo de bloqueo del proyecto. Pulsar Intro para usar el escritorio como destino.",
        "An operation is running. Wait for the transaction to finish before closing. Logs can be copied at any time.": "Hay una operación en curso. Esperar a que termine la transacción antes de cerrar. Los registros se pueden copiar en cualquier momento.",
        "Could not build the operation plan: ": "No se ha podido crear el plan de operación: ",
        "Could not start the operation: ": "No se ha podido iniciar la operación: ",
        "Log: ": "Registro: ",
        "🈶 Repair Chinese paths in Flutter project": "🈶 Reparar rutas chinas del proyecto Flutter",
        "Not installed; nothing to uninstall": "No instalado; nada que desinstalar",
        "Not installed": "No instalado",
        "Not run": "No ejecutado",
        "This feature": "Esta función",
        "Local build directory (moving or cleaning it disables the menu)": "Directorio de compilación local (moverlo o limpiarlo desactiva el menú)",
        "Validate the branch, staging area and upstream, then confirm the push.": "Validar la rama, el área de preparación y el remoto de seguimiento y confirmar el envío.",
        "Validate the Flutter project, then fetch dependencies.": "Validar el proyecto Flutter y obtener las dependencias.",
        "Installing / updating…": "Instalando / actualizando…",
        "This entry has been removed. Existing installations can be uninstalled but cannot be reinstalled.": "Esta entrada se ha eliminado. Las instalaciones existentes se pueden desinstalar, pero no reinstalar.",
        "No features require processing; ": "No hay funciones que procesar; ",
        "No features require processing. No settings were changed.": "No hay funciones que procesar. No se ha cambiado ninguna configuración.",
        "Total cleanup time": "Tiempo total de limpieza",
        "Cleanup time": "Tiempo de limpieza",
        "Click to read the full session log in a new PowerShell window. The current task continues.": "Pulsar para leer el registro completo de la sesión en una nueva ventana de PowerShell. La tarea actual continúa.",
        "Pending": "Pendiente",
        "Waiting to stop…": "Esperando para detenerse…",
        "Ordered Flutter development, diagnostics, repair and maintenance tools. Regular actions use project FVM; environment setup supports FVM / system Flutter and jEnv / system Java.": "Herramientas ordenadas de desarrollo, diagnóstico, reparación y mantenimiento de Flutter. Las acciones habituales usan el FVM del proyecto; la configuración admite FVM / Flutter del sistema y jEnv / Java del sistema.",
        "Detect the Flutter / Android project and preview cleanup scope. iOS cleanup is unavailable on Windows.": "Detectar el proyecto Flutter / Android y previsualizar el alcance de la limpieza. La limpieza de iOS no está disponible en Windows.",
        "Could not read preferences: ": "No se han podido leer las preferencias: ",
        "Could not read the log: ": "No se ha podido leer el registro: ",
        "Explorer context-menu extensions · ": "Extensiones del menú contextual de Explorer · ",
        "Explorer extensions · Manage": "Extensiones de Explorer · Gestionar",
        "Return selection": "Devolver selección",
        "Exit code: ": "Código de salida: ",
        "Choose an operation and select features. Unselected features remain; only installed features can be uninstalled.": "Elegir una operación y seleccionar funciones. Las no seleccionadas se conservan; solo se pueden desinstalar funciones instaladas.",
        "Some features failed; other selected features were still processed. Click a failed status to open the full session log.": "Algunas funciones han fallado; las demás seleccionadas se han procesado igualmente. Pulsar un estado de error para abrir el registro completo de la sesión.",
        "Available for nonempty regular directories outside iOS projects, including Flutter roots. Validated again before opening.": "Disponible para directorios normales no vacíos fuera de proyectos iOS, incluidas las raíces Flutter. Se valida otra vez antes de abrir.",
        "Default installation location (recommended)": "Ubicación de instalación predeterminada (recomendada)",
        "{0}; Results: succeeded {1}; nothing to uninstall {2}; failed {3}; not run {4}": "{0}; resultados: correctos {1}; nada que desinstalar {2}; fallidos {3}; no ejecutados {4}",
        "{0} Exit code: {1}.": "{0} Código de salida: {1}.",
        "{0} {1}": "{0} {1}",
        "{0}{1} {2}": "{0}{1} {2}",
        "{0} in progress; completed {1} / {2} ({3}% by completed items); {4} {5}": "{0} en curso; completados {1} / {2} ({3}% por elementos completados); {4} {5}",
        "{0} Completed {1} / {2} ({3}% by completed items); {4} {5}": "{0} Completados {1} / {2} ({3}% por elementos completados); {4} {5}",
        "Close management panel": "Cerrar el panel de gestión",
        "Run in the menu bar, or quit the installation / uninstallation panel?": "¿Continuar en la barra de menús o salir completamente del panel de instalación / desinstalación?",
        "Run in background": "Ejecutar en segundo plano",
        "Quit completely": "Salir completamente",
        "Show management panel": "Mostrar el panel de gestión",
        "Status: {0}": "Estado: {0}",
        "A task is running. You can quit after it finishes.": "Hay una tarea en curso. Podrá salir cuando termine."
      },
      "de": {
        "Update development environment (update)": "Entwicklungsumgebung aktualisieren (update)",
        "Total disk space": "Gesamter freier Speicherplatz",
        "Create script launcher": "Skriptstarter erstellen",
        "Theme": "Design",
        "Language": "Sprache",
        "🎨 Theme": "🎨 Design",
        "🌐 Language": "🌐 Sprache",
        "Follow system": "Systemeinstellung",
        "Dark": "Dunkel",
        "Light": "Hell",
        "Jobs Finder Extension Manager": "Jobs Finder-Erweiterungsverwaltung",
        "Customize Finder Context Menu": "Finder-Kontextmenü anpassen",
        "Close Manager": "Verwaltung schließen",
        "Edit": "Bearbeiten",
        "Copy": "Kopieren",
        "Select all": "Alle auswählen",
        "Clear all": "Auswahl aufheben",
        "Close": "Schließen",
        "OK": "Bestätigen",
        "Install": "Installieren",
        "Install / Update": "Installieren / Aktualisieren",
        "Uninstall": "Deinstallieren",
        "Cleanup": "Bereinigung",
        "Clean build products": "Build-Erzeugnisse bereinigen",
        "🧹 Clean build products": "🧹 Build-Erzeugnisse bereinigen",
        "Stop installation": "Installation stoppen",
        "Stopping…": "Wird gestoppt…",
        "Action: install / update or uninstall": "Aktion: installieren / aktualisieren oder deinstallieren",
        "Uninstall removes selected menus only. Group selection affects its own group.": "Die Deinstallation entfernt nur ausgewählte Menüs. Eine Gruppenauswahl betrifft nur die jeweilige Gruppe.",
        "Install / uninstall with the combined App in Applications": "Mit der kombinierten App unter Programme installieren / deinstallieren",
        "Install or uninstall the combined App in Applications": "Die kombinierte App unter Programme installieren oder deinstallieren",
        "Selected: manage features in /Applications/Jobs自定义右键菜单.app. Otherwise use the build directory.": "Ausgewählt: Funktionen in /Applications/Jobs自定义右键菜单.app verwalten. Andernfalls das Build-Verzeichnis verwenden.",
        "Clean this build after successful installation": "Diesen Build nach erfolgreicher Installation bereinigen",
        "Clean this build only after the combined App is installed and verified in Applications. Keep failed builds.": "Diesen Build erst bereinigen, nachdem die kombinierte App unter Programme installiert und geprüft wurde. Fehlgeschlagene Builds behalten.",
        "Clean build products of selected features without installing or uninstalling.": "Build-Erzeugnisse der ausgewählten Funktionen bereinigen, ohne zu installieren oder zu deinstallieren.",
        "Clean selected features' build products": "Build-Erzeugnisse ausgewählter Funktionen bereinigen",
        "Open Privacy & Security": "Datenschutz & Sicherheit öffnen",
        "Add and enable Jobs右键菜单管理面板.app in Privacy & Security → App Management. This only opens Settings.": "Jobs右键菜单管理面板.app unter Datenschutz & Sicherheit → App-Verwaltung hinzufügen und aktivieren. Hiermit werden nur die Einstellungen geöffnet.",
        "Target: build directory. Cleaning these products affects installed features.": "Ziel: Build-Verzeichnis. Die Bereinigung dieser Erzeugnisse beeinträchtigt installierte Funktionen.",
        "App: Jobs自定义右键菜单.app at /Applications/Jobs自定义右键菜单.app (build products can be cleaned after installation)": "App: Jobs自定义右键菜单.app unter /Applications/Jobs自定义右键菜单.app (Build-Erzeugnisse können nach der Installation bereinigt werden)",
        "Drag the divider to resize the log. Features and logs scroll separately.": "Trennleiste ziehen, um die Protokollgröße zu ändern. Funktionen und Protokoll lassen sich getrennt scrollen.",
        "Feature list and live log divider": "Trennleiste zwischen Funktionsliste und Live-Protokoll",
        "Live log (select and copy text)": "Live-Protokoll (Text auswählen und kopieren)",
        "Copy log": "Protokoll kopieren",
        "Log file": "Protokolldatei",
        "Auto-scroll": "Automatisch scrollen",
        "Ready. Select features and choose an action.": "Bereit. Funktionen und eine Aktion auswählen.",
        "A task is running. Wait for it to finish before closing.": "Eine Aufgabe läuft. Vor dem Schließen auf ihren Abschluss warten.",
        "Unable to view this log": "Dieses Protokoll kann nicht angezeigt werden",
        "Log is missing or unreadable: {0}": "Protokoll fehlt oder ist nicht lesbar: {0}",
        "Unable to open log terminal: {0}": "Protokollterminal konnte nicht geöffnet werden: {0}",
        "Click to show this session's full log in a new terminal: {0}": "Klicken, um das vollständige Sitzungsprotokoll in einem neuen Terminal anzuzeigen: {0}",
        "Selected {0} / {1}. Select at least one. Changing action keeps selection.": "Ausgewählt: {0} / {1}. Mindestens einen Eintrag auswählen. Die Auswahl bleibt beim Aktionswechsel erhalten.",
        "Selected {0} / {1}": "Ausgewählt: {0} / {1}",
        "{0}: select all": "{0}: alle auswählen",
        "{0}: clear all": "{0}: Auswahl aufheben",
        "Waiting": "Warten",
        "Cleaning…": "Wird bereinigt…",
        "Uninstalling…": "Wird deinstalliert…",
        "Installing…": "Wird installiert…",
        "Cleaned": "Bereinigt",
        "Uninstalled": "Deinstalliert",
        "Installed": "Installiert",
        "Skipped": "Übersprungen",
        "Not installed; nothing to remove": "Nicht installiert; nichts zu entfernen",
        "Failed: see log": "Fehlgeschlagen: siehe Protokoll",
        "Selected": "Ausgewählt",
        "Not selected": "Nicht ausgewählt",
        "App Management permission required": "Berechtigung für App-Verwaltung erforderlich",
        "Permission check required": "Berechtigungsprüfung erforderlich",
        "Stopped": "Gestoppt",
        "Completed": "Abgeschlossen",
        "Task failed": "Aufgabe fehlgeschlagen",
        "{0}: processed {1} / {2} ({3}, completed items); {4} time {5}": "{0}: {1} / {2} bearbeitet ({3}, abgeschlossene Einträge); Zeit für {4}: {5}",
        "{0} ready": "{0} bereit",
        "{0} ready; {1} time {2}": "{0} bereit; Zeit für {1}: {2}",
        "Finishing the current feature, then stopping; install time {0}": "Aktuelle Funktion wird abgeschlossen, danach Stopp; Installationszeit: {0}",
        "{0}: {1} succeeded, {2} failed, {3} skipped; exit {4}; {5}; {6} time {7}": "{0}: {1} erfolgreich, {2} fehlgeschlagen, {3} übersprungen; Exit-Code {4}; {5}; Zeit für {6}: {7}",
        "{0}: {1} succeeded, {2} failed, {3} not installed, {4} skipped; exit {5}; {6}; {7} time {8}": "{0}: {1} erfolgreich, {2} fehlgeschlagen, {3} nicht installiert, {4} übersprungen; Exit-Code {5}; {6}; Zeit für {7}: {8}",
        "{0}: {1} succeeded, {2} failed, {3} not installed; exit {4}; {5}; {6} time {7}": "{0}: {1} erfolgreich, {2} fehlgeschlagen, {3} nicht installiert; Exit-Code {4}; {5}; Zeit für {6}: {7}",
        "{0}: {1} succeeded, {2} failed; exit {3}; {4}; {5} time {6}": "{0}: {1} erfolgreich, {2} fehlgeschlagen; Exit-Code {3}; {4}; Zeit für {5}: {6}",
        "Open projects in IDEs": "Projekte in Entwicklungsumgebungen öffnen",
        "Git tools": "Git-Werkzeuge",
        "Files and general tools": "Dateien und allgemeine Werkzeuge",
        "Flutter tools · submenu actions": "Flutter-Werkzeuge · Untermenüaktionen",
        "iOS / CocoaPods tools": "iOS-/CocoaPods-Werkzeuge",
        "Simulator tools": "Simulatorwerkzeuge",
        "Open project in Android Studio": "Projekt in Android Studio öffnen",
        "Open project in VSCode": "Projekt in VSCode öffnen",
        "Open project in Xcode": "Projekt in Xcode öffnen",
        "Pull latest Git changes": "Neueste Git-Änderungen abrufen",
        "Roll back Git commit": "Git-Commit zurücksetzen",
        "Open Git remote URL": "Git-Remote-URL öffnen",
        "Copy Git remote URL": "Git-Remote-URL kopieren",
        "Copy absolute path": "Absoluten Pfad kopieren",
        "Create file": "Datei erstellen",
        "View file fingerprint Hash (SHA-256)": "Dateiprüfsumme anzeigen (SHA-256)",
        "Hide / show selected items": "Ausgewählte Elemente ausblenden / einblenden",
        "Send to external disk or network volume": "An externen Datenträger oder Netzwerkvolume senden",
        "Grant execute permission (chmod +x)": "Ausführungsrecht erteilen (chmod +x)",
        "Remove execute permission (chmod -x)": "Ausführungsrecht entziehen (chmod -x)",
        "Re-sign IPA without building": "IPA ohne Build erneut signieren",
        "Show / hide files": "Dateien ein-/ausblenden",
        "Create iOS simulator": "iOS-Simulator erstellen",
        "Create Android simulator": "Android-Simulator erstellen",
        "Create Harmony simulator": "Harmony-Simulator erstellen",
        "Check / repair Android simulator": "Android-Simulator prüfen / reparieren",
        "Check / repair Harmony simulator": "Harmony-Simulator prüfen / reparieren",
        "Configure Git proxy": "Git-Proxy konfigurieren",
        "Open in terminal": "Im Terminal öffnen",
        "View file contents in terminal": "Dateiinhalt im Terminal anzeigen",
        "Merge file parts": "Dateiteile zusammenführen",
        "Split file": "Datei aufteilen",
        "Clean Android / OpenHarmony builds": "Android-/OpenHarmony-Builds bereinigen",
        "Update code map (.codegraph)": "Codekarte aktualisieren (.codegraph)",
        "Create empty commit and push in terminal": "Leeren Commit erstellen und im Terminal pushen",
        "Disable CocoaPods build sandbox": "CocoaPods-Build-Sandbox deaktivieren",
        "Install CocoaPods": "CocoaPods installieren",
        "CocoaPods source: CDN → GitHub": "CocoaPods-Quelle: CDN → GitHub",
        "Export all project Pod files": "Alle Pod-Dateien des Projekts exportieren",
        "Inspect Xcode project dependencies": "Xcode-Projektabhängigkeiten untersuchen",
        "Update local CocoaPods repositories": "Lokale CocoaPods-Repositories aktualisieren",
        "Check local Pod builds (.podspec folder)": "Lokale Pod-Builds prüfen (.podspec-Ordner)",
        "Install / update JobsCodeSnippets": "JobsCodeSnippets installieren / aktualisieren",
        "Clean iOS / Xcode builds": "iOS-/Xcode-Builds bereinigen",
        "Set up Flutter project": "Flutter-Projekt einrichten",
        "Run Flutter project in terminal": "Flutter-Projekt im Terminal ausführen",
        "Fetch Flutter Pub dependencies": "Flutter-Pub-Abhängigkeiten abrufen",
        "Fetch native Android dependencies": "Native Android-Abhängigkeiten abrufen",
        "Fetch CocoaPods dependencies": "CocoaPods-Abhängigkeiten abrufen",
        "Fetch Swift Package dependencies": "Swift-Package-Abhängigkeiten abrufen",
        "Fetch OpenHarmony dependencies": "OpenHarmony-Abhängigkeiten abrufen",
        "Prepare native libraries and build dependencies": "Native Bibliotheken und Build-Abhängigkeiten vorbereiten",
        "Download Flutter platform resources": "Flutter-Plattformressourcen herunterladen",
        "Fetch Web project dependencies": "Web-Projektabhängigkeiten abrufen",
        "🧳 Export Flutter dependencies": "🧳 Flutter-Abhängigkeiten exportieren",
        "Export Flutter Pub dependencies": "Flutter-Pub-Abhängigkeiten exportieren",
        "🔐 Export private Flutter dependencies": "🔐 Private Flutter-Abhängigkeiten exportieren",
        "📥 Import Flutter dependencies": "📥 Flutter-Abhängigkeiten importieren",
        "Import Flutter Pub dependencies": "Flutter-Pub-Abhängigkeiten importieren",
        "📥 Import private Flutter dependencies": "📥 Private Flutter-Abhängigkeiten importieren",
        "Export Gradle distributions and cache": "Gradle-Distributionen und -Cache exportieren",
        "Import Gradle distributions and cache": "Gradle-Distributionen und -Cache importieren",
        "Export CocoaPods dependencies": "CocoaPods-Abhängigkeiten exportieren",
        "Import CocoaPods dependencies": "CocoaPods-Abhängigkeiten importieren",
        "Export Swift Package dependencies": "Swift-Package-Abhängigkeiten exportieren",
        "Import Swift Package dependencies": "Swift-Package-Abhängigkeiten importieren",
        "Export OpenHarmony dependencies": "OpenHarmony-Abhängigkeiten exportieren",
        "Import OpenHarmony dependencies": "OpenHarmony-Abhängigkeiten importieren",
        "Export native build cache": "Nativen Build-Cache exportieren",
        "Import native build cache": "Nativen Build-Cache importieren",
        "Export Flutter platform resources": "Flutter-Plattformressourcen exportieren",
        "Import Flutter platform resources": "Flutter-Plattformressourcen importieren",
        "Export Web dependencies": "Web-Abhängigkeiten exportieren",
        "Import Web dependencies": "Web-Abhängigkeiten importieren",
        "Show Flutter project SDK version": "SDK-Version des Flutter-Projekts anzeigen",
        "Install / switch Flutter SDK": "Flutter-SDK installieren / wechseln",
        "Install / switch Flutter@OpenHarmony SDK": "Flutter@OpenHarmony-SDK installieren / wechseln",
        "Install / switch Java SDK": "Java-SDK installieren / wechseln",
        "Download Gradle distributions and plugins": "Gradle-Distributionen und -Plugins herunterladen",
        "Generate Flutter code": "Flutter-Code generieren",
        "Package iOS": "iOS-Paket erstellen",
        "Package Android": "Android-Paket erstellen",
        "Package Harmony (HAP + APP)": "Harmony-Paket erstellen (HAP + APP)",
        "Check native Flutter project": "Natives Flutter-Projekt prüfen",
        "Check OpenHarmony Flutter environment": "OpenHarmony-Flutter-Umgebung prüfen",
        "Repair missing Android SDK / platforms": "Fehlendes Android-SDK / fehlende Plattformen reparieren",
        "Repair Chinese Flutter project paths": "Chinesische Pfade im Flutter-Projekt reparieren",
        "Repair Flutter plugin namespaces": "Namespaces von Flutter-Plugins reparieren",
        "Convert relative Dart imports to packages": "Relative Dart-Importe in Paketimporte umwandeln",
        "Clean current Flutter project builds": "Builds des aktuellen Flutter-Projekts bereinigen",
        "Dependency and cache maintenance": "Abhängigkeiten und Caches warten",
        "Custom Explorer context menu": "Explorer-Kontextmenü anpassen",
        "Jobs Windows · Custom Explorer context menu": "Jobs Windows · Explorer-Kontextmenü anpassen",
        "Show a regular file's SHA-256 in a new terminal and copy the digest; do not modify or execute the file.": "SHA-256 einer regulären Datei in einem neuen Terminal anzeigen und die Prüfsumme kopieren; die Datei weder ändern noch ausführen.",
        " (preview)": " (Vorschau)",
        "⏪ Roll back Git commits": "⏪ Git-Commits zurücksetzen",
        "▶️ Run Flutter project in terminal": "▶️ Flutter-Projekt im Terminal ausführen",
        "☕ Install / switch Java SDK": "☕ Java-SDK installieren / wechseln",
        "♻️ Flutter cleanup and maintenance": "♻️ Flutter bereinigen und warten",
        "⚙️ Generate Flutter code": "⚙️ Flutter-Code generieren",
        "✅ Installed": "✅ Installiert",
        "⬇️ Pull latest Git changes": "⬇️ Neueste Git-Änderungen abrufen",
        "🌈 Create Harmony emulator": "🌈 Harmony-Emulator erstellen",
        "🌐 Open Git remote URL": "🌐 Git-Remote-URL öffnen",
        "🌐 Fetch Web project dependencies": "🌐 Web-Projektabhängigkeiten abrufen",
        "🌳 Open in Sourcetree": "🌳 In Sourcetree öffnen",
        "🏥 Flutter project diagnostics": "🏥 Flutter-Projektdiagnose",
        "🏥 Flutter diagnostics": "🏥 Flutter-Diagnose",
        "🏷️ Repair Flutter plugin namespaces": "🏷️ Namespaces von Flutter-Plugins reparieren",
        "👁️ Show / hide hidden files": "👁️ Versteckte Dateien ein-/ausblenden",
        "💓 OpenHarmony Flutter diagnostics": "💓 OpenHarmony-Flutter-Diagnose",
        "💠 Open project in Visual Studio": "💠 Projekt in Visual Studio öffnen",
        "💻 Open in terminal": "💻 Im Terminal öffnen",
        "📄 View file in terminal": "📄 Datei im Terminal anzeigen",
        "📋 Copy absolute path": "📋 Absoluten Pfad kopieren",
        "📚 Download Gradle distributions and build plugins": "📚 Gradle-Distributionen und Build-Plugins herunterladen",
        "📝 Open project in VSCode": "📝 Projekt in VSCode öffnen",
        "📡 Configure Git dynamic proxy": "📡 Dynamischen Git-Proxy konfigurieren",
        "📤 Import Flutter Pub dependencies": "📤 Flutter-Pub-Abhängigkeiten importieren",
        "📤 Import Flutter platform assets": "📤 Flutter-Plattformressourcen importieren",
        "📤 Import Gradle distributions and dependency caches": "📤 Gradle-Distributionen und Abhängigkeitscaches importieren",
        "📤 Import OpenHarmony dependencies": "📤 OpenHarmony-Abhängigkeiten importieren",
        "📤 Import Web dependencies": "📤 Web-Abhängigkeiten importieren",
        "📤 Import native build caches": "📤 Native Build-Caches importieren",
        "📤 Import Flutter project dependencies": "📤 Flutter-Projektabhängigkeiten importieren",
        "📤 Create empty commit and push": "📤 Leeren Commit erstellen und pushen",
        "📥 Install Flutter dependencies (pub get)": "📥 Flutter-Abhängigkeiten installieren (pub get)",
        "📥 Import private Flutter project dependencies": "📥 Private Flutter-Projektabhängigkeiten importieren",
        "📥 Fetch Flutter Pub dependencies": "📥 Flutter-Pub-Abhängigkeiten abrufen",
        "📥 Fetch Flutter project dependencies": "📥 Flutter-Projektabhängigkeiten abrufen",
        "📦 Package Flutter project": "📦 Flutter-Projektpaket erstellen",
        "📦 Package HarmonyOS (HAP + APP)": "📦 HarmonyOS-Paket erstellen (HAP + APP)",
        "📱 Create Android emulator": "📱 Android-Emulator erstellen",
        "🔀 Install / switch Flutter SDK (FVM)": "🔀 Flutter-SDK installieren / wechseln (FVM)",
        "🔀 Install / switch Flutter SDK": "🔀 Flutter-SDK installieren / wechseln",
        "🔀 Install / switch Flutter environments": "🔀 Flutter-Umgebungen installieren / wechseln",
        "🔎 Show current Flutter SDK version": "🔎 Aktuelle Flutter-SDK-Version anzeigen",
        "🔎 Show current Flutter project's SDK version": "🔎 SDK-Version des aktuellen Flutter-Projekts anzeigen",
        "🔐 Export private Flutter project dependencies": "🔐 Private Flutter-Projektabhängigkeiten exportieren",
        "🔎 Show file fingerprint Hash (SHA-256)": "🔎 Dateiprüfsumme anzeigen (SHA-256)",
        "➕ Grant execute permission": "➕ Ausführungsrecht erteilen",
        "➖ Remove execute permission": "➖ Ausführungsrecht entziehen",
        "🔒 Grant execute permission": "🔒 Ausführungsrecht erteilen",
        "🔓 Remove execute permission": "🔓 Ausführungsrecht entziehen",
        "🔗 Copy Git remote URL": "🔗 Git-Remote-URL kopieren",
        "🔧 Flutter repairs": "🔧 Flutter-Reparaturen",
        "🕊️ Install / switch Flutter@OpenHarmony SDK": "🕊️ Flutter@OpenHarmony-SDK installieren / wechseln",
        "🕊️ Fetch OpenHarmony dependencies": "🕊️ OpenHarmony-Abhängigkeiten abrufen",
        "🗃️ Download Flutter platform assets": "🗃️ Flutter-Plattformressourcen herunterladen",
        "🗺️ Update code map (.codegraph)": "🗺️ Codekarte aktualisieren (.codegraph)",
        "🤖 Fetch Android native dependencies": "🤖 Native Android-Abhängigkeiten abrufen",
        "🦋 Flutter development": "🦋 Flutter-Entwicklung",
        "🦋 Flutter development tools": "🦋 Flutter-Entwicklungswerkzeuge",
        "🧑‍⚕️ Native Flutter diagnostics": "🧑‍⚕️ Native Flutter-Diagnose",
        "🧩 Export Flutter Pub dependencies": "🧩 Flutter-Pub-Abhängigkeiten exportieren",
        "🧩 Export Flutter platform assets": "🧩 Flutter-Plattformressourcen exportieren",
        "🧩 Export Flutter third-party dependencies": "🧩 Flutter-Drittanbieterabhängigkeiten exportieren",
        "🧩 Export Gradle distributions and dependency caches": "🧩 Gradle-Distributionen und Abhängigkeitscaches exportieren",
        "🧩 Export OpenHarmony dependencies": "🧩 OpenHarmony-Abhängigkeiten exportieren",
        "🧩 Export Web dependencies": "🧩 Web-Abhängigkeiten exportieren",
        "🧩 Export native build caches": "🧩 Native Build-Caches exportieren",
        "🧩 Export Flutter project dependencies": "🧩 Flutter-Projektabhängigkeiten exportieren",
        "🧩 Merge file volumes / ✂️ Split file": "🧩 Dateivolumes zusammenführen / ✂️ Datei aufteilen",
        "🧭 Open project in Android Studio": "🧭 Projekt in Android Studio öffnen",
        "🧯 Clean build output": "🧯 Build-Ausgaben bereinigen",
        "🧰 Diagnose and repair Harmony emulator": "🧰 Harmony-Emulator diagnostizieren und reparieren",
        "🧱 Flutter assets and build dependencies": "🧱 Flutter-Ressourcen und Build-Abhängigkeiten",
        "🧱 Prepare native libraries and build dependencies (combined)": "🧱 Native Bibliotheken und Build-Abhängigkeiten vorbereiten (kombiniert)",
        "🧹 Clean build output": "🧹 Build-Ausgaben bereinigen",
        "🩹 Repair missing Android SDK / platforms": "🩹 Fehlendes Android-SDK / fehlende Plattformen reparieren",
        "🩺 Diagnose and repair Android emulator": "🩺 Android-Emulator diagnostizieren und reparieren",
        "🚀 Set up Flutter project": "🚀 Flutter-Projekt einrichten",
        "🚚 Import all Flutter dependencies": "🚚 Alle Flutter-Abhängigkeiten importieren",
        "🚚 Export all Flutter dependencies": "🚚 Alle Flutter-Abhängigkeiten exportieren",
        "Jobs Windows · Uninstall Explorer extensions": "Jobs Windows · Explorer-Erweiterungen deinstallieren",
        "Jobs Windows · Install Explorer extensions": "Jobs Windows · Explorer-Erweiterungen installieren",
        "Jobs Windows · Manage Explorer extensions": "Jobs Windows · Explorer-Erweiterungen verwalten",
        "Jobs Windows · Configure Explorer extensions": "Jobs Windows · Explorer-Erweiterungen konfigurieren",
        "Drag the divider vertically to resize the log": "Trennleiste vertikal ziehen, um die Protokollgröße zu ändern",
        "Drag vertically to resize the log": "Vertikal ziehen, um die Protokollgröße zu ändern",
        "Validate the Flutter project, diagnose the toolchain in terminal, and choose a Flutter SDK version with fzf.": "Flutter-Projekt prüfen, die Werkzeugkette im Terminal diagnostizieren und mit fzf eine Flutter-SDK-Version wählen.",
        "Validate the Flutter project, then show the active SDK version (project FVM or system SDK) in terminal and compare it with .fvmrc and pubspec constraints.": "Flutter-Projekt prüfen, dann die aktive SDK-Version (Projekt-FVM oder System-SDK) im Terminal anzeigen und mit .fvmrc und den pubspec-Vorgaben vergleichen.",
        "Flutter roots only. Choose Android / iOS / HarmonyOS with fzf in CMD. Supports APK / AAB and HAP / APP. iOS requires MacOS and Xcode.": "Nur Flutter-Projektwurzeln. Android / iOS / HarmonyOS mit fzf in CMD wählen. Unterstützt APK / AAB und HAP / APP. iOS benötigt MacOS und Xcode.",
        "Flutter roots only. Choose a device and view logs in CMD; the app continues in the background after the window closes.": "Nur Flutter-Projektwurzeln. Gerät wählen und Protokolle in CMD anzeigen; die App läuft nach dem Schließen des Fensters im Hintergrund weiter.",
        "Flutter roots only. Read-only version and doctor diagnostics in terminal; no dependency fetching, cleanup, or tool upgrades.": "Nur Flutter-Projektwurzeln. Schreibgeschützte Versions- und doctor-Diagnose im Terminal; kein Abruf von Abhängigkeiten, keine Bereinigung und keine Werkzeug-Upgrades.",
        "Flutter roots only. Preview configured generators, then fetch dependencies and generate code after confirmation. Deleting conflicts requires separate opt-in.": "Nur Flutter-Projektwurzeln. Konfigurierte Generatoren anzeigen, dann nach Bestätigung Abhängigkeiten abrufen und Code generieren. Das Löschen von Konflikten erfordert eine gesonderte Zustimmung.",
        "Git worktree folders only. Detect nested repositories. Soft mode preserves the index and worktree; hard mode requires exact YES confirmation.": "Nur Git-Arbeitsverzeichnisse. Verschachtelte Repositories erkennen. Der Modus soft erhält Index und Arbeitsverzeichnis; der Modus hard verlangt die exakte Bestätigung YES.",
        "Desktop background on x64 Windows only. Missing tools come from the SDL mirror; missing system images come from the official Emulator. Enter selects a stable phone image; confirm its license to create and start a unique instance.": "Nur Desktop-Hintergrund unter Windows x64. Fehlende Werkzeuge kommen vom SDL-Mirror; fehlende Systemabbilder vom offiziellen Emulator. Eingabe wählt ein stabiles Telefonabbild; dessen Lizenz bestätigen, um eine eindeutig benannte Instanz zu erstellen und zu starten.",
        "Manage only this package's actions. Unselected actions remain when uninstalling.": "Nur Aktionen dieses Pakets verwalten. Nicht ausgewählte Aktionen bleiben bei der Deinstallation erhalten.",
        "Desktop background only. Configure user-level Git to prefer the system proxy and fall back to a direct connection.": "Nur Desktop-Hintergrund. Git für den Benutzer so konfigurieren, dass der Systemproxy bevorzugt und bei Bedarf eine direkte Verbindung verwendet wird.",
        "Desktop background only. Diagnose the SDK in CMD, choose a device and system image, then create or start an Android AVD.": "Nur Desktop-Hintergrund. SDK in CMD diagnostizieren, Gerät und Systemabbild wählen, dann ein Android-AVD erstellen oder starten.",
        "Desktop background only. Check existing DevEco Emulator instances, then start one or confirm a nondestructive restart. Data is preserved.": "Nur Desktop-Hintergrund. Vorhandene DevEco-Emulator-Instanzen prüfen, dann eine starten oder einen Neustart ohne Datenverlust bestätigen. Daten bleiben erhalten.",
        "Desktop background only. Check emulator location and /data; optionally reset caches, precisely uninstall, back up the AVD, and retest with a cold boot.": "Nur Desktop-Hintergrund. Emulatorpfad und /data prüfen; optional Caches zurücksetzen, gezielt deinstallieren, das AVD sichern und mit einem Kaltstart erneut prüfen.",
        "Show the next action on the desktop background. Toggle hidden files for the current user's Explorer without changing protected-system-file settings.": "Nächste Aktion auf dem Desktop-Hintergrund anzeigen. Versteckte Dateien im Explorer des aktuellen Benutzers umschalten, ohne die Einstellung für geschützte Systemdateien zu ändern.",
        "Visible only for nonempty native Android or valid Flutter (official / HarmonyOS) project roots. Validated again before opening.": "Nur für nicht leere native Android- oder gültige Flutter-Projektwurzeln (offiziell / HarmonyOS) sichtbar. Vor dem Öffnen erneut geprüft.",
        "Preview: the selection is shown in the log. No installation or uninstallation was performed.": "Vorschau: Die Auswahl wird im Protokoll angezeigt. Es wurde nichts installiert oder deinstalliert.",
        "Preview only. Confirming displays the selection in the log without installing, uninstalling, or writing state or registry entries.": "Nur Vorschau. Die Bestätigung zeigt die Auswahl im Protokoll an, ohne Installation, Deinstallation oder Änderungen an Status und Registrierung.",
        "Deployed copies use their bound location. To change it, open the manager from the source directory. Default installations run in the current user's LocalAppData; local builds run under this package's work directory and stop working if it moves.": "Bereitgestellte Kopien verwenden ihren gebundenen Speicherort. Zum Ändern die Verwaltung aus dem Quellverzeichnis öffnen. Standardinstallationen laufen unter LocalAppData des aktuellen Benutzers; lokale Builds im Arbeitsverzeichnis dieses Pakets und funktionieren nach dessen Verschieben nicht mehr.",
        "Prefer Windows Terminal; otherwise use system PowerShell.": "Windows Terminal bevorzugen; andernfalls System-PowerShell verwenden.",
        "Could not save preferences: ": "Einstellungen konnten nicht gespeichert werden: ",
        "Save settings": "Einstellungen speichern",
        "Protect local changes. On conflict, choose to restore, discard changes, or commit and retry.": "Lokale Änderungen schützen. Bei Konflikten Wiederherstellen, Änderungen verwerfen oder Commit erstellen und erneut versuchen wählen.",
        "All operations completed. Copy the log or close the panel.": "Alle Vorgänge abgeschlossen. Protokoll kopieren oder Fenster schließen.",
        "Other context-menu features": "Weitere Kontextmenüfunktionen",
        "Create or synchronize the code map for the current directory.": "Codekarte für das aktuelle Verzeichnis erstellen oder synchronisieren.",
        "Feature and log divider": "Trennleiste zwischen Funktionen und Protokoll",
        "Select features, then confirm. Unselected features remain. Hover for installation details.": "Funktionen auswählen und bestätigen. Nicht ausgewählte Funktionen bleiben erhalten. Für Installationsdetails den Mauszeiger darüber bewegen.",
        "Checked features are installed; unchecked ones are uninstalled. Saving an empty selection disables all installed features.": "Markierte Funktionen werden installiert, nicht markierte deinstalliert. Das Speichern einer leeren Auswahl deaktiviert alle installierten Funktionen.",
        "Select features to install. Enabled sibling actions and other unselected features remain.": "Zu installierende Funktionen auswählen. Aktivierte benachbarte Aktionen und andere nicht ausgewählte Funktionen bleiben erhalten.",
        "Total uninstall time": "Gesamte Deinstallationszeit",
        "Uninstall selected": "Auswahl deinstallieren",
        "Uninstall selected features": "Ausgewählte Funktionen deinstallieren",
        "Uninstall time": "Deinstallationszeit",
        "Cancel": "Abbrechen",
        "Uninstall only selected installed features. Other features, logs, backups and tools remain.": "Nur ausgewählte installierte Funktionen deinstallieren. Andere Funktionen, Protokolle, Sicherungen und Werkzeuge bleiben erhalten.",
        "Change only the current user's ExecuteFile ACL for a single regular NTFS file after confirmation. Does not launch the file or change global policy.": "Nach Bestätigung nur die ExecuteFile-ACL des aktuellen Benutzers für eine einzelne reguläre NTFS-Datei ändern. Die Datei wird nicht gestartet und die globale Richtlinie bleibt unverändert.",
        "View a single regular file. Files over 1 MiB or suspected binary files require YES in the terminal.": "Eine einzelne reguläre Datei anzeigen. Dateien über 1 MiB oder vermutlich binäre Dateien erfordern YES im Terminal.",
        "Clean only the selected packages' build workspaces. Installed DLLs, scripts, settings and registry entries remain.": "Nur Build-Arbeitsbereiche ausgewählter Pakete bereinigen. Installierte DLLs, Skripte, Einstellungen und Registrierungseinträge bleiben erhalten.",
        "Copy full log": "Vollständiges Protokoll kopieren",
        "Copy the original remote URL for the current branch.": "Ursprüngliche Remote-URL des aktuellen Branches kopieren.",
        "Copy the absolute path of a file or folder.": "Absoluten Pfad einer Datei oder eines Ordners kopieren.",
        "Could not copy the log: ": "Protokoll konnte nicht kopiert werden: ",
        "Failed — open log": "Fehlgeschlagen — Protokoll öffnen",
        "Install / update": "Installieren / aktualisieren",
        "Install / update selected features": "Ausgewählte Funktionen installieren / aktualisieren",
        "Total install time": "Gesamte Installationszeit",
        "Install time": "Installationszeit",
        "Merge appears for a complete selected volume set; split appears for one regular file. Originals are always preserved.": "Zusammenführen erscheint für einen vollständig ausgewählten Volumesatz; Aufteilen für eine einzelne reguläre Datei. Originale bleiben immer erhalten.",
        "Live log (drag the divider to resize)": "Live-Protokoll (Trennleiste zum Ändern der Größe ziehen)",
        "Installation stopped after the current package transaction. Unstarted items are marked Not run.": "Installation nach der aktuellen Pakettransaktion gestoppt. Nicht begonnene Einträge sind als Nicht ausgeführt markiert.",
        "Stop requested. Waiting for the current package transaction; later items will not run.": "Stopp angefordert. Warten auf die aktuelle Pakettransaktion; nachfolgende Einträge werden nicht ausgeführt.",
        "Selected {0} / {1}. Closing or cancelling makes no changes.": "Ausgewählt: {0} / {1}. Schließen oder Abbrechen nimmt keine Änderungen vor.",
        "Hover for feature details. Windows 11: right-click → Show more options.": "Für Funktionsdetails den Mauszeiger darüber bewegen. Windows 11: Rechtsklick → Weitere Optionen anzeigen.",
        "Could not open the full log: ": "Vollständiges Protokoll konnte nicht geöffnet werden: ",
        "Open the repository website for the current Git worktree.": "Repository-Website des aktuellen Git-Arbeitsverzeichnisses öffnen.",
        "Open the solution or project at the current directory level.": "Projektmappe oder Projekt auf der aktuellen Verzeichnisebene öffnen.",
        "Export resolved third-party Pub sources and licenses from the project lockfile. Press Enter to use the desktop as output.": "Aufgelöste Pub-Drittanbieterquellen und Lizenzen aus der Sperrdatei des Projekts exportieren. Eingabe drücken, um den Desktop als Ausgabeziel zu verwenden.",
        "An operation is running. Wait for the transaction to finish before closing. Logs can be copied at any time.": "Ein Vorgang läuft. Vor dem Schließen auf den Abschluss der Transaktion warten. Protokolle können jederzeit kopiert werden.",
        "Could not build the operation plan: ": "Vorgangsplan konnte nicht erstellt werden: ",
        "Could not start the operation: ": "Vorgang konnte nicht gestartet werden: ",
        "Log: ": "Protokoll: ",
        "🈶 Repair Chinese paths in Flutter project": "🈶 Chinesische Pfade im Flutter-Projekt reparieren",
        "Not installed; nothing to uninstall": "Nicht installiert; nichts zu deinstallieren",
        "Not installed": "Nicht installiert",
        "Not run": "Nicht ausgeführt",
        "This feature": "Diese Funktion",
        "Local build directory (moving or cleaning it disables the menu)": "Lokales Build-Verzeichnis (Verschieben oder Bereinigen deaktiviert das Menü)",
        "Validate the branch, staging area and upstream, then confirm the push.": "Branch, Staging-Bereich und Upstream prüfen und danach den Push bestätigen.",
        "Validate the Flutter project, then fetch dependencies.": "Flutter-Projekt prüfen und anschließend Abhängigkeiten abrufen.",
        "Installing / updating…": "Wird installiert / aktualisiert…",
        "This entry has been removed. Existing installations can be uninstalled but cannot be reinstalled.": "Dieser Eintrag wurde entfernt. Vorhandene Installationen können deinstalliert, aber nicht erneut installiert werden.",
        "No features require processing; ": "Keine Funktionen zu bearbeiten; ",
        "No features require processing. No settings were changed.": "Keine Funktionen zu bearbeiten. Es wurden keine Einstellungen geändert.",
        "Total cleanup time": "Gesamte Bereinigungszeit",
        "Cleanup time": "Bereinigungszeit",
        "Click to read the full session log in a new PowerShell window. The current task continues.": "Klicken, um das vollständige Sitzungsprotokoll in einem neuen PowerShell-Fenster zu lesen. Die aktuelle Aufgabe läuft weiter.",
        "Pending": "Ausstehend",
        "Waiting to stop…": "Warten auf Stopp…",
        "Ordered Flutter development, diagnostics, repair and maintenance tools. Regular actions use project FVM; environment setup supports FVM / system Flutter and jEnv / system Java.": "Geordnete Flutter-Werkzeuge für Entwicklung, Diagnose, Reparatur und Wartung. Reguläre Aktionen verwenden Projekt-FVM; die Einrichtung unterstützt FVM / System-Flutter und jEnv / System-Java.",
        "Detect the Flutter / Android project and preview cleanup scope. iOS cleanup is unavailable on Windows.": "Flutter-/Android-Projekt erkennen und den Bereinigungsumfang anzeigen. iOS-Bereinigung ist unter Windows nicht verfügbar.",
        "Could not read preferences: ": "Einstellungen konnten nicht gelesen werden: ",
        "Could not read the log: ": "Protokoll konnte nicht gelesen werden: ",
        "Explorer context-menu extensions · ": "Explorer-Kontextmenüerweiterungen · ",
        "Explorer extensions · Manage": "Explorer-Erweiterungen · Verwalten",
        "Return selection": "Auswahl zurückgeben",
        "Exit code: ": "Exit-Code: ",
        "Choose an operation and select features. Unselected features remain; only installed features can be uninstalled.": "Vorgang und Funktionen auswählen. Nicht ausgewählte Funktionen bleiben erhalten; nur installierte Funktionen können deinstalliert werden.",
        "Some features failed; other selected features were still processed. Click a failed status to open the full session log.": "Einige Funktionen sind fehlgeschlagen; andere ausgewählte Funktionen wurden dennoch bearbeitet. Auf einen Fehlerstatus klicken, um das vollständige Sitzungsprotokoll zu öffnen.",
        "Available for nonempty regular directories outside iOS projects, including Flutter roots. Validated again before opening.": "Für nicht leere reguläre Verzeichnisse außerhalb von iOS-Projekten verfügbar, einschließlich Flutter-Projektwurzeln. Vor dem Öffnen erneut geprüft.",
        "Default installation location (recommended)": "Standard-Installationsort (empfohlen)",
        "{0}; Results: succeeded {1}; nothing to uninstall {2}; failed {3}; not run {4}": "{0}; Ergebnisse: erfolgreich {1}; nichts zu deinstallieren {2}; fehlgeschlagen {3}; nicht ausgeführt {4}",
        "{0} Exit code: {1}.": "{0} Exit-Code: {1}.",
        "{0} {1}": "{0} {1}",
        "{0}{1} {2}": "{0}{1} {2}",
        "{0} in progress; completed {1} / {2} ({3}% by completed items); {4} {5}": "{0} läuft; abgeschlossen {1} / {2} ({3}% nach abgeschlossenen Einträgen); {4} {5}",
        "{0} Completed {1} / {2} ({3}% by completed items); {4} {5}": "{0} Abgeschlossen {1} / {2} ({3}% nach abgeschlossenen Einträgen); {4} {5}",
        "Close management panel": "Verwaltungsfenster schließen",
        "Run in the menu bar, or quit the installation / uninstallation panel?": "In der Menüleiste weiterlaufen lassen oder das Installations- / Deinstallationsfenster vollständig beenden?",
        "Run in background": "Im Hintergrund ausführen",
        "Quit completely": "Vollständig beenden",
        "Show management panel": "Verwaltungsfenster anzeigen",
        "Status: {0}": "Status: {0}",
        "A task is running. You can quit after it finishes.": "Eine Aufgabe wird ausgeführt. Nach ihrem Abschluss können Sie beenden."
      },
      "ru": {
        "Update development environment (update)": "Обновить среду разработки (update)",
        "Total disk space": "Общее свободное место на дисках",
        "Create script launcher": "Создать ярлык скрипта",
        "Theme": "Тема",
        "Language": "Язык",
        "🎨 Theme": "🎨 Тема",
        "🌐 Language": "🌐 Язык",
        "Follow system": "Как в системе",
        "Dark": "Тёмная",
        "Light": "Светлая",
        "Jobs Finder Extension Manager": "Диспетчер расширений Finder Jobs",
        "Customize Finder Context Menu": "Настройка контекстного меню Finder",
        "Close Manager": "Закрыть диспетчер",
        "Edit": "Правка",
        "Copy": "Копировать",
        "Select all": "Выбрать все",
        "Clear all": "Снять все",
        "Close": "Закрыть",
        "OK": "ОК",
        "Install": "Установить",
        "Install / Update": "Установить / обновить",
        "Uninstall": "Удалить",
        "Cleanup": "Очистить",
        "Clean build products": "Удалить результаты сборки",
        "🧹 Clean build products": "🧹 Удалить результаты сборки",
        "Stop installation": "Остановить установку",
        "Stopping…": "Остановка…",
        "Action: install / update or uninstall": "Действие: установка / обновление или удаление",
        "Uninstall removes selected menus only. Group selection affects its own group.": "Удаляются только выбранные пункты меню. Выбор внутри группы действует только на эту группу.",
        "Install / uninstall with the combined App in Applications": "Устанавливать / удалять через объединённое приложение в «Программах»",
        "Install or uninstall the combined App in Applications": "Установить или удалить через объединённое приложение в «Программах»",
        "Selected: manage features in /Applications/Jobs自定义右键菜单.app. Otherwise use the build directory.": "Включено: управлять выбранными функциями в /Applications/Jobs自定义右键菜单.app. Иначе использовать каталог сборки.",
        "Clean this build after successful installation": "Удалить результаты этой сборки после успешной установки",
        "Clean this build only after the combined App is installed and verified in Applications. Keep failed builds.": "Очищать эту сборку только после установки и проверки объединённого приложения в «Программах». Не удалять неудачные сборки.",
        "Clean build products of selected features without installing or uninstalling.": "Очистить результаты сборки выбранных функций без установки или удаления.",
        "Clean selected features' build products": "Очистить результаты сборки выбранных функций",
        "Open Privacy & Security": "Открыть «Конфиденциальность и безопасность»",
        "Add and enable Jobs右键菜单管理面板.app in Privacy & Security → App Management. This only opens Settings.": "Добавьте и разрешите Jobs右键菜单管理面板.app в «Конфиденциальность и безопасность → Управление приложениями». Кнопка только открывает настройки.",
        "Target: build directory. Cleaning these products affects installed features.": "Цель: каталог сборки. Его очистка нарушит работу установленных функций.",
        "App: Jobs自定义右键菜单.app at /Applications/Jobs自定义右键菜单.app (build products can be cleaned after installation)": "Приложение: Jobs自定义右键菜单.app в /Applications/Jobs自定义右键菜单.app (после установки результаты сборки можно удалить)",
        "Drag the divider to resize the log. Features and logs scroll separately.": "Перетащите разделитель вверх или вниз, чтобы изменить высоту журнала. Список функций и журнал прокручиваются отдельно.",
        "Feature list and live log divider": "Разделитель списка функций и текущего журнала",
        "Live log (select and copy text)": "Текущий журнал (текст можно выделять и копировать)",
        "Copy log": "Копировать журнал",
        "Log file": "Файл журнала",
        "Auto-scroll": "Автопрокрутка",
        "Ready. Select features and choose an action.": "Готово. Выберите функции и действие.",
        "A task is running. Wait for it to finish before closing.": "Задача выполняется. Дождитесь завершения перед закрытием, чтобы не прервать установку.",
        "Unable to view this log": "Не удалось просмотреть этот журнал",
        "Log is missing or unreadable: {0}": "Журнал отсутствует или недоступен для чтения: {0}",
        "Unable to open log terminal: {0}": "Не удалось открыть терминал журнала: {0}",
        "Click to show this session's full log in a new terminal: {0}": "Нажмите, чтобы показать полный журнал этого сеанса в новом терминале: {0}",
        "Selected {0} / {1}. Select at least one. Changing action keeps selection.": "Выбрано {0} из {1}. Выберите хотя бы один пункт. При смене действия выбор сохраняется.",
        "Selected {0} / {1}": "Выбрано {0} из {1}",
        "{0}: select all": "{0}: выбрать все",
        "{0}: clear all": "{0}: снять все",
        "Waiting": "Ожидание",
        "Cleaning…": "Очистка…",
        "Uninstalling…": "Удаление…",
        "Installing…": "Установка…",
        "Cleaned": "Очищено",
        "Uninstalled": "Удалено",
        "Installed": "Установлено",
        "Skipped": "Не выполнено",
        "Not installed; nothing to remove": "Не установлено; удаление не требуется",
        "Failed: see log": "Ошибка: см. журнал",
        "Selected": "Выбрано",
        "Not selected": "Не выбрано",
        "App Management permission required": "Требуется разрешение на управление приложениями",
        "Permission check required": "Требуется проверка разрешений",
        "Stopped": "Остановлено",
        "Completed": "Завершено",
        "Task failed": "Задача завершилась ошибкой",
        "{0}: processed {1} / {2} ({3}, completed items); {4} time {5}": "{0}: обработано {1} из {2} ({3}, по завершённым пунктам); время операции «{4}»: {5}",
        "{0} ready": "{0}: готово",
        "{0} ready; {1} time {2}": "{0}: готово; время операции «{1}»: {2}",
        "Finishing the current feature, then stopping; install time {0}": "Завершается текущая функция, затем установка остановится; время установки: {0}",
        "{0}: {1} succeeded, {2} failed, {3} skipped; exit {4}; {5}; {6} time {7}": "{0}: успешно {1}, ошибок {2}, не выполнено {3}; код завершения {4}; {5}; общее время операции «{6}»: {7}",
        "{0}: {1} succeeded, {2} failed, {3} not installed, {4} skipped; exit {5}; {6}; {7} time {8}": "{0}: успешно {1}, ошибок {2}, не установлено {3}, не выполнено {4}; код завершения {5}; {6}; общее время операции «{7}»: {8}",
        "{0}: {1} succeeded, {2} failed, {3} not installed; exit {4}; {5}; {6} time {7}": "{0}: успешно {1}, ошибок {2}, не установлено {3}; код завершения {4}; {5}; общее время операции «{6}»: {7}",
        "{0}: {1} succeeded, {2} failed; exit {3}; {4}; {5} time {6}": "{0}: успешно {1}, ошибок {2}; код завершения {3}; {4}; общее время операции «{5}»: {6}",
        "Open projects in IDEs": "Открытие проектов в IDE",
        "Git tools": "Инструменты Git",
        "Files and general tools": "Файлы и общие инструменты",
        "Flutter tools · submenu actions": "Инструменты Flutter · действия подменю",
        "iOS / CocoaPods tools": "Инструменты iOS / CocoaPods",
        "Simulator tools": "Инструменты эмуляторов",
        "Open project in Android Studio": "Открыть проект в Android Studio",
        "Open project in VSCode": "Открыть проект в VSCode",
        "Open project in Xcode": "Открыть проект в Xcode",
        "Pull latest Git changes": "Получить последние изменения Git",
        "Roll back Git commit": "Откатить коммит Git",
        "Open Git remote URL": "Открыть адрес удалённого репозитория Git",
        "Copy Git remote URL": "Копировать адрес удалённого репозитория Git",
        "Copy absolute path": "Копировать абсолютный путь",
        "Create file": "Создать файл",
        "View file fingerprint Hash (SHA-256)": "Показать хеш файла (SHA-256)",
        "Hide / show selected items": "Скрыть / показать выбранные объекты",
        "Send to external disk or network volume": "Отправить на внешний диск или сетевой том",
        "Grant execute permission (chmod +x)": "Разрешить выполнение (chmod +x)",
        "Remove execute permission (chmod -x)": "Запретить выполнение (chmod -x)",
        "Re-sign IPA without building": "Повторно подписать IPA без сборки",
        "Show / hide files": "Показать / скрыть скрытые файлы",
        "Create iOS simulator": "Создать эмулятор iOS",
        "Create Android simulator": "Создать эмулятор Android",
        "Create Harmony simulator": "Создать эмулятор Harmony",
        "Check / repair Android simulator": "Проверить / восстановить эмулятор Android",
        "Check / repair Harmony simulator": "Проверить / восстановить эмулятор Harmony",
        "Configure Git proxy": "Настроить динамический прокси Git",
        "Open in terminal": "Открыть в терминале",
        "View file contents in terminal": "Просмотреть содержимое файла в терминале",
        "Merge file parts": "Объединить части файла",
        "Split file": "Разделить файл",
        "Clean Android / OpenHarmony builds": "Очистить результаты сборки Android / OpenHarmony",
        "Update code map (.codegraph)": "Обновить карту кода (.codegraph)",
        "Create empty commit and push in terminal": "Создать пустой коммит и отправить в терминале",
        "Disable CocoaPods build sandbox": "Отключить песочницу сборки CocoaPods",
        "Install CocoaPods": "Установить CocoaPods",
        "CocoaPods source: CDN → GitHub": "Источник CocoaPods: CDN → GitHub",
        "Export all project Pod files": "Экспортировать все файлы Pod проекта",
        "Inspect Xcode project dependencies": "Проверить зависимости проекта Xcode",
        "Update local CocoaPods repositories": "Обновить локальные репозитории CocoaPods",
        "Check local Pod builds (.podspec folder)": "Проверить сборку локального Pod (каталог .podspec)",
        "Install / update JobsCodeSnippets": "Установить / обновить JobsCodeSnippets",
        "Clean iOS / Xcode builds": "Очистить результаты сборки iOS / Xcode",
        "Set up Flutter project": "Настроить проект Flutter",
        "Run Flutter project in terminal": "Запустить проект Flutter в терминале",
        "Fetch Flutter Pub dependencies": "Получить зависимости Flutter Pub",
        "Fetch native Android dependencies": "Получить нативные зависимости Android",
        "Fetch CocoaPods dependencies": "Получить зависимости CocoaPods",
        "Fetch Swift Package dependencies": "Получить зависимости Swift Package",
        "Fetch OpenHarmony dependencies": "Получить зависимости OpenHarmony",
        "Prepare native libraries and build dependencies": "Подготовить нативные библиотеки и зависимости сборки",
        "Download Flutter platform resources": "Загрузить ресурсы платформ Flutter",
        "Fetch Web project dependencies": "Получить зависимости веб-проекта",
        "🧳 Export Flutter dependencies": "🧳 Экспортировать все зависимости Flutter",
        "Export Flutter Pub dependencies": "Экспортировать зависимости Flutter Pub",
        "🔐 Export private Flutter dependencies": "🔐 Экспортировать закрытые зависимости Flutter",
        "📥 Import Flutter dependencies": "📥 Импортировать все зависимости Flutter",
        "Import Flutter Pub dependencies": "Импортировать зависимости Flutter Pub",
        "📥 Import private Flutter dependencies": "📥 Импортировать закрытые зависимости Flutter",
        "Export Gradle distributions and cache": "Экспортировать дистрибутивы и кэш Gradle",
        "Import Gradle distributions and cache": "Импортировать дистрибутивы и кэш Gradle",
        "Export CocoaPods dependencies": "Экспортировать зависимости CocoaPods",
        "Import CocoaPods dependencies": "Импортировать зависимости CocoaPods",
        "Export Swift Package dependencies": "Экспортировать зависимости Swift Package",
        "Import Swift Package dependencies": "Импортировать зависимости Swift Package",
        "Export OpenHarmony dependencies": "Экспортировать зависимости OpenHarmony",
        "Import OpenHarmony dependencies": "Импортировать зависимости OpenHarmony",
        "Export native build cache": "Экспортировать кэш нативной сборки",
        "Import native build cache": "Импортировать кэш нативной сборки",
        "Export Flutter platform resources": "Экспортировать ресурсы платформ Flutter",
        "Import Flutter platform resources": "Импортировать ресурсы платформ Flutter",
        "Export Web dependencies": "Экспортировать зависимости веб-проекта",
        "Import Web dependencies": "Импортировать зависимости веб-проекта",
        "Show Flutter project SDK version": "Показать версию SDK проекта Flutter",
        "Install / switch Flutter SDK": "Установить / сменить Flutter SDK",
        "Install / switch Flutter@OpenHarmony SDK": "Установить / сменить Flutter@OpenHarmony SDK",
        "Install / switch Java SDK": "Установить / сменить Java SDK",
        "Download Gradle distributions and plugins": "Загрузить дистрибутивы и плагины сборки Gradle",
        "Generate Flutter code": "Сгенерировать код Flutter",
        "Package iOS": "Собрать пакет iOS",
        "Package Android": "Собрать пакет Android",
        "Package Harmony (HAP + APP)": "Собрать пакет Harmony (HAP + APP)",
        "Check native Flutter project": "Диагностика нативного проекта Flutter",
        "Check OpenHarmony Flutter environment": "Диагностика среды Flutter для OpenHarmony",
        "Repair missing Android SDK / platforms": "Восстановить отсутствующие Android SDK / платформы",
        "Repair Chinese Flutter project paths": "Исправить китайские пути проекта Flutter",
        "Repair Flutter plugin namespaces": "Исправить пространства имён плагинов Flutter",
        "Convert relative Dart imports to packages": "Преобразовать относительные импорты Dart в ссылки package",
        "Clean current Flutter project builds": "Очистить результаты сборки текущего проекта Flutter",
        "Dependency and cache maintenance": "Обслуживание зависимостей и кэша",
        "Custom Explorer context menu": "Настройка контекстного меню Explorer",
        "Jobs Windows · Custom Explorer context menu": "Jobs Windows · Настройка контекстного меню Explorer",
        "Show a regular file's SHA-256 in a new terminal and copy the digest; do not modify or execute the file.": "Показать SHA-256 одного обычного файла в новом терминале и скопировать хеш, не изменяя и не запуская файл.",
        " (preview)": " (предпросмотр)",
        "⏪ Roll back Git commits": "⏪ Откатить коммиты Git",
        "▶️ Run Flutter project in terminal": "▶️ Запустить проект Flutter в терминале",
        "☕ Install / switch Java SDK": "☕ Установить / переключить Java SDK",
        "♻️ Flutter cleanup and maintenance": "♻️ Очистка и обслуживание Flutter",
        "⚙️ Generate Flutter code": "⚙️ Сгенерировать код Flutter",
        "✅ Installed": "✅ Установлено",
        "⬇️ Pull latest Git changes": "⬇️ Получить последние изменения Git",
        "🌈 Create Harmony emulator": "🌈 Создать эмулятор Harmony",
        "🌐 Open Git remote URL": "🌐 Открыть URL удалённого репозитория Git",
        "🌐 Fetch Web project dependencies": "🌐 Загрузить зависимости веб-проекта",
        "🌳 Open in Sourcetree": "🌳 Открыть в Sourcetree",
        "🏥 Flutter project diagnostics": "🏥 Диагностика проекта Flutter",
        "🏥 Flutter diagnostics": "🏥 Диагностика проекта Flutter",
        "🏷️ Repair Flutter plugin namespaces": "🏷️ Исправить пространства имён плагинов Flutter",
        "👁️ Show / hide hidden files": "👁️ Показать / скрыть скрытые файлы",
        "💓 OpenHarmony Flutter diagnostics": "💓 Диагностика Flutter OpenHarmony",
        "💠 Open project in Visual Studio": "💠 Открыть проект в Visual Studio",
        "💻 Open in terminal": "💻 Открыть в терминале",
        "📄 View file in terminal": "📄 Просмотреть файл в терминале",
        "📋 Copy absolute path": "📋 Копировать абсолютный путь",
        "📚 Download Gradle distributions and build plugins": "📚 Загрузить дистрибутивы Gradle и плагины сборки",
        "📝 Open project in VSCode": "📝 Открыть проект в VSCode",
        "📡 Configure Git dynamic proxy": "📡 Настроить динамический прокси Git",
        "📤 Import Flutter Pub dependencies": "📤 Импортировать зависимости Flutter Pub",
        "📤 Import Flutter platform assets": "📤 Импортировать ресурсы платформ Flutter",
        "📤 Import Gradle distributions and dependency caches": "📤 Импортировать дистрибутивы Gradle и кеши зависимостей",
        "📤 Import OpenHarmony dependencies": "📤 Импортировать зависимости OpenHarmony",
        "📤 Import Web dependencies": "📤 Импортировать веб-зависимости",
        "📤 Import native build caches": "📤 Импортировать кеши нативных сборок",
        "📤 Import Flutter project dependencies": "📤 Импортировать зависимости проекта Flutter",
        "📤 Create empty commit and push": "📤 Создать пустой коммит и отправить",
        "📥 Install Flutter dependencies (pub get)": "📥 Установить зависимости Flutter (pub get)",
        "📥 Import private Flutter project dependencies": "📥 Импортировать приватные зависимости проекта Flutter",
        "📥 Fetch Flutter Pub dependencies": "📥 Загрузить зависимости Flutter Pub",
        "📥 Fetch Flutter project dependencies": "📥 Получить зависимости проекта Flutter",
        "📦 Package Flutter project": "📦 Собрать пакет проекта Flutter",
        "📦 Package HarmonyOS (HAP + APP)": "📦 Собрать HarmonyOS (HAP + APP)",
        "📱 Create Android emulator": "📱 Создать эмулятор Android",
        "🔀 Install / switch Flutter SDK (FVM)": "🔀 Установить / сменить Flutter SDK (FVM)",
        "🔀 Install / switch Flutter SDK": "🔀 Установить / переключить Flutter SDK",
        "🔀 Install / switch Flutter environments": "🔀 Установить / сменить среду выполнения Flutter",
        "🔎 Show current Flutter SDK version": "🔎 Показать версию текущего Flutter SDK",
        "🔎 Show current Flutter project's SDK version": "🔎 Показать версию SDK текущего проекта Flutter",
        "🔐 Export private Flutter project dependencies": "🔐 Экспортировать приватные зависимости проекта Flutter",
        "🔎 Show file fingerprint Hash (SHA-256)": "🔎 Показать хеш файла (SHA-256)",
        "➕ Grant execute permission": "➕ Разрешить выполнение",
        "➖ Remove execute permission": "➖ Запретить выполнение",
        "🔒 Grant execute permission": "🔒 Разрешить выполнение",
        "🔓 Remove execute permission": "🔓 Запретить выполнение",
        "🔗 Copy Git remote URL": "🔗 Копировать URL удалённого репозитория Git",
        "🔧 Flutter repairs": "🔧 Исправление проекта Flutter",
        "🕊️ Install / switch Flutter@OpenHarmony SDK": "🕊️ Установить / переключить Flutter@OpenHarmony SDK",
        "🕊️ Fetch OpenHarmony dependencies": "🕊️ Загрузить зависимости OpenHarmony",
        "🗃️ Download Flutter platform assets": "🗃️ Загрузить ресурсы платформ Flutter",
        "🗺️ Update code map (.codegraph)": "🗺️ Обновить карту кода (.codegraph)",
        "🤖 Fetch Android native dependencies": "🤖 Загрузить нативные зависимости Android",
        "🦋 Flutter development": "🦋 Разработка на Flutter",
        "🦋 Flutter development tools": "🦋 Инструменты разработки Flutter",
        "🧑‍⚕️ Native Flutter diagnostics": "🧑‍⚕️ Диагностика нативного Flutter",
        "🧩 Export Flutter Pub dependencies": "🧩 Экспортировать зависимости Flutter Pub",
        "🧩 Export Flutter platform assets": "🧩 Экспортировать ресурсы платформ Flutter",
        "🧩 Export Flutter third-party dependencies": "🧩 Экспортировать сторонние зависимости Flutter",
        "🧩 Export Gradle distributions and dependency caches": "🧩 Экспортировать дистрибутивы Gradle и кеши зависимостей",
        "🧩 Export OpenHarmony dependencies": "🧩 Экспортировать зависимости OpenHarmony",
        "🧩 Export Web dependencies": "🧩 Экспортировать веб-зависимости",
        "🧩 Export native build caches": "🧩 Экспортировать кеши нативных сборок",
        "🧩 Export Flutter project dependencies": "🧩 Экспортировать зависимости проекта Flutter",
        "🧩 Merge file volumes / ✂️ Split file": "🧩 Объединить части файла / ✂️ Разделить файл",
        "🧭 Open project in Android Studio": "🧭 Открыть проект в Android Studio",
        "🧯 Clean build output": "🧯 Очистить результаты сборки",
        "🧰 Diagnose and repair Harmony emulator": "🧰 Диагностика и восстановление эмулятора Harmony",
        "🧱 Flutter assets and build dependencies": "🧱 Ресурсы Flutter и зависимости сборки",
        "🧱 Prepare native libraries and build dependencies (combined)": "🧱 Подготовить нативные библиотеки и зависимости сборки (комплексно)",
        "🧹 Clean build output": "🧹 Очистить результаты сборки",
        "🩹 Repair missing Android SDK / platforms": "🩹 Исправить отсутствующие Android SDK / платформы",
        "🩺 Diagnose and repair Android emulator": "🩺 Диагностика и восстановление эмулятора Android",
        "🚀 Set up Flutter project": "🚀 Настроить проект Flutter",
        "🚚 Import all Flutter dependencies": "🚚 Импортировать все зависимости Flutter",
        "🚚 Export all Flutter dependencies": "🚚 Экспортировать все зависимости Flutter",
        "Jobs Windows · Uninstall Explorer extensions": "Jobs Windows · Удаление расширений Explorer",
        "Jobs Windows · Install Explorer extensions": "Jobs Windows · Установка расширений Explorer",
        "Jobs Windows · Manage Explorer extensions": "Jobs Windows · Управление расширениями Explorer",
        "Jobs Windows · Configure Explorer extensions": "Jobs Windows · Настройка расширений Explorer",
        "Drag the divider vertically to resize the log": "Перетащите разделитель вверх или вниз, чтобы изменить высоту журнала",
        "Drag vertically to resize the log": "Перетащите вверх или вниз, чтобы изменить высоту журнала",
        "Validate the Flutter project, diagnose the toolchain in terminal, and choose a Flutter SDK version with fzf.": "Проверить проект Flutter, выполнить диагностику инструментов в терминале и выбрать версию Flutter SDK через fzf.",
        "Validate the Flutter project, then show the active SDK version (project FVM or system SDK) in terminal and compare it with .fvmrc and pubspec constraints.": "Проверить проект Flutter, показать текущую версию SDK в терминале (проектный FVM или системный SDK) и сверить её с .fvmrc и ограничениями pubspec.",
        "Flutter roots only. Choose Android / iOS / HarmonyOS with fzf in CMD. Supports APK / AAB and HAP / APP. iOS requires MacOS and Xcode.": "Только для корней проектов Flutter. В CMD выберите Android / iOS / HarmonyOS через fzf. Поддерживаются APK / AAB и HAP / APP. Для iOS нужны MacOS и Xcode.",
        "Flutter roots only. Choose a device and view logs in CMD; the app continues in the background after the window closes.": "Только для корней проектов Flutter. Выберите устройство и просматривайте журнал в CMD; после закрытия окна приложение продолжит работать в фоне.",
        "Flutter roots only. Read-only version and doctor diagnostics in terminal; no dependency fetching, cleanup, or tool upgrades.": "Только для корней проектов Flutter. В терминале выполняются только чтение версии и диагностика doctor; без загрузки зависимостей, очистки и обновления инструментов.",
        "Flutter roots only. Preview configured generators, then fetch dependencies and generate code after confirmation. Deleting conflicts requires separate opt-in.": "Только для корней проектов Flutter. Просмотрите настроенные генераторы, затем после подтверждения загрузите зависимости и сгенерируйте код. Удаление конфликтующих файлов требует отдельного согласия.",
        "Git worktree folders only. Detect nested repositories. Soft mode preserves the index and worktree; hard mode requires exact YES confirmation.": "Только для каталогов рабочих деревьев Git. Распознаются вложенные репозитории. Режим soft сохраняет индекс и рабочие файлы; hard требует точного подтверждения YES.",
        "Desktop background on x64 Windows only. Missing tools come from the SDL mirror; missing system images come from the official Emulator. Enter selects a stable phone image; confirm its license to create and start a unique instance.": "Только в контекстном меню рабочего стола x64 Windows. Недостающие инструменты загружаются с зеркала SDL, образы системы — через официальный Emulator. Нажмите Enter для выбора стабильного образа телефона, подтвердите лицензию, чтобы создать и запустить уникальный экземпляр.",
        "Manage only this package's actions. Unselected actions remain when uninstalling.": "Управлять только действиями этого пакета. При удалении невыбранные действия сохраняются.",
        "Desktop background only. Configure user-level Git to prefer the system proxy and fall back to a direct connection.": "Только в контекстном меню рабочего стола. Настроить Git текущего пользователя: сначала системный прокси, при сбое — прямое соединение.",
        "Desktop background only. Diagnose the SDK in CMD, choose a device and system image, then create or start an Android AVD.": "Только в контекстном меню рабочего стола. Проверить SDK в CMD, выбрать модель и образ системы, затем создать или запустить Android AVD.",
        "Desktop background only. Check existing DevEco Emulator instances, then start one or confirm a nondestructive restart. Data is preserved.": "Только в контекстном меню рабочего стола. Проверить существующие экземпляры DevEco Emulator, затем запустить выбранный или подтвердить перезапуск без потери данных.",
        "Desktop background only. Check emulator location and /data; optionally reset caches, precisely uninstall, back up the AVD, and retest with a cold boot.": "Только в контекстном меню рабочего стола. Проверить расположение эмулятора и /data; при необходимости сбросить кэш, точно удалить выбранный эмулятор, создать полную копию AVD и проверить холодный запуск.",
        "Show the next action on the desktop background. Toggle hidden files for the current user's Explorer without changing protected-system-file settings.": "В контекстном меню рабочего стола показано следующее действие. Переключает отображение скрытых файлов в Explorer текущего пользователя, не меняя настройки защищённых системных файлов.",
        "Visible only for nonempty native Android or valid Flutter (official / HarmonyOS) project roots. Validated again before opening.": "Доступно только для непустых корней нативных проектов Android или допустимых проектов Flutter (официальных / HarmonyOS). Перед открытием выполняется повторная проверка.",
        "Preview: the selection is shown in the log. No installation or uninstallation was performed.": "Предпросмотр: выбранные пункты показаны в журнале. Установка и удаление не выполнялись.",
        "Preview only. Confirming displays the selection in the log without installing, uninstalling, or writing state or registry entries.": "Только предпросмотр. Подтверждение показывает выбор в журнале, без установки, удаления и записи состояния или реестра.",
        "Deployed copies use their bound location. To change it, open the manager from the source directory. Default installations run in the current user's LocalAppData; local builds run under this package's work directory and stop working if it moves.": "Установленные копии используют закреплённое расположение. Чтобы изменить его, откройте диспетчер из исходного каталога. При обычной установке приложение работает в LocalAppData текущего пользователя; локальная сборка — в каталоге work этого пакета и перестаёт работать при его перемещении.",
        "Prefer Windows Terminal; otherwise use system PowerShell.": "Предпочитать Windows Terminal; иначе использовать системный PowerShell.",
        "Could not save preferences: ": "Не удалось сохранить настройки: ",
        "Save settings": "Сохранить настройки",
        "Protect local changes. On conflict, choose to restore, discard changes, or commit and retry.": "Защитить локальные изменения. При конфликте выберите восстановление, отмену изменений или создание коммита с повторной попыткой.",
        "All operations completed. Copy the log or close the panel.": "Все операции завершены. Можно скопировать журнал или закрыть панель.",
        "Other context-menu features": "Другие функции контекстного меню",
        "Create or synchronize the code map for the current directory.": "Создать или синхронизировать карту кода текущего каталога.",
        "Feature and log divider": "Разделитель функций и журнала",
        "Select features, then confirm. Unselected features remain. Hover for installation details.": "Выберите функции и подтвердите. Невыбранные сохраняются. Наведите указатель, чтобы узнать состояние установки.",
        "Checked features are installed; unchecked ones are uninstalled. Saving an empty selection disables all installed features.": "Выбранные функции устанавливаются, невыбранные удаляются. Сохранение пустого выбора отключает все установленные функции.",
        "Select features to install. Enabled sibling actions and other unselected features remain.": "Выберите функции для установки. Уже включённые соседние действия и другие невыбранные функции сохраняются.",
        "Total uninstall time": "Общее время удаления",
        "Uninstall selected": "Удалить выбранное",
        "Uninstall selected features": "Удалить выбранные функции",
        "Uninstall time": "Время удаления",
        "Cancel": "Отмена",
        "Uninstall only selected installed features. Other features, logs, backups and tools remain.": "Удалить только выбранные установленные функции. Остальные функции, журналы, резервные копии и инструменты сохраняются.",
        "Change only the current user's ExecuteFile ACL for a single regular NTFS file after confirmation. Does not launch the file or change global policy.": "После подтверждения изменить только ExecuteFile ACL текущего пользователя для одного обычного файла NTFS. Не запускает файл и не меняет глобальную политику.",
        "View a single regular file. Files over 1 MiB or suspected binary files require YES in the terminal.": "Просмотреть один обычный файл. Для файлов больше 1 MiB или предположительно двоичных файлов требуется ввести YES в терминале.",
        "Clean only the selected packages' build workspaces. Installed DLLs, scripts, settings and registry entries remain.": "Очистить только рабочие каталоги сборки выбранных пакетов. Установленные DLL, скрипты, настройки и записи реестра сохраняются.",
        "Copy full log": "Копировать полный журнал",
        "Copy the original remote URL for the current branch.": "Копировать исходный удалённый адрес текущей ветки.",
        "Copy the absolute path of a file or folder.": "Копировать абсолютный путь файла или папки.",
        "Could not copy the log: ": "Не удалось скопировать журнал: ",
        "Failed — open log": "Ошибка — открыть журнал",
        "Install / update": "Установить / обновить",
        "Install / update selected features": "Установить / обновить выбранные функции",
        "Total install time": "Общее время установки",
        "Install time": "Время установки",
        "Merge appears for a complete selected volume set; split appears for one regular file. Originals are always preserved.": "Объединение доступно при выборе полного набора частей файла; разделение — для одного обычного файла. Оригиналы всегда сохраняются.",
        "Live log (drag the divider to resize)": "Текущий журнал (высота изменяется перетаскиванием разделителя)",
        "Installation stopped after the current package transaction. Unstarted items are marked Not run.": "Установка остановлена после завершения операции с текущим пакетом. Не начатые пункты отмечены как «Не выполнено».",
        "Stop requested. Waiting for the current package transaction; later items will not run.": "Запрошена остановка. Ожидание завершения операции с текущим пакетом; последующие пункты выполняться не будут.",
        "Selected {0} / {1}. Closing or cancelling makes no changes.": "Выбрано {0} из {1}. Закрытие или отмена не вносят изменений.",
        "Hover for feature details. Windows 11: right-click → Show more options.": "Наведите указатель для описания функции. Windows 11: щелчок правой кнопкой → Показать дополнительные параметры.",
        "Could not open the full log: ": "Не удалось открыть полный журнал: ",
        "Open the repository website for the current Git worktree.": "Открыть сайт репозитория текущего рабочего дерева Git.",
        "Open the solution or project at the current directory level.": "Открыть решение или проект на текущем уровне каталога.",
        "Export resolved third-party Pub sources and licenses from the project lockfile. Press Enter to use the desktop as output.": "Экспортировать исходники сторонних зависимостей Pub с определёнными версиями и их лицензии по файлу блокировки проекта. Нажмите Enter, чтобы сохранить на рабочий стол.",
        "An operation is running. Wait for the transaction to finish before closing. Logs can be copied at any time.": "Операция выполняется. Дождитесь завершения транзакции перед закрытием. Журнал можно скопировать в любое время.",
        "Could not build the operation plan: ": "Не удалось составить план операции: ",
        "Could not start the operation: ": "Не удалось запустить операцию: ",
        "Log: ": "Журнал: ",
        "🈶 Repair Chinese paths in Flutter project": "🈶 Исправить китайские пути проекта Flutter",
        "Not installed; nothing to uninstall": "Не установлено; удаление не требуется",
        "Not installed": "Не установлено",
        "Not run": "Не выполнено",
        "This feature": "Эта функция",
        "Local build directory (moving or cleaning it disables the menu)": "Локальный каталог сборки (перемещение или очистка отключает меню)",
        "Validate the branch, staging area and upstream, then confirm the push.": "Проверить ветку, индекс и вышестоящую ветку, затем подтвердить отправку.",
        "Validate the Flutter project, then fetch dependencies.": "Проверить текущий проект Flutter, затем получить зависимости.",
        "Installing / updating…": "Установка / обновление…",
        "This entry has been removed. Existing installations can be uninstalled but cannot be reinstalled.": "Этот пункт удалён. Существующую установку можно удалить, но повторная установка недоступна.",
        "No features require processing; ": "Нет функций для обработки; ",
        "No features require processing. No settings were changed.": "Нет функций для обработки. Настройки не изменены.",
        "Total cleanup time": "Общее время очистки",
        "Cleanup time": "Время очистки",
        "Click to read the full session log in a new PowerShell window. The current task continues.": "Нажмите, чтобы прочитать полный журнал этого сеанса в новом окне PowerShell. Текущая задача продолжит работу.",
        "Pending": "В ожидании",
        "Waiting to stop…": "Ожидание остановки…",
        "Ordered Flutter development, diagnostics, repair and maintenance tools. Regular actions use project FVM; environment setup supports FVM / system Flutter and jEnv / system Java.": "Меню разработки, диагностики, исправления и обслуживания Flutter в едином порядке. Обычные действия используют FVM проекта; настройка среды поддерживает FVM / системный Flutter и jEnv / системную Java.",
        "Detect the Flutter / Android project and preview cleanup scope. iOS cleanup is unavailable on Windows.": "Определить проект Flutter / Android и показать область очистки. Очистка iOS в Windows недоступна.",
        "Could not read preferences: ": "Не удалось прочитать настройки: ",
        "Could not read the log: ": "Не удалось прочитать журнал: ",
        "Explorer context-menu extensions · ": "Расширения контекстного меню Explorer · ",
        "Explorer extensions · Manage": "Расширения Explorer · Управление",
        "Return selection": "Вернуть выбранное",
        "Exit code: ": "Код завершения: ",
        "Choose an operation and select features. Unselected features remain; only installed features can be uninstalled.": "Выберите действие и одну или несколько функций. Невыбранные сохраняются; удаляются только установленные функции.",
        "Some features failed; other selected features were still processed. Click a failed status to open the full session log.": "Некоторые функции завершились ошибкой; остальные выбранные функции были обработаны. Нажмите на статус ошибки, чтобы открыть полный журнал сеанса.",
        "Available for nonempty regular directories outside iOS projects, including Flutter roots. Validated again before opening.": "Доступно для непустых обычных каталогов вне проектов iOS, включая корни Flutter. Перед открытием выполняется повторная проверка.",
        "Default installation location (recommended)": "Стандартное расположение установки (рекомендуется)",
        "{0}; Results: succeeded {1}; nothing to uninstall {2}; failed {3}; not run {4}": "{0}; результаты: успешно {1}; удаление не требуется {2}; ошибок {3}; не выполнено {4}",
        "{0} Exit code: {1}.": "{0} Код завершения: {1}.",
        "{0} {1}": "{0} {1}",
        "{0}{1} {2}": "{0}{1} {2}",
        "{0} in progress; completed {1} / {2} ({3}% by completed items); {4} {5}": "Выполняется {0}; завершено {1} из {2} ({3}% по завершённым пунктам); {4} {5}",
        "{0} Completed {1} / {2} ({3}% by completed items); {4} {5}": "{0} Завершено {1} из {2} ({3}% по завершённым пунктам); {4} {5}",
        "Close management panel": "Закрыть панель управления",
        "Run in the menu bar, or quit the installation / uninstallation panel?": "Продолжить работу в строке меню или полностью закрыть панель установки / удаления?",
        "Run in background": "Продолжить в фоне",
        "Quit completely": "Полностью выйти",
        "Show management panel": "Показать панель управления",
        "Status: {0}": "Состояние: {0}",
        "A task is running. You can quit after it finishes.": "Выполняется задача. Выйти можно после её завершения."
      },
      "ko": {
        "Update development environment (update)": "개발 환경 업데이트 (update)",
        "Total disk space": "전체 디스크 여유 공간",
        "Create script launcher": "스크립트 실행 파일 만들기",
        "Theme": "테마",
        "Language": "언어",
        "🎨 Theme": "🎨 테마",
        "🌐 Language": "🌐 언어",
        "Follow system": "시스템 설정 따름",
        "Dark": "어둡게",
        "Light": "밝게",
        "Jobs Finder Extension Manager": "Jobs Finder 확장 관리자",
        "Customize Finder Context Menu": "Finder 오른쪽 클릭 메뉴 사용자화",
        "Close Manager": "관리자 닫기",
        "Edit": "편집",
        "Copy": "복사",
        "Select all": "모두 선택",
        "Clear all": "모두 선택 해제",
        "Close": "닫기",
        "OK": "확인",
        "Install": "설치",
        "Install / Update": "설치 / 업데이트",
        "Uninstall": "제거",
        "Cleanup": "정리",
        "Clean build products": "빌드 결과물 정리",
        "🧹 Clean build products": "🧹 빌드 결과물 정리",
        "Stop installation": "설치 중지",
        "Stopping…": "중지 중…",
        "Action: install / update or uninstall": "작업: 설치 / 업데이트 또는 제거",
        "Uninstall removes selected menus only. Group selection affects its own group.": "선택한 메뉴만 제거합니다. 그룹 선택은 해당 그룹에만 적용됩니다.",
        "Install / uninstall with the combined App in Applications": "응용 프로그램의 통합 App으로 설치 / 제거",
        "Install or uninstall the combined App in Applications": "응용 프로그램의 통합 App 설치 또는 제거",
        "Selected: manage features in /Applications/Jobs自定义右键菜单.app. Otherwise use the build directory.": "선택하면 /Applications/Jobs自定义右键菜单.app의 기능을 관리합니다. 선택하지 않으면 빌드 디렉터리를 사용합니다.",
        "Clean this build after successful installation": "설치 성공 후 이번 빌드 정리",
        "Clean this build only after the combined App is installed and verified in Applications. Keep failed builds.": "통합 App을 응용 프로그램에 설치하고 검증한 뒤에만 이번 빌드를 정리합니다. 실패한 빌드는 유지합니다.",
        "Clean build products of selected features without installing or uninstalling.": "선택한 기능의 빌드 결과물만 정리합니다. 설치하거나 제거하지 않습니다.",
        "Clean selected features' build products": "선택한 기능의 빌드 결과물 정리",
        "Open Privacy & Security": "개인정보 보호 및 보안 열기",
        "Add and enable Jobs右键菜单管理面板.app in Privacy & Security → App Management. This only opens Settings.": "개인정보 보호 및 보안 → App 관리에서 Jobs右键菜单管理面板.app을 추가하고 활성화하세요. 이 버튼은 설정만 엽니다.",
        "Target: build directory. Cleaning these products affects installed features.": "대상: 빌드 디렉터리. 결과물을 정리하면 설치된 기능에 영향을 줍니다.",
        "App: Jobs自定义右键菜单.app at /Applications/Jobs自定义右键菜单.app (build products can be cleaned after installation)": "App: /Applications/Jobs自定义右键菜单.app (설치 후 빌드 결과물 정리 가능)",
        "Drag the divider to resize the log. Features and logs scroll separately.": "구분선을 위아래로 드래그해 로그 높이를 조절하세요. 기능과 로그는 각각 스크롤됩니다.",
        "Feature list and live log divider": "기능 목록과 실시간 로그 구분선",
        "Live log (select and copy text)": "실시간 로그 (텍스트 선택 및 복사 가능)",
        "Copy log": "로그 복사",
        "Log file": "로그 파일",
        "Auto-scroll": "자동 스크롤",
        "Ready. Select features and choose an action.": "준비되었습니다. 기능을 선택하고 작업 버튼을 누르세요.",
        "A task is running. Wait for it to finish before closing.": "작업이 실행 중입니다. 완료된 후 닫으세요.",
        "Unable to view this log": "이 로그를 볼 수 없습니다",
        "Log is missing or unreadable: {0}": "로그가 없거나 읽을 수 없습니다: {0}",
        "Unable to open log terminal: {0}": "로그 터미널을 열 수 없습니다: {0}",
        "Click to show this session's full log in a new terminal: {0}": "클릭하면 새 터미널에서 이번 세션의 전체 로그를 표시합니다: {0}",
        "Selected {0} / {1}. Select at least one. Changing action keeps selection.": "{0} / {1}개 선택됨. 하나 이상 선택하세요. 작업을 전환해도 선택은 유지됩니다.",
        "Selected {0} / {1}": "{0} / {1}개 선택됨",
        "{0}: select all": "{0}: 모두 선택",
        "{0}: clear all": "{0}: 모두 선택 해제",
        "Waiting": "대기 중",
        "Cleaning…": "정리 중…",
        "Uninstalling…": "제거 중…",
        "Installing…": "설치 중…",
        "Cleaned": "정리됨",
        "Uninstalled": "제거됨",
        "Installed": "설치됨",
        "Skipped": "실행 안 함",
        "Not installed; nothing to remove": "미설치: 제거할 항목 없음",
        "Failed: see log": "실패: 로그 확인",
        "Selected": "선택됨",
        "Not selected": "선택 안 됨",
        "App Management permission required": "App 관리 권한 필요",
        "Permission check required": "권한 확인 필요",
        "Stopped": "중지됨",
        "Completed": "완료",
        "Task failed": "작업 실패",
        "{0}: processed {1} / {2} ({3}, completed items); {4} time {5}": "{0}: 처리됨 {1} / {2} ({3}, 완료 항목 기준); {4} 시간 {5}",
        "{0} ready": "{0} 준비됨",
        "{0} ready; {1} time {2}": "{0} 준비됨; {1} 시간 {2}",
        "Finishing the current feature, then stopping; install time {0}": "현재 기능을 완료한 후 중지합니다; 설치 시간 {0}",
        "{0}: {1} succeeded, {2} failed, {3} skipped; exit {4}; {5}; {6} time {7}": "{0}: 성공 {1}, 실패 {2}, 실행 안 함 {3}; 종료 {4}; {5}; {6} 시간 {7}",
        "{0}: {1} succeeded, {2} failed, {3} not installed, {4} skipped; exit {5}; {6}; {7} time {8}": "{0}: 성공 {1}, 실패 {2}, 제거 불필요 {3}, 실행 안 함 {4}; 종료 {5}; {6}; {7} 시간 {8}",
        "{0}: {1} succeeded, {2} failed, {3} not installed; exit {4}; {5}; {6} time {7}": "{0}: 성공 {1}, 실패 {2}, 제거 불필요 {3}; 종료 {4}; {5}; {6} 시간 {7}",
        "{0}: {1} succeeded, {2} failed; exit {3}; {4}; {5} time {6}": "{0}: 성공 {1}, 실패 {2}; 종료 {3}; {4}; {5} 시간 {6}",
        "Open projects in IDEs": "IDE에서 프로젝트 열기",
        "Git tools": "Git 도구",
        "Files and general tools": "파일 및 일반 도구",
        "Flutter tools · submenu actions": "Flutter 도구 · 하위 메뉴 작업",
        "iOS / CocoaPods tools": "iOS / CocoaPods 도구",
        "Simulator tools": "시뮬레이터 도구",
        "Open project in Android Studio": "Android Studio에서 프로젝트 열기",
        "Open project in VSCode": "VSCode에서 프로젝트 열기",
        "Open project in Xcode": "Xcode에서 프로젝트 열기",
        "Pull latest Git changes": "최신 Git 변경 사항 가져오기",
        "Roll back Git commit": "Git 커밋 되돌리기",
        "Open Git remote URL": "Git 원격 URL 열기",
        "Copy Git remote URL": "Git 원격 URL 복사",
        "Copy absolute path": "절대 경로 복사",
        "Create file": "파일 만들기",
        "View file fingerprint Hash (SHA-256)": "파일 해시 보기 (SHA-256)",
        "Hide / show selected items": "선택한 항목 숨기기 / 표시",
        "Send to external disk or network volume": "외장 디스크 또는 네트워크 볼륨으로 보내기",
        "Grant execute permission (chmod +x)": "실행 권한 부여 (chmod +x)",
        "Remove execute permission (chmod -x)": "실행 권한 제거 (chmod -x)",
        "Re-sign IPA without building": "빌드 없이 IPA 다시 서명",
        "Show / hide files": "파일 표시 / 숨기기",
        "Create iOS simulator": "iOS 시뮬레이터 만들기",
        "Create Android simulator": "Android 시뮬레이터 만들기",
        "Create Harmony simulator": "Harmony 시뮬레이터 만들기",
        "Check / repair Android simulator": "Android 시뮬레이터 진단 / 복구",
        "Check / repair Harmony simulator": "Harmony 시뮬레이터 진단 / 복구",
        "Configure Git proxy": "Git 프록시 설정",
        "Open in terminal": "터미널에서 열기",
        "View file contents in terminal": "터미널에서 파일 내용 보기",
        "Merge file parts": "분할 파일 합치기",
        "Split file": "파일 분할",
        "Clean Android / OpenHarmony builds": "Android / OpenHarmony 빌드 정리",
        "Update code map (.codegraph)": "코드 맵 업데이트 (.codegraph)",
        "Create empty commit and push in terminal": "터미널에서 빈 커밋을 만들고 Push",
        "Disable CocoaPods build sandbox": "CocoaPods 빌드 샌드박스 비활성화",
        "Install CocoaPods": "CocoaPods 설치",
        "CocoaPods source: CDN → GitHub": "CocoaPods 소스: CDN → GitHub",
        "Export all project Pod files": "프로젝트의 모든 Pod 파일 내보내기",
        "Inspect Xcode project dependencies": "Xcode 프로젝트 의존성 확인",
        "Update local CocoaPods repositories": "로컬 CocoaPods 저장소 업데이트",
        "Check local Pod builds (.podspec folder)": "로컬 Pod 빌드 확인 (.podspec 폴더)",
        "Install / update JobsCodeSnippets": "JobsCodeSnippets 설치 / 업데이트",
        "Clean iOS / Xcode builds": "iOS / Xcode 빌드 정리",
        "Set up Flutter project": "Flutter 프로젝트 설정",
        "Run Flutter project in terminal": "터미널에서 Flutter 프로젝트 실행",
        "Fetch Flutter Pub dependencies": "Flutter Pub 의존성 가져오기",
        "Fetch native Android dependencies": "Android 네이티브 의존성 가져오기",
        "Fetch CocoaPods dependencies": "CocoaPods 의존성 가져오기",
        "Fetch Swift Package dependencies": "Swift Package 의존성 가져오기",
        "Fetch OpenHarmony dependencies": "OpenHarmony 의존성 가져오기",
        "Prepare native libraries and build dependencies": "네이티브 라이브러리와 빌드 의존성 준비",
        "Download Flutter platform resources": "Flutter 플랫폼 리소스 다운로드",
        "Fetch Web project dependencies": "Web 프로젝트 의존성 가져오기",
        "🧳 Export Flutter dependencies": "🧳 Flutter 의존성 내보내기",
        "Export Flutter Pub dependencies": "Flutter Pub 의존성 내보내기",
        "🔐 Export private Flutter dependencies": "🔐 Flutter 비공개 의존성 내보내기",
        "📥 Import Flutter dependencies": "📥 Flutter 의존성 가져오기",
        "Import Flutter Pub dependencies": "Flutter Pub 의존성 가져오기",
        "📥 Import private Flutter dependencies": "📥 Flutter 비공개 의존성 가져오기",
        "Export Gradle distributions and cache": "Gradle 배포 파일과 캐시 내보내기",
        "Import Gradle distributions and cache": "Gradle 배포 파일과 캐시 가져오기",
        "Export CocoaPods dependencies": "CocoaPods 의존성 내보내기",
        "Import CocoaPods dependencies": "CocoaPods 의존성 가져오기",
        "Export Swift Package dependencies": "Swift Package 의존성 내보내기",
        "Import Swift Package dependencies": "Swift Package 의존성 가져오기",
        "Export OpenHarmony dependencies": "OpenHarmony 의존성 내보내기",
        "Import OpenHarmony dependencies": "OpenHarmony 의존성 가져오기",
        "Export native build cache": "네이티브 빌드 캐시 내보내기",
        "Import native build cache": "네이티브 빌드 캐시 가져오기",
        "Export Flutter platform resources": "Flutter 플랫폼 리소스 내보내기",
        "Import Flutter platform resources": "Flutter 플랫폼 리소스 가져오기",
        "Export Web dependencies": "Web 의존성 내보내기",
        "Import Web dependencies": "Web 의존성 가져오기",
        "Show Flutter project SDK version": "Flutter 프로젝트 SDK 버전 보기",
        "Install / switch Flutter SDK": "Flutter SDK 설치 / 전환",
        "Install / switch Flutter@OpenHarmony SDK": "Flutter@OpenHarmony SDK 설치 / 전환",
        "Install / switch Java SDK": "Java SDK 설치 / 전환",
        "Download Gradle distributions and plugins": "Gradle 배포 파일과 플러그인 다운로드",
        "Generate Flutter code": "Flutter 코드 생성",
        "Package iOS": "iOS 패키징",
        "Package Android": "Android 패키징",
        "Package Harmony (HAP + APP)": "Harmony 패키징 (HAP + APP)",
        "Check native Flutter project": "네이티브 Flutter 프로젝트 진단",
        "Check OpenHarmony Flutter environment": "OpenHarmony Flutter 환경 진단",
        "Repair missing Android SDK / platforms": "누락된 Android SDK / platforms 복구",
        "Repair Chinese Flutter project paths": "Flutter 프로젝트 중국어 경로 복구",
        "Repair Flutter plugin namespaces": "Flutter 플러그인 namespace 복구",
        "Convert relative Dart imports to packages": "Dart 상대 import를 package 참조로 변환",
        "Clean current Flutter project builds": "현재 Flutter 프로젝트 빌드 정리",
        "Dependency and cache maintenance": "의존성 및 캐시 유지 관리",
        "Custom Explorer context menu": "Explorer 오른쪽 클릭 메뉴 사용자화",
        "Jobs Windows · Custom Explorer context menu": "Jobs Windows · Explorer 오른쪽 클릭 메뉴 사용자화",
        "Show a regular file's SHA-256 in a new terminal and copy the digest; do not modify or execute the file.": "새 터미널에서 일반 파일의 SHA-256을 표시하고 해시를 복사합니다. 파일을 수정하거나 실행하지 않습니다.",
        " (preview)": " (미리 보기)",
        "⏪ Roll back Git commits": "⏪ Git 커밋 되돌리기",
        "▶️ Run Flutter project in terminal": "▶️ 터미널에서 Flutter 프로젝트 실행",
        "☕ Install / switch Java SDK": "☕ Java SDK 설치 / 전환",
        "♻️ Flutter cleanup and maintenance": "♻️ Flutter 정리 및 유지 관리",
        "⚙️ Generate Flutter code": "⚙️ Flutter 코드 생성",
        "✅ Installed": "✅ 설치됨",
        "⬇️ Pull latest Git changes": "⬇️ 최신 Git 변경 사항 가져오기",
        "🌈 Create Harmony emulator": "🌈 Harmony 에뮬레이터 만들기",
        "🌐 Open Git remote URL": "🌐 Git 원격 URL 열기",
        "🌐 Fetch Web project dependencies": "🌐 Web 프로젝트 의존성 가져오기",
        "🌳 Open in Sourcetree": "🌳 Sourcetree에서 열기",
        "🏥 Flutter project diagnostics": "🏥 Flutter 프로젝트 진단",
        "🏥 Flutter diagnostics": "🏥 Flutter 진단",
        "🏷️ Repair Flutter plugin namespaces": "🏷️ Flutter 플러그인 namespace 복구",
        "👁️ Show / hide hidden files": "👁️ 숨김 파일 표시 / 숨기기",
        "💓 OpenHarmony Flutter diagnostics": "💓 OpenHarmony Flutter 환경 진단",
        "💠 Open project in Visual Studio": "💠 Visual Studio에서 프로젝트 열기",
        "💻 Open in terminal": "💻 터미널에서 열기",
        "📄 View file in terminal": "📄 터미널에서 파일 보기",
        "📋 Copy absolute path": "📋 절대 경로 복사",
        "📚 Download Gradle distributions and build plugins": "📚 Gradle 배포 파일과 빌드 플러그인 다운로드",
        "📝 Open project in VSCode": "📝 VSCode에서 프로젝트 열기",
        "📡 Configure Git dynamic proxy": "📡 Git 동적 프록시 설정",
        "📤 Import Flutter Pub dependencies": "📤 Flutter Pub 의존성 가져오기",
        "📤 Import Flutter platform assets": "📤 Flutter 플랫폼 에셋 가져오기",
        "📤 Import Gradle distributions and dependency caches": "📤 Gradle 배포 파일과 의존성 캐시 가져오기",
        "📤 Import OpenHarmony dependencies": "📤 OpenHarmony 의존성 가져오기",
        "📤 Import Web dependencies": "📤 Web 의존성 가져오기",
        "📤 Import native build caches": "📤 네이티브 빌드 캐시 가져오기",
        "📤 Import Flutter project dependencies": "📤 Flutter 프로젝트 의존성 가져오기",
        "📤 Create empty commit and push": "📤 빈 커밋을 만들고 Push",
        "📥 Install Flutter dependencies (pub get)": "📥 Flutter 의존성 설치 (pub get)",
        "📥 Import private Flutter project dependencies": "📥 Flutter 프로젝트 비공개 의존성 가져오기",
        "📥 Fetch Flutter Pub dependencies": "📥 Flutter Pub 의존성 가져오기",
        "📥 Fetch Flutter project dependencies": "📥 Flutter 프로젝트 의존성 가져오기",
        "📦 Package Flutter project": "📦 Flutter 프로젝트 패키징",
        "📦 Package HarmonyOS (HAP + APP)": "📦 HarmonyOS 패키징 (HAP + APP)",
        "📱 Create Android emulator": "📱 Android 에뮬레이터 만들기",
        "🔀 Install / switch Flutter SDK (FVM)": "🔀 Flutter SDK 설치 / 전환 (FVM)",
        "🔀 Install / switch Flutter SDK": "🔀 Flutter SDK 설치 / 전환",
        "🔀 Install / switch Flutter environments": "🔀 Flutter 실행 환경 설치 / 전환",
        "🔎 Show current Flutter SDK version": "🔎 현재 Flutter SDK 버전 보기",
        "🔎 Show current Flutter project's SDK version": "🔎 현재 Flutter 프로젝트 SDK 버전 보기",
        "🔐 Export private Flutter project dependencies": "🔐 Flutter 프로젝트 비공개 의존성 내보내기",
        "🔎 Show file fingerprint Hash (SHA-256)": "🔎 파일 해시 보기 (SHA-256)",
        "➕ Grant execute permission": "➕ 실행 권한 부여",
        "➖ Remove execute permission": "➖ 실행 권한 제거",
        "🔒 Grant execute permission": "🔒 실행 권한 부여",
        "🔓 Remove execute permission": "🔓 실행 권한 제거",
        "🔗 Copy Git remote URL": "🔗 Git 원격 URL 복사",
        "🔧 Flutter repairs": "🔧 Flutter 복구",
        "🕊️ Install / switch Flutter@OpenHarmony SDK": "🕊️ Flutter@OpenHarmony SDK 설치 / 전환",
        "🕊️ Fetch OpenHarmony dependencies": "🕊️ OpenHarmony 의존성 가져오기",
        "🗃️ Download Flutter platform assets": "🗃️ Flutter 플랫폼 에셋 다운로드",
        "🗺️ Update code map (.codegraph)": "🗺️ 코드 맵 업데이트 (.codegraph)",
        "🤖 Fetch Android native dependencies": "🤖 Android 네이티브 의존성 가져오기",
        "🦋 Flutter development": "🦋 Flutter 개발",
        "🦋 Flutter development tools": "🦋 Flutter 개발 도구",
        "🧑‍⚕️ Native Flutter diagnostics": "🧑‍⚕️ 네이티브 Flutter 진단",
        "🧩 Export Flutter Pub dependencies": "🧩 Flutter Pub 의존성 내보내기",
        "🧩 Export Flutter platform assets": "🧩 Flutter 플랫폼 에셋 내보내기",
        "🧩 Export Flutter third-party dependencies": "🧩 Flutter 서드 파티 의존성 내보내기",
        "🧩 Export Gradle distributions and dependency caches": "🧩 Gradle 배포 파일과 의존성 캐시 내보내기",
        "🧩 Export OpenHarmony dependencies": "🧩 OpenHarmony 의존성 내보내기",
        "🧩 Export Web dependencies": "🧩 Web 의존성 내보내기",
        "🧩 Export native build caches": "🧩 네이티브 빌드 캐시 내보내기",
        "🧩 Export Flutter project dependencies": "🧩 Flutter 프로젝트 의존성 내보내기",
        "🧩 Merge file volumes / ✂️ Split file": "🧩 분할 파일 합치기 / ✂️ 파일 분할",
        "🧭 Open project in Android Studio": "🧭 Android Studio에서 프로젝트 열기",
        "🧯 Clean build output": "🧯 빌드 출력 정리",
        "🧰 Diagnose and repair Harmony emulator": "🧰 Harmony 에뮬레이터 진단 및 복구",
        "🧱 Flutter assets and build dependencies": "🧱 Flutter 에셋 및 빌드 의존성",
        "🧱 Prepare native libraries and build dependencies (combined)": "🧱 네이티브 라이브러리와 빌드 의존성 준비 (통합)",
        "🧹 Clean build output": "🧹 빌드 출력 정리",
        "🩹 Repair missing Android SDK / platforms": "🩹 누락된 Android SDK / platforms 복구",
        "🩺 Diagnose and repair Android emulator": "🩺 Android 에뮬레이터 진단 및 복구",
        "🚀 Set up Flutter project": "🚀 Flutter 프로젝트 설정",
        "🚚 Import all Flutter dependencies": "🚚 모든 Flutter 의존성 가져오기",
        "🚚 Export all Flutter dependencies": "🚚 모든 Flutter 의존성 내보내기",
        "Jobs Windows · Uninstall Explorer extensions": "Jobs Windows · Explorer 확장 제거",
        "Jobs Windows · Install Explorer extensions": "Jobs Windows · Explorer 확장 설치",
        "Jobs Windows · Manage Explorer extensions": "Jobs Windows · Explorer 확장 관리",
        "Jobs Windows · Configure Explorer extensions": "Jobs Windows · Explorer 확장 설정",
        "Drag the divider vertically to resize the log": "구분선을 위아래로 드래그해 로그 높이 조절",
        "Drag vertically to resize the log": "위아래로 드래그해 로그 높이 조절",
        "Validate the Flutter project, diagnose the toolchain in terminal, and choose a Flutter SDK version with fzf.": "Flutter 프로젝트를 검증하고 터미널에서 도구 체인을 진단한 뒤 fzf로 Flutter SDK 버전을 선택합니다.",
        "Validate the Flutter project, then show the active SDK version (project FVM or system SDK) in terminal and compare it with .fvmrc and pubspec constraints.": "Flutter 프로젝트를 검증하고 실제 사용 중인 SDK 버전(프로젝트 FVM 또는 시스템 SDK)을 터미널에서 읽기 전용으로 표시한 뒤 .fvmrc 및 pubspec 제약과 비교합니다.",
        "Flutter roots only. Choose Android / iOS / HarmonyOS with fzf in CMD. Supports APK / AAB and HAP / APP. iOS requires MacOS and Xcode.": "Flutter 루트에만 표시됩니다. CMD의 fzf로 Android / iOS / HarmonyOS를 선택합니다. APK / AAB 및 HAP / APP을 지원하며 iOS에는 MacOS와 Xcode가 필요합니다.",
        "Flutter roots only. Choose a device and view logs in CMD; the app continues in the background after the window closes.": "Flutter 루트에만 표시됩니다. CMD에서 기기를 선택하고 로그를 확인합니다. 창을 닫아도 앱은 백그라운드에서 계속 실행됩니다.",
        "Flutter roots only. Read-only version and doctor diagnostics in terminal; no dependency fetching, cleanup, or tool upgrades.": "Flutter 루트에만 표시됩니다. 터미널에서 버전 및 doctor 진단만 읽기 전용으로 실행합니다. 의존성 가져오기, 정리 또는 도구 업그레이드는 수행하지 않습니다.",
        "Flutter roots only. Preview configured generators, then fetch dependencies and generate code after confirmation. Deleting conflicts requires separate opt-in.": "Flutter 루트에만 표시됩니다. 설정된 생성기를 미리 본 뒤 확인하면 의존성을 가져오고 코드를 생성합니다. 충돌 파일 삭제는 별도의 명시적 동의가 필요합니다.",
        "Git worktree folders only. Detect nested repositories. Soft mode preserves the index and worktree; hard mode requires exact YES confirmation.": "Git 작업 트리 폴더에만 표시됩니다. 중첩 저장소를 인식합니다. soft는 인덱스와 작업 내용을 유지하고 hard는 정확한 YES 확인이 필요합니다.",
        "Desktop background on x64 Windows only. Missing tools come from the SDL mirror; missing system images come from the official Emulator. Enter selects a stable phone image; confirm its license to create and start a unique instance.": "x64 Windows 바탕 화면 배경에만 표시됩니다. 누락 도구는 SDL 미러에서, 시스템 이미지는 공식 Emulator에서 가져옵니다. Enter로 안정 버전 휴대전화 이미지를 선택하고 라이선스를 확인한 후 고유 인스턴스를 만들고 실행합니다.",
        "Manage only this package's actions. Unselected actions remain when uninstalling.": "이 패키지의 작업만 관리합니다. 제거할 때 선택하지 않은 작업은 유지합니다.",
        "Desktop background only. Configure user-level Git to prefer the system proxy and fall back to a direct connection.": "바탕 화면 배경에만 표시됩니다. 사용자 수준 Git이 시스템 프록시를 우선 사용하고 실패하면 직접 연결로 전환하도록 설정합니다.",
        "Desktop background only. Diagnose the SDK in CMD, choose a device and system image, then create or start an Android AVD.": "바탕 화면 배경에만 표시됩니다. CMD에서 SDK를 진단하고 기종과 시스템 이미지를 선택하여 Android AVD를 만들거나 실행합니다.",
        "Desktop background only. Check existing DevEco Emulator instances, then start one or confirm a nondestructive restart. Data is preserved.": "바탕 화면 배경에만 표시됩니다. 기존 DevEco Emulator와 인스턴스를 확인한 뒤 선택한 항목을 실행하거나 확인 후 데이터를 유지하며 다시 시작합니다.",
        "Desktop background only. Check emulator location and /data; optionally reset caches, precisely uninstall, back up the AVD, and retest with a cold boot.": "바탕 화면 배경에만 표시됩니다. 에뮬레이터 위치와 /data를 확인합니다. 필요하면 캐시 초기화, 정확한 제거, 전체 AVD 백업 및 콜드 부팅 재검사를 수행할 수 있습니다.",
        "Show the next action on the desktop background. Toggle hidden files for the current user's Explorer without changing protected-system-file settings.": "바탕 화면 배경에 다음 작업을 표시합니다. 현재 사용자의 Explorer 숨김 파일 표시를 전환하며 보호된 시스템 파일 설정은 변경하지 않습니다.",
        "Visible only for nonempty native Android or valid Flutter (official / HarmonyOS) project roots. Validated again before opening.": "비어 있지 않은 네이티브 Android 또는 유효한 Flutter(공식 / HarmonyOS) 프로젝트 루트에만 표시되며 열기 전에 다시 검증합니다.",
        "Preview: the selection is shown in the log. No installation or uninstallation was performed.": "미리 보기 전용: 선택 내용이 로그에 표시되었습니다. 설치하거나 제거하지 않았습니다.",
        "Preview only. Confirming displays the selection in the log without installing, uninstalling, or writing state or registry entries.": "기능 선택 미리 보기 전용입니다. 확인하면 아래 로그에 선택 내용만 표시하며 설치, 제거, 상태 또는 레지스트리 쓰기는 수행하지 않습니다.",
        "Deployed copies use their bound location. To change it, open the manager from the source directory. Default installations run in the current user's LocalAppData; local builds run under this package's work directory and stop working if it moves.": "배포된 복사본은 현재 연결된 위치를 사용합니다. 위치를 바꾸려면 소스 디렉터리에서 관리자를 여세요. 기본 설치는 현재 사용자의 LocalAppData에서 독립 실행되며 로컬 빌드는 이 패키지의 work에서 실행되어 경로를 옮기면 작동하지 않습니다.",
        "Prefer Windows Terminal; otherwise use system PowerShell.": "Windows Terminal을 우선 사용하고 없으면 시스템 PowerShell을 사용합니다.",
        "Could not save preferences: ": "설정을 저장할 수 없습니다: ",
        "Save settings": "설정 저장",
        "Protect local changes. On conflict, choose to restore, discard changes, or commit and retry.": "로컬 변경을 보호합니다. 충돌하면 복원, 변경 취소 또는 커밋 후 다시 시도를 선택하세요.",
        "All operations completed. Copy the log or close the panel.": "모든 작업이 완료되었습니다. 로그를 복사하거나 패널을 닫으세요.",
        "Other context-menu features": "기타 오른쪽 클릭 메뉴 기능",
        "Create or synchronize the code map for the current directory.": "현재 디렉터리의 코드 맵을 생성하거나 동기화합니다.",
        "Feature and log divider": "기능 및 로그 구분선",
        "Select features, then confirm. Unselected features remain. Hover for installation details.": "기능을 선택하고 확인하세요. 선택하지 않은 기능은 유지됩니다. 마우스를 올리면 설치 상태를 볼 수 있습니다.",
        "Checked features are installed; unchecked ones are uninstalled. Saving an empty selection disables all installed features.": "선택한 기능은 설치하고 선택 해제한 기능은 제거합니다. 모두 선택 해제한 상태로 저장하면 설치된 모든 기능이 비활성화됩니다.",
        "Select features to install. Enabled sibling actions and other unselected features remain.": "설치할 기능을 선택하세요. 활성화된 같은 패키지의 다른 작업과 선택하지 않은 기능은 유지됩니다.",
        "Total uninstall time": "총 제거 시간",
        "Uninstall selected": "선택 항목 제거",
        "Uninstall selected features": "선택한 기능 제거",
        "Uninstall time": "제거 시간",
        "Cancel": "취소",
        "Uninstall only selected installed features. Other features, logs, backups and tools remain.": "선택한 설치된 기능만 제거합니다. 다른 기능, 로그, 백업 및 도구는 유지합니다.",
        "Change only the current user's ExecuteFile ACL for a single regular NTFS file after confirmation. Does not launch the file or change global policy.": "확인 후 일반 NTFS 파일 하나의 현재 사용자 ExecuteFile ACL만 변경합니다. 파일을 실행하거나 전역 정책을 변경하지 않습니다.",
        "View a single regular file. Files over 1 MiB or suspected binary files require YES in the terminal.": "일반 파일 하나만 표시합니다. 1 MiB를 넘거나 바이너리로 의심되면 터미널에 YES를 입력해야 합니다.",
        "Clean only the selected packages' build workspaces. Installed DLLs, scripts, settings and registry entries remain.": "선택한 패키지의 전용 빌드 작업 영역만 정리합니다. 설치된 DLL, 스크립트, 설정 및 레지스트리 항목은 유지합니다.",
        "Copy full log": "전체 로그 복사",
        "Copy the original remote URL for the current branch.": "현재 브랜치의 원래 원격 URL을 복사합니다.",
        "Copy the absolute path of a file or folder.": "파일 또는 폴더의 절대 경로를 복사합니다.",
        "Could not copy the log: ": "로그를 복사할 수 없습니다: ",
        "Failed — open log": "실패 — 로그 열기",
        "Install / update": "설치 / 업데이트",
        "Install / update selected features": "선택한 기능 설치 / 업데이트",
        "Total install time": "총 설치 시간",
        "Install time": "설치 시간",
        "Merge appears for a complete selected volume set; split appears for one regular file. Originals are always preserved.": "같은 그룹의 모든 분할 파일을 선택하면 합치기를 표시하고 일반 파일 하나를 선택하면 분할을 표시합니다. 원본은 항상 유지합니다.",
        "Live log (drag the divider to resize)": "실시간 로그 (위 구분선을 드래그해 높이 조절)",
        "Installation stopped after the current package transaction. Unstarted items are marked Not run.": "현재 패키지 트랜잭션이 끝난 뒤 설치가 중지되었습니다. 시작하지 않은 항목은 실행 안 함으로 표시됩니다.",
        "Stop requested. Waiting for the current package transaction; later items will not run.": "중지를 요청했습니다. 현재 패키지 트랜잭션이 끝나기를 기다리고 있으며 이후 항목은 실행하지 않습니다.",
        "Selected {0} / {1}. Closing or cancelling makes no changes.": "{0} / {1}개 선택됨. 닫거나 취소하면 변경하지 않습니다.",
        "Hover for feature details. Windows 11: right-click → Show more options.": "마우스를 올리면 기능 설명이 표시됩니다. Windows 11: 오른쪽 클릭 → 더 많은 옵션 표시.",
        "Could not open the full log: ": "전체 로그를 열 수 없습니다: ",
        "Open the repository website for the current Git worktree.": "현재 Git 작업 트리의 저장소 웹사이트를 엽니다.",
        "Open the solution or project at the current directory level.": "현재 디렉터리 수준의 솔루션이나 프로젝트를 엽니다.",
        "Export resolved third-party Pub sources and licenses from the project lockfile. Press Enter to use the desktop as output.": "프로젝트 잠금 파일에 따라 확인된 서드 파티 Pub 소스와 라이선스를 내보냅니다. 출력 위치에서 Enter를 누르면 바탕 화면을 사용합니다.",
        "An operation is running. Wait for the transaction to finish before closing. Logs can be copied at any time.": "작업이 실행 중입니다. 트랜잭션이 끝난 후 닫으세요. 로그는 언제든 복사할 수 있습니다.",
        "Could not build the operation plan: ": "작업 계획을 만들 수 없습니다: ",
        "Could not start the operation: ": "작업을 시작할 수 없습니다: ",
        "Log: ": "로그: ",
        "🈶 Repair Chinese paths in Flutter project": "🈶 Flutter 프로젝트 중국어 경로 복구",
        "Not installed; nothing to uninstall": "미설치: 제거할 항목 없음",
        "Not installed": "설치되지 않음",
        "Not run": "실행 안 함",
        "This feature": "이 기능",
        "Local build directory (moving or cleaning it disables the menu)": "로컬 빌드 디렉터리 (이동하거나 정리하면 메뉴 비활성화)",
        "Validate the branch, staging area and upstream, then confirm the push.": "브랜치, 스테이징 영역 및 업스트림을 검증한 뒤 Push를 확인합니다.",
        "Validate the Flutter project, then fetch dependencies.": "Flutter 프로젝트를 검증한 후 의존성을 가져옵니다.",
        "Installing / updating…": "설치 / 업데이트 중…",
        "This entry has been removed. Existing installations can be uninstalled but cannot be reinstalled.": "이 항목은 삭제되었습니다. 기존 설치 항목은 제거할 수 있지만 다시 설치할 수는 없습니다.",
        "No features require processing; ": "처리할 기능이 없습니다; ",
        "No features require processing. No settings were changed.": "처리할 기능이 없습니다. 설정을 변경하지 않았습니다.",
        "Total cleanup time": "총 정리 시간",
        "Cleanup time": "정리 시간",
        "Click to read the full session log in a new PowerShell window. The current task continues.": "클릭하면 새 PowerShell 창에서 이번 전체 세션 로그를 표시합니다. 현재 작업은 계속 실행됩니다.",
        "Pending": "대기 중",
        "Waiting to stop…": "중지 대기 중…",
        "Ordered Flutter development, diagnostics, repair and maintenance tools. Regular actions use project FVM; environment setup supports FVM / system Flutter and jEnv / system Java.": "Flutter 개발, 진단, 복구 및 유지 관리 도구를 정해진 순서로 표시합니다. 일반 작업에는 프로젝트 FVM을 사용하며 환경 설정에는 FVM / 시스템 Flutter 및 jEnv / 시스템 Java를 지원합니다.",
        "Detect the Flutter / Android project and preview cleanup scope. iOS cleanup is unavailable on Windows.": "Flutter / Android 프로젝트를 감지하고 정리 범위를 미리 봅니다. Windows에서는 iOS 정리를 사용할 수 없습니다.",
        "Could not read preferences: ": "설정을 읽을 수 없습니다: ",
        "Could not read the log: ": "로그를 읽을 수 없습니다: ",
        "Explorer context-menu extensions · ": "Explorer 오른쪽 클릭 메뉴 확장 · ",
        "Explorer extensions · Manage": "Explorer 확장 · 관리",
        "Return selection": "선택 내용 반환",
        "Exit code: ": "종료 코드: ",
        "Choose an operation and select features. Unselected features remain; only installed features can be uninstalled.": "작업을 고르고 기능을 선택하세요. 선택하지 않은 기능은 유지됩니다. 설치된 기능만 제거할 수 있습니다.",
        "Some features failed; other selected features were still processed. Click a failed status to open the full session log.": "일부 기능이 실패했지만 선택한 다른 기능은 계속 처리했습니다. 실패 상태를 클릭하면 전체 세션 로그를 볼 수 있습니다.",
        "Available for nonempty regular directories outside iOS projects, including Flutter roots. Validated again before opening.": "iOS 프로젝트가 아닌 비어 있지 않은 일반 디렉터리에서 사용할 수 있습니다. Flutter 루트를 지원하며 열기 전에 다시 검증합니다.",
        "Default installation location (recommended)": "기본 설치 위치 (권장)",
        "{0}; Results: succeeded {1}; nothing to uninstall {2}; failed {3}; not run {4}": "{0}; 결과: 성공 {1}; 제거 불필요 {2}; 실패 {3}; 실행 안 함 {4}",
        "{0} Exit code: {1}.": "{0} 종료 코드: {1}.",
        "{0} {1}": "{0} {1}",
        "{0}{1} {2}": "{0}{1} {2}",
        "{0} in progress; completed {1} / {2} ({3}% by completed items); {4} {5}": "{0} 진행 중; 완료 {1} / {2} ({3}%, 완료 항목 기준); {4} {5}",
        "{0} Completed {1} / {2} ({3}% by completed items); {4} {5}": "{0} 완료 {1} / {2} ({3}%, 완료 항목 기준); {4} {5}",
        "Close management panel": "관리 패널 닫기",
        "Run in the menu bar, or quit the installation / uninstallation panel?": "메뉴 막대에서 계속 실행할까요, 아니면 설치 / 제거 패널을 완전히 종료할까요?",
        "Run in background": "백그라운드에서 실행",
        "Quit completely": "완전히 종료",
        "Show management panel": "관리 패널 표시",
        "Status: {0}": "상태: {0}",
        "A task is running. You can quit after it finishes.": "작업이 실행 중입니다. 완료된 후 완전히 종료할 수 있습니다."
      }
    }
    """#
    // JOBS_MANAGER_TRANSLATIONS_END

    private static let translationTable = """
    主题|Theme
    语言|Language
    🎨 主题|🎨 Theme
    🌐 语言|🌐 Language
    跟随系统|Follow system
    黑夜|Dark
    白天|Light
    Jobs Finder 扩展管理|Jobs Finder Extension Manager
    自定义Finder右键菜单|Customize Finder Context Menu
    关闭管理器|Close Manager
    关闭管理面板|Close management panel
    退到系统状态栏，还是完全退出安装／卸载面板？|Run in the menu bar, or quit the installation / uninstallation panel?
    退到后台|Run in background
    完全退出|Quit completely
    显示管理面板|Show management panel
    状态：{0}|Status: {0}
    任务进行中，完成后可完全退出。|A task is running. You can quit after it finishes.
    取消|Cancel
    编辑|Edit
    复制|Copy
    全选|Select all
    全不选|Clear all
    关闭|Close
    确定|OK
    安装|Install
    安装 / 更新|Install / Update
    卸载|Uninstall
    清理|Cleanup
    清除构建产物|Clean build products
    🧹 清除构建产物|🧹 Clean build products
    停止安装|Stop installation
    停止中…|Stopping…
    操作：安装 / 更新或卸载|Action: install / update or uninstall
    卸载仅移除所选菜单，其它功能保留；组内选择只影响本组。|Uninstall removes selected menus only. Group selection affects its own group.
    使用「应用程序」中的联合 App 安装 / 卸载|Install / uninstall with the combined App in Applications
    使用应用程序中的联合 App 安装或卸载|Install or uninstall the combined App in Applications
    勾选：在 /Applications/Jobs自定义右键菜单.app 中统一管理所选功能；未勾选：沿用当前构建目录。|Selected: manage features in /Applications/Jobs自定义右键菜单.app. Otherwise use the build directory.
    安装成功后清除此轮构建产物|Clean this build after successful installation
    仅在联合 App 成功安装到「应用程序」并完成核验后清除此轮构建产物；安装失败不清理。|Clean this build only after the combined App is installed and verified in Applications. Keep failed builds.
    只清理当前勾选功能的构建产物，不执行安装或卸载。|Clean build products of selected features without installing or uninstalling.
    清除所选功能的构建产物|Clean selected features' build products
    打开隐私与安全性设置|Open Privacy & Security
    在“隐私与安全性 → App 管理”中添加并启用 Jobs右键菜单管理面板.app；此按钮只打开设置。|Add and enable Jobs右键菜单管理面板.app in Privacy & Security → App Management. This only opens Settings.
    当前目标：构建目录（原有方式；清理构建产物会影响功能）。|Target: build directory. Cleaning these products affects installed features.
    联合 App：Jobs自定义右键菜单.app；位置：/Applications/Jobs自定义右键菜单.app（安装成功后可清理构建产物）|App: Jobs自定义右键菜单.app at /Applications/Jobs自定义右键菜单.app (build products can be cleaned after installation)
    上下拖动分隔条调整日志高度；功能列表和日志可分别滚动。|Drag the divider to resize the log. Features and logs scroll separately.
    功能列表与实时日志高度分隔条|Feature list and live log divider
    实时日志（可选择文字并复制）|Live log (select and copy text)
    复制日志|Copy log
    日志文件|Log file
    自动滚动|Auto-scroll
    就绪；选择功能后点击操作按钮。|Ready. Select features and choose an action.
    任务仍在执行，请等待结束后关闭，避免中断安装。|A task is running. Wait for it to finish before closing.
    无法查看本次日志|Unable to view this log
    日志不存在或不可读：{0}|Log is missing or unreadable: {0}
    无法打开日志终端：{0}|Unable to open log terminal: {0}
    点击在新终端显示本次完整日志：{0}|Click to show this session's full log in a new terminal: {0}
    已选 {0} / {1} 项；空选不能执行，切换操作保留勾选。|Selected {0} / {1}. Select at least one. Changing action keeps selection.
    已选 {0} / {1}|Selected {0} / {1}
    {0}：全选|{0}: select all
    {0}：全不选|{0}: clear all
    等待中|Waiting
    清理中…|Cleaning…
    卸载中…|Uninstalling…
    安装中…|Installing…
    已清理|Cleaned
    已卸载|Uninstalled
    安装成功|Installed
    未执行|Skipped
    未安装，无需卸载|Not installed; nothing to remove
    失败，见日志|Failed: see log
    已选择|Selected
    未选择|Not selected
    需要App管理授权|App Management permission required
    需要权限检查|Permission check required
    已停止|Stopped
    已完成|Completed
    任务失败|Task failed
    {0}中；已处理 {1} / {2} 项（{3}，按完成项计数）；{4}用时 {5}|{0}: processed {1} / {2} ({3}, completed items); {4} time {5}
    {0}就绪|{0} ready
    {0}就绪；{1}用时 {2}|{0} ready; {1} time {2}
    正在完成当前功能，随后停止；安装用时 {0}|Finishing the current feature, then stopping; install time {0}
    {0}：成功 {1}，失败 {2}，未执行 {3}；退出码 {4}；进度 {5}；{6}总用时 {7}|{0}: {1} succeeded, {2} failed, {3} skipped; exit {4}; {5}; {6} time {7}
    {0}：成功 {1}，失败 {2}，无需卸载 {3}，未执行 {4}；退出码 {5}；进度 {6}；{7}总用时 {8}|{0}: {1} succeeded, {2} failed, {3} not installed, {4} skipped; exit {5}; {6}; {7} time {8}
    {0}：成功 {1}，失败 {2}，无需卸载 {3}；退出码 {4}；进度 {5}；{6}总用时 {7}|{0}: {1} succeeded, {2} failed, {3} not installed; exit {4}; {5}; {6} time {7}
    {0}：成功 {1}，失败 {2}；退出码 {3}；进度 {4}；{5}总用时 {6}|{0}: {1} succeeded, {2} failed; exit {3}; {4}; {5} time {6}
    IDE 项目打开|Open projects in IDEs
    Git 工具|Git tools
    文件与通用工具|Files and general tools
    Flutter 工具 · 子菜单功能|Flutter tools · submenu actions
    iOS / CocoaPods 工具|iOS / CocoaPods tools
    模拟器工具|Simulator tools
    用 Android Studio 打开项目|Open project in Android Studio
    用 VSCode 打开项目|Open project in VSCode
    用 Xcode 打开项目|Open project in Xcode
    拉取 Git 到最新|Pull latest Git changes
    Git 提交回退|Roll back Git commit
    打开 Git 远程地址|Open Git remote URL
    复制 Git 远程地址|Copy Git remote URL
    复制绝对路径|Copy absolute path
    创建脚本快捷入口|Create script launcher
    新建文件|Create file
    查看文件指纹 Hash（SHA-256）|View file fingerprint Hash (SHA-256)
    隐藏 / 显示所选项目|Hide / show selected items
    永久删除所选项目|Permanently delete selected items
    发送到外部磁盘或网络卷|Send to external disk or network volume
    更新开发环境（update）|Update development environment (update)
    磁盘空间总览|Total disk space
    授予执行权限（chmod +x）|Grant execute permission (chmod +x)
    移除执行权限（chmod -x）|Remove execute permission (chmod -x)
    IPA 免编译重签|Re-sign IPA without building
    显示 / 隐藏文件|Show / hide files
    新建 iOS 模拟器|Create iOS simulator
    新建 Android 模拟器|Create Android simulator
    新建 Harmony 模拟器|Create Harmony simulator
    Android 模拟器检测与修复|Check / repair Android simulator
    Harmony 模拟器检测与修复|Check / repair Harmony simulator
    配置 Git 动态代理|Configure Git proxy
    用终端打开|Open in terminal
    用终端查看文件内容|View file contents in terminal
    合并分卷|Merge file parts
    拆分文件|Split file
    清理 Android / OpenHarmony 构建产物|Clean Android / OpenHarmony builds
    更新代码地图（.codegraph）|Update code map (.codegraph)
    在终端创建空白 Commit 并 Push|Create empty commit and push in terminal
    禁用 CocoaPods 构建沙盒|Disable CocoaPods build sandbox
    安装 CocoaPods|Install CocoaPods
    CocoaPods 源：CDN → GitHub|CocoaPods source: CDN → GitHub
    提取项目所有 Pod 相关文件|Export all project Pod files
    查询 Xcode 工程依赖关系|Inspect Xcode project dependencies
    更新 CocoaPods 本地仓库|Update local CocoaPods repositories
    检查本地 Pod 能否编译（仅 .podspec 目录）|Check local Pod builds (.podspec folder)
    安装 / 升级 JobsCodeSnippets|Install / update JobsCodeSnippets
    清理 iOS/Xcode 构建产物|Clean iOS / Xcode builds
    一键配置 Flutter 项目|Set up Flutter project
    从终端运行 Flutter 项目|Run Flutter project in terminal
    拉取 Flutter Pub 依赖|Fetch Flutter Pub dependencies
    拉取 Android 原生依赖|Fetch native Android dependencies
    拉取 CocoaPods 依赖|Fetch CocoaPods dependencies
    拉取 Swift Package 依赖|Fetch Swift Package dependencies
    拉取 OpenHarmony 依赖|Fetch OpenHarmony dependencies
    准备原生库与构建依赖（组合操作）|Prepare native libraries and build dependencies
    下载Flutter平台资源|Download Flutter platform resources
    拉取 Web 工程依赖|Fetch Web project dependencies
    🧳 一键提取 Flutter 依赖|🧳 Export Flutter dependencies
    提取 Flutter Pub 依赖|Export Flutter Pub dependencies
    🔐 提取Flutter项目工程私库依赖|🔐 Export private Flutter dependencies
    📥 一键导入 Flutter 依赖|📥 Import Flutter dependencies
    导入 Flutter Pub 依赖|Import Flutter Pub dependencies
    📥 导入Flutter项目工程私库依赖|📥 Import private Flutter dependencies
    提取 Gradle 分发与依赖缓存|Export Gradle distributions and cache
    导入 Gradle 分发与依赖缓存|Import Gradle distributions and cache
    提取 CocoaPods 依赖|Export CocoaPods dependencies
    导入 CocoaPods 依赖|Import CocoaPods dependencies
    提取 Swift Package 依赖|Export Swift Package dependencies
    导入 Swift Package 依赖|Import Swift Package dependencies
    提取 OpenHarmony 依赖|Export OpenHarmony dependencies
    导入 OpenHarmony 依赖|Import OpenHarmony dependencies
    提取 原生构建缓存|Export native build cache
    导入 原生构建缓存|Import native build cache
    提取 Flutter 平台资源|Export Flutter platform resources
    导入 Flutter 平台资源|Import Flutter platform resources
    提取 Web 依赖|Export Web dependencies
    导入 Web 依赖|Import Web dependencies
    查看当前Flutter项目工程的SDK版本|Show Flutter project SDK version
    安装/切换Flutter SDK|Install / switch Flutter SDK
    安装/切换Flutter@OpenHarmony SDK|Install / switch Flutter@OpenHarmony SDK
    安装/切换Java SDK|Install / switch Java SDK
    下载Gradled分发与构建插件|Download Gradle distributions and plugins
    Flutter 自动化生产代码|Generate Flutter code
    打包 iOS|Package iOS
    打包 Android|Package Android
    打包鸿蒙（HAP + APP）|Package Harmony (HAP + APP)
    原生 Flutter 项目体检|Check native Flutter project
    OpenHarmony Flutter 环境体检|Check OpenHarmony Flutter environment
    修复 Android SDK / platforms 缺失|Repair missing Android SDK / platforms
    修复 Flutter 项目中文路径|Repair Chinese Flutter project paths
    修复 Flutter 插件 namespace|Repair Flutter plugin namespaces
    修复 Dart 相对 import 为 package 引用|Convert relative Dart imports to packages
    清理当前 Flutter 项目构建产物|Clean current Flutter project builds
    依赖与缓存维护|Dependency and cache maintenance
    """
}

/// 保留源文案绑定，切换语言只更新现有控件，不重建选择和后台任务。
private struct ManagerTextBinding {

    var source: String
    var rendered: String
}

private extension FeatureSelectionController {
    /// 预留各语言文字宽度，切换时无需重建窗口或打断任务。
    func fitLocalizedControl(_ control: NSControl, maximumWidth: CGFloat? = nil) {
        if let label = control as? NSTextField {
            fitLabel(label, reserving: [label.stringValue], maximumWidth: maximumWidth)
            return
        }
        if let segmented = control as? NSSegmentedControl {
            let originalFont = segmented.font ?? NSFont.systemFont(ofSize: 13)
            var height: CGFloat = 0
            for index in 0..<segmented.segmentCount {
                let source = segmented.label(forSegment: index) ?? ""
                let width = ManagerPanelPreferences.languages.filter { $0 != "system" }.map { language in
                    let font = ManagerPanelPreferences.scriptFont(originalFont, language: language)
                    height = max(height, font.ascender - font.descender + font.leading + 8)
                    return (preferences.text(source, language: language) as NSString).size(withAttributes: [.font: font]).width
                }.max() ?? 0
                segmented.setWidth(ceil(width) + 24, forSegment: index)
            }
            segmented.sizeToFit()
            segmented.setFrameSize(NSSize(width: segmented.frame.width, height: max(segmented.frame.height, ceil(height))))
            return
        }
        let source = (control as? NSButton)?.title ?? control.stringValue
        let originalFont = control.font ?? NSFont.systemFont(ofSize: 13)
        var size = NSSize.zero
        for language in ManagerPanelPreferences.languages where language != "system" {
            let value = preferences.text(source, language: language)
            control.font = ManagerPanelPreferences.scriptFont(originalFont, language: language)
            if let button = control as? NSButton {
                button.title = value
            } else {
                control.stringValue = value
            }
            control.sizeToFit()
            size.width = max(size.width, control.frame.width)
            size.height = max(size.height, control.frame.height)
        }
        control.font = originalFont
        if let button = control as? NSButton {
            button.title = source
        } else {
            control.stringValue = source
        }
        let limit = maximumWidth ?? maximumTextWidth
        if size.width > limit, let button = control as? NSButton {
            button.cell?.wraps = true
            button.cell?.usesSingleLineMode = false
            button.cell?.lineBreakMode = .byWordWrapping
            var height: CGFloat = 0
            for language in ManagerPanelPreferences.languages where language != "system" {
                let text = preferences.text(source, language: language)
                let font = ManagerPanelPreferences.scriptFont(originalFont, language: language)
                let bounds = (text as NSString).boundingRect(with: NSSize(width: limit - 28, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font])
                height = max(height, ceil(bounds.height) + 8)
            }
            size = NSSize(width: limit, height: max(size.height, height))
        }
        control.setFrameSize(size)
    }

    func makePreferencesRow() -> NSView {
        let row = NSView()
        let themeLabel = NSTextField(labelWithString: "🎨 主题")
        let languageLabel = NSTextField(labelWithString: "🌐 语言")
        let theme = NSPopUpButton(frame: .zero, pullsDown: false)
        let language = NSPopUpButton(frame: .zero, pullsDown: false)
        for (value, title) in zip(ManagerPanelPreferences.themes, ["跟随系统", "黑夜", "白天"]) {
            theme.addItem(withTitle: title)
            theme.lastItem?.representedObject = value
        }
        for (value, title) in zip(ManagerPanelPreferences.languages, ManagerPanelPreferences.languageNames) {
            language.addItem(withTitle: title)
            language.lastItem?.representedObject = value
        }
        theme.target = self
        theme.action = #selector(themeChanged)
        language.target = self
        language.action = #selector(languageChanged)
        theme.setAccessibilityLabel("主题")
        language.setAccessibilityLabel("语言")
        theme.selectItem(at: ManagerPanelPreferences.themes.firstIndex(of: preferences.theme) ?? 0)
        language.selectItem(at: ManagerPanelPreferences.languages.firstIndex(of: preferences.language) ?? 0)
        themeControl = theme
        languageControl = language
        for control in [themeLabel, theme, languageLabel, language] {
            control.font = .systemFont(ofSize: 12)
            if let popup = control as? NSPopUpButton {
                popup.controlSize = .small
                popup.alignment = .center
                popup.setFrameSize(NSSize(width: 112, height: 28))
            }
            row.addSubview(control)
        }
        layoutPreferencesRow(row)
        return row
    }

    /// 只按当前文案测宽，避免中文标题后留下英文预留空白。
    func layoutPreferencesRow(_ row: NSView) {
        var x: CGFloat = 0
        let controls = row.subviews.compactMap { view in
            return view as? NSControl
        }
        let height = max(28, controls.map { $0.frame.height }.max() ?? 28)
        for control in controls {
            if control is NSTextField {
                control.sizeToFit()
            } else if let popup = control as? NSPopUpButton {
                let title = popup.title
                let font = popup.font ?? NSFont.systemFont(ofSize: 12)
                let width = ceil((title as NSString).size(withAttributes: [.font: font]).width) + 32
                popup.setFrameSize(NSSize(width: min(132, max(100, width)), height: 28))
                popup.alignment = .center
            }
            control.setFrameOrigin(NSPoint(x: x, y: (height - control.frame.height) / 2))
            x += control.frame.width + (control === themeControl ? 16 : 6)
        }
        row.setFrameSize(NSSize(width: x - 6, height: height))
    }

    /// 当前语言按实际文字紧邻排列，长语言在预留行高内折行。
    func layoutDeploymentControls() {
        guard let location = installLocationButton, let cleanup = cleanupBuildProductsButton, let header = headerView else {
            return
        }
        let available = header.bounds.width
        for button in [location, cleanup] {
            let font = button.font ?? NSFont.systemFont(ofSize: 13)
            let textWidth = (button.title as NSString).size(withAttributes: [.font: font]).width + 22
            let width = min(available * 0.56, ceil(textWidth))
            let textHeight = (button.title as NSString).boundingRect(with: NSSize(width: max(1, width - 22), height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font]).height + 8
            button.cell?.wraps = true
            button.cell?.usesSingleLineMode = false
            button.cell?.lineBreakMode = .byWordWrapping
            button.setFrameSize(NSSize(width: width, height: max(20, ceil(textHeight))))
        }
        let rowHeight = max(location.frame.height, cleanup.frame.height)
        location.setFrameOrigin(NSPoint(x: 0, y: deploymentRowBaseY + (deploymentRowHeight - rowHeight) / 2 + (rowHeight - location.frame.height) / 2))
        let remaining = max(80, available - location.frame.maxX - installControlGap)
        if cleanup.frame.width > remaining {
            let font = cleanup.font ?? NSFont.systemFont(ofSize: 13)
            let height = (cleanup.title as NSString).boundingRect(with: NSSize(width: max(1, remaining - 22), height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font]).height + 8
            cleanup.setFrameSize(NSSize(width: remaining, height: max(20, ceil(height))))
        }
        cleanup.setFrameOrigin(NSPoint(x: location.frame.maxX + installControlGap,
                                       y: deploymentRowBaseY + (deploymentRowHeight - cleanup.frame.height) / 2))
    }

    func layoutButtonRow(_ row: NSView) {
        guard let install = installButton, let close = closeButton else {
            return
        }
        var right = row.bounds.width
        if let cleanup = cleanupNowButton, !cleanup.isHidden {
            cleanup.setFrameOrigin(NSPoint(x: right - cleanup.frame.width, y: 0))
            right = cleanup.frame.minX - 10
        }
        install.setFrameOrigin(NSPoint(x: right - install.frame.width, y: 0))
        close.setFrameOrigin(NSPoint(x: install.frame.minX - close.frame.width - 10, y: 0))
        for control in row.subviews {
            control.setFrameOrigin(NSPoint(x: control.frame.minX, y: (row.bounds.height - control.frame.height) / 2))
        }
    }

    /// 标题和偏好共用顶行；空间不足时仅多留一行，工具区始终贴齐内容右边缘。
    func layoutPreferencesHeader() {
        guard let window, let content = window.contentView, let header = headerView,
              let title = headerTitleLabel, let toolbar = preferencesToolbar,
              let split = logSplitView else {
            return
        }
        layoutDeploymentControls()
        if let row = buttonRow {
            layoutButtonRow(row)
        }
        layoutPreferencesRow(toolbar)
        let wraps = header.bounds.width < headerTitleFrame.width + 24 + toolbar.frame.width
        let extraHeight = wraps ? toolbar.frame.height + 8 : 0
        let height = headerBaseHeight + extraHeight
        header.frame = NSRect(x: header.frame.minX,
                              y: content.bounds.height - headerTopInset - height,
                              width: header.frame.width,
                              height: height)
        title.frame = headerTitleFrame.offsetBy(dx: 0, dy: extraHeight)
        toolbar.setFrameOrigin(NSPoint(x: header.bounds.width - toolbar.frame.width,
                                       y: wraps ? headerTitleFrame.minY : title.frame.midY - toolbar.frame.height / 2))
        split.setFrameSize(NSSize(width: split.frame.width,
                                  height: max(0, header.frame.minY - headerListGap - split.frame.minY)))
        split.adjustSubviews()
        let minimumHeight = minimumWindowHeightWithoutWrap + extraHeight
        if window.contentMinSize.height != minimumHeight {
            window.contentMinSize = NSSize(width: window.contentMinSize.width, height: minimumHeight)
        }
    }

    @objc func themeChanged() {
        preferences.theme = themeControl?.selectedItem?.representedObject as? String ?? "system"
        applyPanelPreferences()
    }

    @objc func languageChanged() {
        preferences.language = languageControl?.selectedItem?.representedObject as? String ?? "system"
        applyPanelPreferences()
    }

    @objc func systemPreferencesChanged() {
        applyPanelPreferences()
    }

    /// 原生 appearance=nil 交由 AppKit 跟随系统，不修改系统外观。
    func applyPanelPreferences() {
        switch preferences.theme {
        case "dark":
            window?.appearance = NSAppearance(named: .darkAqua)
        case "light":
            window?.appearance = NSAppearance(named: .aqua)
        default:
            window?.appearance = nil
        }
        themeControl?.selectItem(at: ManagerPanelPreferences.themes.firstIndex(of: preferences.theme) ?? 0)
        languageControl?.selectItem(at: ManagerPanelPreferences.languages.firstIndex(of: preferences.language) ?? 0)
        localizeInterface()
        layoutPreferencesHeader()
        applyLogPalette()
        window?.contentView?.needsDisplay = true
    }

    func applyLogPalette() {
        // 已追加文本也使用语义颜色；主题切换不会清空日志或改变选择范围。
        if let text = logTextView, let storage = text.textStorage {
            let selection = text.selectedRanges
            let origin = text.enclosingScrollView?.contentView.bounds.origin
            text.backgroundColor = logPalette.background
            logScrollView?.backgroundColor = logPalette.background
            text.textColor = logPalette.foreground(.normal)
            ManagerLogStyling.recolor(storage, palette: logPalette)
            text.selectedRanges = selection
            if let origin, let scroll = text.enclosingScrollView {
                scroll.contentView.scroll(to: origin)
                scroll.reflectScrolledClipView(scroll.contentView)
            }
        }
    }

    /// 业务刷新写入新原文后重新绑定，已经翻译的文字仍关联最初原文。
    func localizedValue(_ current: String, object: AnyObject, property: String) -> String {
        let key = "\(ObjectIdentifier(object))-\(property)"
        let source: String
        if let binding = textBindings[key], current == binding.rendered {
            source = binding.source
        } else {
            source = current
        }
        let rendered = preferences.text(source, language: interfaceLanguage)
        textBindings[key] = ManagerTextBinding(source: source, rendered: rendered)
        return rendered
    }

    func localizeMenu(_ menu: NSMenu) {
        menu.title = localizedValue(menu.title, object: menu, property: "title")
        for item in menu.items {
            // 语言名称使用各语言自称，让任何界面语言下都能找到返回入口。
            let language = item.representedObject as? String
            if !ManagerPanelPreferences.languages.dropFirst().contains(language ?? "") {
                item.title = localizedValue(item.title, object: item, property: "title")
            }
            if let submenu = item.submenu {
                localizeMenu(submenu)
            }
        }
    }

    func localizeView(_ view: NSView) {
        // 吸顶副本直接跟随已经翻译的原卡片，避免重复绑定译文。
        if let header = view as? ManagerFeaturePinnedHeader {
            if let toolbar = header.sourceBox?.groupToolbar {
                localizeView(toolbar)
            }
            return
        }
        if let control = view as? NSControl, let font = control.font {
            let key = ObjectIdentifier(control)
            let original = originalPanelFonts[key] ?? font
            originalPanelFonts[key] = original
            control.font = ManagerPanelPreferences.scriptFont(original, language: interfaceLanguage)
        }
        if let tooltip = view.toolTip {
            view.toolTip = localizedValue(tooltip, object: view, property: "tooltip")
        }
        if let label = view.accessibilityLabel() {
            view.setAccessibilityLabel(localizedValue(label, object: view, property: "accessibility"))
        }
        if let popup = view as? NSPopUpButton {
            if let menu = popup.menu {
                localizeMenu(menu)
            }
        } else if let button = view as? NSButton {
            let source = button.attributedTitle
            let title = localizedValue(button.title, object: button, property: "title")
            if button === cleanupNowButton {
                var attributes = source.length > 0 ? source.attributes(at: 0, effectiveRange: nil) : [.foregroundColor: NSColor.white]
                attributes[.font] = button.font
                button.attributedTitle = NSAttributedString(string: title, attributes: attributes)
            } else {
                button.title = title
            }
        } else if let field = view as? NSTextField {
            let attributes = field.attributedStringValue
            let title = localizedValue(field.stringValue, object: field, property: "text")
            var values = attributes.length > 0 ? attributes.attributes(at: 0, effectiveRange: nil) : [:]
            values[.font] = field.font
            field.attributedStringValue = NSAttributedString(string: title, attributes: values)
        } else if let segmented = view as? NSSegmentedControl {
            for index in 0..<segmented.segmentCount {
                segmented.setLabel(localizedValue(segmented.label(forSegment: index) ?? "", object: segmented, property: "segment\(index)"), forSegment: index)
            }
        }
        if let box = view as? NSBox {
            let key = ObjectIdentifier(box)
            let original = originalPanelFonts[key] ?? box.titleFont
            originalPanelFonts[key] = original
            box.titleFont = ManagerPanelPreferences.scriptFont(original, language: interfaceLanguage)
            box.title = localizedValue(box.title, object: box, property: "title")
        }
        // 原始日志是诊断证据，不把后端输出和用户路径当作待翻译文案。
        for child in view.subviews where !(child is NSTextView) {
            localizeView(child)
        }
    }

    func localizeInterface() {
        // 每次刷新只读取一次系统 UI 语言；逐控件翻译复用缓存，流式输出不阻塞主线程。
        interfaceLanguage = preferences.resolvedLanguage
        if let window {
            window.title = localizedValue(window.title, object: window, property: "title")
            if let content = window.contentView {
                localizeView(content)
            }
        }
        if let menu = NSApplication.shared.mainMenu {
            localizeMenu(menu)
        }
        featureDocument?.updatePinnedHeaders()
        updateBackgroundStatus()
    }
}
