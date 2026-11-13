//
//  FinderSync.swift
//  JobsProjectToolsFinderSync
//
//  Created by Jobs on 2026年10月24日，星期六.
//

import AppKit
import FinderSync

final class FinderSync: FIFinderSync {
    override init() {
        super.init()
        FIFinderSyncController.default().directoryURLs = [URL(fileURLWithPath: "/", isDirectory: true)]
        NSLog("JobsProjectTools Finder configuration=%@ enabled=%ld homeAlias=%@",
              ProjectMenuConfiguration.fileURL?.path ?? "unavailable",
              ProjectMenuConfiguration.enabledFeatures().count,
              NSHomeDirectoryForUser(NSUserName()) ?? "unavailable")
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        guard let url = candidateURL(for: menuKind) else { return nil }
        let menu = NSMenu(title: "")
        let gitMenu = NSMenu(title: "🌿 Git操作")
        let actions = ProjectMenuAction.visible(at: url, enabled: ProjectMenuConfiguration.enabledFeatures())
        NSLog("JobsProjectTools Finder menu target=%@ enabled=%ld visible=%ld",
              url.path, ProjectMenuConfiguration.enabledFeatures().count, actions.count)
        for action in actions {
            let item = NSMenuItem(title: action.title, action: selector(for: action, kind: menuKind), keyEquivalent: "")
            item.target = self
            item.tag = menuKind == .contextualMenuForSidebar ? 1 : 0
            if action.isGitAction {
                gitMenu.addItem(item)
            } else {
                menu.addItem(item)
            }
        }
        if !gitMenu.items.isEmpty {
            let parent = NSMenuItem(title: "🌿 Git操作", action: nil, keyEquivalent: "")
            parent.submenu = gitMenu
            menu.addItem(parent)
        }
        return menu.items.isEmpty ? nil : menu
    }

    private func candidateURL(for kind: FIMenuKind) -> URL? {
        let controller = FIFinderSyncController.default()
        switch kind {
        case .contextualMenuForItems:
            guard let urls = controller.selectedItemURLs(), urls.count == 1,
                  let url = urls.first, url.isFileURL else { return nil }
            return url.standardizedFileURL
        case .contextualMenuForContainer:
            guard let url = controller.targetedURL(), url.isFileURL,
                  !FinderDesktopMenuPolicy.isDesktopContainer(url) else { return nil }
            return url.standardizedFileURL
        /// 侧边栏只使用右键指向的真实目录，不借用主区域的选中项。
        case .contextualMenuForSidebar:
            guard let url = controller.targetedURL(), url.isFileURL,
                  (url.host == nil || url.host == "" || url.host?.lowercased() == "localhost"),
                  (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
                return nil
            }
            return url.standardizedFileURL
        default: return nil
        }
    }

    private func targetedMenuKind(for sender: NSMenuItem) -> FIMenuKind {
        return sender.tag == 1 ? .contextualMenuForSidebar : .contextualMenuForContainer
    }

    private func selector(for action: ProjectMenuAction, kind: FIMenuKind) -> Selector {
        let selected = kind == .contextualMenuForItems
        switch action {
        case .androidStudio: return selected ? #selector(androidSelected(_:)) : #selector(androidContainer(_:))
        case .vscode: return selected ? #selector(vscodeSelected(_:)) : #selector(vscodeContainer(_:))
        case .xcode: return selected ? #selector(xcodeSelected(_:)) : #selector(xcodeContainer(_:))
        case .gitSourcetree:
            return selected ? #selector(sourcetreeSelected(_:)) : #selector(sourcetreeContainer(_:))
        case .gitPull: return selected ? #selector(pullSelected(_:)) : #selector(pullContainer(_:))
        case .gitRollback:
            return selected ? #selector(rollbackSelected(_:)) : #selector(rollbackContainer(_:))
        case .gitRemote: return selected ? #selector(remoteSelected(_:)) : #selector(remoteContainer(_:))
        case .gitRemoteCopy: return selected ? #selector(copySelected(_:)) : #selector(copyContainer(_:))
        case .gitProxy: return selected ? #selector(proxySelected(_:)) : #selector(proxyContainer(_:))
        case .gitEmptyCommitPush: return selected ? #selector(commitSelected(_:)) : #selector(commitContainer(_:))
        }
    }

