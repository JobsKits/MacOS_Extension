//
//  GitProxyModel.swift
//  JobsGitProxyConfigurator
//
//  Created by Jobs on 2026年10月22日，星期四.
//

import AppKit
import Darwin

final class GitProxyModel {
    private let identifier = "com.jobs.gitproxyconfigurator.findersync"
    private let launcher = GitProxyTerminalLauncher()
    private let logPath = "/tmp/JobsGitProxyConfigurator.log"

    func record(_ message: String) {
        NSLog("JobsGitProxyConfigurator %@", message)
        // 固定诊断位置拒绝跟随链接，避免临时目录同名链接覆盖用户文件。
        let descriptor = open(logPath, O_WRONLY | O_CREAT | O_APPEND | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else {
            return
        }
        defer {
            close(descriptor)
        }
        let data = Data("[\(Date())] \(message)\n".utf8)
        data.withUnsafeBytes { bytes in
            if let address = bytes.baseAddress {
                _ = write(descriptor, address, bytes.count)
            }
        }
    }

    func configureGitProxy(completion: @escaping () -> Void) {
        record("正在将配置 Git 动态代理流程交给 Terminal。")
        DispatchQueue.global(qos: .userInitiated).async {
            let message: String
            var failureMessage: String?
            do {
                try self.launcher.launch()
                message = "已交给 Terminal；安装、检查或恢复的确认与日志请查看终端。"
            } catch {
                message = "Terminal 派发失败：\(error.localizedDescription)"
                failureMessage = message
            }
            let finalFailureMessage = failureMessage
            DispatchQueue.main.async {
                self.record(message)
                if let finalFailureMessage {
                    self.showLaunchFailure(finalFailureMessage)
                }
                completion()
            }
        }
    }

    private func showLaunchFailure(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "配置 Git 动态代理未启动"
        alert.informativeText = "\(message)\n\n请检查系统设置 → 隐私与安全性 → 自动化，允许本 App 控制 Terminal。诊断日志：\(logPath)"
        alert.addButton(withTitle: "好")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    func enableExtension(completion: @escaping () -> Void) {
        DispatchQueue.global(qos: .utility).async {
            let finalMessages = self.initializeExtension()
            DispatchQueue.main.async {
                finalMessages.forEach(self.record)
                completion()
            }
        }
    }

    /// -vv 的 Path 属于紧邻其前的注册条目，不能用其他路径的 + 状态代替当前产物。
    static func isCurrentExtensionEnabled(in output: String, identifier: String, extensionURL: URL) -> Bool {
        var currentEntryEnabled = false
        for line in output.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let separator = trimmed.firstIndex(of: "="), trimmed[..<separator].trimmingCharacters(in: .whitespaces) == "Path" {
                let path = trimmed[trimmed.index(after: separator)...].trimmingCharacters(in: .whitespaces)
                if currentEntryEnabled && path == extensionURL.path {
                    return true
                }
            } else if !line.hasPrefix("\t"), !trimmed.isEmpty {
                let entry = trimmed.dropFirst().trimmingCharacters(in: .whitespaces)
                currentEntryEnabled = trimmed.hasPrefix("+") && entry.hasPrefix("\(identifier)(")
            }
        }
        return false
    }

    private func initializeExtension() -> [String] {
        let marker = URL(fileURLWithPath: "/tmp/JobsGitProxyConfiguratorNeedsFinderRestart")
        var messages: [String] = []
        guard let plugins = Bundle.main.builtInPlugInsURL else {
            return preserveRefreshMarker(marker, messages: ["无法定位 App 内的 Finder 扩展目录。"])
        }
        let extensionURL = plugins.appendingPathComponent("JobsGitProxyFinderSync.appex")
        guard FileManager.default.fileExists(atPath: extensionURL.path) else {
            return preserveRefreshMarker(marker, messages: ["App 缺少 Finder 扩展资源，请重新安装完整工程。"])
        }
        let registration = command("/usr/bin/pluginkit", ["-a", extensionURL.path])
        messages.append("扩展注册退出码：\(registration.exitCode)；\(registration.output)")
        guard registration.exitCode == 0 else {
            return preserveRefreshMarker(marker, messages: messages)
        }
        let activation = command("/usr/bin/pluginkit", ["-e", "use", "-i", identifier])
        messages.append("扩展启用退出码：\(activation.exitCode)；\(activation.output)")
        guard activation.exitCode == 0 else {
            return preserveRefreshMarker(marker, messages: messages)
        }
        var enabled = false
        for attempt in 0..<10 {
            let status = command("/usr/bin/pluginkit", ["-m", "-i", identifier, "-A", "-D", "-vv"])
            guard status.exitCode == 0 else {
                messages.append("扩展状态查询失败（\(status.exitCode)）：\(status.output)")
                return preserveRefreshMarker(marker, messages: messages)
            }
            if Self.isCurrentExtensionEnabled(in: status.output, identifier: identifier, extensionURL: extensionURL) {
                enabled = true
                break
            }
            if attempt < 9 {
                Thread.sleep(forTimeInterval: 0.2)
            } else {
                messages.append("当前扩展路径尚未启用：\(extensionURL.path)；状态：\(status.output)")
            }
        }
        guard enabled else {
            return preserveRefreshMarker(marker, messages: messages)
        }
        messages.append("当前 App 路径的 Finder 扩展已启用：\(extensionURL.path)")
        if FileManager.default.fileExists(atPath: marker.path) {
            do {
                try FileManager.default.removeItem(at: marker)
            } catch {
                messages.append("无法清理 Finder 刷新标记：\(error.localizedDescription)")
            }
        }
        messages.append("Finder 刷新由外层安装器统一负责；初始化不打开 Git 配置终端。")
        return messages
    }

    private func preserveRefreshMarker(_ marker: URL, messages: [String]) -> [String] {
        let descriptor = open(marker.path, O_WRONLY | O_CREAT | O_NOFOLLOW, 0o600)
        if descriptor >= 0 {
            close(descriptor)
        }
        let markerMessage = descriptor >= 0 ? "已保留 Finder 刷新标记。" : "无法创建 Finder 刷新标记，请检查临时目录权限。"
        return messages + ["初始化未完成；未刷新 Finder 或清除标记。\(markerMessage)请在系统扩展设置中检查或重新运行安装器。"]
    }

    private func command(_ executable: String, _ arguments: [String]) -> (exitCode: Int32, output: String) {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return (process.terminationStatus, String(decoding: data, as: UTF8.self))
        } catch {
            return (-1, error.localizedDescription)
        }
    }
}
