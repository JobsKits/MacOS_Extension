//
//  SelectFinderExtensionFeatures.swift
//  MacOS@Extension
//
//  Created by Jobs on 2026年10月19日，星期一.
//

import AppKit

// 运行选择窗口并把结果写到标准输出：__CANCELLED__、__NONE__ 或逗号分隔的功能标识。
let selectionController = FeatureSelectionController()
print(selectionController.runModal())
exit(0)

/// 总安装器的功能选择窗口：只返回逗号分隔的功能标识，构建、注册与启用交给安装器。
struct FeatureOption {
    let identifier: String
    let title: String

    static let independent: [FeatureOption] = [
        FeatureOption(identifier: "android_studio_opener", title: "用 Android Studio 打开项目"),
        FeatureOption(identifier: "vscode_opener", title: "用 VSCode 打开项目"),
        FeatureOption(identifier: "xcode_opener", title: "用 Xcode 打开项目"),
        FeatureOption(identifier: "git-pull", title: "拉取 Git 到最新"),
        FeatureOption(identifier: "git_remote", title: "打开 Git 远程地址"),
        FeatureOption(identifier: "git_remote_copier", title: "复制 Git 远程地址"),
        FeatureOption(identifier: "path_copier", title: "复制绝对路径"),
        FeatureOption(identifier: "run-authorize", title: "运行授权"),
        FeatureOption(identifier: "run-revoke", title: "解除运行授权"),
        FeatureOption(identifier: "ipa-resign", title: "IPA 免编译重签"),
        FeatureOption(identifier: "hidden-files-toggle", title: "显示 / 隐藏文件"),
        FeatureOption(identifier: "ios-simulator-create", title: "新建 iOS 模拟器"),
        FeatureOption(identifier: "android-simulator-create", title: "新建 Android 模拟器"),
        FeatureOption(identifier: "android-simulator-repair", title: "Android 模拟器检测与修复"),
        FeatureOption(identifier: "harmony-simulator-create", title: "新建 Harmony 模拟器"),
        FeatureOption(identifier: "harmony-simulator-repair", title: "Harmony 模拟器检测与修复"),
        FeatureOption(identifier: "git-proxy-configure", title: "配置 Git 动态代理")
    ]

    static let terminal: [FeatureOption] = [
        FeatureOption(identifier: "terminal_open", title: "用终端打开"),
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
        FeatureOption(identifier: "flutter-run", title: "从终端运行 Flutter 项目"),
        FeatureOption(identifier: "flutter-pub-get", title: "拉取 Flutter 第三方依赖"),
        FeatureOption(identifier: "flutter-extract", title: "提取 Flutter 第三方依赖"),
        FeatureOption(identifier: "flutter-sdk-version", title: "查看当前 Flutter 项目的 SDK 版本"),
        FeatureOption(identifier: "flutter-sdk-manage", title: "安装 / 切换 Flutter SDK 版本"),
        FeatureOption(identifier: "flutter-ohos-sdk-manage", title: "安装 / 切换 Flutter@OpenHarmony SDK"),
        FeatureOption(identifier: "flutter-java-manage", title: "安装 / 切换 Java 环境"),
        FeatureOption(identifier: "flutter-codegen", title: "Flutter 自动化生产代码"),
        FeatureOption(identifier: "flutter-package-ios", title: "打包 iOS"),
        FeatureOption(identifier: "flutter-package-android", title: "打包 Android"),
        FeatureOption(identifier: "flutter-package-ohos", title: "打包 OpenHarmony"),
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
            "git-pull", "git_remote", "git_remote_copier", "git-proxy-configure", "git_empty_commit_push"
        ]),
        FeatureGroup(identifier: "general", title: "文件与通用工具", identifiers: [
            "path_copier", "run-authorize", "run-revoke", "hidden-files-toggle", "terminal_open",
            "clean_build_artifacts", "codegraph_bootstrap"
        ]),
        FeatureGroup(identifier: "flutter", title: "Flutter 工具 · 子菜单功能", identifiers: FeatureOption.flutter.map { $0.identifier }),
        FeatureGroup(identifier: "ios", title: "iOS / CocoaPods 工具", identifiers:
            ["pod_install", "ios-pod-update", "ipa-resign"] + FeatureOption.ios
                .map { $0.identifier }
                .filter { $0 != "ios-pod-update" }
        ),
        FeatureGroup(identifier: "simulators", title: "模拟器工具", identifiers: [
            "ios-simulator-create", "android-simulator-create", "android-simulator-repair", "harmony-simulator-create", "harmony-simulator-repair"
        ])
    ]
}

/// 总安装器的功能选择窗口：只返回逗号分隔的功能标识，构建、注册与启用交给安装器。
final class FeatureSelectionController: NSObject, NSWindowDelegate {
    private enum Outcome {
        case selected([String])
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

    func runModal() -> String {
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        application.finishLaunching()
        buildWindow()
        if let window {
            window.makeKeyAndOrderFront(nil)
            application.activate(ignoringOtherApps: true)
            application.runModal(for: window)
            window.orderOut(nil)
        }

        switch outcome {
        /// 返回用户确认安装的功能。
        case .selected(let identifiers):
            return identifiers.isEmpty ? "__NONE__" : identifiers.joined(separator: ",")
        /// 取消和关闭窗口均不继续安装。
        case .cancelled:
            return "__CANCELLED__"
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        outcome = .cancelled
        NSApplication.shared.stopModal()
        return false
    }
}

private extension FeatureSelectionController {
    func buildWindow(screenSize: NSSize? = nil) {
        let screenSize = screenSize ?? NSScreen.main?.visibleFrame.size ?? NSSize(width: 1280, height: 800)
        let compact = screenSize.height < 700
        let header = NSView()

        let titleLabel = NSTextField(labelWithString: "安装 Finder 右键功能")
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)

