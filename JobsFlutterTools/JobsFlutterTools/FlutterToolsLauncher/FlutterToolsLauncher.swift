//
//  FlutterToolsLauncher.swift
//  JobsFlutterTools
//
//  Created by Jobs on 2026年10月22日，星期四.
//

import Foundation
import Darwin

/// 固定动作枚举 + 私有载体；项目路径从不作为 Shell 源码解释。
struct FlutterToolsLauncher {
    struct PreparedRequest { let commandLine: String; let directoryURL: URL }
    func launch(projectURL: URL, action: FlutterToolsAction) throws {
        guard let toolsURL = Bundle.main.resourceURL?.appendingPathComponent("Tools"),
              FileManager.default.fileExists(atPath: toolsURL.appendingPathComponent("DispatchFlutterTools.zsh").path) else {
            throw failure("App 缺少 Flutter 工具资源，请重新安装。")
        }
        let request = try prepare(projectURL: projectURL, action: action, toolsURL: toolsURL)
        if action == .projectSetup {
            do {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/zsh")
                process.arguments = [request.directoryURL.appendingPathComponent("Tools/OpenSetupWindow.zsh").path, "--project", projectURL.standardizedFileURL.path]
                process.standardOutput = FileHandle.nullDevice
                process.standardError = FileHandle.nullDevice
                try process.run()
            } catch {
                try? FileManager.default.removeItem(at: request.directoryURL)
                throw error
            }
            return
        }
        do { try dispatch(commandLine: request.commandLine) }
        catch { try? FileManager.default.removeItem(at: request.directoryURL); throw error }
    }
    func prepare(projectURL: URL, action: FlutterToolsAction, toolsURL: URL) throws -> PreparedRequest {
        guard FlutterFeatureConfiguration.permits(action, enabled: FlutterFeatureConfiguration.enabledFeatures()) else {
            throw failure("此 Flutter 功能未安装或选择配置已变化，请重新运行总安装器勾选。")
        }
        guard FlutterProjectValidator().isFlutterProject(at: projectURL) else { throw failure("请选择合法 Flutter 项目根目录。") }
        guard action != .packageHarmony || FlutterProjectValidator().isHarmonyFlutterProject(at: projectURL) else {
            throw failure("鸿蒙打包需要当前 Flutter 工程包含普通 ohos 目录、build-profile.json5 和 oh-package.json5，请先完成鸿蒙适配。")
        }
        var template = Array(FileManager.default.temporaryDirectory.appendingPathComponent("JobsFlutterTools-XXXXXX").path.utf8CString)
        guard let path = mkdtemp(&template) else { throw failure("无法建立私有载体。") }
        let directory = URL(fileURLWithPath: String(cString: path), isDirectory: true)
        do {
            try FileManager.default.copyItem(at: toolsURL, to: directory.appendingPathComponent("Tools"))
            let carrier = directory.appendingPathComponent("launch.zsh")
            let body = """
            #!/bin/zsh
            JOBS_TOOLS_REQUEST=${${(%):-%x}:A:h}
            TRAPEXIT() { local result=$?; /bin/rm -rf -- "$JOBS_TOOLS_REQUEST/Tools"; /bin/rm -f -- "$JOBS_TOOLS_REQUEST/launch.zsh"; /bin/rmdir -- "$JOBS_TOOLS_REQUEST"; return "$result"; }
            TRAPINT() { exit 130; }
            TRAPHUP() { exit 129; }
            TRAPTERM() { exit 143; }
            /bin/zsh "$JOBS_TOOLS_REQUEST/Tools/DispatchFlutterTools.zsh" \(shellWord(action.rawValue)) \(shellWord(projectURL.standardizedFileURL.path))
            """
            guard FileManager.default.createFile(atPath: carrier.path, contents: Data(body.utf8), attributes: [.posixPermissions: 0o600]) else { throw failure("无法写入私有载体。") }
            return PreparedRequest(commandLine: "/bin/zsh -l \(shellWord(carrier.path))", directoryURL: directory)
        } catch { try? FileManager.default.removeItem(at: directory); throw error }
    }
    func shellWord(_ value: String) -> String {
        var escaped = ""
        for scalar in value.unicodeScalars {
            switch scalar.value {
            /// ANSI-C 引用中的反斜线必须保持字面量。
            case 0x5C:
                escaped += "\\\\"
            /// 单引号不能关闭当前 Shell 数据参数。
            case 0x27:
                escaped += "\\'"
            /// ASCII 控制符全部编码，保持 Terminal 命令为物理单行。
            case 0x00...0x1F, 0x7F:
                escaped += String(format: "\\x%02x", scalar.value)
            /// Unicode 行分隔符也不能进入 Terminal 输入流。
            case 0x85, 0x2028, 0x2029:
                escaped += String(format: "\\u%04x", scalar.value)
            /// 普通 Unicode 由单引号保护，不参与展开。
            default:
                escaped += String(scalar)
            }
        }
        return "$'\(escaped)'"
    }

    private func dispatch(commandLine: String) throws {
        let script = """
        on run argv
            tell application "Terminal"
                activate
                do script (item 1 of argv)
            end tell
        end run
        """
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script, commandLine]
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw failure("Terminal 启动失败：\(String(decoding: data, as: UTF8.self))")
        }
    }

    private func failure(_ message: String) -> NSError {
        NSError(domain: "JobsFlutterTools", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
