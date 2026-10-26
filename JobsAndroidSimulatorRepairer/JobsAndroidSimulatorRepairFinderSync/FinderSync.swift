//
//  FinderSync.swift
//  JobsAndroidSimulatorRepairFinderSync
//
//  Created by Jobs on 2026年10月23日，星期五.
//

import AppKit
import FinderSync

final class FinderSync: FIFinderSync {
    override init() {
        super.init()
        // Finder 的真实桌面不会可靠地匹配沙盒中的 Desktop 别名；监控根目录，菜单另行严格筛选桌面。
        let observedDirectories = Set([URL(fileURLWithPath: "/", isDirectory: true)] + AndroidSimulatorRepairMenuContext.desktopURLs)
        FIFinderSyncController.default().directoryURLs = observedDirectories
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        guard menuKind == .contextualMenuForContainer,
              candidateURL(for: menuKind) != nil else {
            return nil
        }
        let menu = NSMenu(title: "")
        let item = NSMenuItem(title: "🩺 Android 模拟器检测与修复", action: #selector(repairFromContainer(_:)), keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        return menu
    }

    private func candidateURL(for menuKind: FIMenuKind) -> URL? {
        let controller = FIFinderSyncController.default()
        return AndroidSimulatorRepairMenuContext.candidateURL(
            isContainer: menuKind == .contextualMenuForContainer,
            targetedURL: controller.targetedURL(),
            selectedURLs: nil
        )
    }

    @objc private func repairFromContainer(_ sender: NSMenuItem) {
        // 点击时继续要求桌面空白上下文，不能从已失效菜单转入普通目录。
        guard candidateURL(for: .contextualMenuForContainer) != nil else {
            showFailure("当前菜单不再属于桌面空白处，请关闭菜单后在桌面重新右键。")
            return
        }
        NSLog("JobsAndroidSimulatorRepairFinderSync: 请求宿主Android 模拟器检测与修复。")
        if !NSWorkspace.shared.open(AndroidSimulatorRepairRequest.canonicalURL) {
            showFailure("无法打开后台宿主，请重新安装 JobsAndroidSimulatorRepairer 扩展。")
        }
    }

    private func showFailure(_ message: String) {
        NSLog("JobsAndroidSimulatorRepairFinderSync: %@", message)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Android 模拟器检测与修复未启动"
        alert.informativeText = message
        alert.addButton(withTitle: "好")
        alert.runModal()
    }
}
