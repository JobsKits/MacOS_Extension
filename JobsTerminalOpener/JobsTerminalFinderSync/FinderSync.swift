//
//  FinderSync.swift
//  JobsTerminalFinderSync
//
//  Created by Jobs on 2026年6月28日，星期日.
//

import AppKit
import FinderSync

final class FinderSync: FIFinderSync {
    private let dependencyProjectValidator = DependencyProjectValidator()
    private let logURL: URL = {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        let directoryURL = baseURL.appendingPathComponent("JobsTerminalFinderSync", isDirectory: true)
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return directoryURL.appendingPathComponent("FinderSync.log")
    }()

    override init() {
        super.init()
        configureObservedDirectories()
        writeLog("FinderSync init, enabled features=\(enabledFeatures().map(\.rawValue).sorted().joined(separator: ","))")
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        let urls = candidateURLs()
        writeLog("menu kind=\(menuKind.rawValue), candidates=\(urls.map(\.path).joined(separator: " | "))")
        guard menuKind == .contextualMenuForItems || menuKind == .contextualMenuForContainer else {
            return nil
        }
        let isContainer = menuKind == .contextualMenuForContainer
        let targets = isContainer ? FIFinderSyncController.default().targetedURL().map { [$0] } ?? [] : urls
        let enabledFeatures = enabledFeatures()
        if !isContainer, targets.count > 1 {
            guard enabledFeatures.contains(.fileMerge), FileVolumeSelection.canMerge(targets) else {
                return nil
            }
            let menu = NSMenu(title: "")
            let item = NSMenuItem(title: "🧩 合并分卷", action: #selector(mergeFiles(_:)), keyEquivalent: "")
            item.target = self
            menu.addItem(item)
            return menu
        }
        guard targets.count == 1 else {
            return nil
        }

        let menu = NSMenu(title: "")
        if !isContainer, enabledFeatures.contains(.open) {
            let openItem = NSMenuItem(title: "💻 用终端打开", action: #selector(openInTerminal(_:)), keyEquivalent: "")
            openItem.target = self
            openItem.isEnabled = true
            menu.addItem(openItem)
        }

        if !isContainer, enabledFeatures.contains(.fileContent),
           dependencyProjectValidator.isFileContentTarget(at: targets[0]) {
            let viewItem = NSMenuItem(title: "📄 用终端查看文件内容", action: #selector(viewFileContent(_:)), keyEquivalent: "")
            viewItem.target = self
            menu.addItem(viewItem)
        }

        if !isContainer, enabledFeatures.contains(.fileSplit), FileVolumeSelection.canSplit(targets) {
            let item = NSMenuItem(title: "✂️ 拆分文件", action: #selector(splitFile(_:)), keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }

        let directoryURL = targets[0]
        // Flutter 根目录的此入口只清 Android / OpenHarmony，完整清理仍由 Flutter 子菜单负责。
        if enabledFeatures.contains(.cleanBuildArtifacts),
           dependencyProjectValidator.isAndroidOpenHarmonyBuildArtifactTargetFolder(at: directoryURL) {
            let action = isContainer ? #selector(cleanBuildArtifactsInContainer(_:)) : #selector(cleanBuildArtifacts(_:))
            let cleanItem = NSMenuItem(title: "🧯 清理 Android / OpenHarmony 构建产物", action: action, keyEquivalent: "")
            cleanItem.target = self
            menu.addItem(cleanItem)
        }

        if !isContainer, enabledFeatures.contains(.codeGraphBootstrap),
           dependencyProjectValidator.isCodeGraphTargetFolder(at: directoryURL) {
            let codeGraphItem = NSMenuItem(title: "🗺️ 更新代码地图（.codegraph）", action: #selector(updateCodeGraph(_:)), keyEquivalent: "")
            codeGraphItem.target = self
            codeGraphItem.isEnabled = true
            menu.addItem(codeGraphItem)
        }

        return menu.items.isEmpty ? nil : menu
    }
}

private extension FinderSync {
    func enabledFeatures() -> Set<FinderMenuFeature> {
        FinderMenuFeatureConfiguration.enabledFeatures(fallbackBundle: Bundle(for: FinderSync.self))
    }

    func configureObservedDirectories() {
        let directoryURLs: Set<URL> = [URL(fileURLWithPath: "/", isDirectory: true)]
        FIFinderSyncController.default().directoryURLs = directoryURLs
        writeLog("observed=\(directoryURLs.map(\.path).sorted().joined(separator: " | "))")
    }

    @objc func openInTerminal(_ sender: Any?) {
        performTerminalAction(.open)
    }

    @objc func viewFileContent(_ sender: Any?) {
        performTerminalAction(.fileContent)
    }

    @objc func mergeFiles(_ sender: Any?) {
        performVolumeAction(.fileMerge)
    }

    @objc func splitFile(_ sender: Any?) {
        performVolumeAction(.fileSplit)
    }

    func performVolumeAction(_ action: TerminalAction) {
        let urls = candidateURLs()
        guard action == .fileMerge ? FileVolumeSelection.canMerge(urls) : FileVolumeSelection.canSplit(urls) else {
            return
        }
        var components = URLComponents()
        components.scheme = "jobsterminalopener"
        components.host = "open"
        components.queryItems = [URLQueryItem(name: "action", value: action.rawValue)] + urls.map {
            URLQueryItem(name: "path", value: $0.path)
        }
        guard let request = components.url, NSWorkspace.shared.open(request) else {
            showFailureAlert(title: action.failureTitle, messages: ["无法传递完整文件选择，请减少分卷数量后重试。"])
            return
        }
    }

    @objc func runPodInstallInTerminal(_ sender: Any?) {
        performTerminalAction(.podInstall)
    }

    @objc func runFlutterPubGetInTerminal(_ sender: Any?) {
        performTerminalAction(.flutterPubGet)
    }

    @objc func cleanBuildArtifacts(_ sender: Any?) {
        performTerminalAction(.cleanBuildArtifacts)
    }

    @objc func cleanBuildArtifactsInContainer(_ sender: Any?) {
        let urls = FIFinderSyncController.default().targetedURL().map { [$0] } ?? []
        performTerminalAction(.cleanBuildArtifacts, urls: urls)
    }

    @objc func updateCodeGraph(_ sender: Any?) {
        performTerminalAction(.codeGraphBootstrap)
    }

    @objc func pushEmptyCommitInTerminal(_ sender: Any?) {
        performTerminalAction(.gitEmptyCommitPush)
    }

    func performTerminalAction(_ action: TerminalAction, urls: [URL]? = nil) {
        let urls = urls ?? candidateURLs()
        guard urls.count == 1 else { return }
        if action == .fileContent {
            guard urls.count == 1,
                  dependencyProjectValidator.isFileContentTarget(at: urls[0]) else {
                return
            }
        }
        if action == .cleanBuildArtifacts {
            guard urls.count == 1,
                  dependencyProjectValidator.isAndroidOpenHarmonyBuildArtifactTargetFolder(at: urls[0]) else {
                return
            }
        }
        var messages: [String] = []
        writeLog("action=\(action.rawValue), candidates=\(urls.map(\.path).joined(separator: " | "))")

        for url in urls {
            let didStartAccessing = url.startAccessingSecurityScopedResource()
            defer {
                if didStartAccessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            do {
                let requestURL = try terminalOpenRequestURL(fileURL: url, action: action)
                writeLog("request terminal open via \(requestURL.absoluteString)")
                guard NSWorkspace.shared.open(requestURL) else {
                    throw FinderSyncOpenError.requestFailed
                }
                writeLog("delegate terminal open request accepted \(url.path)")
                return
            } catch {
                writeLog("failed \(url.path): \(error.localizedDescription)")
                messages.append(error.localizedDescription)
            }
        }

        showFailureAlert(title: action.failureTitle, messages: messages)
    }

    func terminalOpenRequestURL(fileURL: URL, action: TerminalAction) throws -> URL {
        var components = URLComponents()
        components.scheme = "jobsterminalopener"
        components.host = "open"
        components.queryItems = [
            URLQueryItem(name: "path", value: fileURL.path),
            URLQueryItem(name: "action", value: action.rawValue)
        ]

        guard let requestURL = components.url else {
            throw FinderSyncOpenError.invalidRequestURL
        };return requestURL
    }

    func candidateURLs() -> [URL] {
        let controller = FIFinderSyncController.default()
        guard let selectedURLs = controller.selectedItemURLs(), !selectedURLs.isEmpty,
              selectedURLs.allSatisfy({ $0.isFileURL }) else {
            return []
        }
        return selectedURLs
    }

    func showFailureAlert(title: String, messages: [String]) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = messages.isEmpty ? "请选择一个文件或文件夹后再试。" : messages.joined(separator: "\n")
        alert.addButton(withTitle: "好")
        alert.runModal()
    }

    func writeLog(_ message: String) {
        let line = "[\(Date())] \(message)\n"
        NSLog("JobsTerminalFinderSync %@", message)

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

private enum TerminalAction: String {
    case open
    case fileContent = "file-content"
    case fileMerge = "file-merge"
    case fileSplit = "file-split"
    case podInstall = "pod-install"
    case flutterPubGet = "flutter-pub-get"
    case cleanBuildArtifacts = "clean-build-artifacts"
    case codeGraphBootstrap = "codegraph-bootstrap"
    case gitEmptyCommitPush = "git-empty-commit-push"

    var failureTitle: String {
        switch self {
        /// 普通打开终端请求失败
        case .open:
            return "用终端打开失败"
        case .fileContent:
            return "查看文件内容失败"
        /// 合并所选分卷失败。
        case .fileMerge:
            return "合并分卷失败"
        /// 拆分所选普通文件失败。
        case .fileSplit:
            return "拆分文件失败"
        /// 在目标文件夹执行 pod install 请求失败
        case .podInstall:
            return "执行 pod install 失败"
        /// 在目标文件夹执行 flutter pub get 请求失败
        case .flutterPubGet:
            return "执行 flutter pub get 失败"
        /// 清理当前工程构建产物请求失败
        case .cleanBuildArtifacts:
            return "清理构建产物失败"
        /// 更新目标文件夹代码地图请求失败
        case .codeGraphBootstrap:
            return "更新代码地图失败"
        /// 在当前文件夹创建空白 Commit 并 Push 请求失败
        case .gitEmptyCommitPush:
            return "空白 Commit 并 Push 失败"
        }
    }
}

private enum FinderSyncOpenError: LocalizedError {
    case invalidRequestURL
    case requestFailed

    var errorDescription: String? {
        switch self {
        /// 无法创建合法的宿主 App 请求地址
        case .invalidRequestURL:
            return "创建终端操作请求失败"
        /// 系统没有接受唤起宿主 App 的请求
        case .requestFailed:
            return "无法唤起 JobsTerminalOpener 宿主 App"
        }
    }
}
