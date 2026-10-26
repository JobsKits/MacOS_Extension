//
//  FinderSync.swift
//  JobsFlutterCodegenFinderSync
//
//  Created by Jobs on 2026年10月22日，星期四.
//

import AppKit
import FinderSync
import Darwin

final class FinderSync: FIFinderSync {
    private let validator = FlutterProjectValidator()

    override init() {
        super.init()
        FIFinderSyncController.default().directoryURLs = [URL(fileURLWithPath: "/", isDirectory: true)]
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        guard menuKind == .contextualMenuForItems || menuKind == .contextualMenuForContainer,
              let projectURL = candidateURL(for: menuKind),
              validator.isFlutterProject(at: projectURL) else {
            return nil
        }
        let menu = NSMenu(title: "")
        let action = menuKind == .contextualMenuForItems ? #selector(generateSelectedProject(_:)) : #selector(generateContainerProject(_:))
        let item = NSMenuItem(title: "⚙️ Flutter 自动化生产代码", action: action, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        return menu
    }

    private func candidateURL(for menuKind: FIMenuKind) -> URL? {
        let controller = FIFinderSyncController.default()
        if menuKind == .contextualMenuForItems {
            guard let items = controller.selectedItemURLs(), items.count == 1 else {
                return nil
            }
            return items.first
        }
        guard let targetURL = controller.targetedURL(), targetURL.isFileURL,
              !FinderDesktopMenuPolicy.isDesktopContainer(targetURL) else {
            return nil
        }
        return targetURL
    }

    @objc private func generateSelectedProject(_ sender: NSMenuItem) {
        generateFlutter(for: .contextualMenuForItems)
    }

    @objc private func generateContainerProject(_ sender: NSMenuItem) {
        generateFlutter(for: .contextualMenuForContainer)
    }

    private func generateFlutter(for menuKind: FIMenuKind) {
        // Finder 转发菜单动作时不依赖 representedObject，重新查询本次菜单上下文。
        guard let projectURL = candidateURL(for: menuKind),
              validator.isFlutterProject(at: projectURL) else {
            showFailure("当前菜单上下文已失效，或文件夹不再是可识别的 Flutter 项目，请关闭菜单后重新右键。")
            return
        }
        guard let requestURL = FlutterCodegenRequest.url(for: projectURL) else {
            showFailure("无法创建 Flutter 自动化生产代码请求，请重新选择项目。")
            return
        }
        NSLog("JobsFlutterCodegenFinderSync: 请求宿主处理 %@", projectURL.path)
        if !NSWorkspace.shared.open(requestURL) {
            showFailure("无法打开宿主，请先运行 JobsFlutterCodegen.app；仍失败时重新安装此扩展。")
        }
    }

    private func showFailure(_ message: String) {
        NSLog("JobsFlutterCodegenFinderSync: %@", message)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Flutter 自动化生产代码未启动"
        alert.informativeText = message
        alert.addButton(withTitle: "好")
        alert.runModal()
    }
}

// 独立工程各自携带同一策略；只屏蔽真实桌面容器，不影响选中的项目或同名目录。
private enum FinderDesktopMenuPolicy {
    static var desktopURLs: [URL] {
        var directories = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)
        // 沙盒中的 Foundation Home 可能重定向，使用用户目录服务识别真实桌面。
        if let home = userHomeDirectoryURL() {
            directories.append(home.appendingPathComponent("Desktop", isDirectory: true))
        }
        return directories
    }

    static func isDesktopContainer(_ url: URL, desktopURLs: [URL] = Self.desktopURLs) -> Bool {
        guard url.isFileURL else {
            return false
        }
        let candidatePath = url.standardizedFileURL.resolvingSymlinksInPath().path
        return desktopURLs.contains { desktopURL in
            desktopURL.isFileURL
                && desktopURL.standardizedFileURL.resolvingSymlinksInPath().path == candidatePath
        }
    }

    private static func userHomeDirectoryURL() -> URL? {
        var bufferSize = max(16_384, Int(sysconf(_SC_GETPW_R_SIZE_MAX)))
        while bufferSize <= 1_048_576 {
            var account = passwd()
            var result: UnsafeMutablePointer<passwd>?
            var buffer = [CChar](repeating: 0, count: bufferSize)
            let lookup = buffer.withUnsafeMutableBufferPointer { storage -> (status: Int32, home: String?) in
                let status = getpwuid_r(getuid(), &account, storage.baseAddress, storage.count, &result)
                guard status == 0, let home = result?.pointee.pw_dir else {
                    return (status, nil)
                }
                return (status, String(cString: home))
            }
            if lookup.status == 0 {
                guard let home = lookup.home, home.hasPrefix("/") else {
                    return nil
                }
                return URL(fileURLWithPath: home, isDirectory: true)
            }
            guard lookup.status == ERANGE else {
                return nil
            }
            bufferSize *= 2
        }
        return nil
    }

}
