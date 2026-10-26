//
//  GitRollbackTerminalLauncher.swift
//  JobsGitRollback
//
//  Created by Jobs on 2026年10月26日，星期一.
//

import Foundation
import Darwin

/// Terminal 只接收一条启动命令，多行逻辑和路径数据留在私有载体内。
struct GitRollbackTerminalLauncher {
    struct PreparedRequest {
        let commandLine: String
        let directoryURL: URL
        let carrierURL: URL
        let businessURL: URL
    }

    private let validator = GitRollbackMenuContext()

    func launch(projectURL: URL) throws {
        guard let scriptURL = Bundle.main.url(forResource: "RollbackGitRepository", withExtension: "zsh") else {
            throw failure("App 缺少 RollbackGitRepository.zsh 资源，请重新构建完整工程。")
        }
        let request = try prepare(projectURL: projectURL, businessScriptURL: scriptURL)
        do {
            try dispatch(commandLine: request.commandLine)
        } catch {
            cleanup(request)
            throw error
        }
    }

    func prepare(projectURL: URL, businessScriptURL: URL) throws -> PreparedRequest {
        guard let identity = validator.identity(at: projectURL) else {
            throw failure("请选择有效 Git 工作树内真实存在的普通文件夹。")
        }
        try verifyIdentity(projectURL: projectURL, expected: identity)
        let scriptData = try Data(contentsOf: businessScriptURL)
        guard !scriptData.isEmpty else {
            throw failure("Git 提交回退资源脚本为空，已停止。")
        }
        var template = Array(FileManager.default.temporaryDirectory.appendingPathComponent("JobsGitRollback-XXXXXX", isDirectory: true).path.utf8CString)
        guard let createdPath = mkdtemp(&template) else {
            throw failure("无法创建私有临时目录：\(String(cString: strerror(errno)))")
        }
        let directoryURL = URL(fileURLWithPath: String(cString: createdPath), isDirectory: true)
        let carrierURL = directoryURL.appendingPathComponent("launch.zsh")
        let businessURL = directoryURL.appendingPathComponent("RollbackGitRepository.zsh")
        let request = PreparedRequest(
            commandLine: "/bin/zsh \(shellWord(carrierURL.path))",
            directoryURL: directoryURL,
            carrierURL: carrierURL,
            businessURL: businessURL
        )
        do {
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directoryURL.path)
            let carrier = carrierScript(projectPath: projectURL.standardizedFileURL.path, identity: identity)
            guard FileManager.default.createFile(atPath: carrierURL.path, contents: Data(carrier.utf8), attributes: [.posixPermissions: 0o600]),
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

    /// 仅由后台宿主调用；Finder 菜单回调仍只读结构，不启动子进程。
    private func verifyIdentity(projectURL: URL, expected: GitRollbackMenuContext.RepositoryIdentity) throws {
        let root = try gitIdentityValue("--show-toplevel", projectURL: projectURL)
        let directory = try gitIdentityValue("--absolute-git-dir", projectURL: projectURL)
        guard URL(fileURLWithPath: root).standardizedFileURL.resolvingSymlinksInPath().path == expected.rootURL.path,
              URL(fileURLWithPath: directory).standardizedFileURL.resolvingSymlinksInPath().path == expected.gitDirectoryURL.path else {
            throw failure("Git 实际工作树与 Finder 选择的最近仓库不一致，请检查 .git 或 core.worktree；没有启动回退。")
        }
    }

    private func gitIdentityValue(_ option: String, projectURL: URL) throws -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["--no-optional-locks", "-C", projectURL.path, "rev-parse", option]
        process.environment = ProcessInfo.processInfo.environment.filter {
            !$0.key.hasPrefix("GIT_")
        }
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              var output = String(data: data, encoding: .utf8), output.hasSuffix("\n") else {
            throw failure("无法只读确认 Git 工作树身份，已停止回退：\(String(decoding: data, as: UTF8.self))")
        }
        output.removeLast()
        guard output.hasPrefix("/"), !output.utf8.contains(0) else {
            throw failure("Git 返回的工作树路径无效，已停止回退。")
        }
        return output
    }

    private func carrierScript(projectPath: String, identity: GitRollbackMenuContext.RepositoryIdentity) -> String {
        """
        # shell: zsh
        # 脚本自述：当前 Finder 请求的私有载体，仅转交业务脚本并精确清理本次文件。
        # 运行提示：业务脚本负责自述、交互确认和日志；不修改用户 Shell 配置。
        JOBS_CARRIER=""
        JOBS_RUNTIME=""
        # 保留业务退出码，只删除本次已读取载体和脚本，空目录才移除。
        jobs_cleanup_request() {
          local result=$?
          /bin/rm -f -- "$JOBS_CARRIER" "$JOBS_RUNTIME/RollbackGitRepository.zsh"
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
          local variable_name=""
          for variable_name in ${(k)parameters}; do
            if [[ "$variable_name" == GIT_* ]]; then
              unset "$variable_name"
            fi
          done
        }
        # 终端实际执行前再次确认身份，避免 core.worktree 或 .git 在派发后转向其它目录。
        jobs_verify_repository_identity() {
          local actual_root="" actual_gitdir=""
          local expected_root=\(shellWord(identity.rootURL.path))
          local expected_gitdir=\(shellWord(identity.gitDirectoryURL.path))
          actual_root="$(/usr/bin/git --no-optional-locks -C \(shellWord(projectPath)) rev-parse --show-toplevel && print -r -- '.')" || return 65
          actual_gitdir="$(/usr/bin/git --no-optional-locks -C \(shellWord(projectPath)) rev-parse --absolute-git-dir && print -r -- '.')" || return 65
          actual_root="${actual_root%$'\\n.'}"
          actual_gitdir="${actual_gitdir%$'\\n.'}"
          if [[ "${actual_root:A}" != "${expected_root:A}" || "${actual_gitdir:A}" != "${expected_gitdir:A}" ]]; then
            print -u2 -r -- 'Git 实际工作树与 Finder 选择的最近仓库不一致，请检查 .git 或 core.worktree；没有执行回退。'
            return 65
          fi
        }
        # 固定命令和数据参数分开传递；业务脚本负责交互自述和确认。
        jobs_execute_request() {
          jobs_verify_repository_identity || return $?
          /bin/zsh "$JOBS_RUNTIME/RollbackGitRepository.zsh" \(shellWord(projectPath))
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
        NSError(domain: "JobsGitRollback", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
