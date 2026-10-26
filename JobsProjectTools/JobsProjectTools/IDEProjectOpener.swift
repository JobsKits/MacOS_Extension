//
//  IDEProjectOpener.swift
//  JobsProjectTools
//
//  Created by Jobs on 2026年10月26日，星期一.
//

import AppKit

/// 宿主统一打开 IDE；路径通过 URL API 传递，不拼接 Shell 命令。
struct IDEProjectOpener {
    func open(_ action: ProjectMenuAction, at selectedURL: URL, completion: @escaping () -> Void) throws {
        guard ProjectMenuAction.visible(at: selectedURL, enabled: [action]).contains(action) else {
            throw NSError(domain: "JobsProjectTools", code: 4,
                          userInfo: [NSLocalizedDescriptionKey: "当前目录为空、不是此 IDE 支持的项目，或已不再是普通文件夹。请重新右键选择项目。"])
        }
        if action == .xcode {
            // 沿用 Xcode 的 workspace 优先、多候选选择与系统打开流程。
            ProjectOpener().open(selectedURL)
            completion()
            return
        }
        let directory = selectedURL
        let candidates: [URL]
        let bundleID: String
        let downloadURL: URL
        switch action {
        /// Android 原生与两种 Flutter 根目录。
        case .androidStudio:
            bundleID = "com.google.android.studio"
            downloadURL = URL(string: "https://developer.android.com/studio")!
            candidates = [directory]
        /// 非空的非 iOS 普通目录。
        case .vscode:
            bundleID = "com.microsoft.VSCode"
            downloadURL = URL(string: "https://code.visualstudio.com/download")!
            candidates = [directory]
        /// 非 IDE 动作由上层分发。
        default:
            completion()
            return
        }
        guard let appURL = NSWorkspace.shared.urlsForApplications(withBundleIdentifier: bundleID).first(where: {
            guard let bundle = Bundle(url: $0), bundle.bundleIdentifier == bundleID,
                  let executable = bundle.executableURL else {
                return false
            }
            return FileManager.default.isExecutableFile(atPath: executable.path)
        }) else {
            guard NSWorkspace.shared.open(downloadURL) else {
                throw NSError(domain: "JobsProjectTools", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "没有找到可用的 IDE，请访问：\(downloadURL.absoluteString)"])
            }
            completion()
            return
        }
        guard let target = candidates.first else {
            completion()
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open([target], withApplicationAt: appURL, configuration: configuration) { _, error in
            DispatchQueue.main.async {
                if let error {
                    AppDelegate.showFailure(error.localizedDescription)
                }
                completion()
            }
        }
    }

}
