//
//  FinderSync.swift
//  JobsFlutterVersionFinderSync
//
//  Created by Jobs on 2026年10月19日，星期一.
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
        let action = menuKind == .contextualMenuForItems ? #selector(manageSelectedProject(_:)) : #selector(manageContainerProject(_:))
        let item = NSMenuItem(title: "🔀 安装/切换 Flutter SDK（FVM）", action: action, keyEquivalent: "")
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

    @objc private func manageSelectedProject(_ sender: NSMenuItem) {
        manageFlutter(for: .contextualMenuForItems)
    }

    @objc private func manageContainerProject(_ sender: NSMenuItem) {
        manageFlutter(for: .contextualMenuForContainer)
    }

    private func manageFlutter(for menuKind: FIMenuKind) {
        // Finder 转发菜单动作时不依赖 representedObject，重新查询本次菜单上下文。
        guard let projectURL = candidateURL(for: menuKind),
              validator.isFlutterProject(at: projectURL) else {
            showFailure("当前菜单上下文已失效，或文件夹不再是可识别的 Flutter 项目，请关闭菜单后重新右键。")
            return
        }
        guard let requestURL = FlutterManagerRequest.url(for: projectURL) else {
            showFailure("无法创建 Flutter 版本管理请求，请重新选择项目。")
            return
        }
        NSLog("JobsFlutterVersionFinderSync: 请求宿主处理 %@", projectURL.path)
        if !NSWorkspace.shared.open(requestURL) {
            showFailure("无法打开宿主，请先运行 JobsFlutterVersionMgr.app；仍失败时重新安装此扩展。")
        }
    }

    private func showFailure(_ message: String) {
        NSLog("JobsFlutterVersionFinderSync: %@", message)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Flutter 版本管理未启动"
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
