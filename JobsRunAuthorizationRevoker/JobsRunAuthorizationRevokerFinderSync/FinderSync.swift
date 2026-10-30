//
//  FinderSync.swift
//  JobsRunAuthorizationRevokerFinderSync
//
//  Created by Jobs on 2026年10月24日，星期六.
//

import AppKit
import FinderSync

final class FinderSync: FIFinderSync {
    private let validator = RunRevocationValidator()

    override init() {
        super.init()
        FIFinderSyncController.default()
            .byDirectoryURLs([URL(fileURLWithPath: "/", isDirectory: true)])
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        guard menuKind == .contextualMenuForItems,
              let fileURL = selectedFile() else {
            return nil
        }
        let menu = NSMenu.make(title: "")
            .byAutoenablesItems(false)
        let item = NSMenuItem.make(title: "🔓 解除运行授权", action: #selector(revokeSelectedFile(_:)), keyEquivalent: "") {
            $0.byTarget(self)
                .byEnabled(validator.hasExecutionPermission(at: fileURL))
        }
        menu.byAddItem(item)
        return menu
    }

    private func selectedFile() -> URL? {
        return validator.selectedFile(from: FIFinderSyncController.default().selectedItemURLs())
    }

    @objc private func revokeSelectedFile(_ sender: NSMenuItem) {
        // 点击时重新读取 Finder 上下文，拒绝菜单打开后改变为目录或多选的目标。
        guard let fileURL = selectedFile(),
              validator.hasExecutionPermission(at: fileURL),
              let requestURL = RunRevocationRequest.url(for: fileURL) else {
            showFailure("请重新右键单个可执行格式文件并确认当前执行权限；普通文档、文件夹、应用包、符号链接和多选均不支持解除运行授权。")
            return
        }
        guard NSWorkspace.shared.open(requestURL) else {
            showFailure("无法打开解除运行授权宿主，请重新安装此扩展后重试。")
            return
        }
    }

    private func showFailure(_ message: String) {
        NSLog("JobsRunAuthorizationRevokerFinderSync: %@", message)
        NSAlert.jobsMake {
            $0.byAlertStyle(.warning)
                .byMessageText("解除运行授权未启动")
                .byInformativeText(message)
                .byAddButton("好")
        }.runModal()
    }
}
