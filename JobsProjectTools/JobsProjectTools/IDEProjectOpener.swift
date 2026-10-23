import AppKit

/// 宿主统一打开 IDE；路径通过 URL API 传递，不拼接 Shell 命令。
struct IDEProjectOpener {
    func open(_ action: ProjectMenuAction, at selectedURL: URL, completion: @escaping () -> Void) throws {
        if action == .xcode {
            // 沿用 Xcode 的 workspace 优先、多候选选择与系统打开流程。
            ProjectOpener().open(selectedURL)
            completion()
            return
        }
        let directory = (try selectedURL.resourceValues(forKeys: [.isDirectoryKey])).isDirectory == true
            ? selectedURL : selectedURL.deletingLastPathComponent()
        let candidates: [URL]
        let bundleID: String
        let downloadURL: URL
        switch action {
        case .androidStudio:
            bundleID = "com.google.android.studio"
            downloadURL = URL(string: "https://developer.android.com/studio")!
            candidates = [editorDirectory(directory)]
        case .vscode:
            bundleID = "com.microsoft.VSCode"
            downloadURL = URL(string: "https://code.visualstudio.com/download")!
            candidates = [editorDirectory(directory)]
        default:
            completion()
            return
        }
        guard let appURL = NSWorkspace.shared.urlsForApplications(withBundleIdentifier: bundleID).first(where: {
            guard let bundle = Bundle(url: $0), bundle.bundleIdentifier == bundleID,
                  let executable = bundle.executableURL else { return false }
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
                if let error { AppDelegate.showFailure(error.localizedDescription) }
                completion()
            }
        }
    }

    private func editorDirectory(_ url: URL) -> URL {
        ["xcodeproj", "xcworkspace"].contains(url.pathExtension.lowercased()) ? url.deletingLastPathComponent() : url
    }

}