    // 独立 selector 保留动作；tag 只区分侧边栏与背景，路径在点击时重新读取。
    @objc private func androidSelected(_ sender: NSMenuItem) { perform(.androidStudio, .contextualMenuForItems) }
    @objc private func androidContainer(_ sender: NSMenuItem) { perform(.androidStudio, targetedMenuKind(for: sender)) }
    @objc private func vscodeSelected(_ sender: NSMenuItem) { perform(.vscode, .contextualMenuForItems) }
    @objc private func vscodeContainer(_ sender: NSMenuItem) { perform(.vscode, targetedMenuKind(for: sender)) }
    @objc private func xcodeSelected(_ sender: NSMenuItem) { perform(.xcode, .contextualMenuForItems) }
    @objc private func xcodeContainer(_ sender: NSMenuItem) { perform(.xcode, targetedMenuKind(for: sender)) }
    @objc private func sourcetreeSelected(_ sender: NSMenuItem) {
        perform(.gitSourcetree, .contextualMenuForItems)
    }
    @objc private func sourcetreeContainer(_ sender: NSMenuItem) {
        perform(.gitSourcetree, targetedMenuKind(for: sender))
    }
    @objc private func pullSelected(_ sender: NSMenuItem) { perform(.gitPull, .contextualMenuForItems) }
    @objc private func pullContainer(_ sender: NSMenuItem) { perform(.gitPull, targetedMenuKind(for: sender)) }
    @objc private func rollbackSelected(_ sender: NSMenuItem) {
        perform(.gitRollback, .contextualMenuForItems)
    }
    @objc private func rollbackContainer(_ sender: NSMenuItem) {
        perform(.gitRollback, targetedMenuKind(for: sender))
    }
    @objc private func remoteSelected(_ sender: NSMenuItem) { perform(.gitRemote, .contextualMenuForItems) }
    @objc private func remoteContainer(_ sender: NSMenuItem) { perform(.gitRemote, targetedMenuKind(for: sender)) }
    @objc private func copySelected(_ sender: NSMenuItem) { perform(.gitRemoteCopy, .contextualMenuForItems) }
    @objc private func copyContainer(_ sender: NSMenuItem) { perform(.gitRemoteCopy, targetedMenuKind(for: sender)) }
    @objc private func proxySelected(_ sender: NSMenuItem) { perform(.gitProxy, .contextualMenuForItems) }
    @objc private func proxyContainer(_ sender: NSMenuItem) { perform(.gitProxy, targetedMenuKind(for: sender)) }
    @objc private func commitSelected(_ sender: NSMenuItem) { perform(.gitEmptyCommitPush, .contextualMenuForItems) }
    @objc private func commitContainer(_ sender: NSMenuItem) { perform(.gitEmptyCommitPush, targetedMenuKind(for: sender)) }

    private func perform(_ action: ProjectMenuAction, _ kind: FIMenuKind) {
        guard let url = candidateURL(for: kind),
              ProjectMenuAction.visible(at: url, enabled: ProjectMenuConfiguration.enabledFeatures()).contains(action),
              let request = ProjectMenuRequest(action: action, fileURL: url).url else { return }
        guard NSWorkspace.shared.open(request) else {
            let alert = NSAlert()
            alert.messageText = "无法打开项目工具"
            alert.informativeText = "请重新运行 Finder 扩展安装脚本，注册 JobsProjectTools 宿主。"
            alert.runModal()
            return
        }
    }
}

private enum FinderDesktopMenuPolicy {
    static func isDesktopContainer(_ url: URL) -> Bool {
        var desktops = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)
        if let home = NSHomeDirectoryForUser(NSUserName()) {
            desktops.append(URL(fileURLWithPath: home).appendingPathComponent("Desktop"))
        }
        return desktops.contains {
            $0.standardizedFileURL.resolvingSymlinksInPath() == url.standardizedFileURL.resolvingSymlinksInPath()
        }
    }
}
