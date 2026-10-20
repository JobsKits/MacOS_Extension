//
//  AppDelegate.swift
//  JobsVSCodeOpener
//
//  Created by Jobs on 2026年10月18日，星期日.
//

import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let extensionIdentifier = "com.jobs.JobsVSCodeOpener.FinderSyncExtension"
    private let logURL = URL(fileURLWithPath: "/tmp/JobsVSCodeOpener.log")
    private let finderRefreshMarkerURL = URL(fileURLWithPath: "/tmp/JobsVSCodeOpenerNeedsFinderRestart")
    private let finderRefreshDelay: TimeInterval = 2.5
    private let finderRefreshRetryDelay: TimeInterval = 1.0
    private let finderRefreshRetryLimit = 12
    /// 需要用户交互时恢复常规策略，否则无窗口模式下弹窗不可见。
    private let opener = ProjectOpener(
        chooseCandidate: { candidates in
            NSApp.setActivationPolicy(.regular)
            return ProjectOpener.chooseProject(candidates)
        },
        reportFailure: { title, message in
            NSApp.setActivationPolicy(.regular)
            ProjectOpener.showFailure(title, message)
        }
    )
    // 'GURL'：kInternetEventClass 与 kAEGetURL，避免只为两个常量引入 Carbon。
    private let getURLEventClass = AEEventClass(0x4755524C)
    private let getURLEventID = AEEventID(0x4755524C)
    // '----'：AppleEvent 的直接对象关键字。
    private let directObjectKeyword = AEKeyword(0x2D2D2D2D)
    private var pendingPaths: [String] = []
    private var isDrainingPaths = false
    private var didFinishLaunching = false
    private var isWindowVisible = false
    private var window: NSWindow?

    func applicationWillFinishLaunching(_ notification: Notification) {
        writeLog("applicationWillFinishLaunching begin")
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURLEvent(_:replyEvent:)),
            forEventClass: getURLEventClass,
            andEventID: getURLEventID
        )
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleDistributedRequest(_:)),
            name: ProjectRequest.notificationName,
            object: nil
        )
        writeLog("applicationWillFinishLaunching end")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        writeLog("applicationDidFinishLaunching begin pending=\(pendingPaths.count)")
        didFinishLaunching = true
        if pendingPaths.isEmpty {
            showMainWindow()
            scheduleFinderRefreshIfNeeded()
        } else {
            // 右键菜单唤起：不出窗口、不进 Dock，处理完请求就退出。
            NSApp.setActivationPolicy(.accessory)
            drainPendingPaths()
        }
        writeLog("applicationDidFinishLaunching end")
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            guard let path = ProjectRequest.path(from: url) else {
                writeLog("ignore unsupported url=\(url.absoluteString)")
                continue
            }
            enqueue(path: path)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }
}

private extension AppDelegate {
    func showMainWindow() {
        let viewController = MainViewController()
        _ = viewController.view
        writeLog("main view loaded")

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 430),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Jobs VSCode Opener"
        window.center()
        window.contentViewController = viewController
        window.makeKeyAndOrderFront(nil)
        self.window = window
        isWindowVisible = true
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func handleGetURLEvent(_ event: NSAppleEventDescriptor, replyEvent: NSAppleEventDescriptor) {
        guard let urlString = event.paramDescriptor(forKeyword: directObjectKeyword)?.stringValue,
              let url = URL(string: urlString),
              let path = ProjectRequest.path(from: url) else {
            writeLog("ignore unsupported URL event")
            return
        }
        enqueue(path: path)
    }

    @objc func handleDistributedRequest(_ notification: Notification) {
        guard let path = notification.userInfo?[ProjectRequest.pathUserInfoKey] as? String else {
            return
        }
        enqueue(path: path)
    }

    func enqueue(path: String) {
        pendingPaths.append(path)
        // 启动途中收到的请求留给 applicationDidFinishLaunching 决定是否显示窗口。
        guard didFinishLaunching else {
            return
        }
        drainPendingPaths()
    }

    func drainPendingPaths() {
        guard !isDrainingPaths else {
            return
        }
        isDrainingPaths = true
        drainNextPath()
    }

    func drainNextPath() {
        guard let path = pendingPaths.first else {
            isDrainingPaths = false
            finishWhenHeadless()
            return
        }
        pendingPaths.removeFirst()
        writeLog("open request path=\(path)")
        opener.open(URL(fileURLWithPath: path)) { [weak self] in
            self?.drainNextPath()
        }
    }

    func finishWhenHeadless() {
        guard didFinishLaunching, !isWindowVisible else {
            return
        }
        writeLog("open request finished, terminate headless host")
        NSApp.terminate(nil)
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
        NSLog("JobsVSCodeOpener %@", message)

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
