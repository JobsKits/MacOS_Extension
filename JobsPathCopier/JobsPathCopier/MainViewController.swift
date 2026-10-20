//
//  MainViewController.swift
//  JobsPathCopier
//
//  Created by Jobs on 2026年6月28日，星期日.
//

import AppKit
import FinderSync

final class MainViewController: NSViewController {
    private let extensionIdentifier = "com.jobs.JobsPathCopier.FinderSyncExtension"
    private let extensionBundleName = "JobsPathCopyFinderSync.appex"
    private let activationRetryDelay: TimeInterval = 1.0
    private let activationRetryLimit = 8
    private let logURL = URL(fileURLWithPath: "/tmp/JobsPathCopier.log")
    private let extensionLogURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Containers/com.jobs.JobsPathCopier.FinderSyncExtension/Data/Library/Application Support/JobsPathCopyFinderSync/FinderSync.log")
    private let statusLabel = NSTextField(labelWithString: "")
    private var activationWorkItem: DispatchWorkItem?

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 680, height: 430))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildInterface()
        enableFinderExtension()
    }
}

private extension MainViewController {
    func buildInterface() {
        let titleLabel = NSTextField(labelWithString: "复制绝对路径")
        titleLabel.font = .systemFont(ofSize: 28, weight: .bold)
        titleLabel.textColor = .labelColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let detailLabel = NSTextField(wrappingLabelWithString: "运行 App 后会自动启用 Finder 扩展。右键任意一个本地文件或文件夹，即可在一级右键菜单区域看到“复制绝对路径”，点击后把当前项目的绝对路径写入系统剪贴板。")
        detailLabel.font = .systemFont(ofSize: 15)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.translatesAutoresizingMaskIntoConstraints = false

        statusLabel.font = .systemFont(ofSize: 14, weight: .medium)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        let openSettingsButton = NSButton(title: "打开扩展设置", target: self, action: #selector(openExtensionSettings))
        openSettingsButton.bezelStyle = .rounded
        openSettingsButton.translatesAutoresizingMaskIntoConstraints = false

        let enableButton = NSButton(title: "重新启用扩展", target: self, action: #selector(enableExtensionAction))
        enableButton.bezelStyle = .rounded
        enableButton.translatesAutoresizingMaskIntoConstraints = false

        let refreshButton = NSButton(title: "刷新状态", target: self, action: #selector(refreshStatusAction))
        refreshButton.bezelStyle = .rounded
        refreshButton.translatesAutoresizingMaskIntoConstraints = false

        let diagnosticButton = NSButton(title: "复制诊断日志", target: self, action: #selector(copyDiagnosticLogAction))
        diagnosticButton.bezelStyle = .rounded
        diagnosticButton.translatesAutoresizingMaskIntoConstraints = false

        let tipLabel = NSTextField(wrappingLabelWithString: "如果右键菜单未刷新，点击“重新启用扩展”，再重新打开 Finder 窗口；必要时执行 killall Finder。系统设置路径：隐私与安全性 -> 扩展 -> Finder 扩展。")
        tipLabel.font = .systemFont(ofSize: 13)
        tipLabel.textColor = .tertiaryLabelColor
        tipLabel.translatesAutoresizingMaskIntoConstraints = false

        let buttonStackView = NSStackView(views: [openSettingsButton, enableButton, refreshButton, diagnosticButton])
        buttonStackView.orientation = .horizontal
        buttonStackView.alignment = .leading
        buttonStackView.spacing = 12
        buttonStackView.translatesAutoresizingMaskIntoConstraints = false

        let stackView = NSStackView(views: [titleLabel, detailLabel, statusLabel, buttonStackView, tipLabel])
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 18
        stackView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 44),
            stackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -44),
            stackView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            detailLabel.widthAnchor.constraint(equalTo: stackView.widthAnchor),
            tipLabel.widthAnchor.constraint(equalTo: stackView.widthAnchor)
        ])
    }

