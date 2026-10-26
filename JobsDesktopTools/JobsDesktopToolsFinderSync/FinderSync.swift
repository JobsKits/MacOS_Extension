//
//  FinderSync.swift
//  JobsDesktopToolsFinderSync
//
//  Created by Jobs on 2026年10月26日，星期一.
//

import AppKit
import FinderSync

final class FinderSync: FIFinderSync {
    var enabledFeatures: () -> Set<DesktopMenuAction> = {
        return DesktopMenuConfiguration.enabledFeatures()
    }
    var readHiddenFilesValue: () throws -> Any? = {
        return try FinderHiddenFilesPreferences().read()
    }
    override init() {
        super.init()
        FIFinderSyncController.default().byDirectoryURLs([URL(fileURLWithPath: "/", isDirectory: true)])
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        guard menuKind == .contextualMenuForContainer else {
            return nil
        }
        let actions = visibleActions()
        guard !actions.isEmpty else {
            return nil
        }
        let menu = NSMenu.make(title: "")
        for action in actions {
            if action == .hiddenFiles {
                do {
                    let visible = try HiddenFilesToggleService.booleanValue(readHiddenFilesValue())
                    menu.byAddItem(NSMenuItem.make(
                        title: visible ? "🙈 隐藏文件" : "👁️ 显示文件",
                        action: visible ? #selector(hideFiles(_:)) : #selector(showFiles(_:)),
                        target: self
                    ))
                } catch {
                    menu.byAddItem(NSMenuItem.make(title: "⚠️ 隐藏文件状态不可用", action: nil, target: self, enabled: false))
                    NSLog("JobsDesktopTools Finder preference read failed: %@", error.localizedDescription)
                }
            } else {
                menu.byAddItem(NSMenuItem.make(title: action.title, action: selector(for: action), target: self))
            }
        }
        return menu
    }

    private func visibleActions() -> [DesktopMenuAction] {
        let target = FIFinderSyncController.default().targetedURL()
        let desktop = DesktopMenuContext.candidateURL(isContainer: true, targetedURL: target, selectedURLs: nil) != nil
        let hidden = HiddenFilesMenuContext.allowsMenu(isContainer: true, targetedURL: target)
        return DesktopMenuAction.visible(enabled: enabledFeatures(), isDesktop: desktop, allowsHiddenFiles: hidden)
    }

    private func selector(for action: DesktopMenuAction) -> Selector? {
        switch action {
        /// 使用 iOS 模拟器新建动作。
        case .createIOS:
            return #selector(createIOS(_:))
        /// 使用 Android 模拟器新建动作。
        case .createAndroid:
            return #selector(createAndroid(_:))
        /// 使用 Harmony 模拟器新建动作。
        case .createHarmony:
            return #selector(createHarmony(_:))
        /// 检测和修复现有 Android 模拟器。
        case .repairAndroid:
            return #selector(repairAndroid(_:))
        /// 检测和修复现有 Harmony 模拟器。
        case .repairHarmony:
            return #selector(repairHarmony(_:))
        /// 显示或隐藏当前用户的隐藏文件。
        case .hiddenFiles:
            return nil
        }
    }

    private func perform(_ action: DesktopMenuAction, showsHiddenFiles: Bool? = nil) {
        guard visibleActions().contains(action),
              let url = DesktopMenuRequest(action: action, showsHiddenFiles: showsHiddenFiles).url else {
            DesktopAlert.show("上下文或功能选择已变化，请关闭菜单后重新右键。")
            return
        }
        guard NSWorkspace.shared.open(url) else {
            DesktopAlert.show("无法打开 JobsDesktopTools，请重新运行安装入口注册完整宿主。")
            return
        }
    }

    @objc private func createIOS(_ sender: NSMenuItem) {
        perform(.createIOS)
    }

    @objc private func createAndroid(_ sender: NSMenuItem) {
        perform(.createAndroid)
    }

    @objc private func createHarmony(_ sender: NSMenuItem) {
        perform(.createHarmony)
    }

    @objc private func repairAndroid(_ sender: NSMenuItem) {
        perform(.repairAndroid)
    }

    @objc private func repairHarmony(_ sender: NSMenuItem) {
        perform(.repairHarmony)
    }

    @objc private func showFiles(_ sender: NSMenuItem) {
        perform(.hiddenFiles, showsHiddenFiles: true)
    }

    @objc private func hideFiles(_ sender: NSMenuItem) {
        perform(.hiddenFiles, showsHiddenFiles: false)
    }
}
