//
//  FinderSync.swift
//  JobsFileVisibilityFinderSync
//
//  Created by Jobs on 2026年11月18日，星期三.
//

import AppKit
import FinderSync

final class FinderSync: FIFinderSync {

    private var nextTag = 0
    private var requests: [Int: FileVisibilityRequest] = [:]

    override init() {
        super.init()
        FIFinderSyncController.default().byDirectoryURLs([URL(fileURLWithPath: "/", isDirectory: true)])
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        let urls: [URL]
        switch menuKind {
        /// Finder supplies the actual selected files and folders.
        case .contextualMenuForItems:
            urls = FIFinderSyncController.default().selectedItemURLs() ?? []
        /// The sidebar's targeted URL is the actual folder.
        case .contextualMenuForSidebar:
            urls = FIFinderSyncController.default().targetedURL().map { [$0] } ?? []
        /// Background and virtual locations do not represent selected objects.
        default:
            return nil
        }
        guard !urls.isEmpty else {
            return nil
        }
        let menu = NSMenu.make()
        for hidden in [true, false] {
            let title = FileVisibilityLocalization.text(hidden ? "hide" : "show")
            guard let request = FileVisibilityRequest(urls: urls, hidden: hidden),
                  nextTag < Int.max else {
                menu.byAddItem(NSMenuItem.make(title: title, enabled: false))
                continue
            }
            nextTag += 1
            requests[nextTag] = request
            // Retain a bounded set of immutable right-click snapshots; never query a later selection.
            if requests.count > 128, let oldest = requests.keys.min() {
                requests.removeValue(forKey: oldest)
            }
            menu.byAddItem(NSMenuItem.make(title: title, action: #selector(changeVisibility(_:)), target: self)
                .byTag(nextTag))
        }
        return menu
    }

    @objc private func changeVisibility(_ sender: NSMenuItem) {
        guard let request = requests.removeValue(forKey: sender.tag),
              let url = request.url,
              let host = FileVisibilityHost.applicationURL(forExtension: Bundle.main.bundleURL) else {
            NSAlert.make()
                .byMessageText(FileVisibilityLocalization.text("failureTitle"))
                .byInformativeText(FileVisibilityLocalization.text("expired"))
                .byAddButton(FileVisibilityLocalization.text("ok"))
                .runModal()
            return
        }
        NSWorkspace.shared.byOpenURLs([url], withApplicationAt: host, configuration: NSWorkspace.OpenConfiguration.make()) { _, error in
            guard let error else {
                return
            }
            DispatchQueue.main.async {
                NSAlert.make()
                    .byMessageText(FileVisibilityLocalization.text("failureTitle"))
                    .byInformativeText(error.localizedDescription)
                    .byAddButton(FileVisibilityLocalization.text("ok"))
                    .runModal()
            }
        }
    }
}
