import AppKit
import FinderSync

final class FinderSync: FIFinderSync {
    override init() {
        super.init()
        FIFinderSyncController.default().directoryURLs = [URL(fileURLWithPath: "/", isDirectory: true)]
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        guard let url = candidateURL(for: menuKind) else { return nil }
        let menu = NSMenu(title: "")
        for action in ProjectMenuAction.visible(at: url, enabled: ProjectMenuConfiguration.enabledFeatures()) {
            let item = NSMenuItem(title: action.title, action: selector(for: action, kind: menuKind), keyEquivalent: "")
            item.target = self
            menu.addItem(item)
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
        default: return nil
        }
    }

    private func selector(for action: ProjectMenuAction, kind: FIMenuKind) -> Selector {
        let selected = kind == .contextualMenuForItems
        switch action {
        case .androidStudio: return selected ? #selector(androidSelected(_:)) : #selector(androidContainer(_:))
        case .vscode: return selected ? #selector(vscodeSelected(_:)) : #selector(vscodeContainer(_:))
        case .xcode: return selected ? #selector(xcodeSelected(_:)) : #selector(xcodeContainer(_:))
        case .gitPull: return selected ? #selector(pullSelected(_:)) : #selector(pullContainer(_:))
        case .gitRemote: return selected ? #selector(remoteSelected(_:)) : #selector(remoteContainer(_:))
        case .gitRemoteCopy: return selected ? #selector(copySelected(_:)) : #selector(copyContainer(_:))
        }
    }

    // 每项使用独立 selector；Finder 转发时不依赖 tag / representedObject。
    @objc private func androidSelected(_ sender: NSMenuItem) { perform(.androidStudio, .contextualMenuForItems) }
    @objc private func androidContainer(_ sender: NSMenuItem) { perform(.androidStudio, .contextualMenuForContainer) }
    @objc private func vscodeSelected(_ sender: NSMenuItem) { perform(.vscode, .contextualMenuForItems) }
    @objc private func vscodeContainer(_ sender: NSMenuItem) { perform(.vscode, .contextualMenuForContainer) }
    @objc private func xcodeSelected(_ sender: NSMenuItem) { perform(.xcode, .contextualMenuForItems) }
    @objc private func xcodeContainer(_ sender: NSMenuItem) { perform(.xcode, .contextualMenuForContainer) }
    @objc private func pullSelected(_ sender: NSMenuItem) { perform(.gitPull, .contextualMenuForItems) }
    @objc private func pullContainer(_ sender: NSMenuItem) { perform(.gitPull, .contextualMenuForContainer) }
    @objc private func remoteSelected(_ sender: NSMenuItem) { perform(.gitRemote, .contextualMenuForItems) }
    @objc private func remoteContainer(_ sender: NSMenuItem) { perform(.gitRemote, .contextualMenuForContainer) }
    @objc private func copySelected(_ sender: NSMenuItem) { perform(.gitRemoteCopy, .contextualMenuForItems) }
    @objc private func copyContainer(_ sender: NSMenuItem) { perform(.gitRemoteCopy, .contextualMenuForContainer) }

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
