//
//  TerminalOpener.swift
//  JobsTerminalFinderSync
//
//  Created by Jobs on 2026年6月28日，星期日.
//

import AppKit
import Darwin

struct TerminalOpener {
    enum Action: String {
        case open
        case fileContent = "file-content"
        case fileMerge = "file-merge"
        case fileSplit = "file-split"
        case podInstall = "pod-install"
        case flutterPubGet = "flutter-pub-get"
        case cleanBuildArtifacts = "clean-build-artifacts"
        case codeGraphBootstrap = "codegraph-bootstrap"
        case gitEmptyCommitPush = "git-empty-commit-push"
    }

    struct PreparedTerminalRequest {
        let commandLine: String
        let runtimeDirectoryURL: URL?
        let scriptURL: URL?
    }

    private let dependencyProjectValidator = DependencyProjectValidator()
    private let executeAppleScript: ((String, String) throws -> Void)?
    private let writeLog: (String) -> Void

    init(writeLog: @escaping (String) -> Void = { _ in }) {
        self.executeAppleScript = nil
        self.writeLog = writeLog
    }

    init(
        executeAppleScript: @escaping (String, String) throws -> Void,
        writeLog: @escaping (String) -> Void = { _ in }
    ) {
        self.executeAppleScript = executeAppleScript
        self.writeLog = writeLog
    }

    func openTerminal(from fileURL: URL, action: Action) throws -> URL {
        if action == .fileMerge || action == .fileSplit {
            return try openFileVolumes(from: [fileURL], action: action)
        }
        if action == .fileContent, !dependencyProjectValidator.isFileContentTarget(at: fileURL) {
            throw TerminalOpenError.terminalCommandFailed("请选择一个可读取的普通文件；不支持文件夹、链接、替身或特殊文件。")
        }
        let standardizedURL = action == .fileContent ? fileURL : fileURL.standardizedFileURL
        guard standardizedURL.isFileURL else {
            throw TerminalOpenError.unsupportedURL(fileURL)
        }

        let directoryURL = try terminalWorkingDirectory(from: standardizedURL, action: action)
        try runTerminalCommand(directoryURL: directoryURL, action: action)
        return directoryURL
    }
}

extension TerminalOpener {
    // 把可交互短命令与异步执行的私有脚本分开准备，目标路径只按字面量传递。
    func prepareTerminalRequest(directoryURL: URL, action: Action) throws -> PreparedTerminalRequest {
        if action == .fileMerge || action == .fileSplit {
            return try prepareFileVolumeRequest(urls: [directoryURL], action: action)
        }
        let targetDirectoryURL = try terminalWorkingDirectory(from: directoryURL, action: action)
        let targetWord = terminalShellWord(targetDirectoryURL.path)
        let businessScript: String

        switch action {
        /// 普通打开保留交互 Shell 的工作目录。
        case .open:
            return PreparedTerminalRequest(
                commandLine: "cd -- \(targetWord)",
                runtimeDirectoryURL: nil,
                scriptURL: nil
            )
        /// 文件正文不进入 AppleScript，交互确认与流式读取由打包脚本负责。
        case .fileContent:
            guard let scriptURL = Bundle.main.url(forResource: "ViewFileContent", withExtension: "zsh") else {
                throw TerminalOpenError.terminalCommandFailed("缺少文件内容查看脚本，请重新构建或安装扩展。")
            }
            businessScript = try String(contentsOf: scriptURL, encoding: .utf8)
        /// 多文件请求由完整选择专用入口准备。
        case .fileMerge, .fileSplit:
            throw TerminalOpenError.terminalCommandFailed("请从文件选择入口启动分卷操作。")
        /// Flutter 命令本身很短，继续在新终端中切目录后执行。
        case .flutterPubGet:
            return PreparedTerminalRequest(
                commandLine: "cd -- \(targetWord) && flutter pub get",
                runtimeDirectoryURL: nil,
                scriptURL: nil
            )
        /// Pod 直接使用当前终端环境，进入目标目录后执行安装。
        case .podInstall:
            return PreparedTerminalRequest(
                commandLine: "cd -- \(targetWord) && pod install",
                runtimeDirectoryURL: nil,
                scriptURL: nil
            )
        /// 打包的清理脚本在 Terminal 执行时重新识别当前工程。
        case .cleanBuildArtifacts:
            guard let scriptURL = Bundle.main.url(forResource: "CleanBuildArtifacts", withExtension: "zsh") else {
                throw TerminalOpenError.terminalCommandFailed("缺少构建产物清理脚本，请重新构建或安装扩展。")
            }
            businessScript = "set -- \"$1\" --android-openharmony\n" + (try String(contentsOf: scriptURL, encoding: .utf8))
        /// CodeGraph 的依赖链与地图操作使用同一个私有载体。
        case .codeGraphBootstrap:
            businessScript = codeGraphDependencyCommand()
        /// Git 动作在私有子进程中进入目录，保留原有提交与推送校验。
        case .gitEmptyCommitPush:
            businessScript = "cd -- \"$1\" || exit 1\n" + gitEmptyCommitPushCommand()
        }

        return try preparePrivateScript(businessScript: businessScript, arguments: [targetDirectoryURL.path], action: action)
    }

    /// 多选参数只进入权限为 0600 的私有载体；Terminal 输入始终是一条短命令。
    func prepareFileVolumeRequest(urls: [URL], action: Action) throws -> PreparedTerminalRequest {
        guard action == .fileMerge || action == .fileSplit,
              action == .fileMerge ? FileVolumeSelection.canMerge(urls) : FileVolumeSelection.canSplit(urls) else {
            throw TerminalOpenError.terminalCommandFailed("合并须完整选中同一组分卷；拆分须选择一个普通文件。")
        }
        guard let scriptURL = Bundle.main.url(forResource: "FileVolumes", withExtension: "zsh") else {
            throw TerminalOpenError.terminalCommandFailed("缺少分卷脚本，请重新构建或安装扩展。")
        }
        let script = try String(contentsOf: scriptURL, encoding: .utf8)
        return try preparePrivateScript(
            businessScript: script,
            arguments: [action == .fileMerge ? "merge" : "split"] + urls.map(\.path),
            action: action
        )
    }

    func openFileVolumes(from urls: [URL], action: Action) throws -> URL {
        _ = try terminalApplicationURL()
        let request = try prepareFileVolumeRequest(urls: urls, action: action)
        do {
            if let executeAppleScript {
                try executeAppleScript(terminalOpenAppleScript(), request.commandLine)
            } else {
                try runTerminalAppleScript(commandLine: request.commandLine)
            }
        } catch {
            cleanupPreparedTerminalRequest(request)
            throw error
        }
        activateTerminalWhenAvailable()
        return urls[0].deletingLastPathComponent()
    }

