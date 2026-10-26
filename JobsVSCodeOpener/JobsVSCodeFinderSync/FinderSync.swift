//
//  FinderSync.swift
//  JobsVSCodeFinderSync
//
//  Created by Jobs on 2026年10月18日，星期日.
//

import AppKit
import FinderSync

final class FinderSync: FIFinderSync {
    override init() {
        super.init()
        FIFinderSyncController.default().directoryURLs = [URL(fileURLWithPath: "/", isDirectory: true)]
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        guard menuKind == .contextualMenuForItems || menuKind == .contextualMenuForContainer,
              let selectedURL = candidateURL(for: menuKind),
              !ProjectOpener.isXcodeProject(at: selectedURL) else {
            return nil
        }

        let menu = NSMenu(title: "")
        let action = menuKind == .contextualMenuForItems ? #selector(openSelectedProject(_:)) : #selector(openContainerProject(_:))
        let item = NSMenuItem(title: "📝 用 VSCode 打开项目", action: action, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        return menu
    }
}

private extension FinderSync {
    func candidateURL(for menuKind: FIMenuKind) -> URL? {
        let controller = FIFinderSyncController.default()
        if menuKind == .contextualMenuForItems {
            guard let selectedURLs = controller.selectedItemURLs(), selectedURLs.count == 1,
                  let selectedURL = selectedURLs.first, selectedURL.isFileURL else {
                return nil
            }
            return selectedURL.standardizedFileURL
        }

        guard let targetURL = controller.targetedURL(), targetURL.isFileURL,
              !FinderDesktopMenuPolicy.isDesktopContainer(targetURL) else {
            return nil
        }
        return targetURL.standardizedFileURL
    }

    @objc func openSelectedProject(_ sender: NSMenuItem) {
        openProject(for: .contextualMenuForItems)
    }

    @objc func openContainerProject(_ sender: NSMenuItem) {
        openProject(for: .contextualMenuForContainer)
    }

    func openProject(for menuKind: FIMenuKind) {
        // Finder 转发菜单动作时不保留 representedObject，点击时重新查询对应上下文。
        guard let selectedURL = candidateURL(for: menuKind) else {
            showFailure("当前菜单上下文已失效，请关闭菜单后重新选择本地文件或文件夹。")
            return
        }
        guard !ProjectOpener.isXcodeProject(at: selectedURL) else {
            showFailure("当前目录是 Xcode 项目，请使用“用 Xcode 打开项目”。")
            return
        }
        NSLog("JobsVSCodeFinderSync: request host path=%@", selectedURL.path)
        handOffToHost(selectedURL)
    }

    func showFailure(_ message: String) {
        NSLog("JobsVSCodeFinderSync: %@", message)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "VSCode 打开请求未发送"
        alert.informativeText = message
        alert.addButton(withTitle: "好")
        alert.runModal()
    }

    /// 沙盒扩展进程调用 LaunchServices 启动外部 App 可能静默失败，
    /// 因此菜单点击只把路径交给宿主 App，由宿主完成查找、打开与错误提示。
    func handOffToHost(_ selectedURL: URL) {
        let path = selectedURL.path
        guard let requestURL = ProjectRequest.url(forPath: path) else {
            NSLog("JobsVSCodeFinderSync: encode failed path=%@", path)
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        NSWorkspace.shared.open(requestURL, configuration: configuration) { _, error in
            guard let error else {
                NSLog("JobsVSCodeFinderSync: handoff ok path=%@", path)
                return
            }
            // 宿主尚未被 LaunchServices 登记时退而通知已在运行的宿主。
            NSLog("JobsVSCodeFinderSync: handoff failed %@", error.localizedDescription)
            DistributedNotificationCenter.default().postNotificationName(
                ProjectRequest.notificationName,
                object: ProjectRequest.distributedObject,
                userInfo: [ProjectRequest.pathUserInfoKey: path],
                deliverImmediately: true
            )
        }
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