        let subtitleLabel = NSTextField(labelWithString:
            "组内全选 / 全不选只影响本组；底部按钮控制全部功能。"
        )
        subtitleLabel.font = .systemFont(ofSize: 12)
        subtitleLabel.textColor = .secondaryLabelColor

        let summaryLabel = NSTextField(labelWithString: "已选 \(FeatureOption.all.count) / \(FeatureOption.all.count) 项；什么都不选时不能安装。")
        summaryLabel.font = .systemFont(ofSize: 12, weight: .medium)
        summaryLabel.textColor = .secondaryLabelColor
        self.summaryLabel = summaryLabel

        var headerHeight: CGFloat = 0
        var headerWidth: CGFloat = 0
        for label in [summaryLabel, subtitleLabel, titleLabel] {
            label.sizeToFit()
            label.setFrameOrigin(NSPoint(x: 0, y: headerHeight))
            header.addSubview(label)
            headerHeight += label.frame.height + (compact ? 6 : 10)
            headerWidth = max(headerWidth, label.frame.width)
        }
        header.setFrameSize(NSSize(width: headerWidth, height: headerHeight - (compact ? 6 : 10)))

        let boxes = FeatureGroup.all.map { makeGroupBox(group: $0, spacing: compact ? 3 : 6) }
        let verticalPadding: CGFloat = compact ? 44 : 72
        let featureList = makeFeatureList(
            boxes: boxes,
            screenSize: screenSize,
            reservedHeight: header.frame.height + 32 + verticalPadding + 32
        )
        let contentWidth = max(featureList.frame.width, headerWidth)
        let buttonRow = makeButtonRow(width: contentWidth)
        let headerSize = header.frame.size
        let buttonHeight = buttonRow.frame.height
        let contentSize = NSSize(
            width: contentWidth + 52,
            height: headerSize.height + featureList.frame.height + buttonHeight + verticalPadding
        )
        let container = NSView(frame: NSRect(origin: .zero, size: contentSize))
        for view in [header, featureList, buttonRow] {
            container.addSubview(view)
        }
        // 底栏固定；选项超出屏幕时仅滚动中间列表，避免裁掉子菜单和安装按钮。
        buttonRow.frame = NSRect(x: 26, y: compact ? 14 : 20, width: contentWidth, height: buttonHeight)
        featureList.setFrameOrigin(NSPoint(x: 26, y: buttonRow.frame.maxY + (compact ? 8 : 16)))
        header.frame = NSRect(x: 26, y: featureList.frame.maxY + (compact ? 8 : 14), width: contentWidth, height: headerSize.height)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Jobs Finder 扩展安装"
        window.contentView = container
        window.delegate = self
        self.window = window
        container.layoutSubtreeIfNeeded()
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
        let layouts = [2, 3, 1].flatMap { count in
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
        guard list.frame.height > availableHeight else {
            return list
        }
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: size.width + 16, height: availableHeight))
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = false
        scroll.drawsBackground = false
        scroll.documentView = list
        scroll.contentView.scroll(to: NSPoint(x: 0, y: size.height - availableHeight))
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
        let summary = NSTextField(labelWithString: "已选 \(group.options.count) / \(group.options.count)")
        summary.font = .systemFont(ofSize: 11)
        summary.textColor = .secondaryLabelColor
        summary.sizeToFit()
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
            checkbox.state = .on
            checkboxes.append((option, checkbox))
            checkbox.sizeToFit()
            optionButtons.append(checkbox)
            contentWidth = max(contentWidth, checkbox.frame.width)
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

        let cancelButton = NSButton(title: "取消", target: self, action: #selector(cancelClicked))
        cancelButton.bezelStyle = .rounded
        cancelButton.keyEquivalent = "\u{1b}"

        let installButton = NSButton(title: "安装", target: self, action: #selector(installClicked))
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
        return row
    }

    func styleAuxiliaryButton(_ button: NSButton) {
        button.bezelStyle = .rounded
        button.font = .systemFont(ofSize: 12, weight: .medium)
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
        guard let group = FeatureGroup.all.first(where: { $0.identifier == sender.identifier?.rawValue }) else {
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
        outcome = .selected(identifiers)
        NSApplication.shared.stopModal()
    }

    @objc func cancelClicked() {
        outcome = .cancelled
        NSApplication.shared.stopModal()
    }

    func checkedIdentifiers() -> [String] {
        let selected = Set(checkboxes
            .filter { $0.button.state == .on }
            .map { $0.option.identifier })
        return FeatureOption.all.map { $0.identifier }.filter { selected.contains($0) }
    }

    func refreshSelectionState() {
        let checkedCount = checkboxes.filter { $0.button.state == .on }.count
        installButton?.isEnabled = checkedCount > 0
        clearButton?.isEnabled = checkedCount > 0
        selectAllButton?.isEnabled = checkedCount < checkboxes.count
        summaryLabel?.stringValue = "已选 \(checkedCount) / \(checkboxes.count) 项；什么都不选时不能安装。"
        for controls in groupControls {
            let identifiers = Set(controls.group.identifiers)
            let count = checkboxes.filter { identifiers.contains($0.option.identifier) && $0.button.state == .on }.count
            controls.select.isEnabled = count < identifiers.count
            controls.clear.isEnabled = count > 0
            controls.summary.stringValue = "已选 \(count) / \(identifiers.count)"
        }
    }
}
