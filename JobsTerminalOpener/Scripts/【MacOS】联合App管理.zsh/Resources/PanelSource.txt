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

    var preferences: ManagerPanelPreferences = .shared

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
final class FeatureSelectionController: NSObject, NSWindowDelegate, NSSplitViewDelegate {
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
    private var textBindings: [String: ManagerTextBinding] = [:]
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

    static func parseArguments(_ arguments: [String]) throws -> FeatureSelectionController {
        var action = "install"
        var scope: [String]?
        var managerPath: String?
        var installLocation = "build"
        var cleanupBuildProducts = false
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            if argument == "--cleanup-build-products" {
                cleanupBuildProducts = true
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
        let controller = FeatureSelectionController(action: action,
                                                    scope: scope,
                                                    installLocation: installLocation)
        controller.managerPath = managerPath
        controller.cleanupBuildProducts = cleanupBuildProducts && managerPath != nil && installLocation == "applications" && action == "install"
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
        defer {
            localizeInterface()
        }
        guard !isRunning else {
            executionLabel?.stringValue = "任务仍在执行，请等待结束后关闭，避免中断安装。"
            return false
        }
        outcome = .cancelled
        NSApplication.shared.stop(nil)
        return false
    }

    func windowDidResize(_ notification: Notification) {
        layoutPreferencesHeader()
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
        textBindings.removeAll()
        let preferencesRow = makePreferencesRow()

        let titleLabel = NSTextField(labelWithString: "管理 Finder 右键功能")
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

        let summaryLabel = NSTextField(labelWithString: "已选 0 / \(scopeIdentifiers.count) 项；空选不能执行，切换操作会清空勾选。")
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
            header.addSubview(cleanupNow)
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
                    "已选 \(count) / \(scopeIdentifiers.count) 项；空选不能执行，切换操作会清空勾选。"
                })
            } else if label === installLocationLabel, let locationLabel = installLocationLabel {
                fitLabel(locationLabel, reserving: [
                    "当前目标：构建目录（原有方式；清理构建产物会影响功能）。",
                    "联合 App：Jobs自定义右键菜单.app；位置：/Applications/Jobs自定义右键菜单.app（安装成功后可清理构建产物）"
                ])
            } else {
                fitLocalizedControl(label)
            }
            if label === installLocationButton,
               let cleanup = cleanupBuildProductsButton, let cleanupNow = cleanupNowButton {
                fitLocalizedControl(cleanup)
                fitLocalizedControl(cleanupNow)
                cleanupNow.setFrameSize(NSSize(width: cleanupNow.frame.width + 18,
                                               height: max(24, cleanupNow.frame.height)))
                let rowHeight = max(label.frame.height, cleanup.frame.height, cleanupNow.frame.height)
                label.setFrameOrigin(NSPoint(x: 0, y: headerHeight + (rowHeight - label.frame.height) / 2))
                cleanup.setFrameOrigin(NSPoint(x: label.frame.maxX + installControlGap,
                                                y: headerHeight + (rowHeight - cleanup.frame.height) / 2))
                cleanupNow.setFrameOrigin(NSPoint(x: cleanup.frame.maxX + installControlGap,
                                                   y: headerHeight + (rowHeight - cleanupNow.frame.height) / 2))
                header.addSubview(label)
                header.addSubview(cleanup)
                headerHeight += rowHeight + (compact ? 6 : 10)
                headerWidth = max(headerWidth, cleanupNow.frame.maxX)
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
            fitLocalizedControl(checkbox)
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
            fitLocalizedControl(button)
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
        for value in values.flatMap({ preferences.variants($0) }) {
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
        messages.append("已停止：成功 \(count)，失败 \(count)，未执行 \(count)；退出码 \(Int32.min)；进度 100.0%；安装总用时 9999:59:59")
        messages.append("正在完成当前功能，随后停止；安装用时 9999:59:59")
        messages.append("需要App管理授权：成功 \(count)，失败 \(count)，未执行 \(count)；退出码 77；进度 100.0%；安装总用时 9999:59:59")
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
        fitLocalizedControl(label)
        let copy = NSButton(title: "复制日志", target: self, action: #selector(copyLogClicked))
        let reveal = NSButton(title: "日志文件", target: self, action: #selector(revealLogClicked))
        let follow = NSButton(checkboxWithTitle: "自动滚动", target: nil, action: nil)
        follow.state = .on
        followLogButton = follow
        let buttons = [copy, reveal, follow]
        for button in buttons {
            button.font = .systemFont(ofSize: 11)
            fitLocalizedControl(button)
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
        text.preferences = preferences
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
        alert.messageText = preferences.text("无法查看本次日志")
        alert.informativeText = preferences.text(message)
        alert.addButton(withTitle: preferences.text("确定"))
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
              !text.hasPrefix("JOBS_MANAGER_STOPPED"), !"JOBS_MANAGER_STOPPED".hasPrefix(text),
              !text.hasPrefix("JOBS_MANAGER_BLOCKED"), !"JOBS_MANAGER_BLOCKED".hasPrefix(text),
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
        if parts.count >= 2, parts[0] == "JOBS_MANAGER_BLOCKED", parts[1] == "app-management" {
            appManagementBlocked = true
            let responsibleApp = ProcessInfo.processInfo.environment["JOBS_FINDER_RESPONSIBLE_APP"] ?? "Jobs右键菜单管理面板.app"
            appendLog("需要App管理授权：请在“隐私与安全性 → App 管理”中添加并启用 \(responsibleApp)，然后重新执行。面板不会自动更改授权。\n")
            refreshSelectionState()
        } else if parts.first == "JOBS_MANAGER_STOPPED", activeWorkerAction == "install" {
            workerReportedStopped = true
            appendLog("已收到停止确认；当前安装单元已经完成。\n")
            refreshExecutionState()
        } else if parts.count >= 3, parts[0] == "JOBS_MANAGER_EVENT", runningIdentifiers.contains(parts[1]),
           ["running", "succeeded", "failed", "skipped"].contains(parts[2]) {
            featureStates[parts[1]] = parts[2]
            if parts.count == 4, !parts[3].isEmpty {
                appendLog(parts[3] + "\n")
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
        for identifier in runningIdentifiers where !["succeeded", "failed", "skipped"].contains(featureStates[identifier] ?? "") {
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
        let result = appManagementBlocked ? "需要App管理授权" : (workerReportedStopped ? "已停止" : (exitStatus == 0 && failed == 0 ? "已完成" : "任务失败"))
        let percentage = completionPercentage(completed: succeeded + failed, total: runningIdentifiers.count)
        let skippedDescription = skipped > 0 ? "，未执行 \(skipped)" : ""
        executionLabel?.stringValue = "\(result)：成功 \(succeeded)，失败 \(failed)\(skippedDescription)；退出码 \(exitStatus)；进度 \(percentage)；\(completedTimingTitle)总用时 \(formattedElapsedTime(completedElapsed))"
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
                let action = activeWorkerAction ?? lastWorkerAction ?? managementAction
                text = action == "cleanup" ? "清理中…" : (action == "uninstall" ? "卸载中…" : "安装中…")
                color = .systemBlue
            case "succeeded":
                let action = activeWorkerAction ?? lastWorkerAction ?? managementAction
                text = action == "cleanup" ? "已清理" : (action == "uninstall" ? "已卸载" : "✅ 安装成功")
                color = .systemGreen
            case "skipped":
                text = "未执行"
                color = .secondaryLabelColor
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
        defer {
            localizeInterface()
        }
        if isRunning {
            let completed = runningIdentifiers.filter { ["succeeded", "failed"].contains(featureStates[$0] ?? "") }.count
            let elapsed = executionTiming.startedAt.map { max(0, ProcessInfo.processInfo.systemUptime - $0) } ?? executionTiming.elapsed
            let percentage = completionPercentage(completed: completed, total: runningIdentifiers.count)
            if stopRequested && activeWorkerAction == "install" {
                executionLabel?.stringValue = "正在完成当前功能，随后停止；安装用时 \(formattedElapsedTime(elapsed))"
                return
            }
            executionLabel?.stringValue = "\(executionActionTitle)中；已处理 \(completed) / \(runningIdentifiers.count) 项（\(percentage)，按完成项计数）；\(timingTitle)用时 \(formattedElapsedTime(elapsed))"
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
        lastWorkerAction = nil
        clearAllClicked()
    }

    private var installLocationDescription: String {
        return installLocation == "applications"
            ? "联合 App：Jobs自定义右键菜单.app；位置：/Applications/Jobs自定义右键菜单.app（安装成功后可清理构建产物）"
            : "当前目标：构建目录（原有方式；清理构建产物会影响功能）。"
    }

    private var isCleanupOptionAvailable: Bool {
        return managerPath != nil && installLocation == "applications" && managementAction == "install"
    }

    /// 清理只适用于成功安装到应用程序的操作，离开该组合即撤回勾选。
    func refreshCleanupBuildProductsOption() {
        if !isCleanupOptionAvailable {
            cleanupBuildProducts = false
        }
        cleanupBuildProductsButton?.state = cleanupBuildProducts ? .on : .off
        cleanupBuildProductsButton?.isHidden = !isCleanupOptionAvailable
        cleanupBuildProductsButton?.isEnabled = isCleanupOptionAvailable && !isRunning
        let standaloneAvailable = managerPath != nil && installLocation == "applications"
        cleanupNowButton?.isHidden = !standaloneAvailable
        cleanupNowButton?.isEnabled = standaloneAvailable && !isRunning && !checkedIdentifiers().isEmpty
        cleanupNowButton?.layer?.opacity = cleanupNowButton?.isEnabled == true ? 1 : 0.55
        privacySettingsButton?.isHidden = !appManagementBlocked
        privacySettingsButton?.isEnabled = appManagementBlocked && !isRunning
        if let location = installLocationButton, let cleanupNow = cleanupNowButton,
           let cleanupButton = cleanupBuildProductsButton {
            cleanupNow.setFrameOrigin(NSPoint(x: isCleanupOptionAvailable ? cleanupButton.frame.maxX + installControlGap : location.frame.maxX + installControlGap,
                                              y: cleanupNow.frame.minY))
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
        let canStop = isRunning && activeWorkerAction == "install"
        installButton?.title = canStop ? (stopRequested ? "停止中…" : "停止安装") : actionTitle
        installButton?.isEnabled = canStop ? !stopRequested : (checkedCount > 0 && !isRunning)
        clearButton?.isEnabled = checkedCount > 0 && !isRunning
        selectAllButton?.isEnabled = checkedCount < checkboxes.count && !isRunning
        actionControl?.isEnabled = !isRunning
        installLocationButton?.isEnabled = !isRunning
        refreshCleanupBuildProductsOption()
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
// MARK: - Panel preferences

/// 总面板与独立包共用偏好；测试可注入独立 suite，不改用户设置。
final class ManagerPanelPreferences {

    static let shared = ManagerPanelPreferences()
    static let domain = "com.jobs.finderextensions.managementpanel.preferences"
    static let themes = ["system", "dark", "light"]
    static let languages = ["system", "zh-Hans", "zh-Hant", "en"]
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

    var resolvedLanguage: String {
        return language == "system" ? Self.resolveLanguage(systemLanguages().first ?? "en") : language
    }

    static func resolveLanguage(_ identifier: String) -> String {
        let parts = identifier.lowercased().replacingOccurrences(of: "_", with: "-").split(separator: "-").map(String.init)
        guard parts.first == "zh" else {
            return "en"
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
            return language == "en" ? entry.english : Self.traditional(entry.source)
        }
        for entry in Self.translations where entry.expression != nil {
            guard let match = entry.expression?.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)) else {
                continue
            }
            var result = language == "en" ? entry.english : Self.traditional(entry.source)
            for (index, token) in entry.tokens.enumerated() {
                let argument = (source as NSString).substring(with: match.range(at: index + 1))
                // 插值默认当数据；只有固定动作名可作为界面短语翻译，路径原样保留。
                let value = Self.translations.first(where: { $0.tokens.isEmpty && $0.source == argument }).map {
                    language == "en" ? $0.english : Self.traditional($0.source)
                } ?? argument
                result = result.replacingOccurrences(of: token, with: value)
            }
            return result
        }
        return language == "zh-Hant" ? Self.traditional(source) : source
    }

    func variants(_ source: String) -> [String] {
        return [source, text(source, language: "zh-Hant"), text(source, language: "en")]
    }

    private static let translationTable = """
    主题|Theme
    语言|Language
    跟随系统|Follow system
    黑夜|Dark
    白天|Light
    Jobs Finder 扩展管理|Jobs Finder Extension Manager
    管理 Finder 右键功能|Manage Finder context menu
    关闭管理器|Close Manager
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
    已选 {0} / {1} 项；空选不能执行，切换操作会清空勾选。|Selected {0} / {1}. Select at least one. Changing action clears selection.
    已选 {0} / {1}|Selected {0} / {1}
    {0}：全选|{0}: select all
    {0}：全不选|{0}: clear all
    等待中|Waiting
    清理中…|Cleaning…
    卸载中…|Uninstalling…
    安装中…|Installing…
    已清理|Cleaned
    已卸载|Uninstalled
    ✅ 安装成功|✅ Installed
    未执行|Skipped
    失败，见日志|Failed: see log
    已选择|Selected
    未选择|Not selected
    需要App管理授权|App Management permission required
    已停止|Stopped
    已完成|Completed
    任务失败|Task failed
    {0}中；已处理 {1} / {2} 项（{3}，按完成项计数）；{4}用时 {5}|{0}: processed {1} / {2} ({3}, completed items); {4} time {5}
    {0}就绪；{1}用时 {2}|{0} ready; {1} time {2}
    正在完成当前功能，随后停止；安装用时 {0}|Finishing the current feature, then stopping; install time {0}
    {0}：成功 {1}，失败 {2}，未执行 {3}；退出码 {4}；进度 {5}；{6}总用时 {7}|{0}: {1} succeeded, {2} failed, {3} skipped; exit {4}; {5}; {6} time {7}
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
    新建文件|Create file
    运行授权|Grant run permission
    解除运行授权|Revoke run permission
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
    func fitLocalizedControl(_ control: NSControl) {
        if let segmented = control as? NSSegmentedControl {
            for index in 0..<segmented.segmentCount {
                let font = segmented.font ?? NSFont.systemFont(ofSize: 13)
                let width = preferences.variants(segmented.label(forSegment: index) ?? "").map {
                    ($0 as NSString).size(withAttributes: [.font: font]).width
                }.max() ?? 0
                segmented.setWidth(ceil(width) + 24, forSegment: index)
            }
            segmented.sizeToFit()
            return
        }
        let source = (control as? NSButton)?.title ?? control.stringValue
        var size = NSSize.zero
        for value in preferences.variants(source) {
            if let button = control as? NSButton {
                button.title = value
            } else {
                control.stringValue = value
            }
            control.sizeToFit()
            size.width = max(size.width, control.frame.width)
            size.height = max(size.height, control.frame.height)
        }
        if let button = control as? NSButton {
            button.title = source
        } else {
            control.stringValue = source
        }
        control.setFrameSize(size)
    }

    func makePreferencesRow() -> NSView {
        let row = NSView()
        let themeLabel = NSTextField(labelWithString: "主题")
        let languageLabel = NSTextField(labelWithString: "语言")
        let theme = NSPopUpButton(frame: .zero, pullsDown: false)
        let language = NSPopUpButton(frame: .zero, pullsDown: false)
        for (value, title) in zip(ManagerPanelPreferences.themes, ["跟随系统", "黑夜", "白天"]) {
            theme.addItem(withTitle: title)
            theme.lastItem?.representedObject = value
        }
        for (value, title) in zip(ManagerPanelPreferences.languages, ["跟随系统", "简体中文", "繁體中文", "English"]) {
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
        var x: CGFloat = 0
        for control in [themeLabel, theme, languageLabel, language] {
            control.font = .systemFont(ofSize: 12)
            if let popup = control as? NSPopUpButton {
                popup.controlSize = .small
                popup.setFrameSize(NSSize(width: 124, height: 24))
            } else {
                fitLocalizedControl(control)
            }
            control.setFrameOrigin(NSPoint(x: x, y: (24 - control.frame.height) / 2))
            row.addSubview(control)
            x += control.frame.width + (control === theme ? 16 : 8)
        }
        row.setFrameSize(NSSize(width: x - 8, height: 24))
        return row
    }

    /// 标题和偏好共用顶行；空间不足时仅多留一行，工具区始终贴齐内容右边缘。
    func layoutPreferencesHeader() {
        guard let window, let content = window.contentView, let header = headerView,
              let title = headerTitleLabel, let toolbar = preferencesToolbar,
              let split = logSplitView else {
            return
        }
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
        // 已追加文本也使用语义颜色；主题切换不会清空日志或改变选择范围。
        if let text = logTextView, let storage = text.textStorage {
            storage.addAttribute(.foregroundColor, value: NSColor.textColor, range: NSRange(location: 0, length: storage.length))
            text.backgroundColor = .textBackgroundColor
            text.textColor = .textColor
        }
        window?.contentView?.needsDisplay = true
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
            if !["zh-Hans", "zh-Hant", "en"].contains(language ?? "") {
                item.title = localizedValue(item.title, object: item, property: "title")
            }
            if let submenu = item.submenu {
                localizeMenu(submenu)
            }
        }
    }

    func localizeView(_ view: NSView) {
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
                button.attributedTitle = NSAttributedString(string: title, attributes: source.length > 0 ? source.attributes(at: 0, effectiveRange: nil) : [.foregroundColor: NSColor.white])
            } else {
                button.title = title
            }
        } else if let field = view as? NSTextField {
            let attributes = field.attributedStringValue
            let title = localizedValue(field.stringValue, object: field, property: "text")
            field.attributedStringValue = NSAttributedString(string: title, attributes: attributes.length > 0 ? attributes.attributes(at: 0, effectiveRange: nil) : [:])
        } else if let segmented = view as? NSSegmentedControl {
            for index in 0..<segmented.segmentCount {
                segmented.setLabel(localizedValue(segmented.label(forSegment: index) ?? "", object: segmented, property: "segment\(index)"), forSegment: index)
            }
        }
        if let box = view as? NSBox {
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
    }
}
