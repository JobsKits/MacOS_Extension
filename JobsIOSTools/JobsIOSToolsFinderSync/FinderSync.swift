//
//  FinderSync.swift
//  JobsIOSToolsFinderSync
//
//  Created by Jobs on 2026年10月23日，星期五.
//

import AppKit
import FinderSync

final class FinderSync: FIFinderSync {
    private let validator = IOSProjectValidator()

    override init() {
        super.init()
        FIFinderSyncController.default().byDirectoryURLs([URL(fileURLWithPath: "/", isDirectory: true)])
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        guard menuKind == .contextualMenuForItems || menuKind == .contextualMenuForContainer,
              let candidate = candidateURL(for: menuKind), validator.isIOSProject(at: candidate) else {
            return nil
        }
        let enabled = IOSFeatureConfiguration.enabledFeatures()
        let actions = IOSToolsAction.allCases.filter { enabled.contains($0) && validator.supports($0, at: candidate) }
        guard !actions.isEmpty else {
            return nil
        }
        let menu = NSMenu.make(title: "")
        let tools = NSMenu.make(title: "🧑‍💻 iOS / CocoaPods 辅助工具")
        let group = NSMenuItem.make(title: tools.title, action: nil, keyEquivalent: "") {
            $0.bySubmenu(tools)
        }
        menu.byAddItem(group)
        for action in actions {
            let item = NSMenuItem.make(title: action.title, action: #selector(performAction(_:)), keyEquivalent: "") {
                $0.byTarget(self)
            }
            // tag 只传固定动作和菜单种类，路径在点击时重新读取。
            item.tag = IOSToolsAction.allCases.firstIndex(of: action)! * 2 + (menuKind == .contextualMenuForItems ? 1 : 0)
            tools.byAddItem(item)
        }
        return menu
    }

    private func candidateURL(for kind: FIMenuKind) -> URL? {
        let controller = FIFinderSyncController.default()
        if kind == .contextualMenuForItems {
            guard let urls = controller.selectedItemURLs(), urls.count == 1 else {
                return nil
            }
            return urls.first
        }
        return controller.targetedURL()
    }

    @objc private func performAction(_ sender: NSMenuItem) {
        let index = sender.tag / 2
        guard IOSToolsAction.allCases.indices.contains(index) else {
            return
        }
        let action = IOSToolsAction.allCases[index]
        let kind: FIMenuKind = sender.tag % 2 == 1 ? .contextualMenuForItems : .contextualMenuForContainer
        guard IOSFeatureConfiguration.enabledFeatures().contains(action),
              let project = candidateURL(for: kind), validator.supports(action, at: project),
              let request = IOSToolsRequest.url(for: project, action: action), NSWorkspace.shared.open(request) else {
            NSAlert.jobsMake {
                $0.byAlertStyle(.warning)
                    .byMessageText("iOS 辅助工具未启动")
                    .byInformativeText("当前项目或启用配置已变化，请关闭菜单后重新右键；仍失败时重新安装扩展。")
                    .byAddButton("好")
            }.runModal()
            return
        }
    }
}
