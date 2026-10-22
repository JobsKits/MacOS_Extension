//
//  FinderSync.swift
//  JobsRunAuthorizerFinderSync
//
//  Created by Jobs on 2026年10月22日，星期四.
//

import AppKit
import FinderSync

final class FinderSync: FIFinderSync {
    private let validator = RunAuthorizationValidator()

    override init() {
        super.init()
        FIFinderSyncController.default()
            .byDirectoryURLs([URL(fileURLWithPath: "/", isDirectory: true)])
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        guard menuKind == .contextualMenuForItems,
              selectedFile() != nil else {
            return nil
        }
        let menu = NSMenu.make(title: "")
        let item = NSMenuItem.make(title: "运行授权", action: #selector(authorizeSelectedFile(_:)), keyEquivalent: "") {
            $0.byTarget(self)
        }
        menu.addItem(item)
        return menu
    }

    private func selectedFile() -> URL? {
        return validator.selectedFile(from: FIFinderSyncController.default().selectedItemURLs())
    }

    @objc private func authorizeSelectedFile(_ sender: NSMenuItem) {
        // 点击时重新读取 Finder 上下文，拒绝菜单打开后改变为目录或多选的目标。
        guard let fileURL = selectedFile(),
              let requestURL = RunAuthorizationRequest.url(for: fileURL) else {
            showFailure("请重新右键单个普通文件；文件夹、应用包、符号链接和多选均不支持运行授权。")
            return
        }
        guard NSWorkspace.shared.open(requestURL) else {
            showFailure("无法打开运行授权宿主，请重新安装此扩展后重试。")
            return
        }
    }

    private func showFailure(_ message: String) {
        NSLog("JobsRunAuthorizerFinderSync: %@", message)
        NSAlert.jobsMake {
            $0.byAlertStyle(.warning)
                .byMessageText("运行授权未启动")
                .byInformativeText(message)
                .byAddButton("好")
        }.runModal()
    }
}
