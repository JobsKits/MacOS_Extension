//
//  FlutterRunTerminalLauncher.swift
//  JobsFlutterRunner
//
//  Created by Jobs on 2026年10月20日，星期二.
//

import Foundation
import Darwin

/// Terminal 只接收一条启动命令，多行逻辑和路径数据留在私有载体内。
struct FlutterRunTerminalLauncher {
    struct PreparedRequest {
        let commandLine: String
        let directoryURL: URL
        let carrierURL: URL
        let businessURL: URL
        let helperURL: URL
    }

    private let validator = FlutterProjectValidator()

    func launch(projectURL: URL) throws {
        guard let scriptURL = Bundle.main.url(forResource: "RunFlutterProject", withExtension: "zsh"),
              let helperURL = Bundle.main.url(forResource: "FlutterRunner", withExtension: "jxa") else {
            throw failure("App 缺少 RunFlutterProject.zsh 或 FlutterRunner.jxa 资源，请重新构建完整工程。")
        }
        let request = try prepare(projectURL: projectURL, businessScriptURL: scriptURL, helperScriptURL: helperURL)
        do {
            try dispatch(commandLine: request.commandLine)
        } catch {
            cleanup(request)
            throw error
        }
    }

    func prepare(projectURL: URL, businessScriptURL: URL, helperScriptURL: URL) throws -> PreparedRequest {
        guard validator.isFlutterProject(at: projectURL) else {
            throw failure("请选择真实普通 Flutter 项目文件夹；根 pubspec.yaml 必须声明 dependencies.flutter.sdk: flutter。")
        }
        let scriptData = try Data(contentsOf: businessScriptURL)
        let helperData = try Data(contentsOf: helperScriptURL)
        guard !scriptData.isEmpty, !helperData.isEmpty else {
            throw failure("Flutter 运行资源脚本为空，已停止。")
        }
        var template = Array(FileManager.default.temporaryDirectory.appendingPathComponent("JobsFlutterRunner-XXXXXX", isDirectory: true).path.utf8CString)
        guard let createdPath = mkdtemp(&template) else {
            throw failure("无法创建私有临时目录：\(String(cString: strerror(errno)))")
        }
        let directoryURL = URL(fileURLWithPath: String(cString: createdPath), isDirectory: true)
        let carrierURL = directoryURL.appendingPathComponent("launch.zsh")
        let businessURL = directoryURL.appendingPathComponent("RunFlutterProject.zsh")
        let helperURL = directoryURL.appendingPathComponent("FlutterRunner.jxa")
        let request = PreparedRequest(
            commandLine: "/bin/zsh -l \(shellWord(carrierURL.path))",
            directoryURL: directoryURL,
            carrierURL: carrierURL,
            businessURL: businessURL,
            helperURL: helperURL
        )
        do {
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directoryURL.path)
            let carrier = carrierScript(projectPath: projectURL.standardizedFileURL.path)
            guard FileManager.default.createFile(atPath: carrierURL.path, contents: Data(carrier.utf8), attributes: [.posixPermissions: 0o600]),
                  FileManager.default.createFile(atPath: businessURL.path, contents: scriptData, attributes: [.posixPermissions: 0o600]),
                  FileManager.default.createFile(atPath: helperURL.path, contents: helperData, attributes: [.posixPermissions: 0o600]) else {
                throw failure("无法写入终端私有载体。")
            }
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: carrierURL.path)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: businessURL.path)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: helperURL.path)
        } catch {
            cleanup(request)
            throw error
        }
        return request
    }

    func cleanup(_ request: PreparedRequest) {
        _ = unlink(request.carrierURL.path)
        _ = unlink(request.businessURL.path)
        _ = unlink(request.helperURL.path)
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

    private func carrierScript(projectPath: String) -> String {
        """
        # shell: zsh
        # 脚本自述：当前 Finder 请求的私有载体，仅转交业务脚本并精确清理本次文件。
        # 运行提示：业务脚本负责自述、交互确认和日志；不修改用户 Shell 配置。
        JOBS_CARRIER=""
        JOBS_RUNTIME=""
        # 保留业务退出码，只删除本次已读取载体和脚本，空目录才移除。
        jobs_cleanup_request() {
          local result=$?
          /bin/rm -f -- "$JOBS_CARRIER" "$JOBS_RUNTIME/RunFlutterProject.zsh" "$JOBS_RUNTIME/FlutterRunner.jxa"
          /bin/rmdir -- "$JOBS_RUNTIME" 2>/dev/null
          return "$result"
        }
        # zsh 函数内注册 EXIT 会在函数返回时触发，使用脚本级命名陷阱保持完整生命周期。
        TRAPEXIT() {
          jobs_cleanup_request
        }
        # 用户中断按标准退出码结束整个载体。
        TRAPINT() {
          exit 130
        }
        # 终端关闭时同样交给脚本级退出清理。
        TRAPHUP() {
          exit 129
        }
        # 外部终止保持可识别的失败码。
        TRAPTERM() {
          exit 143
        }
        # 初始化本次私有文件路径，不在函数内注册临时 EXIT 陷阱。
        jobs_initialize_request() {
          setopt NO_NOMATCH
          JOBS_CARRIER="${(%):-%x}"
          JOBS_CARRIER="${JOBS_CARRIER:A}"
          JOBS_RUNTIME="${JOBS_CARRIER:h}"
        }
        # 固定命令和数据参数分开传递；业务脚本负责交互自述和确认。
        jobs_execute_request() {
          /bin/zsh -l "$JOBS_RUNTIME/RunFlutterProject.zsh" --project \(shellWord(projectPath))
        }
        # 私有转发入口复用业务脚本自述，不增加重复确认。
        main() {
          jobs_initialize_request # 先准备退出清理，避免请求结束后遗留载体。
          jobs_execute_request # 交给本次业务脚本并保留其退出码。
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
        NSError(domain: "JobsFlutterRunner", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
