//
//  HarmonySimulatorRepairTerminalLauncher.swift
//  JobsHarmonySimulatorRepairer
//
//  Created by Jobs on 2026年10月24日，星期六.
//

import Foundation
import Darwin

/// Terminal 只接收固定启动器；业务脚本复制到本次请求独有的私有目录。
struct HarmonySimulatorRepairTerminalLauncher {
    struct PreparedRequest {
        let commandLine: String
        let directoryURL: URL
        let carrierURL: URL
        let businessURL: URL
    }

    func launch() throws {
        guard let scriptURL = Bundle.main.url(forResource: "RepairHarmonySimulator", withExtension: "zsh") else {
            throw failure("App 缺少 RepairHarmonySimulator.zsh 资源，请重新构建完整工程。")
        }
        let request = try prepare(businessScriptURL: scriptURL)
        do {
            try dispatch(commandLine: request.commandLine)
        } catch {
            cleanup(request)
            throw error
        }
    }

    func prepare(businessScriptURL: URL, temporaryDirectory: URL = FileManager.default.temporaryDirectory) throws -> PreparedRequest {
        let scriptData = try Data(contentsOf: businessScriptURL)
        guard !scriptData.isEmpty else {
            throw failure("检测与修复模拟器资源脚本为空，已停止。")
        }
        var template = Array(temporaryDirectory.appendingPathComponent("JobsHarmonySimulatorRepairer-XXXXXX", isDirectory: true).path.utf8CString)
        guard let createdPath = mkdtemp(&template) else {
            throw failure("无法创建私有临时目录：\(String(cString: strerror(errno)))")
        }
        let directoryURL = URL(fileURLWithPath: String(cString: createdPath), isDirectory: true)
        let carrierURL = directoryURL.appendingPathComponent("launch.zsh")
        let businessURL = directoryURL.appendingPathComponent("RepairHarmonySimulator.zsh")
        let request = PreparedRequest(
            commandLine: "/bin/zsh \(shellWord(carrierURL.path))",
            directoryURL: directoryURL,
            carrierURL: carrierURL,
            businessURL: businessURL
        )
        do {
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directoryURL.path)
            guard FileManager.default.createFile(atPath: carrierURL.path, contents: Data(carrierScript.utf8), attributes: [.posixPermissions: 0o600]),
                  FileManager.default.createFile(atPath: businessURL.path, contents: scriptData, attributes: [.posixPermissions: 0o600]) else {
                throw failure("无法写入终端私有载体。")
            }
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: carrierURL.path)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: businessURL.path)
        } catch {
            cleanup(request)
            throw error
        }
        return request
    }

    func cleanup(_ request: PreparedRequest) {
        _ = unlink(request.carrierURL.path)
        _ = unlink(request.businessURL.path)
        _ = rmdir(request.directoryURL.path)
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
            /// 控制符编码后保持 Terminal 输入为物理单行。
            case 0x00...0x1F, 0x7F:
                escaped += String(format: "\\x%02x", scalar.value)
            /// Unicode 行分隔符也不进入 Terminal 输入流。
            case 0x85, 0x2028, 0x2029:
                escaped += String(format: "\\u%04x", scalar.value)
            /// 普通 Unicode 留在引用内，不参与 Shell 展开。
            default:
                escaped += String(scalar)
            }
        }
        return "$'\(escaped)'"
    }

    private var carrierScript: String {
        """
        #!/bin/zsh
        # 脚本自述：本次 Finder 请求的私有载体，只运行同目录检测与修复模拟器脚本。
        # 运行提示：业务脚本负责交互和日志；退出时只清理本次私有文件。
        JOBS_CARRIER=""
        JOBS_RUNTIME=""
        # 保留业务退出码，只删除本次载体和脚本，空目录才移除。
        jobs_cleanup_request() {
          local result=$?
          /bin/rm -f -- "$JOBS_CARRIER" "$JOBS_RUNTIME/RepairHarmonySimulator.zsh"
          /bin/rmdir -- "$JOBS_RUNTIME" 2>/dev/null
          return "$result"
        }
        # 脚本级命名陷阱覆盖整个请求生命周期。
        TRAPEXIT() {
          jobs_cleanup_request
        }
        # 用户中断保留标准退出码。
        TRAPINT() {
          exit 130
        }
        # 终端关闭同样精确清理载体。
        TRAPHUP() {
          exit 129
        }
        # 外部终止按信号语义退出。
        TRAPTERM() {
          exit 143
        }
        # 使用原始脚本名，避免 prompt 的 %x 转义控制字符后改变真实路径。
        jobs_initialize_request() {
          setopt NO_NOMATCH
          JOBS_CARRIER="${ZSH_ARGZERO:A}"
          JOBS_RUNTIME="${JOBS_CARRIER:h}"
        }
        # 全局模拟器动作不接收外部命令或目录参数。
        jobs_execute_request() {
          /bin/zsh "$JOBS_RUNTIME/RepairHarmonySimulator.zsh" --repair
        }
        # 私有载体复用业务脚本交互，不叠加确认。
        main() {
          jobs_initialize_request # 先定位本次文件，准备退出清理。
          jobs_execute_request # 交给业务脚本并保留其退出码。
        }
        main "$@"
        """
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
        let output = Pipe.make()
        let process = Process.jobsMake {
            $0.byExecutableURL(URL(fileURLWithPath: "/usr/bin/osascript"))
                .byArguments(["-e", script, commandLine])
                .byStandardOutput(output)
                .byStandardError(output)
        }
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw failure("Terminal 启动失败：\(String(decoding: data, as: UTF8.self))；请检查系统设置中的自动化权限。")
        }
    }

    private func failure(_ message: String) -> NSError {
        return NSError.make(domain: "JobsHarmonySimulatorRepairer", message: message)
    }
}
