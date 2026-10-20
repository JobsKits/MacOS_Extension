//
//  FlutterDependencyModel.swift
//  JobsFlutterDependencyExtractor
//
//  Created by Jobs on 2026年10月19日，星期一.
//

import Foundation

final class FlutterDependencyModel {
    private let identifier = "com.jobs.JobsFlutterDependencyExtractor.FinderSync"
    private let launcher = FlutterDependencyTerminalLauncher()
    private let logURL = URL(fileURLWithPath: "/tmp/JobsFlutterDependencyExtractor.log")

    func record(_ message: String) {
        NSLog("JobsFlutterDependencyExtractor %@", message)
        let data = Data("[\(Date())] \(message)\n".utf8)
        if FileManager.default.fileExists(atPath: logURL.path),
           let handle = try? FileHandle(forWritingTo: logURL) {
            defer {
                try? handle.close()
            }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
            return
        }
        try? data.write(to: logURL)
    }

    func extract(_ projectURL: URL, completion: @escaping () -> Void) {
        guard FlutterProjectValidator().isFlutterProject(at: projectURL) else {
            record("当前文件夹不是可识别的 Flutter 项目：\(projectURL.path)")
            completion()
            return
        }
        record("正在请求 Terminal：\(projectURL.path)")
        DispatchQueue.global(qos: .userInitiated).async {
            let message: String
            do {
                try self.launcher.launch(projectURL: projectURL)
                message = "已交给 Terminal。依赖提取结果与日志请查看终端。\n\(projectURL.path)"
            } catch {
                message = "Terminal 派发失败：\(error.localizedDescription)"
            }
            DispatchQueue.main.async {
                self.record(message)
                completion()
            }
        }
    }

    func enableExtension(completion: @escaping () -> Void) {
        DispatchQueue.global(qos: .utility).async {
            var messages: [String] = []
            if let plugins = Bundle.main.builtInPlugInsURL {
                let extensionURL = plugins.appendingPathComponent("JobsFlutterDependencyFinderSync.appex")
                if FileManager.default.fileExists(atPath: extensionURL.path) {
                    let registration = self.command("/usr/bin/pluginkit", ["-a", extensionURL.path])
                    messages.append("扩展注册退出码：\(registration.exitCode)；\(registration.output)")
                    let activation = self.command("/usr/bin/pluginkit", ["-e", "use", "-i", self.identifier])
                    messages.append("扩展启用退出码：\(activation.exitCode)；\(activation.output)")
                } else {
                    messages.append("App 缺少 Finder 扩展资源，请重新安装完整工程。")
                }
            } else {
                messages.append("无法定位 App 内的 Finder 扩展目录。")
            }
            let status = self.command("/usr/bin/pluginkit", ["-m", "-p", "com.apple.FinderSync", "-A", "-v"])
            let enabled = status.exitCode == 0 && status.output.components(separatedBy: .newlines).contains {
                $0.contains(self.identifier) && $0.trimmingCharacters(in: .whitespaces).hasPrefix("+")
            }
            messages.append(enabled ? "Finder 扩展已启用。" : "Finder 扩展尚未启用，请在系统扩展设置中检查。")
            if status.exitCode != 0 {
                messages.append("扩展状态查询失败（\(status.exitCode)）：\(status.output)")
            }
            if enabled {
                let marker = URL(fileURLWithPath: "/tmp/JobsFlutterDependencyExtractorNeedsFinderRestart")
                if FileManager.default.fileExists(atPath: marker.path) {
                    let refresh = self.command("/usr/bin/killall", ["Finder"])
                    messages.append("Finder 刷新退出码：\(refresh.exitCode)；\(refresh.output)")
                    if refresh.exitCode == 0 {
                        do {
                            try FileManager.default.removeItem(at: marker)
                        } catch {
                            messages.append("无法清理 Finder 刷新标记：\(error.localizedDescription)")
                        }
                    }
                }
            }
            let finalMessages = messages
            DispatchQueue.main.async {
                finalMessages.forEach(self.record)
                completion()
            }
        }
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
