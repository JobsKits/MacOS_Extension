//
//  FinderSync.swift
//  JobsHarmonySimulatorRepairFinderSync
//
//  Created by Jobs on 2026年10月24日，星期六.
//

import AppKit
import FinderSync

final class FinderSync: FIFinderSync {
    override init() {
        super.init()
        // Finder 的真实桌面不会可靠地匹配沙盒中的 Desktop 别名；监控根目录，菜单另行严格筛选桌面。
        let observedDirectories = Set([URL(fileURLWithPath: "/", isDirectory: true)] + HarmonySimulatorRepairMenuContext.desktopURLs)
        FIFinderSyncController.default().byDirectoryURLs(observedDirectories)
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        guard menuKind == .contextualMenuForContainer,
              candidateURL(for: menuKind) != nil else {
            return nil
        }
        return NSMenu.make(title: "").byAddItem(
            NSMenuItem.make(title: "🧰 Harmony 模拟器检测与修复", action: #selector(repairFromContainer(_:)), keyEquivalent: "") {
                $0.byTarget(self)
            }
        )
    }

    private func candidateURL(for menuKind: FIMenuKind) -> URL? {
        let controller = FIFinderSyncController.default()
        return HarmonySimulatorRepairMenuContext.candidateURL(
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
        NSLog("JobsHarmonySimulatorRepairFinderSync: 请求宿主Harmony 模拟器检测与修复。")
        if !NSWorkspace.shared.open(HarmonySimulatorRepairRequest.canonicalURL) {
            showFailure("无法打开后台宿主，请重新安装 JobsHarmonySimulatorRepairer 扩展。")
        }
    }

    private func showFailure(_ message: String) {
        NSLog("JobsHarmonySimulatorRepairFinderSync: %@", message)
        NSAlert.jobsMake {
            $0.byAlertStyle(.warning)
                .byMessageText("Harmony 模拟器检测与修复未启动")
                .byInformativeText(message)
                .byAddButton("好")
        }.runModal()
    }
}
