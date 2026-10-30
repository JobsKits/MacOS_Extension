//
//  FinderSync.swift
//  JobsFileCreatorFinderSync
//
//  Created by Jobs on 2026年10月29日，星期四.
//

import AppKit
import FinderSync

final class FinderSync: FIFinderSync {

    private var nextRequestTag = 0
    private var requests: [Int: FileCreationRequest] = [:]
    private let requestLimit = 64

    override init() {
        super.init()
        FIFinderSyncController.default().byDirectoryURLs([URL(fileURLWithPath: "/",
                                                             isDirectory: true)])
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        guard let directory = FileCreationContext.directory(isContainer: menuKind == .contextualMenuForContainer,
                                                              targetedURL: FIFinderSyncController.default().targetedURL()),
              let request = FileCreationRequest(directoryURL: directory),
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
            .byAddItem(NSMenuItem.make(title: "📃 新建文件…",
                                        action: #selector(createFile(_:)),
                                        target: self)
                .byTag(tag))
    }

    @objc private func createFile(_ sender: NSMenuItem) {
        // Finder 跨进程复制菜单时仅保留 tag 等支持属性，请求留在扩展内按 tag 查取。
        guard let request = requests.removeValue(forKey: sender.tag) else {
            showFailure("右键菜单已失效，请重新打开右键菜单。")
            return
        }
        guard FileCreationContext.directory(isContainer: true,
                                             targetedURL: request.directoryURL) != nil,
              let url = request.url else {
            NSLog("JobsFileCreator: Finder target is no longer a valid directory")
            showFailure("目标文件夹已失效，请重新打开右键菜单。")
            return
        }
        guard let applicationURL = FileCreatorHost.applicationURL(forExtension: Bundle.main.bundleURL) else {
            showFailure("当前扩展缺少完整的新建文件 App，请重新运行本功能管理入口安装 / 更新。")
            return
        }
        // 明确指定本扩展所属 App，不依赖系统对自定义 URL scheme 的默认处理器登记。
        NSWorkspace.shared.byOpenURLs([url],
                                       withApplicationAt: applicationURL,
                                       configuration: NSWorkspace.OpenConfiguration.make()) { _, error in
            guard let error else {
                return
            }
            NSLog("JobsFileCreator: unable to open host at %@: %@", applicationURL.path, error.localizedDescription)
            DispatchQueue.main.async {
                self.showFailure("无法启动新建文件 App：\(error.localizedDescription)\n请运行本功能管理入口安装 / 更新后重试。")
            }
        }
    }

    private func showFailure(_ message: String) {
        NSAlert.make()
            .byMessageText("无法打开新建文件工具")
            .byInformativeText(message)
            .byAlertStyle(.warning)
            .byAddButton("好")
            .runModal()
    }
}