    private func preparePrivateScript(businessScript: String, arguments: [String], action: Action) throws -> PreparedTerminalRequest {
        var directoryTemplate = Array(
            FileManager.default.temporaryDirectory
                .appendingPathComponent("JobsTerminalOpener-XXXXXX", isDirectory: true)
                .path.utf8CString
        )
        guard let createdPath = mkdtemp(&directoryTemplate) else {
            throw TerminalOpenError.terminalCommandFailed("无法创建终端私有临时目录：\(String(cString: strerror(errno)))")
        }

        let runtimeDirectoryURL = URL(fileURLWithPath: String(cString: createdPath), isDirectory: true)
        let scriptURL = runtimeDirectoryURL.appendingPathComponent("action.zsh")
        let request = PreparedTerminalRequest(
            commandLine: "/bin/zsh \(terminalShellWord(scriptURL.path))",
            runtimeDirectoryURL: runtimeDirectoryURL,
            scriptURL: scriptURL
        )

        do {
            let script = terminalScriptCleanupPrefix() + "\nset -- " + arguments.map(terminalShellWord).joined(separator: " ") + "\n" + businessScript + "\n"
            guard FileManager.default.createFile(
                atPath: scriptURL.path,
                contents: Data(script.utf8),
                attributes: [.posixPermissions: 0o600]
            ) else {
                throw TerminalOpenError.terminalCommandFailed("无法写入终端私有脚本：\(scriptURL.path)")
            }
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: runtimeDirectoryURL.path)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: scriptURL.path)
        } catch {
            cleanupPreparedTerminalRequest(request)
            throw error
        }

        writeLog("terminal prepared script=\(scriptURL.path), action=\(action.rawValue)")
        return request
    }

    // 请求未被 Terminal 接受时，只清理当前请求的文件及空目录。
    func cleanupPreparedTerminalRequest(_ request: PreparedTerminalRequest) {
        if let scriptURL = request.scriptURL {
            _ = unlink(scriptURL.path)
        }
        if let runtimeDirectoryURL = request.runtimeDirectoryURL {
            _ = rmdir(runtimeDirectoryURL.path)
        }
    }

    // 发送单行启动命令；成功只代表已调度，脚本由自己的退出陷阱清理。
    func openDirectoryInTerminal(_ directoryURL: URL, action: Action) throws {
        let request = try prepareTerminalRequest(directoryURL: directoryURL, action: action)

        do {
            if let executeAppleScript {
                try executeAppleScript(terminalOpenAppleScript(), request.commandLine)
            } else {
                try runTerminalAppleScript(commandLine: request.commandLine)
            }
        } catch {
            cleanupPreparedTerminalRequest(request)
            throw error
        }
    }

    // ANSI-C 引用保持命令为物理单行，并将路径中的控制符与 Shell 元字符视为数据。
    func terminalShellWord(_ value: String) -> String {
        var escapedValue = ""
        for scalar in value.unicodeScalars {
            switch scalar.value {
            /// 保护 ANSI-C 引用中的反斜杠。
            case 0x5C:
                escapedValue += "\\\\"
            /// 保护 ANSI-C 引用本身使用的单引号。
            case 0x27:
                escapedValue += "\\'"
            /// 换行与回车只以转义文本进入交互命令。
            case 0x0A:
                escapedValue += "\\n"
            /// 回车不能成为 Terminal 的另一个输入行。
            case 0x0D:
                escapedValue += "\\r"
            /// 其余 ASCII 控制符保持字节语义，不直接发送终端控制字符。
            case 0x00...0x1F, 0x7F:
                escapedValue += String(format: "\\x%02x", scalar.value)
            /// Unicode 换行字符同样编码为单行文本。
            case 0x85, 0x2028, 0x2029:
                escapedValue += String(format: "\\u%04x", scalar.value)
            /// 普通字符由单引号保护，无需展开变量、命令替换或通配符。
            default:
                escapedValue += String(scalar)
            }
        }
        return "$'\(escapedValue)'"
    }
}

private extension TerminalOpener {
    enum TerminalOpenError: LocalizedError {
        case unsupportedURL(URL)
        case missingTerminal
        case invalidCocoaPodsProject(URL)
        case invalidFlutterProject(URL)
        case invalidCodeGraphTargetFolder(URL)
        case invalidGitEmptyCommitPushTargetFolder(URL)
        case terminalCommandFailed(String)

        var errorDescription: String? {
            switch self {
            /// 请求目标不是本地文件 URL
            case .unsupportedURL(let url):
                return "不是本地文件路径：\(url.absoluteString)"
            /// 系统没有安装 Terminal.app
            case .missingTerminal:
                return "没有找到系统 Terminal.app"
            /// pod install 目标缺少同层的工程包或依赖清单
            case .invalidCocoaPodsProject(let url):
                return "当前文件夹需要同层同时存在 *.xcodeproj 目录和 Podfile 文件：\(url.path)"
            /// flutter pub get 请求目标不是合法的 Flutter 工程目录
            case .invalidFlutterProject(let url):
                return "当前文件夹不是合法的 Flutter 工程目录，需要存在 pubspec.yaml、lib/，且清单声明 sdk: flutter：\(url.path)"
            /// CodeGraph 请求目标不是普通文件夹
            case .invalidCodeGraphTargetFolder(let url):
                return "代码地图只能在普通文件夹中更新：\(url.path)"
            /// 空白 Commit 与 Push 请求目标不是普通文件夹
            case .invalidGitEmptyCommitPushTargetFolder(let url):
                return "空白 Commit 并 Push 只能对普通文件夹执行：\(url.path)"
            /// 请求 Terminal.app 执行命令失败
            case .terminalCommandFailed(let message):
                return message
            }
        }
    }

