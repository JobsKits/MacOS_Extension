//
//  FinderSync.swift
//  JobsEnvironmentUpdaterFinderSync
//
//  Created by Jobs on 2026年11月17日，星期二.
//

import AppKit
import FinderSync

final class FinderSync: FIFinderSync {

    private lazy var orderedDesktopMenu = OrderedDesktopMenuCoordinator(extensionURL: Bundle.main.bundleURL)

    override init() {
        super.init()
        // 与现有桌面工具使用同一观察根，菜单仍由下方桌面白名单限制。
        FIFinderSyncController.default().byUpdateDirectoryURLs([URL(fileURLWithPath: "/", isDirectory: true)])
        recordDiagnostic("monitoring filesystem root; desktop filtering enabled")
    }

    override func beginObservingDirectory(at url: URL) {
        let isDesktop = EnvironmentUpdateContext.candidateURL(isContainer: true, targetedURL: url, selectedURLs: nil) != nil
        recordDiagnostic("observation desktopMatch=\(isDesktop)")
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        let coordinated = orderedDesktopMenu.menu(
            isContainer: menuKind == .contextualMenuForContainer,
            targetedURL: FIFinderSyncController.default().targetedURL(),
            actionTarget: self
        )
        if coordinated.handled {
            return coordinated.menu
        }

        let target = FIFinderSyncController.default().targetedURL()
        let desktop = EnvironmentUpdateContext.candidateURL(
            isContainer: menuKind == .contextualMenuForContainer,
            targetedURL: target,
            selectedURLs: nil
        )
        recordDiagnostic("menu kind=\(menuKind.rawValue) targetPresent=\(target != nil) desktopMatch=\(desktop != nil)")
        guard desktop != nil else {
            return nil
        }
        return NSMenu.makeUpdateMenu(target: self, action: #selector(launchUpdate(_:)))
    }

    // Finder 将菜单 selector 派发给扩展主对象，再由协调器核验原始 tag 快照。
    @objc func performOrderedAction(_ sender: NSMenuItem) {
        orderedDesktopMenu.performOrderedAction(sender)
    }

    private func desktopURL() -> URL? {
        return EnvironmentUpdateContext.candidateURL(
            isContainer: true,
            targetedURL: FIFinderSyncController.default().targetedURL(),
            selectedURLs: nil
        )
    }

    // 仅保存本进程最近一次回调状态，不记录文件名，也不让诊断失败影响菜单。
    private func recordDiagnostic(_ event: String) {
        NSLog("JobsEnvironmentUpdater %@", event)
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("JobsEnvironmentUpdater-menu-\(ProcessInfo.processInfo.processIdentifier).log")
        try? event.write(to: file, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }

    @objc private func launchUpdate(_ sender: NSMenuItem) {
        guard desktopURL() != nil,
              let request = EnvironmentUpdateRequest().url,
              let host = EnvironmentUpdateHost.applicationURL(forExtension: Bundle.main.bundleURL) else {
            NSAlert.showEnvironmentUpdateFailure("桌面上下文或宿主位置已变化，请重新右键或更新本功能。")
            return
        }
        NSWorkspace.shared.byOpenEnvironmentUpdate(request, application: host) { _, error in
            guard let error else {
                return
            }
            DispatchQueue.main.async {
                NSAlert.showEnvironmentUpdateFailure(error.localizedDescription)
            }
        }
    }
}

private extension FIFinderSyncController {

    @discardableResult
    func byUpdateDirectoryURLs(_ value: Set<URL>) -> Self {
        directoryURLs = value
        return self
    }
}

private extension NSMenu {

    static func makeUpdateMenu(target: AnyObject, action: Selector) -> NSMenu {
        let menu = NSMenu(title: "")
        let item = NSMenuItem(title: "🔄 更新开发环境（update）", action: action, keyEquivalent: "")
        item.target = target
        menu.addItem(item)
        return menu
    }
}
