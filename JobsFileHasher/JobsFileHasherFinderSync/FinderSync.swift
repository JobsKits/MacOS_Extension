//
//  FinderSync.swift
//  JobsFileHasherFinderSync
//
//  Created by Jobs on 2026年11月6日，星期五.
//

import AppKit
import FinderSync

final class FinderSync: FIFinderSync {

    private var nextRequestTag = 0
    private var requests: [Int: FileHashRequest] = [:]
    private let requestLimit = 64

    override init() {
        super.init()
        FIFinderSyncController.default().byDirectoryURLs([URL(fileURLWithPath: "/", isDirectory: true)])
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        guard menuKind == .contextualMenuForItems,
              let file = FileHashTarget.singleSelection(FIFinderSyncController.default().selectedItemURLs()),
              let request = FileHashRequest(fileURL: file),
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
        return NSMenu.make().byAddItem(NSMenuItem.make(title: "🔎 查看文件指纹 Hash（SHA-256）",
                                                      action: #selector(showHash(_:)),
                                                      target: self,
                                                      tag: tag))
    }

    @objc private func showHash(_ sender: NSMenuItem) {
        // Finder 复制菜单只保留 tag，请求内容不依赖 representedObject。
        guard let request = requests.removeValue(forKey: sender.tag),
              FileHashTarget.regularFile(request.fileURL) != nil,
              let url = request.url else {
            showFailure("所选文件已失效，请重新打开右键菜单。")
            return
        }
        guard let app = FileHasherHost.applicationURL(forExtension: Bundle.main.bundleURL) else {
            showFailure("找不到当前扩展所属完整 App，请运行本功能管理入口安装 / 更新。")
            return
        }
        NSWorkspace.shared.byOpenURLs([url],
                                       withApplicationAt: app,
                                       configuration: NSWorkspace.OpenConfiguration.make()) { _, error in
            guard let error else {
                return
            }
            DispatchQueue.main.async {
                self.showFailure("无法启动文件指纹 App：\(error.localizedDescription)")
            }
        }
    }

    private func showFailure(_ details: String) {
        NSAlert.make(message: "无法查看文件指纹", details: details).runModal()
    }
}
