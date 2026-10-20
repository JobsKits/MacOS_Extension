//
//  ProjectOpener.swift
//  JobsVSCodeFinderSync
//
//  Created by Jobs on 2026年10月18日，星期日.
//

import AppKit

/// LaunchServices 负责发现应用，URL API 负责传递路径，避免路径被解释为 Shell 命令。
final class ProjectOpener {
    typealias OpenDocument = (URL, URL, @escaping (Error?) -> Void) -> Void

    private let applicationURLs: () -> [URL]
    private let openDocument: OpenDocument
    private let openDownload: (URL) -> Bool
    private let chooseCandidate: ([URL]) -> URL?
    private let reportFailure: (String, String) -> Void
    private let fileManager: FileManager

    init(
        applicationURLs: @escaping () -> [URL] = {
            NSWorkspace.shared.urlsForApplications(withBundleIdentifier: "com.microsoft.VSCode")
        },
        openDocument: @escaping OpenDocument = { targetURL, applicationURL, completion in
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.open([targetURL], withApplicationAt: applicationURL, configuration: configuration) { _, error in
                completion(error)
            }
        },
        openDownload: @escaping (URL) -> Bool = {
            NSWorkspace.shared.open($0)
        },
        chooseCandidate: @escaping ([URL]) -> URL? = ProjectOpener.chooseProject,
        reportFailure: @escaping (String, String) -> Void = ProjectOpener.showFailure,
        fileManager: FileManager = .default
    ) {
        self.applicationURLs = applicationURLs
        self.openDocument = openDocument
        self.openDownload = openDownload
        self.chooseCandidate = chooseCandidate
        self.reportFailure = reportFailure
        self.fileManager = fileManager
    }

    /// completion 固定切回主线程，宿主 App 靠它决定处理完请求后是否退出。
    func open(_ selectedURL: URL, completion: (() -> Void)? = nil) {
        let finish: () -> Void = {
            DispatchQueue.main.async {
                completion?()
            }
        }
        guard !Self.isXcodeProject(at: selectedURL, fileManager: fileManager) else {
            reportFailure("请使用 Xcode 打开项目", "当前目录是 Xcode 项目，请使用 Finder 中的“用 Xcode 打开项目”。")
            finish()
            return
        }
        guard let applicationURL = usableApplicationURL(in: applicationURLs()) else {
            // 缺失或残缺安装必须终止项目打开流程，只转到官方下载页。
            let downloadURL = URL(string: "https://code.visualstudio.com/download")!
            NSLog("JobsVSCodeFinderSync: VSCode unavailable; opening official download page")
            if !openDownload(downloadURL) {
                reportFailure("没有可用的 VSCode", "无法打开默认浏览器，请手动访问：\n\(downloadURL.absoluteString)")
            }
            finish()
            return
        }

        let didStartAccessing = selectedURL.startAccessingSecurityScopedResource()
        do {
            let candidates = try projectCandidates(from: selectedURL)
            let chosenURL = candidates.count == 1 ? candidates.first : chooseCandidate(candidates)
            guard let targetURL = chosenURL, candidates.contains(targetURL) else {
                if didStartAccessing {
                    selectedURL.stopAccessingSecurityScopedResource()
                }
                finish()
                return
            }
            openDocument(targetURL, applicationURL) { [reportFailure] error in
                if didStartAccessing {
                    selectedURL.stopAccessingSecurityScopedResource()
                }
                DispatchQueue.main.async {
                    if let error {
                        reportFailure("VSCode 未能打开项目", error.localizedDescription)
                    }
                    completion?()
                }
            }
        } catch {
            if didStartAccessing {
                selectedURL.stopAccessingSecurityScopedResource()
            }
            reportFailure("无法读取项目位置", error.localizedDescription)
            finish()
        }
    }

    /// 文件按所在目录判断，文件夹只检查本层，不递归寻找 iOS 子工程。
    static func isXcodeProject(at selectedURL: URL, fileManager: FileManager = .default) -> Bool {
        guard selectedURL.isFileURL else {
            return false
        }
        let selectedURL = selectedURL.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: selectedURL.path, isDirectory: &isDirectory) else {
            return false
        }
        let directoryURL = isDirectory.boolValue ? selectedURL : selectedURL.deletingLastPathComponent()
        if XcodeProjectDetector.canOpen(directoryURL, fileManager: fileManager) {
            return true
        }
        // 后缀目录仍沿用打开器的父目录归一，防止无效包绕过父目录的 Xcode 判断。
        if ["xcworkspace", "xcodeproj"].contains(directoryURL.pathExtension.lowercased()) {
            return XcodeProjectDetector.canOpen(directoryURL.deletingLastPathComponent(), fileManager: fileManager)
        }
        return false
    }

    /// 忽略 LaunchServices 的过期注册，以及只有 App 外壳而缺失可执行文件的残缺安装。
    func usableApplicationURL(in candidates: [URL]) -> URL? {
        for candidate in candidates {
            guard candidate.isFileURL,
                  let bundle = Bundle(url: candidate),
                  bundle.bundleIdentifier == "com.microsoft.VSCode",
                  let executableURL = bundle.executableURL,
                  fileManager.isExecutableFile(atPath: executableURL.path) else {
                continue
            }
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: candidate.path, isDirectory: &isDirectory), isDirectory.boolValue,
                  fileManager.fileExists(atPath: executableURL.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
                continue
            }
            return candidate
        }
        return nil
    }

    func projectCandidates(from selectedURL: URL) throws -> [URL] {
        guard selectedURL.isFileURL else {
            throw NSError(domain: "JobsVSCodeFinderSync", code: 1, userInfo: [NSLocalizedDescriptionKey: "请选择本地文件或文件夹。"])
        }
        let selectedURL = selectedURL.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: selectedURL.path, isDirectory: &isDirectory) else {
            throw NSError(domain: "JobsVSCodeFinderSync", code: 2, userInfo: [NSLocalizedDescriptionKey: "所选文件或文件夹已不存在。"])
        }
        let directoryURL = isDirectory.boolValue ? selectedURL : selectedURL.deletingLastPathComponent()
        // Finder 将 Xcode 工程显示为文件包；编辑器应该打开它所在的项目目录。
        if ["xcworkspace", "xcodeproj"].contains(directoryURL.pathExtension.lowercased()) {
            return [directoryURL.deletingLastPathComponent()]
        }
        return [directoryURL]
    }

    static func chooseProject(_ candidates: [URL]) -> URL? {
        guard !candidates.isEmpty else {
            return nil
        }
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "选择要用 VSCode 打开的项目"
        alert.informativeText = "当前文件夹包含多个候选项目，请明确选择一个。"
        let picker = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 420, height: 28), pullsDown: false)
        picker.addItems(withTitles: candidates.map(\.lastPathComponent))
        alert.accessoryView = picker
        alert.addButton(withTitle: "打开所选项目")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn,
              candidates.indices.contains(picker.indexOfSelectedItem) else {
            return nil
        }
        return candidates[picker.indexOfSelectedItem]
    }

    static func showFailure(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "好")
        alert.runModal()
    }
}
