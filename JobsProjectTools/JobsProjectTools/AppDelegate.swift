import AppKit

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var pendingOperations = 0
    private var didFinishLaunching = false
    private var idleGeneration = 0

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(self,
            andSelector: #selector(handleOpenURL(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        didFinishLaunching = true
        scheduleExit()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls { handle(url) }
    }

    @objc private func handleOpenURL(_ event: NSAppleEventDescriptor, withReplyEvent reply: NSAppleEventDescriptor) {
        if let value = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
           let url = URL(string: value) { handle(url) }
    }

    private func handle(_ url: URL) {
        guard let request = ProjectMenuRequest(url: url),
              ProjectMenuAction.visible(at: request.fileURL, enabled: ProjectMenuConfiguration.enabledFeatures()).contains(request.action) else {
            Self.showFailure("当前菜单功能已关闭，或项目位置 / 类型已改变，请重新右键。")
            scheduleExit()
            return
        }
        pendingOperations += 1
        idleGeneration += 1
        do {
            switch request.action {
            case .androidStudio, .vscode, .xcode:
                try IDEProjectOpener().open(request.action, at: request.fileURL) { self.finish() }
            case .gitPull:
                DispatchQueue.global(qos: .userInitiated).async {
                    var failure: String?
                    do { try GitPullTerminalLauncher().launch(projectURL: request.fileURL) }
                    catch { failure = error.localizedDescription }
                    let message = failure
                    DispatchQueue.main.async {
                        if let message { Self.showFailure(message) }
                        self.finish()
                    }
                }
            case .gitRemote:
                let remote = try GitRemoteResolver().webURL(from: request.fileURL)
                guard NSWorkspace.shared.open(remote) else {
                    throw NSError(domain: "JobsProjectTools", code: 2,
                                  userInfo: [NSLocalizedDescriptionKey: "浏览器未能打开 Git 远程地址。"])
                }
                finish()
            case .gitRemoteCopy:
                let remote = try GitRemoteResolver().remoteURLString(from: request.fileURL)
                NSPasteboard.general.clearContents()
                guard NSPasteboard.general.setString(remote, forType: .string) else {
                    throw NSError(domain: "JobsProjectTools", code: 3,
                                  userInfo: [NSLocalizedDescriptionKey: "写入剪贴板失败。"])
                }
                finish()
            }
        } catch {
            Self.showFailure(error.localizedDescription)
            finish()
        }
    }

    private func finish() {
        pendingOperations -= 1
        scheduleExit()
    }

    private func scheduleExit() {
        guard didFinishLaunching, pendingOperations == 0 else { return }
        idleGeneration += 1
        let generation = idleGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            guard self.pendingOperations == 0, generation == self.idleGeneration else { return }
            NSApp.terminate(nil)
        }
    }

    static func showFailure(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "项目工具操作失败"
        alert.informativeText = message
        alert.addButton(withTitle: "好")
        alert.runModal()
    }
}
