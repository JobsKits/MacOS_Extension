//
//  FinderSync.swift
//  JobsGitRemoteFinderSync
//
//  Created by Jobs on 2026年6月27日，星期六.
//

import AppKit
import FinderSync

final class FinderSync: FIFinderSync {
    private let logURL: URL = {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        let directoryURL = baseURL.appendingPathComponent("JobsGitRemoteFinderSync", isDirectory: true)
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return directoryURL.appendingPathComponent("FinderSync.log")
    }()

    override init() {
        super.init()
        configureObservedDirectories()
        writeLog("FinderSync init")
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        let urls = menuKind == .contextualMenuForSidebar ? sidebarCandidateURLs() : candidateURLs()
        writeLog("menu kind=\(menuKind.rawValue), candidates=\(urls.map(\.path).joined(separator: " | "))")
        guard menuKind == .contextualMenuForItems || menuKind == .contextualMenuForSidebar,
              urls.count == 1 else {
            return nil
        }

        let menu = NSMenu(title: "")
        let action = menuKind == .contextualMenuForSidebar ? #selector(openGitRemoteURLFromSidebar(_:)) : #selector(openGitRemoteURL(_:))
        let openItem = NSMenuItem(title: "🌐 打开 Git 远程地址",
                                  action: action,
                                  keyEquivalent: "")
        openItem.target = self
        openItem.isEnabled = true
        menu.addItem(openItem)
        return menu
    }
}

private extension FinderSync {
    func configureObservedDirectories() {
        let directoryURLs: Set<URL> = [URL(fileURLWithPath: "/", isDirectory: true)]
        FIFinderSyncController.default().directoryURLs = directoryURLs
        writeLog("observed=\(directoryURLs.map(\.path).sorted().joined(separator: " | "))")
    }

    @objc func openGitRemoteURL(_ sender: Any?) {
        openGitRemoteURL(urls: candidateURLs())
    }

    @objc func openGitRemoteURLFromSidebar(_ sender: Any?) {
        openGitRemoteURL(urls: sidebarCandidateURLs())
    }

    func openGitRemoteURL(urls: [URL]) {
        var messages: [String] = []
        writeLog("action candidates=\(urls.map(\.path).joined(separator: " | "))")

        for url in urls {
            let didStartAccessing = url.startAccessingSecurityScopedResource()
            defer {
                if didStartAccessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            guard let requestURL = openRequestURL(for: url) else {
                messages.append("请选择真实存在的普通 Git 文件夹或仓库文件，不能使用链接、替身或应用包。")
                continue
            }
            writeLog("request host \(url.path)")
            guard NSWorkspace.shared.open(requestURL) else {
                messages.append("无法打开宿主，请先运行 JobsGitRemoteOpener.app；仍失败时重新安装此扩展。")
                continue
            }
            return
        }

        showFailureAlert(messages: messages)
    }

    // 原有单文件入口使用其父目录；不存在、链接和替身不转成其它有效目标。
    func openRequestURL(for url: URL) -> URL? {
        guard url.isFileURL,
              url.host == nil || url.host == "" || url.host?.lowercased() == "localhost",
              url.query == nil, url.fragment == nil else {
            return nil
        }
        if let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .isAliasFileKey]),
           values.isRegularFile == true,
           values.isSymbolicLink != true,
           values.isAliasFile != true {
            return GitRemoteOpenRequest.url(for: url.deletingLastPathComponent())
        }
        return GitRemoteOpenRequest.url(for: url)
    }

    func sidebarCandidateURLs() -> [URL] {
        guard let targetURL = FIFinderSyncController.default().targetedURL(),
              targetURL.isFileURL,
              targetURL.host.map({ $0.isEmpty || $0.lowercased() == "localhost" }) ?? true,
              (try? targetURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
            return []
        }
        return [targetURL.standardizedFileURL]
    }

    func candidateURLs() -> [URL] {
        let controller = FIFinderSyncController.default()
        guard let selectedURLs = controller.selectedItemURLs(),
              selectedURLs.count == 1,
              let selectedURL = selectedURLs.first,
              selectedURL.isFileURL else { return [] };return [selectedURL.standardizedFileURL]
    }

    func showFailureAlert(messages: [String]) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "没有找到可打开的 Git 远程地址"
        alert.informativeText = messages.isEmpty ? "请选择一个 Git 仓库文件或文件夹后再试。" : messages.joined(separator: "\n")
        alert.addButton(withTitle: "好")
        alert.runModal()
    }

    func writeLog(_ message: String) {
        let line = "[\(Date())] \(message)\n"
        NSLog("JobsGitRemoteFinderSync %@", message)

        if FileManager.default.fileExists(atPath: logURL.path),
           let handle = try? FileHandle(forWritingTo: logURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(line.utf8))
            return
        }

        try? Data(line.utf8).write(to: logURL)
    }
}
