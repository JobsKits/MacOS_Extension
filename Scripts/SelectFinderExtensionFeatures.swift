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
        FeatureOption(identifier: "git_remote", title: "打开 Git 远程地址"),
        FeatureOption(identifier: "git_remote_copier", title: "复制 Git 远程地址"),
        FeatureOption(identifier: "path_copier", title: "复制绝对路径"),
        FeatureOption(identifier: "run-authorize", title: "运行授权"),
        FeatureOption(identifier: "xcode_opener", title: "用 Xcode 打开项目"),
        FeatureOption(identifier: "vscode_opener", title: "用 VSCode 打开项目"),
        FeatureOption(identifier: "android_studio_opener", title: "用 Android Studio 打开项目"),
        FeatureOption(identifier: "flutter_version_manager", title: "安装/切换 Flutter SDK（FVM）"),
        FeatureOption(identifier: "flutter_sdk_version", title: "查看当前 Flutter SDK 版本"),
        FeatureOption(identifier: "git-pull", title: "拉取 Git 到最新"),
        FeatureOption(identifier: "flutter-dependency-extract", title: "提取 Flutter 第三方依赖"),
        FeatureOption(identifier: "flutter-run", title: "运行 Flutter 项目"),
        FeatureOption(identifier: "flutter-package", title: "Flutter打包"),
        FeatureOption(identifier: "flutter-doctor", title: "Flutter 项目体检"),
        FeatureOption(identifier: "flutter-codegen", title: "Flutter 自动化生产代码"),
        FeatureOption(identifier: "ios-simulator-create", title: "新建 iOS 模拟器"),
        FeatureOption(identifier: "android-simulator-create", title: "新建 Android 模拟器"),
        FeatureOption(identifier: "harmony-simulator-create", title: "新建鸿蒙模拟器"),
        FeatureOption(identifier: "git-proxy-configure", title: "配置 Git 动态代理")
    ]

    static let terminal: [FeatureOption] = [
        FeatureOption(identifier: "terminal_open", title: "用终端打开"),
        FeatureOption(identifier: "pod_install", title: "pod install"),
        FeatureOption(identifier: "flutter_pub_get", title: "在终端执行 flutter pub get"),
        FeatureOption(identifier: "codegraph_bootstrap", title: "更新代码地图（.codegraph）"),
        FeatureOption(identifier: "git_empty_commit_push", title: "在终端创建空白 Commit 并 Push")
    ]

    static let all: [FeatureOption] = independent + terminal
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
    func buildWindow() {
        let screenSize = NSScreen.main?.visibleFrame.size ?? NSSize(width: 800, height: 600)
        let usesColumns = screenSize.height < 600
        let header = NSStackView()
        header.orientation = .vertical
        header.alignment = .leading
        header.spacing = 10

        let titleLabel = NSTextField(labelWithString: "安装 Finder 右键功能")
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)

        let subtitleLabel = NSTextField(wrappingLabelWithString:
            "勾选本次要安装的右键菜单功能；可使用全选或全不选，选好后点击安装。"
        )
        subtitleLabel.font = .systemFont(ofSize: 12)
        subtitleLabel.textColor = .secondaryLabelColor

        let summaryLabel = NSTextField(labelWithString: "")
        summaryLabel.font = .systemFont(ofSize: 12, weight: .medium)
        summaryLabel.textColor = .secondaryLabelColor
        self.summaryLabel = summaryLabel

        header.addArrangedSubview(titleLabel)
        header.addArrangedSubview(subtitleLabel)
        header.addArrangedSubview(summaryLabel)

        let independentBox = makeGroupBox(title: "独立 Finder 扩展", options: FeatureOption.independent)
        let terminalBox = makeGroupBox(title: "JobsTerminalOpener 内含功能", options: FeatureOption.terminal)
        let featureList = NSStackView()
        featureList.orientation = usesColumns ? .horizontal : .vertical
        featureList.alignment = usesColumns ? .top : .leading
        featureList.spacing = 14
        featureList.addArrangedSubview(independentBox)
        featureList.addArrangedSubview(terminalBox)

        let buttonRow = makeButtonRow()

        let container = NSView()
        for view in [header, featureList, buttonRow] {
            container.addSubview(view)
            view.translatesAutoresizingMaskIntoConstraints = false
        }

        // 全部选项固定显示；较矮屏幕改用两列，避免裁掉底部按钮。
        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 26),
            header.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -26),
            header.topAnchor.constraint(equalTo: container.topAnchor, constant: 22),
            subtitleLabel.widthAnchor.constraint(equalTo: header.widthAnchor),
            featureList.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            featureList.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            featureList.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 14),
            featureList.bottomAnchor.constraint(equalTo: buttonRow.topAnchor, constant: -16),
            independentBox.widthAnchor.constraint(
                equalTo: featureList.widthAnchor,
                multiplier: usesColumns ? 0.5 : 1,
                constant: usesColumns ? -7 : 0
            ),
            terminalBox.widthAnchor.constraint(equalTo: independentBox.widthAnchor),
            buttonRow.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            buttonRow.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            buttonRow.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -20)
        ])

        let contentSize = NSSize(
            width: min(usesColumns ? 900 : 560, screenSize.width - 40),
            height: min(640, screenSize.height - 72)
        )
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
        window.setContentSize(NSSize(width: contentSize.width, height: container.fittingSize.height))
        container.layoutSubtreeIfNeeded()
        window.center()
        refreshSelectionState()
    }

    func makeGroupBox(title: String, options: [FeatureOption]) -> NSBox {
        let box = NSBox()
        box.title = title
        box.titleFont = .systemFont(ofSize: 13, weight: .semibold)

        let column = NSStackView()
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 6
        for option in options {
            let checkbox = NSButton(
                title: option.title,
                target: self,
                action: #selector(selectionChanged)
            )
            checkbox.setButtonType(.switch)
            checkbox.font = .systemFont(ofSize: 13)
            checkbox.state = .on
            checkboxes.append((option, checkbox))
            column.addArrangedSubview(checkbox)
        }
        box.contentView = column
        return box
    }

    func makeButtonRow() -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10

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

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        row.addArrangedSubview(selectAllButton)
        row.addArrangedSubview(clearButton)
        row.addArrangedSubview(spacer)
        row.addArrangedSubview(cancelButton)
        row.addArrangedSubview(installButton)

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
        checkboxes
            .filter { $0.button.state == .on }
            .map { $0.option.identifier }
    }

    func refreshSelectionState() {
        let checkedCount = checkboxes.filter { $0.button.state == .on }.count
        installButton?.isEnabled = checkedCount > 0
        clearButton?.isEnabled = checkedCount > 0
        selectAllButton?.isEnabled = checkedCount < checkboxes.count
        summaryLabel?.stringValue = "已选 \(checkedCount) / \(checkboxes.count) 项；什么都不选时不能安装。"
    }
}
