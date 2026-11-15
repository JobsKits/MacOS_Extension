//
//  AppDelegate.swift
//  JobsGitRemoteOpener
//
//  Created by Jobs on 2026年6月27日，星期六.
//

import AppKit

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let extensionIdentifier = "com.jobs.JobsGitRemoteOpener.FinderSyncExtension"
    private let logURL = URL(fileURLWithPath: "/tmp/JobsGitRemoteOpener.log")
    private let finderRefreshMarkerURL = URL(fileURLWithPath: "/tmp/JobsGitRemoteOpenerNeedsFinderRestart")
    private let finderRefreshDelay: TimeInterval = 2.5
    private let finderRefreshRetryDelay: TimeInterval = 1.0
    private let finderRefreshRetryLimit = 12
    private var window: NSWindow?
    private var hasReceivedOpenRequest = false
    private var didFinishLaunching = false
    private var pendingOperations = 0
    private var idleGeneration = 0
    private var recentRequests: [String: Date] = [:]

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleOpenURL(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        writeLog("applicationDidFinishLaunching begin")
        didFinishLaunching = true
        // 冷启动的 URL 先进入接收器，避免选择远程时弹出管理窗口。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self, !self.hasReceivedOpenRequest else {
                return
            }
            self.showManagementWindow()
        }
        scheduleExitIfIdle()
        writeLog("applicationDidFinishLaunching end")
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard urls.count == 1, let url = urls.first else {
            rejectOpenRequest("无法识别 Git 远程打开请求，请重新右键选择一个文件夹。")
            return
        }
        handleRequest(url)
    }

    @objc private func handleOpenURL(_ event: NSAppleEventDescriptor,
                                    withReplyEvent reply: NSAppleEventDescriptor) {
        guard let value = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: value) else {
            rejectOpenRequest("无法识别 Git 远程打开请求，请重新右键。")
            return
        }
        handleRequest(url)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication,
                                      hasVisibleWindows flag: Bool) -> Bool {
        showManagementWindow()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return pendingOperations == 0
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }
}

private extension AppDelegate {

    func showManagementWindow() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let viewController = MainViewController()
        _ = viewController.view
        writeLog("main view loaded")

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 430),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Jobs Git Remote Opener"
        window.center()
        window.contentViewController = viewController
        window.makeKeyAndOrderFront(nil)
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        scheduleFinderRefreshIfNeeded()
    }

    func handleRequest(_ url: URL) {
        hasReceivedOpenRequest = true
        guard let request = GitRemoteOpenRequest(url: url) else {
            rejectOpenRequest("当前文件夹已失效，或请求格式错误，请重新右键。")
            return
        }
        // 两种系统 URL 回调可能重复交付同一次点击，只派发一次浏览器操作。
        let now = Date()
        recentRequests = recentRequests.filter { now.timeIntervalSince($0.value) < 1 }
        let key = request.projectURL.path
        guard recentRequests[key] == nil else {
            return
        }
        recentRequests[key] = now
        pendingOperations += 1
        idleGeneration += 1
        DispatchQueue.global(qos: .userInitiated).async {
            var failure: String?
            do {
                try GitRemoteBrowserOpener().open(from: request.projectURL)
            } catch {
                failure = error.localizedDescription
            }
            let message = failure
            DispatchQueue.main.async {
                if let message {
                    self.showRequestFailure(message)
                }
                self.pendingOperations -= 1
                self.scheduleExitIfIdle()
            }
        }
    }

    func rejectOpenRequest(_ message: String) {
        hasReceivedOpenRequest = true
        showRequestFailure(message)
        scheduleExitIfIdle()
    }

    func showRequestFailure(_ message: String) {
        writeLog("remote open failed: \(message)")
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Git 远程地址未打开"
        alert.informativeText = message
        alert.addButton(withTitle: "好")
        alert.runModal()
    }

    func scheduleExitIfIdle() {
        guard didFinishLaunching, hasReceivedOpenRequest,
              pendingOperations == 0, window?.isVisible != true else {
            return
        }
        idleGeneration += 1
        let generation = idleGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self, self.pendingOperations == 0,
                  self.window?.isVisible != true, self.idleGeneration == generation else {
                return
            }
            NSApp.terminate(nil)
        }
    }

    func scheduleFinderRefreshIfNeeded() {
        guard FileManager.default.fileExists(atPath: finderRefreshMarkerURL.path) else {
            writeLog("finder refresh marker missing")
            return
        }

        writeLog("schedule Finder refresh")
        DispatchQueue.main.asyncAfter(deadline: .now() + finderRefreshDelay) { [weak self] in
            self?.refreshFinderAfterExtensionActivation(remainingAttempts: self?.finderRefreshRetryLimit ?? 0)
        }
    }

    func refreshFinderAfterExtensionActivation(remainingAttempts: Int) {
        guard FileManager.default.fileExists(atPath: finderRefreshMarkerURL.path) else {
            writeLog("finder refresh marker already consumed")
            return
        }

        _ = runPluginKit(arguments: ["-e", "use", "-i", extensionIdentifier])
        if isFinderExtensionEnabledByPluginKit() {
            writeLog("Finder extension enabled, restart Finder")
            restartFinder()
            try? FileManager.default.removeItem(at: finderRefreshMarkerURL)
            return
        }

        guard remainingAttempts > 0 else {
            writeLog("Finder extension still not enabled, keep marker")
            return
        }

        writeLog("Finder extension not enabled yet, retry remaining=\(remainingAttempts)")
        DispatchQueue.main.asyncAfter(deadline: .now() + finderRefreshRetryDelay) { [weak self] in
            self?.refreshFinderAfterExtensionActivation(remainingAttempts: remainingAttempts - 1)
        }
    }

    func isFinderExtensionEnabledByPluginKit() -> Bool {
        let result = runPluginKit(arguments: ["-m", "-p", "com.apple.FinderSync", "-A", "-v"])
        let matchedLine = result.output.components(separatedBy: .newlines).first { $0.contains(extensionIdentifier) } ?? ""
        let isEnabled = matchedLine.trimmingCharacters(in: .whitespaces).hasPrefix("+")
        writeLog("Finder extension status line=\(matchedLine), isEnabled=\(isEnabled)")
        return isEnabled
    }

    func restartFinder() {
        let result = runCommand(executablePath: "/usr/bin/killall", arguments: ["Finder"])
        writeLog("killall Finder success=\(result.didSucceed), output=\(result.output)")
    }

    func runPluginKit(arguments: [String]) -> AppCommandResult {
        runCommand(executablePath: "/usr/bin/pluginkit", arguments: arguments)
    }

    func runCommand(executablePath: String, arguments: [String]) -> AppCommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            writeLog("\(executablePath) \(arguments.joined(separator: " ")) failed: \(error.localizedDescription)")
            return AppCommandResult(didSucceed: false, output: error.localizedDescription)
        }

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8) ?? ""
        writeLog("\(executablePath) \(arguments.joined(separator: " ")) status=\(process.terminationStatus) output=\(output)")
        return AppCommandResult(didSucceed: process.terminationStatus == 0, output: output)
    }

    func writeLog(_ message: String) {
        let line = "[\(Date())] \(message)\n"
        NSLog("JobsGitRemoteOpener %@", message)

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

private struct AppCommandResult {
    let didSucceed: Bool
    let output: String
}
