//
//  FinderSync.swift
//  JobsGitRemoteFinderSync
//
//  Created by Jobs on 2026年6月27日，星期六.
//

import AppKit
import FinderSync

final class FinderSync: FIFinderSync {
    private let resolver = GitRemoteResolver()
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
        let urls = candidateURLs()
        writeLog("menu kind=\(menuKind.rawValue), candidates=\(urls.map(\.path).joined(separator: " | "))")
        guard menuKind == .contextualMenuForItems, urls.count == 1 else { return nil }

        let menu = NSMenu(title: "")
        let openItem = NSMenuItem(title: "打开 Git 远程地址", action: #selector(openGitRemoteURL(_:)), keyEquivalent: "")
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
        let urls = candidateURLs()
        var messages: [String] = []
        writeLog("action candidates=\(urls.map(\.path).joined(separator: " | "))")

        for url in urls {
            let didStartAccessing = url.startAccessingSecurityScopedResource()
            defer {
                if didStartAccessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            do {
                let webURL = try resolver.webURL(from: url)
                writeLog("open \(webURL.absoluteString)")
                NSWorkspace.shared.open(webURL)
                return
            } catch {
                writeLog("failed \(url.path): \(error.localizedDescription)")
                messages.append(error.localizedDescription)
            }
        }

        showFailureAlert(messages: messages)
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
