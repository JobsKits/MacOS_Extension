//
//  FinderSync.swift
//  JobsIPAResignerFinderSync
//
//  Created by Jobs on 2026年10月23日，星期五.
//

import AppKit
import FinderSync

final class FinderSync: FIFinderSync {
    private let validator = IPAResignValidator()

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
        let item = NSMenuItem.make(title: "IPA 免编译重签", action: #selector(resignSelectedFile(_:)), keyEquivalent: "") {
            $0.byTarget(self)
        }
        menu.addItem(item)
        return menu
    }

    private func selectedFile() -> URL? {
        return validator.selectedFile(from: FIFinderSyncController.default().selectedItemURLs())
    }

    @objc private func resignSelectedFile(_ sender: NSMenuItem) {
        // 点击时重新读取 Finder 上下文，拒绝菜单打开后改变为目录或多选的目标。
        guard let fileURL = selectedFile(),
              let requestURL = IPAResignRequest.url(for: fileURL) else {
            showFailure("请重新右键单个普通 .ipa 文件；目录、符号链接和多选均不支持 IPA 免编译重签。")
            return
        }
        guard NSWorkspace.shared.open(requestURL) else {
            showFailure("无法打开IPA 免编译重签宿主，请重新安装此扩展后重试。")
            return
        }
    }

    private func showFailure(_ message: String) {
        NSLog("JobsIPAResignerFinderSync: %@", message)
        NSAlert.jobsMake {
            $0.byAlertStyle(.warning)
                .byMessageText("IPA 免编译重签未启动")
                .byInformativeText(message)
                .byAddButton("好")
        }.runModal()
    }
}
