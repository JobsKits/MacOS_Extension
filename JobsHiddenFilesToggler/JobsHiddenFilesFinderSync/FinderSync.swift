//
//  FinderSync.swift
//  JobsHiddenFilesFinderSync
//
//  Created by Jobs on 2026年10月23日，星期五.
//

import AppKit
import FinderSync

final class FinderSync: FIFinderSync {
    private let preferences = FinderHiddenFilesPreferences()

    override init() {
        super.init()
        // 根目录监控覆盖真实桌面、普通文件夹和已挂载卷；只在 container 回调加入菜单。
        FIFinderSyncController.default()
            .byDirectoryURLs([URL(fileURLWithPath: "/", isDirectory: true)])
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        guard allowsMenu(for: menuKind) else {
            return nil
        }
        var title = "⚠️ 隐藏文件状态不可用"
        var isEnabled = false
        do {
            title = try nextActionTitle()
            isEnabled = true
        } catch {
            NSLog("JobsHiddenFilesFinderSync: %@", error.localizedDescription)
        }
        let menu = NSMenu.make(title: "")
            .byAutoenablesItems(false)
        let item = NSMenuItem.make(title: title, action: #selector(toggleHiddenFiles(_:)), keyEquivalent: "") {
            $0.byTarget(self)
                .byEnabled(isEnabled)
        }
        menu.byAddItem(item)
        return menu
    }

    private func nextActionTitle() throws -> String {
        let showsHiddenFiles = try HiddenFilesToggleService.booleanValue(preferences.read())
        return showsHiddenFiles ? "🙈 隐藏文件" : "👁️ 显示文件"
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
        do {
            _ = try nextActionTitle()
        } catch {
            showFailure("无法读取当前隐藏文件状态，请关闭菜单后重试。\n\(error.localizedDescription)")
            return
        }
        if !NSWorkspace.shared.open(HiddenFilesRequest.canonicalURL) {
            showFailure("无法打开后台宿主，请重新安装 JobsHiddenFilesToggler 扩展。")
        }
    }

    private func showFailure(_ message: String) {
        NSLog("JobsHiddenFilesFinderSync: %@", message)
        NSAlert.jobsMake {
            $0.byAlertStyle(.warning)
                .byMessageText("隐藏文件切换未启动")
                .byInformativeText(message)
                .byAddButton("好")
        }.runModal()
    }
}

/// 独立 Finder 工程的 AppKit 创建与配置在本地工厂层承接。
extension NSMenu {
    static func make(title: String) -> NSMenu {
        return NSMenu(title: title)
    }

    @discardableResult
    func byAutoenablesItems(_ value: Bool) -> Self {
        autoenablesItems = value
        return self
    }

    @discardableResult
    func byAddItem(_ item: NSMenuItem) -> Self {
        addItem(item)
        return self
    }
}

extension NSMenuItem {
    static func make(title: String, action: Selector, keyEquivalent: String, configure: (NSMenuItem) -> Void) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        configure(item)
        return item
    }

    @discardableResult
    func byTarget(_ value: AnyObject) -> Self {
        target = value
        return self
    }

    @discardableResult
    func byEnabled(_ value: Bool) -> Self {
        isEnabled = value
        return self
    }
}

extension NSAlert {
    static func jobsMake(_ configure: (NSAlert) -> Void) -> NSAlert {
        let alert = NSAlert()
        configure(alert)
        return alert
    }

    @discardableResult
    func byAlertStyle(_ value: NSAlert.Style) -> Self {
        alertStyle = value
        return self
    }

    @discardableResult
    func byMessageText(_ value: String) -> Self {
        messageText = value
        return self
    }

    @discardableResult
    func byInformativeText(_ value: String) -> Self {
        informativeText = value
        return self
    }

    @discardableResult
    func byAddButton(_ title: String) -> Self {
        addButton(withTitle: title)
        return self
    }
}

extension FIFinderSyncController {
    @discardableResult
    func byDirectoryURLs(_ value: Set<URL>) -> Self {
        directoryURLs = value
        return self
    }
}
