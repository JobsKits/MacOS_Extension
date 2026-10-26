//
//  FinderSync.swift
//  JobsFlutterSdkInspectorFinderSync
//
//  Created by Jobs on 2026年10月21日，星期二.
//

import AppKit
import FinderSync

final class FinderSync: FIFinderSync {
    private let validator = FlutterProjectValidator()

    override init() {
        super.init()
        FIFinderSyncController.default().directoryURLs = [URL(fileURLWithPath: "/", isDirectory: true)]
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        guard menuKind == .contextualMenuForItems || menuKind == .contextualMenuForContainer,
              let projectURL = candidateURL(for: menuKind),
              validator.isFlutterProject(at: projectURL) else {
            return nil
        }
        let menu = NSMenu(title: "")
        let action = menuKind == .contextualMenuForItems ? #selector(inspectSelectedProject(_:)) : #selector(inspectContainerProject(_:))
        let item = NSMenuItem(title: "🔎 查看当前 Flutter SDK 版本", action: action, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        return menu
    }

    private func candidateURL(for menuKind: FIMenuKind) -> URL? {
        let controller = FIFinderSyncController.default()
        if menuKind == .contextualMenuForItems {
            guard let items = controller.selectedItemURLs(), items.count == 1 else {
                return nil
            }
            return items.first
        }
        guard let targetURL = controller.targetedURL(), targetURL.isFileURL,
              !FinderDesktopMenuPolicy.isDesktopContainer(targetURL) else {
            return nil
        }
        return targetURL
    }

    @objc private func inspectSelectedProject(_ sender: NSMenuItem) {
        inspectFlutter(for: .contextualMenuForItems)
    }

    @objc private func inspectContainerProject(_ sender: NSMenuItem) {
        inspectFlutter(for: .contextualMenuForContainer)
    }

    private func inspectFlutter(for menuKind: FIMenuKind) {
        // Finder 转发菜单动作时不依赖 representedObject，重新查询本次菜单上下文。
        guard let projectURL = candidateURL(for: menuKind),
              validator.isFlutterProject(at: projectURL) else {
            showFailure("当前菜单上下文已失效，或文件夹不再是可识别的 Flutter 项目，请关闭菜单后重新右键。")
            return
        }
        guard let requestURL = FlutterInspectorRequest.url(for: projectURL) else {
            showFailure("无法创建 Flutter SDK 版本查询请求，请重新选择项目。")
            return
        }
        NSLog("JobsFlutterSdkInspectorFinderSync: 请求宿主处理 %@", projectURL.path)
        if !NSWorkspace.shared.open(requestURL) {
            showFailure("无法打开宿主，请先运行 JobsFlutterSdkInspector.app；仍失败时重新安装此扩展。")
        }
    }

    private func showFailure(_ message: String) {
        NSLog("JobsFlutterSdkInspectorFinderSync: %@", message)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Flutter SDK 版本查询未启动"
        alert.informativeText = message
        alert.addButton(withTitle: "好")
        alert.runModal()
    }
}

// 独立工程各自携带同一策略；只屏蔽真实桌面容器，不影响选中的项目或同名目录。
private enum FinderDesktopMenuPolicy {
    static var desktopURLs: [URL] {
        var directories = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)
        // Finder 扩展运行在沙盒内，额外从用户目录服务解析真实 Home。
        if let homePath = NSHomeDirectoryForUser(NSUserName()) {
            let desktop = URL(fileURLWithPath: homePath, isDirectory: true)
                .appendingPathComponent("Desktop", isDirectory: true)
            directories.append(desktop)
        }
        return directories
    }

    static func isDesktopContainer(_ url: URL, desktopURLs: [URL] = Self.desktopURLs) -> Bool {
        guard url.isFileURL else {
            return false
        }
        let candidatePath = url.standardizedFileURL.resolvingSymlinksInPath().path
        return desktopURLs.contains { desktopURL in
            desktopURL.isFileURL
                && desktopURL.standardizedFileURL.resolvingSymlinksInPath().path == candidatePath
        }
    }
}
