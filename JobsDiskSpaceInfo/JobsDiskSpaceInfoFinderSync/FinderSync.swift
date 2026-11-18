//
//  FinderSync.swift
//  JobsDiskSpaceInfoFinderSync
//
//  Created by Jobs on 2026年11月15日，星期日.
//

import AppKit
import FinderSync

final class FinderSync: FIFinderSync {

    private lazy var orderedDesktopMenu = OrderedDesktopMenuCoordinator(extensionURL: Bundle.main.bundleURL)

    override init() {
        super.init()
        FIFinderSyncController.default()
            .byDirectoryURLs([URL(fileURLWithPath: "/", isDirectory: true)])
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

        switch menuKind {
        case .contextualMenuForItems, .contextualMenuForContainer, .contextualMenuForSidebar:
            return DiskSpaceSummary.makeMenu(action: #selector(cleanDiskSpace(_:)), target: self)
        default:
            return nil
        }
    }

    // Finder 将菜单 selector 派发给扩展主对象，再由协调器核验原始 tag 快照。
    @objc func performOrderedAction(_ sender: NSMenuItem) {
        orderedDesktopMenu.performOrderedAction(sender)
    }

    @objc private func cleanDiskSpace(_ sender: NSMenuItem) {
        guard let request = DiskCleanupRequest().url,
              let app = DiskCleanupHost.applicationURL(forExtension: Bundle.main.bundleURL) else {
            NSAlert.showDiskCleanupFailure("找不到当前扩展所属的完整宿主，请安装／更新本功能。")
            return
        }
        NSWorkspace.shared.byOpenDiskCleanup(request, application: app) { _, error in
            guard let error else {
                return
            }
            DispatchQueue.main.async {
                NSAlert.showDiskCleanupFailure(error.localizedDescription)
            }
        }
    }
}

private extension FIFinderSyncController {

    @discardableResult
    func byDirectoryURLs(_ value: Set<URL>) -> Self {
        directoryURLs = value
        return self
    }
}
