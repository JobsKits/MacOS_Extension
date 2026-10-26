//
//  FinderSync.swift
//  JobsGitRollbackFinderSync
//
//  Created by Jobs on 2026年10月26日，星期一.
//

import AppKit
import Darwin
import FinderSync

final class FinderSync: FIFinderSync {
    private let validator = GitRollbackMenuContext()

    override init() {
        super.init()
        FIFinderSyncController.default().directoryURLs = [URL(fileURLWithPath: "/", isDirectory: true)]
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        guard menuKind == .contextualMenuForItems || menuKind == .contextualMenuForContainer,
              let projectURL = candidateURL(for: menuKind),
              validator.isFolder(at: projectURL) else {
            return nil
        }
        let menu = NSMenu(title: "")
        let action = menuKind == .contextualMenuForItems ? #selector(manageSelectedProject(_:)) : #selector(manageContainerProject(_:))
        let item = NSMenuItem(title: "⏪ Git 提交回退", action: action, keyEquivalent: "")
        item.target = self
        let submenu = NSMenu(title: "🌿 Git操作")
        submenu.addItem(item)
        let group = NSMenuItem(title: "🌿 Git操作", action: nil, keyEquivalent: "")
        group.submenu = submenu
        menu.addItem(group)
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
        rollbackGit(for: .contextualMenuForItems)
    }

    @objc private func manageContainerProject(_ sender: NSMenuItem) {
        rollbackGit(for: .contextualMenuForContainer)
    }

    private func rollbackGit(for menuKind: FIMenuKind) {
        // Finder 转发菜单动作时不依赖 representedObject，重新查询本次菜单上下文。
        guard let projectURL = candidateURL(for: menuKind),
              validator.isFolder(at: projectURL) else {
            showFailure("当前菜单上下文已失效，或文件夹已移走，请关闭菜单后重新右键。")
            return
        }
        guard let requestURL = GitRollbackRequest.url(for: projectURL) else {
            showFailure("无法创建 Git 提交回退请求，请重新选择文件夹。")
            return
        }
        NSLog("JobsGitRollbackFinderSync: 请求宿主处理 %@", projectURL.path)
        if !NSWorkspace.shared.open(requestURL) {
            showFailure("无法打开宿主，请先运行 JobsGitRollback.app；仍失败时重新安装此扩展。")
        }
    }

    private func showFailure(_ message: String) {
        NSLog("JobsGitRollbackFinderSync: %@", message)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Git 提交回退未启动"
        alert.informativeText = message
        alert.addButton(withTitle: "好")
        alert.runModal()
    }
}

// 独立工程各自携带同一策略；只屏蔽真实桌面容器，不影响选中的项目或同名目录。
private enum FinderDesktopMenuPolicy {
    static var desktopURLs: [URL] {
        var directories = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)
        // Foundation 的用户目录可被沙盒重定向，passwd 返回真实 Home。
        var entry = passwd()
        var result: UnsafeMutablePointer<passwd>?
        var buffer = [CChar](repeating: 0, count: 16_384)
        let status = buffer.withUnsafeMutableBufferPointer { storage in
            getpwuid_r(getuid(), &entry, storage.baseAddress, storage.count, &result)
        }
        if status == 0, result != nil, let home = entry.pw_dir {
            let homePath = String(cString: home)
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
        let candidatePath = url.standardizedFileURL.path
        return desktopURLs.contains { desktopURL in
            desktopURL.isFileURL
                && (desktopURL.standardizedFileURL.path == candidatePath
                    || desktopURL.standardizedFileURL.resolvingSymlinksInPath().path == url.standardizedFileURL.resolvingSymlinksInPath().path)
        }
    }
}
