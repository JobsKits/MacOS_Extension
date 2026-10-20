//
//  FinderSync.swift
//  JobsXcodeFinderSync
//
//  Created by Jobs on 2026年10月18日，星期日.
//

import AppKit
import FinderSync

final class FinderSync: FIFinderSync {
    private let opener = ProjectOpener()

    override init() {
        super.init()
        FIFinderSyncController.default().directoryURLs = [URL(fileURLWithPath: "/", isDirectory: true)]
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        guard menuKind == .contextualMenuForItems || menuKind == .contextualMenuForContainer,
              let selectedURL = candidateURL(for: menuKind),
              XcodeProjectDetector.canOpen(selectedURL) else {
            return nil
        }

        let menu = NSMenu(title: "")
        let action = menuKind == .contextualMenuForItems ? #selector(openSelectedProject(_:)) : #selector(openContainerProject(_:))
        let item = NSMenuItem(title: "用 Xcode 打开项目", action: action, keyEquivalent: "")
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
        // Finder 转发动作可能丢失 representedObject，点击时按原菜单上下文重新读取。
        guard let selectedURL = candidateURL(for: menuKind),
              XcodeProjectDetector.canOpen(selectedURL) else {
            return
        }
        opener.open(selectedURL)
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
