//
//  FinderSync.swift
//  JobsPermanentDeleterFinderSync
//
//  Created by Jobs on 2026年11月18日，星期三.
//

import AppKit
import FinderSync

final class FinderSync: FIFinderSync {

    private var nextTag = 0
    private var requests: [Int: PermanentDeleteRequest] = [:]

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
        do {
            let title = PermanentDeleteLocalization.text("menu")
            guard let request = PermanentDeleteRequest(urls: urls),
                  nextTag < Int.max else {
                menu.byAddItem(NSMenuItem.make(title: title, enabled: false))
                return menu
            }
            nextTag += 1
            requests[nextTag] = request
            // Retain a bounded set of immutable right-click snapshots; never query a later selection.
            if requests.count > 128, let oldest = requests.keys.min() {
                requests.removeValue(forKey: oldest)
            }
            menu.byAddItem(NSMenuItem.make(title: title, action: #selector(deleteSelected(_:)), target: self)
                .byTag(nextTag))
        }
        return menu
    }

    @objc private func deleteSelected(_ sender: NSMenuItem) {
        guard let request = requests.removeValue(forKey: sender.tag),
              let url = request.url,
              let host = PermanentDeleteHost.applicationURL(forExtension: Bundle.main.bundleURL) else {
            NSAlert.make()
                .byMessageText(PermanentDeleteLocalization.text("failureTitle"))
                .byInformativeText(PermanentDeleteLocalization.text("expired"))
                .byAddButton(PermanentDeleteLocalization.text("ok"))
                .runModal()
            return
        }
        NSWorkspace.shared.byOpenURLs([url], withApplicationAt: host, configuration: NSWorkspace.OpenConfiguration.make()) { _, error in
            guard let error else {
                return
            }
            DispatchQueue.main.async {
                NSAlert.make()
                    .byMessageText(PermanentDeleteLocalization.text("failureTitle"))
                    .byInformativeText(error.localizedDescription)
                    .byAddButton(PermanentDeleteLocalization.text("ok"))
                    .runModal()
            }
        }
    }
}