    @objc func openExtensionSettings() {
        if #available(macOS 10.14, *) {
            FIFinderSyncController.showExtensionManagementInterface()
        } else if let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.extensions") {
            NSWorkspace.shared.open(settingsURL)
        }
    }

    @objc func refreshStatusAction() {
        refreshStatus()
    }

    @objc func enableExtensionAction() {
        enableFinderExtension()
    }

    @objc func copyDiagnosticLogAction() {
        let report = diagnosticReport()
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let didCopy = pasteboard.setString(report, forType: .string)
        statusLabel.stringValue = didCopy ? "当前状态：诊断日志已复制，可直接粘贴给 Codex。" : "当前状态：诊断日志复制失败。"
        writeLog("copyDiagnosticLogAction didCopy=\(didCopy), reportLength=\(report.count)")
    }

    func enableFinderExtension() {
        activationWorkItem?.cancel()
        writeLog("enableFinderExtension begin")
        let didActivate = activateBundledFinderExtension()
        refreshStatus()

        if !didActivate || !isFinderExtensionEnabledByPluginKit() {
            scheduleActivationRetry(remainingAttempts: activationRetryLimit)
        }
    }

    func activateBundledFinderExtension() -> Bool {
        guard let plugInsURL = Bundle.main.builtInPlugInsURL else {
            statusLabel.stringValue = "当前状态：没有找到 App 内置扩展目录。"
            return false
        }

        let extensionURL = plugInsURL.appendingPathComponent(extensionBundleName, isDirectory: true)
        guard FileManager.default.fileExists(atPath: extensionURL.path) else {
            statusLabel.stringValue = "当前状态：没有找到内置 Finder 扩展。"
            writeLog("extension missing: \(extensionURL.path)")
            return false
        }

        let registerResult = runPluginKit(arguments: ["-a", extensionURL.path])
        let enableResult = runPluginKit(arguments: ["-e", "use", "-i", extensionIdentifier])
        let isEnabled = isFinderExtensionEnabledByPluginKit()
        writeLog("activate result register=\(registerResult.didSucceed), enable=\(enableResult.didSucceed), isEnabled=\(isEnabled)")
        return registerResult.didSucceed && enableResult.didSucceed && isEnabled
    }

    func scheduleActivationRetry(remainingAttempts: Int) {
        guard remainingAttempts > 0 else { return }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let didActivate = self.activateBundledFinderExtension()
            self.refreshStatus()
            guard !didActivate || !self.isFinderExtensionEnabledByPluginKit() else { return }
            self.scheduleActivationRetry(remainingAttempts: remainingAttempts - 1)
        }
        activationWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + activationRetryDelay, execute: workItem)
    }

    func runPluginKit(arguments: [String]) -> PluginKitResult {
        runCommand(executablePath: "/usr/bin/pluginkit", arguments: arguments)
    }

    func runCommand(executablePath: String, arguments: [String]) -> PluginKitResult {
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
            return PluginKitResult(didSucceed: false, output: error.localizedDescription)
        }

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8) ?? ""
        writeLog("\(executablePath) \(arguments.joined(separator: " ")) status=\(process.terminationStatus) output=\(output)")
        return PluginKitResult(didSucceed: process.terminationStatus == 0, output: output)
    }

    func refreshStatus() {
        statusLabel.stringValue = isFinderExtensionEnabledByPluginKit() ? "当前状态：Finder 扩展已启用。" : "当前状态：Finder 扩展尚未启用。"
    }

    func isFinderExtensionEnabledByPluginKit() -> Bool {
        let result = runPluginKit(arguments: ["-m", "-p", "com.apple.FinderSync", "-A", "-v"])
        let lines = result.output.components(separatedBy: .newlines)
        let matchedLine = lines.first { $0.contains(extensionIdentifier) } ?? ""
        let isEnabled = matchedLine.trimmingCharacters(in: .whitespaces).hasPrefix("+")
        writeLog("status line=\(matchedLine), isEnabled=\(isEnabled)")
        return isEnabled
    }

    func diagnosticReport() -> String {
        let pluginKitResult = runPluginKit(arguments: ["-m", "-p", "com.apple.FinderSync", "-A", "-v"])
        let processResult = runCommand(executablePath: "/usr/bin/pgrep", arguments: ["-afil", "JobsPathCopyFinderSync|JobsPathCopier"])
        let appLog = logExcerpt(from: logURL)
        let extensionLog = logExcerpt(from: extensionLogURL)
        return """
        JobsPathCopier Diagnostic Report
        Time: \(Date())
        App Bundle: \(Bundle.main.bundlePath)
        App PID: \(ProcessInfo.processInfo.processIdentifier)
        Extension ID: \(extensionIdentifier)

        [pluginkit status success=\(pluginKitResult.didSucceed)]
        \(pluginKitResult.output)

        [process status success=\(processResult.didSucceed)]
        \(processResult.output)

        [app log: \(logURL.path)]
        \(appLog)

        [extension log: \(extensionLogURL.path)]
        \(extensionLog)
        """
    }

    func logExcerpt(from url: URL) -> String {
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else { return "<missing or unreadable>" }
        let limit = 24_000
        guard text.count > limit else { return text }
        let startIndex = text.index(text.endIndex, offsetBy: -limit)
        return "<truncated to last \(limit) characters>\n" + text[startIndex...]
    }

    func writeLog(_ message: String) {
        let line = "[\(Date())] \(message)\n"
        NSLog("JobsPathCopier %@", message)

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

private struct PluginKitResult {
    let didSucceed: Bool
    let output: String
}
