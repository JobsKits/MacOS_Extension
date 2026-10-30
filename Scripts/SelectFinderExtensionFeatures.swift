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
        FeatureOption(identifier: "file-create", title: "新建文件"),
        FeatureOption(identifier: "run-authorize", title: "运行授权"),
        FeatureOption(identifier: "run-revoke", title: "解除运行授权"),
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
        FeatureOption(identifier: "flutter-extract", title: "提取 Flutter Pub 依赖"),
        FeatureOption(identifier: "flutter-export-private-dependencies", title: "🔐 提取Flutter项目工程私库依赖"),
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
            "path_copier", "file-create", "run-authorize", "run-revoke", "hidden-files-toggle", "terminal_open", "file_content", "file_merge", "file_split",
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

/// 右键动作明确绑定日志自身，避免焦点仍在复选框时误选其它内容。
private final class ManagerLogTextView: NSTextView {

    override func menu(for event: NSEvent) -> NSMenu? {
        window?.makeFirstResponder(self)
        let menu = super.menu(for: event) ?? NSMenu()
        if !menu.items.contains(where: { $0.action == #selector(selectAll(_:)) }) {
            if !menu.items.isEmpty {
                menu.addItem(.separator())
            }
            let item = NSMenuItem(title: "全选", action: #selector(selectAll(_:)), keyEquivalent: "a")
            item.target = self
            menu.addItem(item)
        }
        return menu
    }
}

/// 面板持有后台任务；兼容未传管理器路径时只返回选择计划的调用方。
final class FeatureSelectionController: NSObject, NSWindowDelegate, NSSplitViewDelegate {
    private enum Outcome {
        case selected(String, [String])
        case cancelled
    }

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
    private var managerPath: String?
    private var worker: Process?
    private var runningIdentifiers: [String] = []
    private var featureStates: [String: String] = [:]
    private var statusLabels: [String: NSTextField] = [:]
    private var activityIndicators: [String: NSProgressIndicator] = [:]
    private var progressIndicator: NSProgressIndicator?
    private var executionLabel: NSTextField?
    private var executionTimer: Timer?
    private struct ExecutionTiming {

        var startedAt: TimeInterval?
        var elapsed: TimeInterval = 0
    }
    private var installationTiming = ExecutionTiming()
    private var uninstallationTiming = ExecutionTiming()

    // 刷新事件共用，安装与卸载的起点和最终耗时分别保存。
    private var executionTiming: ExecutionTiming {
        get {
            return managementAction == "uninstall" ? uninstallationTiming : installationTiming
        }
        set {
            if managementAction == "uninstall" {
                uninstallationTiming = newValue
            } else {
                installationTiming = newValue
            }
        }
    }

    private var timingTitle: String {
        return managementAction == "uninstall" ? "卸载" : "安装"
    }
    private var logTextView: NSTextView?
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

    private var isRunning: Bool {
        worker != nil
    }

    init(action: String = "install", scope: [String]? = nil) {
        managementAction = action
        scopeIdentifiers = Set(scope ?? FeatureOption.all.map { $0.identifier })
        super.init()
    }

    static func parseArguments(_ arguments: [String]) throws -> FeatureSelectionController {
        var action = "install"
        var scope: [String]?
        var managerPath: String?
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            guard ["--action", "--scope", "--manager"].contains(argument), index + 1 < arguments.count else {
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
            } else {
                guard value.hasPrefix("/"), FileManager.default.isReadableFile(atPath: value) else {
                    throw NSError(domain: "JobsFinderFeatureSelection", code: 2,
                                  userInfo: [NSLocalizedDescriptionKey: "管理脚本不可读取：\(value)"])
                }
                managerPath = value
            }
            index += 1
        }
        let controller = FeatureSelectionController(action: action, scope: scope)
        controller.managerPath = managerPath
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
        application.setActivationPolicy(.accessory)
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
        guard !isRunning else {
            executionLabel?.stringValue = "任务仍在执行，请等待结束后关闭，避免中断安装。"
            return false
        }
        outcome = .cancelled
        NSApplication.shared.stop(nil)
        return false
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
        statusLabels.removeAll()
        activityIndicators.removeAll()
        let screenSize = screenSize ?? NSScreen.main?.visibleFrame.size ?? NSSize(width: 1280, height: 800)
        let compact = screenSize.height < 700
        let header = NSView()

        let titleLabel = NSTextField(labelWithString: "管理 Finder 右键功能")
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)

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

        let summaryLabel = NSTextField(labelWithString: "已选 0 / \(scopeIdentifiers.count) 项；空选不能执行，切换操作会清空勾选。")
        summaryLabel.font = .systemFont(ofSize: 12, weight: .medium)
        summaryLabel.textColor = .secondaryLabelColor
        self.summaryLabel = summaryLabel

        var headerHeight: CGFloat = 0
        var headerWidth: CGFloat = 0
        for label: NSControl in [summaryLabel, subtitleLabel, actionControl, titleLabel] {
            if label === summaryLabel {
                fitLabel(summaryLabel, reserving: (0...scopeIdentifiers.count).map { count in
                    "已选 \(count) / \(scopeIdentifiers.count) 项；空选不能执行，切换操作会清空勾选。"
                })
            } else {
                label.sizeToFit()
            }
            label.setFrameOrigin(NSPoint(x: 0, y: headerHeight))
            header.addSubview(label)
            headerHeight += label.frame.height + (compact ? 6 : 10)
            headerWidth = max(headerWidth, label.frame.width)
        }
        header.setFrameSize(NSSize(width: headerWidth, height: headerHeight - (compact ? 6 : 10)))

        let boxes = visibleGroups.map { makeGroupBox(group: $0, spacing: compact ? 3 : 6) }
        let verticalPadding: CGFloat = compact ? 56 : 84
        let logHeight: CGFloat = compact ? 140 : 180
        let executionHeight: CGFloat = 32
        let featureList = makeFeatureList(
            boxes: boxes,
            screenSize: screenSize,
            reservedHeight: header.frame.height + 32 + verticalPadding + 32 + logHeight + executionHeight
        )
        let logPanel = makeLogPanel(width: 0, height: logHeight)
        let executionRow = makeExecutionRow(width: 0, height: executionHeight)
        let contentWidth = max(featureList.frame.width, headerWidth, logPanel.frame.width, executionRow.frame.width)
        logPanel.setFrameSize(NSSize(width: contentWidth, height: logHeight))
        executionRow.setFrameSize(NSSize(width: contentWidth, height: executionHeight))
        let buttonRow = makeButtonRow(width: contentWidth)
        let headerSize = header.frame.size
        let buttonHeight = buttonRow.frame.height
        let contentSize = NSSize(
            width: contentWidth + 52,
            height: headerSize.height + featureList.frame.height + buttonHeight + verticalPadding + logHeight + executionHeight
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
        minimumUpperPaneHeight = 100 + executionHeight + buttonHeight + listGap + 4
        executionRow.setFrameOrigin(.zero)
        executionRow.autoresizingMask = [.width]
        buttonRow.frame = NSRect(x: 0, y: executionHeight + 4, width: contentWidth, height: buttonHeight)
        buttonRow.autoresizingMask = [.width]
        installButton?.autoresizingMask = [.minXMargin]
        closeButton?.autoresizingMask = [.minXMargin]
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
        container.layoutSubtreeIfNeeded()
        split.adjustSubviews()
        split.setPosition(split.bounds.height - split.dividerThickness - logHeight, ofDividerAt: 0)
        window.center()
        refreshSelectionState()
    }

    /// 测量连续分组的最佳分列，常规屏幕两列，矮屏在宽度允许时改成三列。
    func makeFeatureList(boxes: [NSBox], screenSize: NSSize, reservedHeight: CGFloat) -> NSView {
        let gap: CGFloat = 14
        func dimensions(_ columns: [[NSBox]]) -> NSSize {
            let widths = columns.map { $0.map { $0.frame.width }.max() ?? 0 }
            let heights = columns.map { column in
                column.reduce(CGFloat(0)) { $0 + $1.frame.height } + CGFloat(column.count - 1) * gap
            }
            return NSSize(width: widths.reduce(0, +) + CGFloat(columns.count - 1) * gap, height: heights.max() ?? 0)
        }
        func partitions(_ remaining: [NSBox], count: Int) -> [[[NSBox]]] {
            if count == 1 {
                return [[remaining]]
            }
            return (1...(remaining.count - count + 1)).flatMap { cut in
                partitions(Array(remaining.dropFirst(cut)), count: count - 1).map {
                    [Array(remaining.prefix(cut))] + $0
                }
            }
        }
        let layouts = [2, 3, 1].filter { $0 <= boxes.count }.flatMap { count in
            partitions(boxes, count: count).sorted { dimensions($0).height < dimensions($1).height }
        }
        let columns = layouts.first { columns in
            let size = dimensions(columns)
            return size.width + 68 <= screenSize.width - 40 && size.height + reservedHeight <= screenSize.height
        } ?? layouts.filter { dimensions($0).width + 68 <= screenSize.width - 40 }.min {
            dimensions($0).height < dimensions($1).height
        } ?? layouts[0]
        let size = dimensions(columns)
        let list = NSView(frame: NSRect(origin: .zero, size: size))
        var x: CGFloat = 0
        for column in columns {
            let width = column.map { $0.frame.width }.max() ?? 0
            var y = size.height
            for box in column {
                let height = box.frame.height
                y -= height
                box.frame = NSRect(x: x, y: y, width: width, height: height)
                list.addSubview(box)
                y -= gap
            }
            x += width + gap
        }
        let availableHeight = max(140, screenSize.height - reservedHeight)
        // 始终保留滚动容器，拖大日志后缩小的列表仍可到达最后一项。
        let viewportHeight = min(size.height, availableHeight)
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: size.width + 16, height: viewportHeight))
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = false
        scroll.drawsBackground = false
        scroll.documentView = list
        featureScrollView = scroll
        scroll.contentView.scroll(to: NSPoint(x: 0, y: max(0, size.height - viewportHeight)))
        scroll.reflectScrolledClipView(scroll.contentView)
        return scroll
    }

    func makeGroupBox(group: FeatureGroup, spacing: CGFloat) -> NSBox {
        let box = NSBox()
        box.title = group.title
        box.titleFont = .systemFont(ofSize: 13, weight: .semibold)

        let column = NSView()
        let controls = NSView()
        let select = NSButton(title: "全选", target: self, action: #selector(selectGroupClicked(_:)))
        let clear = NSButton(title: "全不选", target: self, action: #selector(clearGroupClicked(_:)))
        var controlsWidth: CGFloat = 0
        var controlsHeight: CGFloat = 0
        for button in [select, clear] {
            styleAuxiliaryButton(button)
            button.identifier = NSUserInterfaceItemIdentifier(group.identifier)
            button.setAccessibilityLabel("\(group.title)：\(button.title)")
            button.sizeToFit()
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
            checkbox.sizeToFit()
            optionButtons.append(checkbox)
            contentWidth = max(contentWidth, checkbox.frame.width + 112)
            contentHeight += checkbox.frame.height + spacing
        }
        contentHeight -= spacing
        column.setFrameSize(NSSize(width: contentWidth, height: contentHeight))
        controls.setFrameOrigin(NSPoint(x: 0, y: contentHeight - controlsHeight))
        column.addSubview(controls)
        var y = controls.frame.minY - spacing
        for checkbox in optionButtons {
            y -= checkbox.frame.height
            checkbox.setFrameOrigin(NSPoint(x: 0, y: y))
            column.addSubview(checkbox)
            let identifier = checkboxes.first { $0.button === checkbox }!.option.identifier
            let status = NSTextField(labelWithString: "未选择")
            status.font = .systemFont(ofSize: 11)
            status.textColor = .secondaryLabelColor
            status.frame = NSRect(x: contentWidth - 88, y: y + 2, width: 88, height: 18)
            status.identifier = NSUserInterfaceItemIdentifier(identifier)
            let click = NSClickGestureRecognizer(target: self, action: #selector(failedStatusClicked(_:)))
            click.isEnabled = false
            status.addGestureRecognizer(click)
            column.addSubview(status)
            statusLabels[identifier] = status
            let activity = NSProgressIndicator(frame: NSRect(x: contentWidth - 108, y: y + 2, width: 16, height: 16))
            activity.style = .spinning
            activity.controlSize = .small
            activity.isDisplayedWhenStopped = false
            column.addSubview(activity)
            activityIndicators[identifier] = activity
            y -= spacing
        }
        box.contentView = column
        box.setFrameFromContentFrame(NSRect(origin: .zero, size: NSSize(width: contentWidth, height: contentHeight)))
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
        for button in [selectAllButton, clearButton, cancelButton, installButton] {
            button.sizeToFit()
            row.addSubview(button)
            height = max(height, button.frame.height)
        }
        selectAllButton.setFrameOrigin(.zero)
        clearButton.setFrameOrigin(NSPoint(x: selectAllButton.frame.maxX + 10, y: 0))
        installButton.setFrameOrigin(NSPoint(x: width - installButton.frame.width, y: 0))
        cancelButton.setFrameOrigin(NSPoint(x: installButton.frame.minX - cancelButton.frame.width - 10, y: 0))
        row.setFrameSize(NSSize(width: width, height: height))

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
    func fitLabel(_ label: NSTextField, reserving values: [String]) {
        let original = label.stringValue
        var size = NSSize.zero
        for value in values {
            label.stringValue = value
            label.sizeToFit()
            size.width = max(size.width, label.frame.width)
            size.height = max(size.height, label.frame.height)
        }
        label.stringValue = original
        label.setFrameSize(NSSize(width: ceil(size.width) + 2, height: ceil(size.height)))
    }

    func makeExecutionRow(width: CGFloat, height: CGFloat) -> NSView {
        let label = NSTextField(labelWithString: "就绪；选择功能后点击操作按钮。")
        label.font = .systemFont(ofSize: 12)
        let count = scopeIdentifiers.count
        var messages = [label.stringValue, "任务仍在执行，请等待结束后关闭，避免中断安装。"]
        for action in ["安装 / 更新", "卸载"] {
            let timing = action == "卸载" ? "卸载" : "安装"
            messages += (0...count).map { completed in
                "\(action)中；已处理 \(completed) / \(count) 项（\(completionPercentage(completed: completed, total: count))，按完成项计数）；\(timing)用时 9999:59:59"
            }
        }
        for failed in 0...count {
            messages.append("任务失败：成功 \(count - failed)，失败 \(failed)；退出码 \(Int32.min)；进度 100.0%；安装总用时 9999:59:59")
        }
        messages.append("已完成：成功 \(count)，失败 0；退出码 0；进度 100.0%；安装总用时 9999:59:59")
        fitLabel(label, reserving: messages)
        let rowWidth = max(width, 152 + label.frame.width)
        let row = NSView(frame: NSRect(x: 0, y: 0, width: rowWidth, height: height))
        let progress = NSProgressIndicator(frame: NSRect(x: 0, y: 8, width: 140, height: 14))
        progress.isIndeterminate = false
        progress.minValue = 0
        progress.maxValue = 1
        row.addSubview(progress)
        progressIndicator = progress
        label.frame = NSRect(x: 152, y: 6, width: rowWidth - 152, height: 20)
        label.autoresizingMask = [.width]
        row.addSubview(label)
        executionLabel = label
        return row
    }

    func makeLogPanel(width: CGFloat, height: CGFloat) -> NSView {
        let label = NSTextField(labelWithString: "实时日志（可选择文字并复制）")
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.sizeToFit()
        let copy = NSButton(title: "复制日志", target: self, action: #selector(copyLogClicked))
        let reveal = NSButton(title: "日志文件", target: self, action: #selector(revealLogClicked))
        let follow = NSButton(checkboxWithTitle: "自动滚动", target: nil, action: nil)
        follow.state = .on
        followLogButton = follow
        let buttons = [copy, reveal, follow]
        for button in buttons {
            button.font = .systemFont(ofSize: 11)
            button.sizeToFit()
        }
        let minimumWidth = ceil(label.frame.width) + 12 + buttons.reduce(CGFloat(0)) { $0 + $1.frame.width } + 16
        let panelWidth = max(width, minimumWidth)
        let panel = NSView(frame: NSRect(x: 0, y: 0, width: panelWidth, height: height))
        label.frame = NSRect(x: 0, y: height - 26, width: ceil(label.frame.width) + 2, height: 22)
        label.autoresizingMask = [.minYMargin]
        panel.addSubview(label)
        var right = panelWidth
        for button in buttons {
            right -= button.frame.width
            button.setFrameOrigin(NSPoint(x: right, y: height - 28))
            button.autoresizingMask = [.minXMargin, .minYMargin]
            panel.addSubview(button)
            right -= 8
        }
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: panelWidth, height: height - 32))
        scroll.autoresizingMask = [.width, .height]
        scroll.borderType = .bezelBorder
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        let text = ManagerLogTextView(frame: scroll.contentView.bounds)
        text.isEditable = false
        text.isSelectable = true
        text.isRichText = false
        text.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        text.textColor = .textColor
        text.backgroundColor = .textBackgroundColor
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
        alert.messageText = "无法查看本次日志"
        alert.informativeText = message
        if let window, window.isVisible {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }

    func appendLog(_ message: String) {
        removeLiveOutput()
        let clean = message.replacingOccurrences(of: "\u{1B}\\[[0-?]*[ -/]*[@-~]", with: "", options: .regularExpression)
        if let data = clean.data(using: .utf8) {
            logHandle?.write(data)
        }
        guard let text = logTextView, let storage = text.textStorage else {
            return
        }
        storage.append(NSAttributedString(string: clean, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
            .foregroundColor: NSColor.textColor
        ]))
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
              let storage = logTextView?.textStorage else {
            return
        }
        let clean = text.replacingOccurrences(of: "\u{1B}\\[[0-?]*[ -/]*[@-~]|\u{1B}(?:\\[[0-?]*[ -/]*)?$", with: "", options: .regularExpression)
        let visible = String(clean.suffix(100_000))
        storage.append(NSAttributedString(string: visible, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
            .foregroundColor: NSColor.textColor
        ]))
        liveOutputLength = (visible as NSString).length
        if followLogButton?.state == .on {
            logTextView?.scrollToEndOfDocument(nil)
        }
    }

    func consumeOutputLine(_ line: String) {
        let parts = line.split(separator: "\t", maxSplits: 3, omittingEmptySubsequences: false).map(String.init)
        if parts.count >= 3, parts[0] == "JOBS_MANAGER_EVENT", runningIdentifiers.contains(parts[1]),
           ["running", "succeeded", "failed"].contains(parts[2]) {
            featureStates[parts[1]] = parts[2]
            if parts.count == 4, !parts[3].isEmpty {
                appendLog(parts[3] + "\n")
            }
            refreshExecutionState()
        } else {
            appendLog(line + "\n")
        }
    }

    func startWorker(identifiers: [String], path: String) {
        guard !isRunning else {
            return
        }
        executionTimer?.invalidate()
        executionTiming.startedAt = ProcessInfo.processInfo.systemUptime
        executionTiming.elapsed = 0
        runningIdentifiers = identifiers
        featureStates = Dictionary(uniqueKeysWithValues: identifiers.map { ($0, "waiting") })
        lastExitStatus = nil
        logTextView?.string = ""
        liveOutputLength = 0
        try? logHandle?.close()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("JobsFinderManager-\(UUID().uuidString).log")
        FileManager.default.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600])
        logURL = url
        logHandle = try? FileHandle(forWritingTo: url)
        appendLog("\(actionTitle) \(identifiers.count) 项；日志文件：\(url.path)\n")
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [path, "--non-interactive", "--action", managementAction, "--features", identifiers.joined(separator: ",")]
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice
        var environment = ProcessInfo.processInfo.environment
        environment["NO_COLOR"] = "1"
        environment["CLICOLOR"] = "0"
        environment["TERM"] = "dumb"
        environment["NSUnbufferedIO"] = "YES"
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
        if let startedAt = executionTiming.startedAt {
            executionTiming.elapsed = max(0, ProcessInfo.processInfo.systemUptime - startedAt)
        }
        executionTiming.startedAt = nil
        executionTimer?.invalidate()
        executionTimer = nil
        lastExitStatus = exitStatus
        for identifier in runningIdentifiers where !["succeeded", "failed"].contains(featureStates[identifier] ?? "") {
            featureStates[identifier] = "failed"
        }
        worker = nil
        refreshSelectionState()
        refreshExecutionState()
        let failed = runningIdentifiers.filter { featureStates[$0] == "failed" }.count
        let result = exitStatus == 0 && failed == 0 ? "已完成" : "任务失败"
        let percentage = completionPercentage(completed: runningIdentifiers.count, total: runningIdentifiers.count)
        executionLabel?.stringValue = "\(result)：成功 \(runningIdentifiers.count - failed)，失败 \(failed)；退出码 \(exitStatus)；进度 \(percentage)；\(timingTitle)总用时 \(formattedElapsedTime(executionTiming.elapsed))"
        appendLog("\n\(executionLabel?.stringValue ?? "")\n")
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
            case "waiting":
                text = "等待中"
                color = .secondaryLabelColor
            case "running":
                text = managementAction == "uninstall" ? "卸载中…" : "安装中…"
                color = .systemBlue
            case "succeeded":
                text = managementAction == "uninstall" ? "已卸载" : "✅ 安装成功"
                color = .systemGreen
            case "failed":
                text = "失败，见日志"
                color = .systemRed
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
            if state == "running" {
                activityIndicators[identifier]?.startAnimation(nil)
            } else {
                activityIndicators[identifier]?.stopAnimation(nil)
            }
        }
        let completed = runningIdentifiers.filter { ["succeeded", "failed"].contains(featureStates[$0] ?? "") }.count
        progressIndicator?.maxValue = Double(max(1, runningIdentifiers.count))
        progressIndicator?.doubleValue = Double(completed)
        refreshExecutionSummary()
    }

    /// 计时独立于日志输出刷新，长时间编译无输出时仍显示实际等待时间。
    func refreshExecutionSummary() {
        if isRunning {
            let completed = runningIdentifiers.filter { ["succeeded", "failed"].contains(featureStates[$0] ?? "") }.count
            let elapsed = executionTiming.startedAt.map { max(0, ProcessInfo.processInfo.systemUptime - $0) } ?? executionTiming.elapsed
            let percentage = completionPercentage(completed: completed, total: runningIdentifiers.count)
            executionLabel?.stringValue = "\(actionTitle)中；已处理 \(completed) / \(runningIdentifiers.count) 项（\(percentage)，按完成项计数）；\(timingTitle)用时 \(formattedElapsedTime(elapsed))"
        } else if lastExitStatus == nil {
            executionLabel?.stringValue = "\(actionTitle)就绪；\(timingTitle)用时 \(formattedElapsedTime(executionTiming.elapsed))"
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
        clearAllClicked()
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

    @objc func installClicked() {
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
        guard !isRunning else {
            return
        }
        outcome = .cancelled
        NSApplication.shared.stop(nil)
    }

    func checkedIdentifiers() -> [String] {
        let selected = Set(checkboxes
            .filter { $0.button.state == .on }
            .map { $0.option.identifier })
        return FeatureOption.all.map { $0.identifier }.filter { selected.contains($0) }
    }

    func refreshSelectionState() {
        let checkedCount = checkboxes.filter { $0.button.state == .on }.count
        installButton?.title = actionTitle
        installButton?.isEnabled = checkedCount > 0 && !isRunning
        clearButton?.isEnabled = checkedCount > 0 && !isRunning
        selectAllButton?.isEnabled = checkedCount < checkboxes.count && !isRunning
        actionControl?.isEnabled = !isRunning
        closeButton?.isEnabled = !isRunning
        for checkbox in checkboxes {
            checkbox.button.isEnabled = !isRunning
        }
        summaryLabel?.stringValue = "已选 \(checkedCount) / \(checkboxes.count) 项；空选不能执行，切换操作会清空勾选。"
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
