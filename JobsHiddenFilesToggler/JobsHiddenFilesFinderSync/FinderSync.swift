//
//  FinderSync.swift
//  JobsHiddenFilesFinderSync
//
//  Created by Jobs on 2026年10月23日，星期五.
//

import AppKit
import FinderSync

final class FinderSync: FIFinderSync {
    override init() {
        super.init()
        // 根目录监控覆盖真实桌面、普通文件夹和已挂载卷；只在 container 回调加入菜单。
        FIFinderSyncController.default().directoryURLs = [URL(fileURLWithPath: "/", isDirectory: true)]
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        guard allowsMenu(for: menuKind) else {
            return nil
        }
        let menu = NSMenu(title: "")
        let item = NSMenuItem(title: "👁️ 显示 / 隐藏文件", action: #selector(toggleHiddenFiles(_:)), keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        return menu
    }

    private func allowsMenu(for menuKind: FIMenuKind) -> Bool {
        return HiddenFilesMenuContext.allowsMenu(
            isContainer: menuKind == .contextualMenuForContainer,
            targetedURL: FIFinderSyncController.default().targetedURL()
        )
    }

    @objc private func toggleHiddenFiles(_ sender: NSMenuItem) {
        guard allowsMenu(for: .contextualMenuForContainer) else {
            showFailure("当前上下文已变化，请在桌面或文件夹空白处重新右键。")
            return
        }
        if !NSWorkspace.shared.open(HiddenFilesRequest.canonicalURL) {
            showFailure("无法打开后台宿主，请重新安装 JobsHiddenFilesToggler 扩展。")
        }
    }

    private func showFailure(_ message: String) {
        NSLog("JobsHiddenFilesFinderSync: %@", message)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "显示 / 隐藏文件未启动"
        alert.informativeText = message
        alert.addButton(withTitle: "好")
        alert.runModal()
    }
}