    func terminalWorkingDirectory(from fileURL: URL, action: TerminalOpener.Action) throws -> URL {
        switch action {
        case .fileMerge, .fileSplit:
            throw TerminalOpenError.terminalCommandFailed("分卷操作需要完整的文件选择。")
        case .fileContent:
            guard dependencyProjectValidator.isFileContentTarget(at: fileURL) else {
                throw TerminalOpenError.terminalCommandFailed("请选择一个可读取的普通文件；不支持文件夹、链接、替身或特殊文件。")
            }
            return fileURL
        /// 普通打开终端时，文件或包文件使用父目录
        case .open:
            if let values = try? fileURL.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey]),
               values.isDirectory == true,
               values.isPackage != true {
                return fileURL
            };return fileURL.deletingLastPathComponent()
        /// pod install 只允许在同层含工程包和 Podfile 的目录执行
        case .podInstall:
            guard dependencyProjectValidator.isCocoaPodsProject(at: fileURL) else {
                throw TerminalOpenError.invalidCocoaPodsProject(fileURL)
            }
            return fileURL
        /// flutter pub get 只允许在合法的 Flutter 工程目录执行
        case .flutterPubGet:
            guard dependencyProjectValidator.isFlutterProject(at: fileURL) else {
                throw TerminalOpenError.invalidFlutterProject(fileURL)
            };return fileURL
        /// 菜单和宿主都要求已识别的工程；脚本执行时再次识别。
        case .cleanBuildArtifacts:
            guard dependencyProjectValidator.isAndroidOpenHarmonyBuildArtifactTargetFolder(at: fileURL) else {
                throw TerminalOpenError.terminalCommandFailed("请选择可识别的 Flutter、Android 或 OpenHarmony 工程文件夹。")
            }
            return fileURL
        /// 代码地图只允许在当前普通文件夹中创建或更新
        case .codeGraphBootstrap:
            guard dependencyProjectValidator.isCodeGraphTargetFolder(at: fileURL) else {
                throw TerminalOpenError.invalidCodeGraphTargetFolder(fileURL)
            };return fileURL
        /// 空白 Commit 与 Push 的 Git 管理状态会在 Terminal 内校验
        case .gitEmptyCommitPush:
            guard dependencyProjectValidator.isGitEmptyCommitPushTargetFolder(at: fileURL) else {
                throw TerminalOpenError.invalidGitEmptyCommitPushTargetFolder(fileURL)
            };return fileURL
        }
    }

    func runTerminalCommand(directoryURL: URL, action: TerminalOpener.Action) throws {
        let terminalURL = try terminalApplicationURL()

        writeLog("terminal action=\(action.rawValue), target directory=\(directoryURL.path)")
        writeLog("terminal app=\(terminalURL.path)")
        try openDirectoryInTerminal(directoryURL, action: action)
        activateTerminalWhenAvailable()
    }

    func terminalApplicationURL() throws -> URL {
        if let terminalURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") {
            return terminalURL
        }

        let candidateURLs = [
            URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app", isDirectory: true),
            URL(fileURLWithPath: "/Applications/Utilities/Terminal.app", isDirectory: true)
        ]

        for candidateURL in candidateURLs where FileManager.default.fileExists(atPath: candidateURL.path) {
            return candidateURL
        }

        throw TerminalOpenError.missingTerminal
    }

    func terminalRunningApplication() -> NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Terminal").first
    }

    func runTerminalAppleScript(commandLine: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = [
            "-e",
            terminalOpenAppleScript(),
            commandLine
        ]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw TerminalOpenError.terminalCommandFailed("请求 Terminal.app 执行命令失败：\(error.localizedDescription)")
        }

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8) ?? ""
        writeLog("terminal command exit=\(process.terminationStatus), output=\(output)")
        guard process.terminationStatus == 0 else {
            throw TerminalOpenError.terminalCommandFailed("Terminal.app 执行命令失败：\(output)")
        }
    }

    func terminalOpenAppleScript() -> String {
        """
        on run argv
            set terminalCommand to item 1 of argv
            tell application "Terminal"
                activate
                do script terminalCommand
            end tell
        end run
        """
    }

    // 在脚本最外层注册清理，覆盖正常结束、业务失败及用户在确认阶段中断。
    func terminalScriptCleanupPrefix() -> String {
        #"""
        # shell: zsh
        # 脚本自述：本文件是当前终端动作的私有载体，业务自述与确认由后续动作负责。
        # 生命周期：仅删除本次脚本及其空目录；不会清理其它运行实例或关闭终端窗口。
        typeset -r JOBS_TERMINAL_RUNTIME_SCRIPT="${0:A}"
        typeset -r JOBS_TERMINAL_RUNTIME_DIRECTORY="${JOBS_TERMINAL_RUNTIME_SCRIPT:h}"
        # 保留业务退出码，只移除当前进程已经读取的专用载体。
        jobs_terminal_cleanup_runtime() {
          local business_result=$?
          /bin/rm -f -- "$JOBS_TERMINAL_RUNTIME_SCRIPT"
          /bin/rmdir -- "$JOBS_TERMINAL_RUNTIME_DIRECTORY" 2>/dev/null
          return "$business_result"
        }
        trap 'jobs_terminal_cleanup_runtime' EXIT
        trap 'exit 130' INT
        trap 'exit 129' HUP
        trap 'exit 143' TERM
        """#
    }

    // 只更新目标目录地图；CLI 缺失时沿 Homebrew、Node/npm 安装链逐层自检。
    func codeGraphDependencyCommand() -> String {
        #"""
        # shell: zsh
        # 脚本自述：
        # - 脚本名称：更新代码地图（.codegraph）。
        # - 核心用途：当前目录已有地图时增量同步，否则创建当前目录地图。
        # - 影响范围：目标目录的 .codegraph；缺失工具安装仅在终端确认后执行。
        # - 运行提示：先阅读自述并回车；安装另行提示回车确认，Ctrl+C 可取消。
        typeset CODEGRAPH_TARGET_DIRECTORY="${1:-}"
        typeset CODEGRAPH_LOG_FILE=""
        typeset CODEGRAPH_BIN=""
        typeset CODEGRAPH_NODE_BIN=""
        typeset CODEGRAPH_NPM_BIN=""
        typeset CODEGRAPH_PREFIX="$HOME/.local/share/jobs-codegraph"
        typeset CODEGRAPH_NPM_REGISTRY="https://registry.npmjs.org/"
        typeset CODEGRAPH_STATUS_JSON=""
        # 为自述提供红色标题、蓝色正文和纯文本降级。
        codegraph_intro_line() {
          local role="$1" message="$2"
          if [[ -t 1 && -n "${TERM:-}" && "${TERM:-}" != dumb && -z "${NO_COLOR+x}" ]]; then
            if [[ "$role" == title ]]; then
              printf '\033[1;31m%s\033[0m\n' "$message"
            else
              printf '\033[0;34m%s\033[0m\n' "$message"
            fi
          else
            print -r -- "$message"
          fi
        }
        # 在任何运行准备或写入之前展示真实行为并等待回车。
        show_script_intro_and_wait() {
          local answer=""
          codegraph_intro_line title '━━━━━━━━━━ 更新代码地图（.codegraph）━━━━━━━━━━'
          codegraph_intro_line body "1、目标目录：$CODEGRAPH_TARGET_DIRECTORY；仅处理该目录自身的 .codegraph。"
          codegraph_intro_line body '2、已有地图数据库执行 sync；首次或尚未初始化的目录执行 init --yes。复用健康 CLI，不主动升级 CodeGraph、Homebrew 或其它全局组件。'
          codegraph_intro_line body '3、每次体检 CodeGraph、Node/npm、Homebrew、bash/curl/Git/Command Line Tools 和地图校验工具；未参与本次执行的安装上游异常会明确警告。'
          codegraph_intro_line body '4、缺少 CLI 时另行回车确认：Homebrew 准备 node@24，再由 npm 安装官方 @colbymchenry/codegraph 到用户独立目录。'
          codegraph_intro_line body '5、没有可确认的官方 CodeGraph Brew 公式；不会猜测同名 formula 或第三方 tap，不修改 Shell 配置和网络代理。'
          codegraph_intro_line body '6、日志为系统临时目录中的 JobsTerminalOpener-CodeGraph.*；按 Ctrl+C 可取消。'
          [[ -t 0 ]] || { print -u2 -r -- '✖ 当前没有可交互输入，请在 Terminal 中重新执行。'; exit 1; }
          IFS= read -r 'answer?👉 已了解用途与影响，按回车继续；按 Ctrl+C 取消：' || exit 1
        }
        # 确认后建立独立日志，所有环境覆盖均限定当前子进程。
        codegraph_initialize_runtime() {
          setopt NO_NOMATCH
          CODEGRAPH_LOG_FILE="$(/usr/bin/mktemp "${TMPDIR:-/tmp}/JobsTerminalOpener-CodeGraph.XXXXXX")" || exit 1
          export CODEGRAPH_DIR=.codegraph CODEGRAPH_TELEMETRY=0 DO_NOT_TRACK=1
          export CODEGRAPH_NO_DOWNLOAD=1 CODEGRAPH_NO_WATCH=0
          export NODE_DISABLE_COMPILE_CACHE=1 NO_COLOR=1 FORCE_COLOR=0
          export HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALL_CLEANUP=1
          export HOMEBREW_NO_ANALYTICS=1
          codegraph_log "ℹ 日志：$CODEGRAPH_LOG_FILE"
        }
        # 同步输出运行信息到终端及本次独立日志。
        codegraph_log() {
          print -r -- "$*" | /usr/bin/tee -a "$CODEGRAPH_LOG_FILE"
        }
        # 给出具体阻塞层级并停止，保留外部命令的非零状态。
        codegraph_stop() {
          codegraph_log "✖ $1；日志：$CODEGRAPH_LOG_FILE"
          exit "${2:-1}"
        }
        # 透传业务与日志写入失败，不用管道最后一项掩盖真实错误。
        codegraph_run_logged() {
          local -a results
          codegraph_log "▶ 执行：${(j: :)${(q)@}}"
          "$@" 2>&1 | /usr/bin/tee -a "$CODEGRAPH_LOG_FILE"
          results=( "${pipestatus[@]}" )
          (( results[1] == 0 )) || return "${results[1]}"
          (( results[2] == 0 )) || return "${results[2]}"
        }
        # 固定到目标的真实路径，拒绝让地图符号链接把写入带到其它项目。
        codegraph_check_target() {
          local map_entry=""
          [[ -n "$CODEGRAPH_TARGET_DIRECTORY" && -d "$CODEGRAPH_TARGET_DIRECTORY" ]] || codegraph_stop "目标目录不存在：$CODEGRAPH_TARGET_DIRECTORY"
          cd -P -- "$CODEGRAPH_TARGET_DIRECTORY" || codegraph_stop "无法进入目标目录：$CODEGRAPH_TARGET_DIRECTORY"
          CODEGRAPH_TARGET_DIRECTORY="$PWD"
          [[ ! -L "$PWD/.codegraph" ]] || codegraph_stop '目标 .codegraph 是符号链接，已停止以免写入其它位置'
          [[ ! -e "$PWD/.codegraph" || -d "$PWD/.codegraph" ]] || codegraph_stop '目标 .codegraph 已存在但不是目录'
          for map_entry in "$PWD/.codegraph"/*(DN); do
            [[ ! -L "$map_entry" ]] || codegraph_stop "地图直属条目是符号链接，已停止以免数据库、锁文件或内部配置写到其它位置：$map_entry"
          done
          [[ -x /usr/bin/plutil ]] || codegraph_stop '缺少 macOS plutil，无法核对地图 JSON 结果'
          [[ "$(print -r -- '{"health":true}' | /usr/bin/plutil -extract health raw -o - - 2>> "$CODEGRAPH_LOG_FILE")" == true ]] || codegraph_stop '系统 plutil 无法解析 JSON，停止地图操作'
          [[ -x /usr/bin/sqlite3 ]] && /usr/bin/sqlite3 -batch -init /dev/null -version >> "$CODEGRAPH_LOG_FILE" 2>&1 || codegraph_stop '系统 SQLite 不可用，无法在不访问父项目的前提下核对地图数据库'
          [[ "$(/usr/bin/sqlite3 -batch -readonly -init /dev/null :memory: 'SELECT 1;' 2>> "$CODEGRAPH_LOG_FILE")" == 1 ]] || codegraph_stop '系统 SQLite 只读查询失败，停止地图操作'
          codegraph_log '✔ 地图校验工具：SQLite 只读接口、plutil JSON 解析健康。'
        }
        # 每个安装上游均给出实际执行结果，诊断失败不等于本次地图运行依赖失败。
        codegraph_health_probe() {
          local label="$1" result=0
          shift
          if [[ -z "${1:-}" ]]; then
            codegraph_log "⚠ 体检：$label 缺失；本次未使用的安装上游不会自动安装。"
            return 0
          fi
          "$@" >> "$CODEGRAPH_LOG_FILE" 2>&1 || result=$?
          if (( result == 0 )); then
            codegraph_log "✔ 体检：$label 可用（$1）。"
          else
            codegraph_log "⚠ 体检：$label 不可用（$1，退出码 $result）；需要该层时必须先修复。"
          fi
        }
        # 在子 Shell 内检查完整安装链，避免探测失败的 Node 候选污染业务 PATH。
        codegraph_report_toolchain_health() {
          codegraph_probe_toolchain_health || codegraph_stop '必需运行工具体检失败，停止地图操作'
        }
        # 隔离只读探测中为 Node/npm 候选临时调整的 PATH。
        codegraph_probe_toolchain_health() (
          local brew_bin="" selector_bin="$(command -v xcode-select 2>/dev/null)"
          local xcrun_bin="$(command -v xcrun 2>/dev/null)" developer_path="" clang_bin=""
          codegraph_log '━━━━━━━━━━ 工具链健康体检 ━━━━━━━━━━'
          codegraph_log "✔ 体检：CodeGraph 版本与 init/sync/status 接口可用（$CODEGRAPH_BIN）。"
          /bin/zsh -f -c 'print -r -- "$ZSH_VERSION"' >> "$CODEGRAPH_LOG_FILE" 2>&1 || codegraph_stop 'zsh 运行时体检失败'
          codegraph_log '✔ 体检：zsh 运行时、SQLite 和 JSON 校验工具可用。'
          codegraph_health_probe bash /bin/bash --version
          codegraph_health_probe curl "$(command -v curl 2>/dev/null)" --version
          codegraph_health_probe Git "$(command -v git 2>/dev/null)" --version
          if [[ -n "$selector_bin" && -n "$xcrun_bin" ]] &&
             developer_path="$("$selector_bin" -p 2>> "$CODEGRAPH_LOG_FILE")" && [[ -d "$developer_path" ]] &&
             clang_bin="$("$xcrun_bin" --find clang 2>> "$CODEGRAPH_LOG_FILE")" && [[ -x "$clang_bin" ]] &&
             "$clang_bin" --version >> "$CODEGRAPH_LOG_FILE" 2>&1; then
            codegraph_log "✔ 体检：Command Line Tools 可用（$developer_path）。"
          else
            codegraph_log '⚠ 体检：Command Line Tools 缺失或不可用；安装链需要该层时停止并提示修复。'
          fi
          if brew_bin="$(jobs_brew_find)"; then
            JOBS_HOMEBREW_BIN="$brew_bin"
            codegraph_health_probe 'Homebrew 配置' "$brew_bin" config
            codegraph_health_probe 'Homebrew doctor' "$brew_bin" doctor
          else
            JOBS_HOMEBREW_BIN=""
            codegraph_log '⚠ 体检：Homebrew 缺失或版本/前缀检查失败；健康 CodeGraph 可继续使用。'
          fi
          if codegraph_find_node_npm; then
            codegraph_log "✔ 体检：Node.js 执行 JS、npm 版本/前缀/全局目录均可用（$CODEGRAPH_NODE_BIN / $CODEGRAPH_NPM_BIN）。"
          else
            codegraph_log '⚠ 体检：Node.js / npm 缺失或真实执行失败；独立 CodeGraph 可继续使用，npm 安装分支必须修复后复检。'
          fi
          codegraph_log 'ℹ 体检结束；上游诊断不会升级健康工具，完整输出见本次日志。'
        )
        # 版本与所需 CLI 接口都可执行才复用，健康探测禁止 shim 隐式下载。
        codegraph_candidate_ok() {
          local candidate="$1"
          [[ -n "$candidate" && -x "$candidate" ]] || return 1
          "$candidate" --version >> "$CODEGRAPH_LOG_FILE" 2>&1 || return 1
          "$candidate" init --help >> "$CODEGRAPH_LOG_FILE" 2>&1 || return 1
          "$candidate" sync --help >> "$CODEGRAPH_LOG_FILE" 2>&1 || return 1
          "$candidate" status --help >> "$CODEGRAPH_LOG_FILE" 2>&1 || return 1
        }
        # 复用当前命令或既有用户安装，避免因 PATH 未加载就重复安装。
        codegraph_find_cli() {
          local candidate=""
          local -a candidates=( "$CODEGRAPH_PREFIX/bin/codegraph" "$(command -v codegraph 2>/dev/null)"
            /opt/homebrew/bin/codegraph /usr/local/bin/codegraph "$HOME/.local/bin/codegraph"
            "$HOME/.npm-global/bin/codegraph" "${JOBS_HOMEBREW_INSTALL_PREFIX:-$HOME/.local/homebrew}/bin/codegraph"
            "$HOME/.homebrew/bin/codegraph" )
          for candidate in "${candidates[@]}"; do
            if codegraph_candidate_ok "$candidate"; then
              CODEGRAPH_BIN="$candidate"
              return 0
            fi
          done
          return 1
        }
        # CLI 缺失时明确说明实际安装通道，只有直接回车才开始修复依赖链。
        codegraph_confirm_installation() {
          local answer=""
          codegraph_log '⚠ 未发现健康 CodeGraph；实际依赖链为 CodeGraph → npm/Node.js → Homebrew → bash/curl/Command Line Tools。'
          codegraph_log "ℹ 安装来源：https://registry.npmjs.org/@colbymchenry/codegraph；目标：$CODEGRAPH_PREFIX"
          codegraph_log 'ℹ 健康组件会复用；仅缺失或损坏的组件修复一次。Homebrew 缺失时仍需选择系统目录或用户目录。'
          IFS= read -r 'answer?👉 按回车确认安装缺失组件；输入任意内容后回车取消，或按 Ctrl+C 取消：' || exit 1
          if [[ -n "$answer" ]]; then
            codegraph_log 'ℹ 已取消安装，未更新代码地图。'
            exit 0
          fi
        }
        # 体检本次安装真正依赖的系统引导层；CLT 安装请求后停止并等待人工完成。
        codegraph_check_installation_tools() {
          local curl_bin="$(command -v curl 2>/dev/null)" selector_bin="$(command -v xcode-select 2>/dev/null)"
          local xcrun_bin="$(command -v xcrun 2>/dev/null)" clang_bin="" developer_path=""
          [[ -x /bin/bash ]] && /bin/bash --version >> "$CODEGRAPH_LOG_FILE" 2>&1 || codegraph_stop '系统 bash 不可用，无法引导 Homebrew'
          [[ -n "$curl_bin" ]] && "$curl_bin" --version >> "$CODEGRAPH_LOG_FILE" 2>&1 || codegraph_stop 'curl 不可用，请先修复系统下载工具'
          [[ -n "$selector_bin" && -n "$xcrun_bin" ]] || codegraph_stop '缺少 xcode-select/xcrun，请先准备 Apple Command Line Tools'
          developer_path="$("$selector_bin" -p 2>> "$CODEGRAPH_LOG_FILE")"
          clang_bin="$("$xcrun_bin" --find clang 2>> "$CODEGRAPH_LOG_FILE")"
          if [[ -z "$developer_path" || ! -d "$developer_path" || -z "$clang_bin" || ! -x "$clang_bin" ]] ||
             ! "$clang_bin" --version >> "$CODEGRAPH_LOG_FILE" 2>&1; then
            codegraph_log '⚠ Command Line Tools 不可用，将请求系统安装；安装完成后请重新点击本入口。'
            codegraph_run_logged "$selector_bin" --install || codegraph_stop '系统未能启动 Command Line Tools 安装'
            codegraph_stop 'Command Line Tools 尚未就绪，本次未继续安装下游组件'
          fi
          codegraph_log '✔ bash、curl 和 Command Line Tools 健康检查通过。'
        }
        # 只复用或安装 Homebrew，不更新公式元数据、不写用户启动配置。
        codegraph_ensure_homebrew() {
          if ! JOBS_HOMEBREW_BIN="$(jobs_brew_find)"; then
            codegraph_log '━━━━━━━━━━ 来源｜Homebrew ━━━━━━━━━━'
            codegraph_log '📥 系统安装器：https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh'
            codegraph_log '📥 用户目录来源：https://github.com/Homebrew/brew.git（官方最新稳定发布）'
            jobs_brew_choose_installation || codegraph_stop 'Homebrew 安装路径选择已取消'
            case "$JOBS_HOMEBREW_INSTALL_MODE" in
              system) jobs_brew_install_system || codegraph_stop '系统目录 Homebrew 安装失败' ;;
              user) jobs_brew_install_user || codegraph_stop '用户目录 Homebrew 安装失败' ;;
              *) codegraph_stop 'Homebrew 安装路径选择无效' ;;
            esac
          fi
          jobs_brew_activate || codegraph_stop 'Homebrew 当前进程环境激活失败'
          codegraph_run_logged "$JOBS_HOMEBREW_BIN" --version || codegraph_stop 'Homebrew 版本检查失败'
          codegraph_run_logged "$JOBS_HOMEBREW_BIN" config || codegraph_stop 'Homebrew 配置检查失败'
          if ! codegraph_run_logged "$JOBS_HOMEBREW_BIN" doctor; then
            codegraph_log '⚠ Homebrew doctor 有诊断提示；用户前缀或无关公式警告不等于本次依赖不可用，继续按实际 Node/npm 健康检查判断。'
          fi
        }
        # 执行真实 JS 并验证配套 npm 的版本与只读配置，不能只判断命令存在。
        codegraph_node_npm_ok() {
          [[ -x "$CODEGRAPH_NODE_BIN" && -x "$CODEGRAPH_NPM_BIN" ]] || return 1
          "$CODEGRAPH_NODE_BIN" --version >> "$CODEGRAPH_LOG_FILE" 2>&1 || return 1
          "$CODEGRAPH_NODE_BIN" -e 'const major = Number(process.versions.node.split(".")[0]); if (major < 20 || major >= 25) process.exit(1); require("node:fs"); require("node:path");' >> "$CODEGRAPH_LOG_FILE" 2>&1 || return 1
          "$CODEGRAPH_NPM_BIN" --version >> "$CODEGRAPH_LOG_FILE" 2>&1 || return 1
          "$CODEGRAPH_NPM_BIN" config get prefix >> "$CODEGRAPH_LOG_FILE" 2>&1 || return 1
          "$CODEGRAPH_NPM_BIN" root --global >> "$CODEGRAPH_LOG_FILE" 2>&1 || return 1
        }
        # 寻找当前环境和 Homebrew 已有成套 Node/npm，健康来源不重新安装。
        codegraph_find_node_npm() {
          local node_path="$(command -v node 2>/dev/null)" candidate="" formula="" prefix=""
          local -a candidates=()
          [[ -z "$node_path" ]] || candidates+=( "${node_path:h}" )
          for formula in node@24 node node@22; do
            [[ -n "${JOBS_HOMEBREW_BIN:-}" && -x "$JOBS_HOMEBREW_BIN" ]] || break
            prefix="$("$JOBS_HOMEBREW_BIN" --prefix "$formula" 2>> "$CODEGRAPH_LOG_FILE")" || continue
            [[ "$prefix" != /* ]] || candidates+=( "$prefix/bin" )
          done
          for candidate in "${candidates[@]}"; do
            CODEGRAPH_NODE_BIN="$candidate/node"
            CODEGRAPH_NPM_BIN="$candidate/npm"
            export PATH="$candidate:$PATH"
            rehash
            codegraph_node_npm_ok && return 0
          done
          return 1
        }
        # 缺失或损坏的 Node/npm 只通过已体检的 Homebrew 修复一次并立即复检。
        codegraph_ensure_node_npm() {
          local node_prefix="" operation=install
          if codegraph_find_node_npm; then
            codegraph_log "✔ 复用健康 Node/npm：$CODEGRAPH_NODE_BIN / $CODEGRAPH_NPM_BIN"
            return 0
          fi
          "$JOBS_HOMEBREW_BIN" list --versions node@24 >> "$CODEGRAPH_LOG_FILE" 2>&1 && operation=reinstall
          codegraph_log '━━━━━━━━━━ 来源｜Node.js / npm ━━━━━━━━━━'
          codegraph_log "📥 来源：Homebrew 官方 node@24 公式；动作：$operation；包下载地址由 Homebrew 解析"
          codegraph_run_logged "$JOBS_HOMEBREW_BIN" "$operation" node@24 || codegraph_stop 'Homebrew Node.js 安装或修复失败'
          node_prefix="$("$JOBS_HOMEBREW_BIN" --prefix node@24 2>> "$CODEGRAPH_LOG_FILE")" || codegraph_stop '无法读取 node@24 安装前缀'
          [[ "$node_prefix" == /* && -d "$node_prefix" ]] || codegraph_stop 'node@24 返回了无效安装前缀'
          CODEGRAPH_NODE_BIN="$node_prefix/bin/node"
          CODEGRAPH_NPM_BIN="$node_prefix/bin/npm"
          export PATH="$node_prefix/bin:$PATH"
          rehash
          codegraph_node_npm_ok || codegraph_stop 'Node/npm 安装后复检失败；停止，不反复安装'
          codegraph_log '✔ Node/npm 安装后健康检查通过。'
        }
        # 官方 npm 包写入用户独立前缀，保留其它全局安装且不修改 npm 配置。
        codegraph_install_cli() {
          [[ ! -L "$CODEGRAPH_PREFIX" ]] || codegraph_stop "CodeGraph 安装前缀是符号链接：$CODEGRAPH_PREFIX"
          codegraph_log '━━━━━━━━━━ 来源｜CodeGraph ━━━━━━━━━━'
          codegraph_log '📦 包：@colbymchenry/codegraph@latest（官方 scoped npm 包）'
          codegraph_log "📥 Registry：$CODEGRAPH_NPM_REGISTRY；目标：$CODEGRAPH_PREFIX"
          codegraph_run_logged "$CODEGRAPH_NPM_BIN" ping --registry "$CODEGRAPH_NPM_REGISTRY" --fetch-retries=1 --fetch-timeout=30000 || codegraph_stop 'npm 官方 Registry 不可用，未开始安装 CodeGraph'
          codegraph_run_logged "$CODEGRAPH_NPM_BIN" install --global --prefix "$CODEGRAPH_PREFIX" --registry "$CODEGRAPH_NPM_REGISTRY" --include=optional --engine-strict --fetch-retries=1 --fetch-timeout=60000 '@colbymchenry/codegraph@latest' || codegraph_stop 'CodeGraph 官方 npm 包安装失败'
          CODEGRAPH_BIN="$CODEGRAPH_PREFIX/bin/codegraph"
          export PATH="$CODEGRAPH_PREFIX/bin:$PATH"
          rehash
          codegraph_candidate_ok "$CODEGRAPH_BIN" || codegraph_stop 'CodeGraph 安装后版本或 CLI 接口复检失败；停止，不反复安装'
          codegraph_log "✔ CodeGraph 安装后健康检查通过：$CODEGRAPH_BIN"
        }
        # 已有健康 CLI 只用于更新地图；缺失时才进入经确认的完整安装链。
        codegraph_ensure_cli() {
          if codegraph_find_cli; then
            codegraph_log "✔ 复用健康 CodeGraph：$CODEGRAPH_BIN"
            return 0
          fi
          codegraph_confirm_installation
          codegraph_check_installation_tools
          codegraph_ensure_homebrew
          codegraph_ensure_node_npm
          codegraph_install_cli
        }
        # 获取官方 JSON 状态，stderr 单独落盘，避免混入解析结果。
        codegraph_read_status() {
          CODEGRAPH_STATUS_JSON="$("$CODEGRAPH_BIN" status --json "$CODEGRAPH_TARGET_DIRECTORY" 2>> "$CODEGRAPH_LOG_FILE")"
          local command_result=$?
          (( command_result == 0 )) || codegraph_stop 'CodeGraph 状态读取失败' "$command_result"
          codegraph_log "$CODEGRAPH_STATUS_JSON"
        }
        # 只读检查精确目标数据库，避免 CLI 对残缺数据库向上回退并打开父项目。
        codegraph_require_target_schema() {
          local database_path="$CODEGRAPH_TARGET_DIRECTORY/.codegraph/codegraph.db" schema_result=""
          [[ -f "$database_path" ]] || codegraph_stop '目标地图数据库尚未生成，未读取可能属于父项目的状态'
          schema_result="$(/usr/bin/sqlite3 -batch -readonly -init /dev/null "$database_path" "SELECT 1 FROM sqlite_master WHERE type='table' AND name='nodes' LIMIT 1;" 2>> "$CODEGRAPH_LOG_FILE")" || codegraph_stop '目标地图数据库无法只读校验，请先排查数据库损坏或锁定问题'
          [[ "$schema_result" == 1 ]] || codegraph_stop '目标数据库缺少 CodeGraph nodes 表，保留原文件且不访问父项目地图'
        }
        # 用系统 JSON 解析器读取必需字段，缺失或格式错误就停止。
        codegraph_status_field() {
          /usr/bin/plutil -extract "$1" raw -o - - <<< "$CODEGRAPH_STATUS_JSON" 2>/dev/null
        }
        # 检查项目身份及输出位置；只有完整状态才显示地图更新完成。
        codegraph_validate_status() {
          local initialized="" project_path="" index_path="" last_indexed="" index_state="" field="" count=""
          initialized="$(codegraph_status_field initialized)" || codegraph_stop 'JSON 缺少 initialized 字段'
          project_path="$(codegraph_status_field projectPath)" || codegraph_stop 'JSON 缺少 projectPath 字段'
          index_path="$(codegraph_status_field indexPath)" || codegraph_stop 'JSON 缺少 indexPath 字段'
          [[ "$initialized" == true && "$project_path" == "$CODEGRAPH_TARGET_DIRECTORY" && "$index_path" == "$CODEGRAPH_TARGET_DIRECTORY/.codegraph" ]] || codegraph_stop '地图项目身份或输出位置不匹配，未继续处理其它目录'
          if [[ "${1:-}" == complete ]]; then
            last_indexed="$(codegraph_status_field lastIndexed)" || codegraph_stop 'JSON 缺少索引时间'
            index_state="$(codegraph_status_field index.state)" || codegraph_stop 'JSON 缺少索引完整状态'
            [[ -n "$last_indexed" && "$last_indexed" != null && "$index_state" == complete && -d "$CODEGRAPH_TARGET_DIRECTORY/.codegraph" ]] || codegraph_stop '地图索引未完成或产物不存在'
            for field in pendingChanges.added pendingChanges.modified pendingChanges.removed index.pendingRefs; do
              count="$(codegraph_status_field "$field")" || codegraph_stop "JSON 缺少索引核验字段：$field"
              [[ "$count" == 0 ]] || codegraph_stop "地图仍存在待处理变更或解析问题：$field=$count"
            done
            for field in index.filesNeedingReindex index.filesWithParseErrors; do
              if count="$(codegraph_status_field "$field")"; then
                [[ "$count" == 0 ]] || codegraph_stop "地图仍存在待处理变更或解析问题：$field=$count"
              fi
            done
          fi
        }
        # 增量同步已有地图或创建首次地图，绝不删除重建既有目录。
        codegraph_update_target_map() {
          local command_result=0
          if [[ -f "$CODEGRAPH_TARGET_DIRECTORY/.codegraph/codegraph.db" ]]; then
            codegraph_require_target_schema
            codegraph_read_status
            codegraph_validate_status
            codegraph_run_logged "$CODEGRAPH_BIN" sync "$CODEGRAPH_TARGET_DIRECTORY" || command_result=$?
          else
            codegraph_run_logged "$CODEGRAPH_BIN" init --yes "$CODEGRAPH_TARGET_DIRECTORY" || command_result=$?
          fi
          (( command_result == 0 )) || codegraph_stop '代码地图命令执行失败，保留现有产物供排查' "$command_result"
          codegraph_require_target_schema
          codegraph_read_status
          codegraph_validate_status complete
          codegraph_log "✔ 代码地图更新完成：$CODEGRAPH_TARGET_DIRECTORY/.codegraph；日志：$CODEGRAPH_LOG_FILE"
        }
        # 先确认再准备环境，只有依赖健康才允许写入目标地图。
        main() {
          show_script_intro_and_wait # 首先展示用途与影响并等待回车。
          codegraph_initialize_runtime # 确认后建立独立日志和进程内环境。
          codegraph_check_target # 固定目标并拒绝跨目录地图引用。
          codegraph_ensure_cli # 复用健康 CLI 或经确认安装缺失依赖。
          codegraph_report_toolchain_health # 每次只读体检完整链，必需运行层失败即停止。
          codegraph_update_target_map # 仅创建或同步当前目标地图并核验结果。
        }
        """# + "\n" + codeGraphHomebrewCommand() + "\nmain \"$@\""
    }

    // 为 Terminal 的交互命令提供 Homebrew 安装路径选择。
    func codeGraphHomebrewCommand() -> String {
        #"""
        # >>> Jobs Homebrew install choice >>>
        # 输出安装诊断，避免混入返回的命令路径。
        jobs_brew_note() {
          codegraph_log "ℹ $*" >&2
        }
        # 验证候选能够执行；共享安装只读不代表未安装。
        jobs_brew_candidate_ok() {
          local candidate="$1" prefix
          [[ -n "$candidate" && -x "$candidate" ]] || return 1
          HOMEBREW_NO_AUTO_UPDATE=1 "$candidate" --version >/dev/null 2>&1 || return 1
          prefix="$("$candidate" --prefix 2>/dev/null)" || return 1
          [[ "$prefix" == /* && -d "$prefix" ]]
        }
        # 发现既有健康安装，不以目录可写性决定是否重新安装。
        jobs_brew_find() {
          local candidate
          local -a candidates
          candidates=("${JOBS_HOMEBREW_BIN:-}" "$(command -v brew 2>/dev/null)" /opt/homebrew/bin/brew /usr/local/bin/brew
            "${JOBS_HOMEBREW_INSTALL_PREFIX:-$HOME/.local/homebrew}/bin/brew" "$HOME/.homebrew/bin/brew")
          for candidate in "${candidates[@]}"; do
            if jobs_brew_candidate_ok "$candidate"; then
              print -r -- "$candidate"
              return 0
            fi
          done
          return 1
        }
        # 计算官方系统目录；实际支持范围和授权交由官方安装器处理。
        jobs_brew_system_prefix() {
          case "$(/usr/bin/uname -m)" in
            arm64) print -r -- /opt/homebrew ;;
            *) print -r -- /usr/local ;;
          esac
        }
        # 缺失时强提示选择安装路径；YES 只表示选择系统目录，不验证密码或权限。
        jobs_brew_choose_installation() {
          local answer="" system_prefix="$(jobs_brew_system_prefix)"
          if [[ ! -t 0 || ! -t 2 || "${IS_SOURCETREE_RUNTIME:-0}" == 1 ]]; then
            jobs_brew_note "缺少 Homebrew，需要人工选择安装路径；请在可交互终端重新运行，未执行安装。"
            return 1
          fi
          print -u2 -r -- "⚠ Homebrew 尚未就绪，必须先选择安装路径："
          print -u2 -r -- "1、输入精确大写 YES：选择系统标准目录 $system_prefix（Apple Silicon：/opt/homebrew；Intel：/usr/local）。"
          print -u2 -r -- "   这表示你准备向系统目录安装；官方安装器可能随后要求管理员密码，并自行验证权限。"
          print -u2 -r -- "2、其它输入或直接回车：选择用户目录 ${JOBS_HOMEBREW_INSTALL_PREFIX:-$HOME/.local/homebrew}，不使用 sudo；有管理员权限也可选此路径。"
          print -u2 -r -- "本步骤只选择路径，不收集或验证密码；选定路径失败就停止，不自动切换。按 Ctrl+C 取消整个任务。"
          print -u2 -n -r -- "➤ 安装路径选择："
          if ! IFS= read -r answer; then
            jobs_brew_note "输入已取消或结束，停止安装。"
            return 1
          fi
          if [[ "$answer" == YES ]]; then
            typeset -g JOBS_HOMEBREW_INSTALL_MODE=system
            jobs_brew_note "已选择系统安装目录：$system_prefix"
          else
            typeset -g JOBS_HOMEBREW_INSTALL_MODE=user
            jobs_brew_note "已选择用户安装目录：${JOBS_HOMEBREW_INSTALL_PREFIX:-$HOME/.local/homebrew}"
          fi
        }
        # 将官方系统安装器下载到临时文件后执行，失败不自动改装到用户目录。
        jobs_brew_install_system() {
          local installer system_prefix="$(jobs_brew_system_prefix)" installer_result=0
          command -v curl >/dev/null 2>&1 || { jobs_brew_note "缺少 curl，无法获取官方安装器。"; return 1; }
          installer="$(mktemp "${TMPDIR:-/tmp}/jobs-homebrew-install.XXXXXX")" || return 1
          if curl -fsSL --connect-timeout 10 --max-time 120 https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh -o "$installer"; then
            codegraph_run_logged /bin/bash "$installer" || installer_result=$?
          else
            installer_result=1
          fi
          rm -- "$installer"
          if (( installer_result != 0 )); then
            jobs_brew_note "系统目录安装失败（退出码 $installer_result）；停止，不自动切换安装路径。"
            return 1
          fi
          typeset -g JOBS_HOMEBREW_BIN="$system_prefix/bin/brew"
          jobs_brew_candidate_ok "$JOBS_HOMEBREW_BIN" || { jobs_brew_note "官方安装器结束后未找到健康 Homebrew：$JOBS_HOMEBREW_BIN"; return 1; }
        }
        # 克隆官方稳定版本到用户目录；不覆盖非空目录，不调用 sudo。
        jobs_brew_install_user() {
          local prefix="${JOBS_HOMEBREW_INSTALL_PREFIX:-$HOME/.local/homebrew}" stage release_tag git_bin
          [[ "$prefix" == /* && "$prefix" != / && "$prefix" != *[[:space:]:]* ]] || {
            jobs_brew_note "Homebrew 用户前缀须为不含空白或冒号的绝对目录：$prefix"
            return 1
          }
          if [[ -L "$prefix" || ( -e "$prefix" && ! -d "$prefix" ) || ( -d "$prefix" && -n "$(ls -A "$prefix" 2>/dev/null)" ) ]]; then
            jobs_brew_note "用户安装目标非空或不是普通目录，不覆盖：$prefix"
            return 1
          fi
          git_bin="$(command -v git 2>/dev/null)"
          [[ -n "$git_bin" ]] && "$git_bin" --version >/dev/null 2>&1 || { jobs_brew_note "用户目录安装需要可用 Git；请先准备 Git / Command Line Tools。"; return 1; }
          command -v curl >/dev/null 2>&1 || { jobs_brew_note "缺少 curl，无法获取官方稳定版本。"; return 1; }
          export HOMEBREW_NO_SUDO=1
          mkdir -p "${prefix:h}" || return 1
          stage="$(mktemp -d "${prefix:h}/.jobs-homebrew.XXXXXX")" || return 1
          if ! curl -fsSL --connect-timeout 10 --max-time 60 https://api.github.com/repos/Homebrew/brew/releases/latest -o "$stage/release.json"; then
            rm -r -- "$stage"
            jobs_brew_note "获取官方稳定版本失败，停止安装。"
            return 1
          fi
          release_tag="$(sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([0-9][0-9.]*\)".*/\1/p' "$stage/release.json" | head -n 1)"
          if [[ ! "$release_tag" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]] ||
             ! GIT_TERMINAL_PROMPT=0 codegraph_run_logged "$git_bin" -c http.lowSpeedLimit=1 -c http.lowSpeedTime=60 clone --depth 1 --branch "$release_tag" --single-branch https://github.com/Homebrew/brew.git "$stage/brew" ||
             ! "$git_bin" -C "$stage/brew" checkout -b stable ||
             ! "$git_bin" -C "$stage/brew" config remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*' ||
             ! mkdir -p "$stage/brew/Cellar" "$stage/brew/Caskroom" "$stage/brew/etc" "$stage/brew/var"; then
            rm -r -- "$stage"
            jobs_brew_note "Homebrew 用户目录初始化失败，停止安装。"
            return 1
          fi
          # 空目录也只在下载成功后移除，避免提前改动用户的目标目录。
          if [[ -d "$prefix" ]] && ! rmdir -- "$prefix"; then
            rm -r -- "$stage"
            return 1
          fi
          if ! mv "$stage/brew" "$prefix"; then
            rm -r -- "$stage"
            return 1
          fi
          rm -r -- "$stage"
          typeset -g JOBS_HOMEBREW_BIN="$prefix/bin/brew"
          jobs_brew_candidate_ok "$JOBS_HOMEBREW_BIN" || { jobs_brew_note "用户目录安装后复检失败：$prefix"; return 1; }
        }
        # 仅激活当前子进程，不持久化用户 Shell 或其它全局配置。
        jobs_brew_activate() {
          local brew_env
          brew_env="$("$JOBS_HOMEBREW_BIN" shellenv)" || return 1
          eval "$brew_env" || return 1
          typeset -g JOBS_HOMEBREW_PREFIX="$("$JOBS_HOMEBREW_BIN" --prefix)"
          [[ "$JOBS_HOMEBREW_PREFIX" == /* && -d "$JOBS_HOMEBREW_PREFIX" ]] || return 1
          export PATH="$JOBS_HOMEBREW_PREFIX/bin:$JOBS_HOMEBREW_PREFIX/sbin:$PATH"
          rehash
          HOMEBREW_NO_AUTO_UPDATE=1 "$JOBS_HOMEBREW_BIN" config >/dev/null || return 1
        }
        # <<< Jobs Homebrew install choice <<<
        """#
    }

    func gitEmptyCommitPushCommand() -> String {
        #"""
        git_empty_commit_push() {
          local git_bin=""
          local inside_work_tree=""
          local repository_root=""
          local current_branch=""
          local upstream=""
          local push_remote=""
          local remote_count="0"
          local index_status="0"
          local commit_hash=""

          printf '\n▶ 正在检查当前文件夹是否由 Git 管理：%s\n' "$PWD"
          git_bin="$(command -v git 2>/dev/null || true)"
          if [[ -z "$git_bin" ]] || ! "$git_bin" --version >/dev/null 2>&1; then
            printf '✖ 未找到可用的 Git，已停止。\n'
            return 1
          fi
          printf '✔ Git 可用：'
          "$git_bin" --version

          inside_work_tree="$("$git_bin" rev-parse --is-inside-work-tree 2>/dev/null || true)"
          if [[ "$inside_work_tree" != "true" ]]; then
            printf '✖ 当前文件夹不在 Git 工作树内，不会创建 Commit：%s\n' "$PWD"
            return 1
          fi

          repository_root="$("$git_bin" rev-parse --show-toplevel 2>/dev/null || true)"
          current_branch="$("$git_bin" symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
          if [[ -z "$repository_root" ]]; then
            printf '✖ 无法读取 Git 仓库根目录，已停止。\n'
            return 1
          fi
          if [[ -z "$current_branch" ]]; then
            printf '✖ 当前处于 detached HEAD，不会创建或推送空白 Commit。\n'
            return 1
          fi
          printf '✔ Git 仓库：%s\n' "$repository_root"
          printf '✔ 当前分支：%s\n' "$current_branch"

          "$git_bin" diff --cached --quiet --
          index_status=$?
          if (( index_status == 1 )); then
            printf '✖ 暂存区存在待提交内容。为保证这次是纯空白 Commit，已停止。\n'
            return 1
          fi
          if (( index_status != 0 )); then
            printf '✖ 无法校验 Git 暂存区，已停止。\n'
            return "$index_status"
          fi
          printf '✔ 暂存区为空，不会带入文件改动。\n'

          upstream="$("$git_bin" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null || true)"
          if [[ -z "$upstream" ]]; then
            if "$git_bin" remote get-url origin >/dev/null 2>&1; then
              push_remote="origin"
            else
              remote_count="$("$git_bin" remote 2>/dev/null | /usr/bin/awk 'NF { count += 1 } END { print count + 0 }')"
              if [[ "$remote_count" == "1" ]]; then
                push_remote="$("$git_bin" remote 2>/dev/null | /usr/bin/head -n 1)"
              else
                printf '✖ 当前分支没有上游，且无法唯一确定推送远程，已停止。\n'
                "$git_bin" remote -v
                return 1
              fi
            fi
          fi

          printf '\n▶ 正在创建不包含文件变更的空白 Commit...\n'
          if ! "$git_bin" commit --allow-empty -m 'chore: empty commit'; then
            printf '✖ 空白 Commit 创建失败，未执行 Push。\n'
            return 1
          fi
          commit_hash="$("$git_bin" rev-parse --short HEAD 2>/dev/null || true)"

          printf '\n▶ 正在推送空白 Commit...\n'
          if [[ -n "$upstream" ]]; then
            if ! "$git_bin" push; then
              printf '✖ Push 失败；空白 Commit 已保留在本地：%s\n' "$commit_hash"
              return 1
            fi
          else
            if ! "$git_bin" push -u "$push_remote" "$current_branch"; then
              printf '✖ Push 失败；空白 Commit 已保留在本地：%s\n' "$commit_hash"
              return 1
            fi
          fi

          printf '\n✔ 空白 Commit 已推送：%s\n' "$commit_hash"
        }
        git_empty_commit_push
        """#
    }

    func activateTerminalWhenAvailable() {
        for attempt in 1...20 {
            if let runningApplication = terminalRunningApplication() {
                let didActivate = runningApplication.activate(options: [.activateAllWindows])
                writeLog("terminal activate attempt=\(attempt), success=\(didActivate)")
                return
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        writeLog("terminal activate skipped, running app not found")
    }
}
