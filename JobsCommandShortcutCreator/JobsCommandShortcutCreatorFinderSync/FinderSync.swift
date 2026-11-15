//
//  FinderSync.swift
//  JobsCommandShortcutCreatorFinderSync
//
//  Created by Jobs on 2026年11月13日，星期五.
//

import AppKit
import FinderSync

final class FinderSync: FIFinderSync {

    private var nextRequestTag = 0
    private var requests: [Int: CommandShortcutRequest] = [:]
    private let requestLimit = 64

    override init() {
        super.init()
        FIFinderSyncController.default().byDirectoryURLs([URL(fileURLWithPath: "/",
                                                             isDirectory: true)])
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        guard let directory = selectedDirectory(for: menuKind),
              let request = CommandShortcutRequest(directoryURL: directory),
              nextRequestTag < Int.max else {
            return nil
        }
        nextRequestTag += 1
        let tag = nextRequestTag
        requests[tag] = request
        if requests.count > requestLimit,
           let oldest = requests.keys.min() {
            requests.removeValue(forKey: oldest)
        }
        return NSMenu.make()
            .byAddItem(NSMenuItem.make(title: CommandShortcutLocalization.text("menu") + "…",
                                        action: #selector(createShortcut(_:)),
                                        target: self)
                .byTag(tag))
    }

    private func selectedDirectory(for menuKind: FIMenuKind) -> URL? {
        let target: URL?
        switch menuKind {
        case .contextualMenuForItems:
            let selected = FIFinderSyncController.default().selectedItemURLs() ?? []
            guard selected.count == 1 else {
                return nil
            }
            target = selected[0]
        case .contextualMenuForSidebar:
            target = FIFinderSyncController.default().targetedURL()
        default:
            return nil
        }
        return CommandShortcutContext.directory(isContainer: true,
                                                  targetedURL: target)
    }

    @objc private func createShortcut(_ sender: NSMenuItem) {
        // Finder 复制菜单时保留 tag；使用本次右键的目录快照，不改用后来选中的目录。
        guard let request = requests.removeValue(forKey: sender.tag) else {
            showFailure(CommandShortcutLocalization.text("expired"))
            return
        }
        guard CommandShortcutContext.directory(isContainer: true,
                                                 targetedURL: request.directoryURL) != nil,
              let url = request.url else {
            showFailure(CommandShortcutLocalization.text("invalidTarget"))
            return
        }
        guard let applicationURL = CommandShortcutHost.applicationURL(forExtension: Bundle.main.bundleURL) else {
            showFailure(CommandShortcutLocalization.text("hostMissing"))
            return
        }
        NSWorkspace.shared.byOpenURLs([url],
                                       withApplicationAt: applicationURL,
                                       configuration: NSWorkspace.OpenConfiguration.make()) { _, error in
            guard let error else {
                return
            }
            DispatchQueue.main.async {
                self.showFailure(CommandShortcutLocalization.text("openFailed") + ": " + error.localizedDescription)
            }
        }
    }

    private func showFailure(_ message: String) {
        NSAlert.make()
            .byMessageText(CommandShortcutLocalization.text("failureTitle"))
            .byInformativeText(message)
            .byAlertStyle(.warning)
            .byAddButton(CommandShortcutLocalization.text("ok"))
            .runModal()
    }
}
