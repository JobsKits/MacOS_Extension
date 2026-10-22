//
//  FinderSync.swift
//  JobsFlutterPackagerFinderSync
//
//  Created by Jobs on 2026年10月22日，星期四.
//

import AppKit
import FinderSync

final class FinderSync: FIFinderSync {
    private let validator = FlutterProjectValidator()

    override init() {
        super.init()
        FIFinderSyncController.default().byDirectoryURLs([URL(fileURLWithPath: "/", isDirectory: true)])
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        guard let projectURL = candidateURL(for: menuKind),
              validator.isFlutterProject(at: projectURL) else {
            return nil
        }
        let action = menuKind == .contextualMenuForItems ? #selector(packageSelectedProject(_:)) : #selector(packageContainerProject(_:))
        let item = NSMenuItem.make(title: "Flutter打包", action: action, keyEquivalent: "") {
            $0.byTarget(self)
        }
        return NSMenu.make(title: "").byAddItem(item)
    }

    private func candidateURL(for menuKind: FIMenuKind) -> URL? {
        let controller = FIFinderSyncController.default()
        return FlutterPackagingMenuContext.candidateURL(
            isItems: menuKind == .contextualMenuForItems,
            isContainer: menuKind == .contextualMenuForContainer,
            targetedURL: controller.targetedURL(),
            selectedURLs: controller.selectedItemURLs()
        )
    }

    @objc private func packageSelectedProject(_ sender: NSMenuItem) {
        packageFlutter(for: .contextualMenuForItems)
    }

    @objc private func packageContainerProject(_ sender: NSMenuItem) {
        packageFlutter(for: .contextualMenuForContainer)
    }

    private func packageFlutter(for menuKind: FIMenuKind) {
        // Finder 转发菜单动作时重新读取上下文，避免菜单展示后项目被移动或替换。
        guard let projectURL = candidateURL(for: menuKind),
              validator.isFlutterProject(at: projectURL) else {
            showFailure("当前文件夹不再是可识别的 Flutter 项目，请关闭菜单后重新右键。")
            return
        }
        guard let requestURL = FlutterPackagingRequest.url(for: projectURL) else {
            showFailure("无法创建 Flutter 打包请求，请重新选择项目。")
            return
        }
        NSLog("JobsFlutterPackagerFinderSync: 请求宿主处理 %@", projectURL.path)
        if !NSWorkspace.shared.open(requestURL) {
            showFailure("无法打开宿主，请重新安装 JobsFlutterPackager Finder 扩展。")
        }
    }

    private func showFailure(_ message: String) {
        NSLog("JobsFlutterPackagerFinderSync: %@", message)
        let alert = NSAlert.jobsMake {
            $0.byAlertStyle(.warning)
                .byMessageText("Flutter 打包未启动")
                .byInformativeText(message)
                .byAddButton("好")
        }
        alert.runModal()
    }
}
