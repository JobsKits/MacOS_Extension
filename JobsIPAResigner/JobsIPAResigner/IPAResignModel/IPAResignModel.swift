//
//  IPAResignModel.swift
//  JobsIPAResigner
//
//  Created by Jobs on 2026年10月23日，星期五.
//

import AppKit
import Darwin

final class IPAResignModel {
    private let identifier = "com.jobs.JobsIPAResigner.FinderSyncExtension"
    private let launcher = IPAResignLauncher()
    private let logURL = URL(fileURLWithPath: "/tmp/JobsIPAResigner.log")

    func record(_ message: String) {
        NSLog("JobsIPAResigner %@", message)
        let data = Data("[\(Date())] \(message)\n".utf8)
        if FileManager.default.fileExists(atPath: logURL.path),
           let handle = try? FileHandle.make(forWritingTo: logURL) {
            defer {
                try? handle.close()
            }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
            return
        }
        try? data.write(to: logURL)
    }

    /// 宿主只派发普通 IPA 请求，重签和安装由可见终端确认。
    func resign(_ fileURL: URL, completion: @escaping () -> Void) {
        guard IPAResignValidator().isRegularFile(at: fileURL) else {
            showFailure("目标已失效，请重新右键单个普通 .ipa 文件。")
            completion()
            return
        }
        record("正在请求 Terminal 处理单文件IPA 免编译重签。")
        DispatchQueue.global(qos: .userInitiated).async {
            let failureMessage: String?
            do {
                try self.launcher.launch(fileURL: fileURL)
                failureMessage = nil
            } catch {
                failureMessage = "Terminal 派发失败：\(error.localizedDescription)"
            }
            DispatchQueue.main.async {
                if let failureMessage {
                    self.showFailure(failureMessage)
                } else {
                    self.record("已交给 Terminal，请在终端确认重签并查看结果。")
                }
                completion()
            }
        }
    }

    private func showFailure(_ message: String) {
        record(message)
        NSAlert.jobsMake {
            $0.byAlertStyle(.warning)
                .byMessageText("IPA 免编译重签未启动")
                .byInformativeText(message)
                .byAddButton("好")
        }.runModal()
    }

    func enableExtension(completion: @escaping () -> Void) {
        DispatchQueue.global(qos: .utility).async {
            let messages = self.initializeExtension()
            DispatchQueue.main.async {
                messages.forEach(self.record)
                completion()
            }
        }
    }

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
        let marker = URL(fileURLWithPath: "/tmp/JobsIPAResignerNeedsFinderRestart")
        var messages: [String] = []
        guard let plugins = Bundle.main.builtInPlugInsURL else {
            return preserveRefreshMarker(marker, messages: ["无法定位 App 内的 Finder 扩展目录。"])
        }
        let extensionURL = plugins.appendingPathComponent("JobsIPAResignerFinderSync.appex")
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
            let refresh = command("/usr/bin/killall", ["Finder"])
            messages.append("Finder 刷新退出码：\(refresh.exitCode)；\(refresh.output)")
            if refresh.exitCode == 0 {
                do {
                    try FileManager.default.removeItem(at: marker)
                } catch {
                    messages.append("无法清理 Finder 刷新标记：\(error.localizedDescription)")
                }
            }
        }
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
        let pipe = Pipe.make()
        let process = Process.jobsMake {
            $0.byExecutableURL(URL(fileURLWithPath: executable))
                .byArguments(arguments)
                .byStandardOutput(pipe)
                .byStandardError(pipe)
        }
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
